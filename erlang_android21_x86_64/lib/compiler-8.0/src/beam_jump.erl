%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1999-2020. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%
%%% Purpose : Optimise jumps and remove unreachable code.

-module(beam_jump).

-export([module/2,
	 remove_unused_labels/1]).

%%% The following optimisations are done:
%%%
%%% (1) This code with two identical instruction sequences
%%% 
%%%     L1: <Instruction sequence>
%%%     L2:
%%%          . . .
%%%     L3: <Instruction sequence>
%%%     L4:
%%%
%%%     can be replaced with
%%% 
%%%     L1: jump L3
%%%     L2:
%%%          . . .
%%%     L3: <Instruction sequence>
%%%     L4
%%%     
%%%     Note: The instruction sequence must end with an instruction
%%%     such as a jump that never transfers control to the instruction
%%%     following it.
%%%
%%% (2) Short sequences starting with a label and ending in case_end, if_end,
%%%     and badmatch, and function calls that cause an exit (such as calls
%%%     to exit/1) are moved to the end of the function, but only if the
%%%     the block is not entered via a fallthrough. The purpose of this move
%%%     is to allow further optimizations at the place from which the
%%%     code was moved (a jump around the block could be replaced with a
%%%     fallthrough).
%%%
%%% (3) Any unreachable code is removed.  Unreachable code is code
%%%     after jump, call_last and other instructions which never
%%%     transfer control to the following instruction.  Code is
%%%     unreachable up to the next *referenced* label.  Note that the
%%%     optimisations below might generate more possibilities for
%%%     removing unreachable code.
%%%
%%% (4) This code:
%%%	L1:	jump L2
%%%          . . .
%%%     L2: ...
%%%
%%%    will be changed to
%%%
%%%    jump L2
%%%          . . .
%%%    L2: ...
%%%
%%%    and all preceding uses of L1 renamed to L2.
%%%    If the jump is unreachable, it will be removed according to (1).
%%%
%%% (5) In
%%%
%%%	 jump L1
%%%      L1:
%%%
%%%	 the jump (but not the label) will be removed.
%%%
%%% (6) If test instructions are used to skip a single jump instruction,
%%%      the test is inverted and the jump is eliminated (provided that
%%%      the test can be inverted).  Example:
%%%
%%%      is_eq L1 {x,1} {x,2}
%%%      jump L2
%%%      L1:
%%%
%%%      will be changed to
%%%
%%%      is_ne L2 {x,1} {x,2}
%%%      L1:
%%%
%%%      Because there may be backward references to the label L1
%%%      (for instance from the wait_timeout/1 instruction), we will
%%%      always keep the label. (beam_clean will remove any unused
%%%      labels.)
%%%
%%% (7)  Replace a jump to a return instruction with a return instruction.
%%%      Similarly, replace a jump to deallocate + return with those
%%%      instructions.
%%%
%%% Note: This modules depends on (almost) all branches and jumps only
%%% going forward, so that we can remove instructions (including definition
%%% of labels) after any label that has not been referenced by the code
%%% preceeding the labels. Regarding the few instructions that have backward
%%% references to labels, we assume that they only transfer control back
%%% to an instruction that has already been executed. That is, code such as
%%%
%%%         jump L_entry
%%%
%%%      L_again:
%%%           .
%%%           .
%%%           .
%%%      L_entry:
%%%           .
%%%           .
%%%           .
%%%         jump L_again;
%%%           
%%% is NOT allowed (and such code is never generated by the code generator).
%%%
%%% Terminology note: The optimisation done here is called unreachable-code
%%% removal, NOT dead-code elimination.  Dead code elimination means the
%%% removal of instructions that are executed, but have no visible effect
%%% on the program state.
%%% 

-import(lists, [foldl/3,keymember/3,mapfoldl/3,reverse/1,reverse/2]).

-type instruction() :: beam_utils:instruction().

-include("beam_types.hrl").

-spec module(beam_utils:module_code(), [compile:option()]) ->
                    {'ok',beam_utils:module_code()}.

module({Mod,Exp,Attr,Fs0,Lc0}, _Opt) ->
    {Fs,Lc} = mapfoldl(fun function/2, Lc0, Fs0),
    {ok,{Mod,Exp,Attr,Fs,Lc}}.

%% function(Function) -> Function'
%%  Optimize jumps and branches.
%%
%%  NOTE: This function assumes that there are no labels inside blocks.
function({function,Name,Arity,CLabel,Asm0}, Lc0) ->
    try
        Asm1 = eliminate_moves(Asm0),
        {Asm2,Lc} = insert_labels(Asm1, Lc0, []),
        Asm3 = share(Asm2),
        Asm4 = move(Asm3),
        Asm5 = opt(Asm4, CLabel),
        Asm6 = unshare(Asm5),
        Asm = remove_unused_labels(Asm6),
        {{function,Name,Arity,CLabel,Asm},Lc}
    catch
        Class:Error:Stack ->
	    io:fwrite("Function: ~w/~w\n", [Name,Arity]),
	    erlang:raise(Class, Error, Stack)
    end.

%%%
%%% Scan instructions in execution order and remove redundant 'move'
%%% instructions. 'move' instructions are redundant if we know that
%%% the register already contains the value being assigned, as in the
%%% following code:
%%%
%%%           select_val Register FailLabel [... Literal => L1...]
%%%                      .
%%%                      .
%%%                      .
%%%   L1:     move Literal Register
%%%

eliminate_moves(Is) ->
    eliminate_moves(Is, #{}, []).

eliminate_moves([{select,select_val,Reg,{f,Fail},List}=I|Is], D0, Acc) ->
    D1 = add_unsafe_label(Fail, D0),
    D = update_value_dict(List, Reg, D1),
    eliminate_moves(Is, D, [I|Acc]);
eliminate_moves([{test,is_eq_exact,_,[Reg,Val]}=I,
                 {block,BlkIs0}|Is], D0, Acc) ->
    D = update_unsafe_labels(I, D0),
    RegVal = {Reg,Val},
    BlkIs = eliminate_moves_blk(BlkIs0, RegVal),
    eliminate_moves([{block,BlkIs}|Is], D, [I|Acc]);
eliminate_moves([{test,is_nonempty_list,Fail,[Reg]}=I|Is], D0, Acc) ->
    case is_proper_list(Reg, Acc) of
        true ->
            D = update_value_dict([nil,Fail], Reg, D0),
            eliminate_moves(Is, D, [I|Acc]);
        false ->
            D = update_unsafe_labels(I, D0),
            eliminate_moves(Is, D, [I|Acc])
    end;
eliminate_moves([{label,Lbl},{block,BlkIs0}=Blk|Is], D, Acc0) ->
    Acc = [{label,Lbl}|Acc0],
    case {no_fallthrough(Acc0),D} of
        {true,#{Lbl:={_,_}=RegVal}} ->
            BlkIs = eliminate_moves_blk(BlkIs0, RegVal),
            eliminate_moves([{block,BlkIs}|Is], D, Acc);
        {_,_} ->
            eliminate_moves([Blk|Is], D, Acc)
    end;
eliminate_moves([{call,_,_}=I|Is], D, Acc) ->
    eliminate_moves_call(Is, D, [I | Acc]);
eliminate_moves([{call_ext,_,_}=I|Is], D, Acc) ->
    eliminate_moves_call(Is, D, [I | Acc]);
eliminate_moves([{block,[]}|Is], D, Acc) ->
    %% Empty blocks can prevent further jump optimizations.
    eliminate_moves(Is, D, Acc);
eliminate_moves([I|Is], D0, Acc) ->
    D = update_unsafe_labels(I, D0),
    eliminate_moves(Is, D, [I|Acc]);
eliminate_moves([], _, Acc) -> reverse(Acc).

eliminate_moves_call([{'%',{var_info,{x,0},Info}}=Anno,
                      {block,BlkIs0}=Blk | Is], D, Acc0) ->
    Acc = [Anno | Acc0],
    RetType = proplists:get_value(type, Info, none),
    case beam_types:get_singleton_value(RetType) of
        {ok, Value} ->
            RegVal = {{x,0}, value_to_literal(Value)},
            BlkIs = eliminate_moves_blk(BlkIs0, RegVal),
            eliminate_moves([{block,BlkIs}|Is], D, Acc);
        error ->
            eliminate_moves(Is, D, [Blk | Acc])
    end;
eliminate_moves_call(Is, D, Acc) ->
    eliminate_moves(Is, D, Acc).

eliminate_moves_blk([{set,[Dst],[_],move}|_]=Is, {_,Dst}) ->
    Is;
eliminate_moves_blk([{set,[Dst],[Lit],move}|Is], {Dst,Lit}) ->
    %% Remove redundant 'move' instruction.
    Is;
eliminate_moves_blk([{set,[Dst],[_],move}|_]=Is, {Dst,_}) ->
    Is;
eliminate_moves_blk([{set,[_],[_],move}=I|Is], {_,_}=RegVal) ->
    [I|eliminate_moves_blk(Is, RegVal)];
eliminate_moves_blk(Is, _) -> Is.

no_fallthrough([{'%',_} | Is]) ->
    no_fallthrough(Is);
no_fallthrough([I|_]) ->
    is_unreachable_after(I).

is_proper_list(Reg, [{'%',{var_info,Reg,Info}}|_]) ->
    case proplists:get_value(type, Info) of
        #t_list{terminator=nil} ->
            true;
        _ ->
            %% Unknown type or not a proper list.
            false
    end;
is_proper_list(Reg, [{'%',{var_info,_,_}}|Is]) ->
    is_proper_list(Reg, Is);
is_proper_list(_, _) -> false.

value_to_literal([]) -> nil;
value_to_literal(A) when is_atom(A) -> {atom,A};
value_to_literal(F) when is_float(F) -> {float,F};
value_to_literal(I) when is_integer(I) -> {integer,I};
value_to_literal(Other) -> {literal,Other}.

update_value_dict([Lit,{f,Lbl}|T], Reg, D0) ->
    D = case D0 of
            #{Lbl:=unsafe} -> D0;
            #{Lbl:={Reg,Lit}} -> D0;
            #{Lbl:=_} -> D0#{Lbl:=unsafe};
            #{} -> D0#{Lbl=>{Reg,Lit}}
        end,
    update_value_dict(T, Reg, D);
update_value_dict([], _, D) -> D.

add_unsafe_label(L, D) ->
    D#{L=>unsafe}.

update_unsafe_labels(I, D) ->
    Ls = instr_labels(I),
    update_unsafe_labels_1(Ls, D).

update_unsafe_labels_1([L|Ls], D) ->
    update_unsafe_labels_1(Ls, D#{L=>unsafe});
update_unsafe_labels_1([], D) -> D.

%%%
%%% It seems to be useful to insert extra labels after certain
%%% test instructions. This used to be done by beam_dead.
%%%

insert_labels([{test,Op,_,_}=I|Is], Lc, Acc) ->
    Useful = case Op of
                 is_lt -> true;
                 is_ge -> true;
                 is_eq_exact -> true;
                 is_ne_exact -> true;
                 _ -> false
             end,
    case Useful of
	false -> insert_labels(Is, Lc, [I|Acc]);
	true -> insert_labels(Is, Lc+1, [{label,Lc},I|Acc])
    end;
insert_labels([I|Is], Lc, Acc) ->
    insert_labels(Is, Lc, [I|Acc]);
insert_labels([], Lc, Acc) ->
    {reverse(Acc),Lc}.

%%%
%%% (1) We try to share the code for identical code segments by replacing all
%%% occurrences except the last with jumps to the last occurrence.
%%%
%%% We must not share code that raises an exception from outside a
%%% try/catch block with code inside a try/catch block and vice versa,
%%% because beam_validator will probably flag it as unsafe
%%% (ambiguous_catch_try_state). The same goes for a plain catch.
%%%

share(Is0) ->
    Is1 = eliminate_fallthroughs(Is0, []),
    Is2 = find_fixpoint(fun(Is) ->
                                share_1(Is)
                        end, Is1),
    reverse(Is2).

share_1(Is) ->
    Safe = classify_labels(Is),
    share_1(Is, Safe, #{}, #{}, [], []).

%% Note that we examine the instructions in reverse execution order.
share_1([{label,L}=Lbl|Is], Safe, Dict0, Lbls0, [_|_]=Seq0, Acc) ->
    Seq = maybe_add_scope(Seq0, L, Safe),

    %% If there are try/catch or catch instructions in this function,
    %% any line instructions in the sequence now include a scope.
    case Dict0 of
        #{Seq := Label} ->
            %% This sequence of instructions has been seen previously.
            %% The scope identifiers added to line instructions ensure
            %% that two sequence will not be equal unless sharing is
            %% also safe.
            Lbls = Lbls0#{L => Label},
            share_1(Is, Safe, Dict0, Lbls, [],
                    [[Lbl,{jump,{f,Label}}]|Acc]);
        #{} ->
            %% This is first time we have seen this sequence of instructions.
            %% Find out whether it is safe to share the sequence.
            case (map_size(Safe) =:= 0 orelse
                  is_shareable(Seq)) andalso
                unambigous_exit_call(Seq)
            of
                true ->
                    %% Either this function does not contain any try/catch
                    %% instructions, in which case it is always safe to share
                    %% exception-raising instructions such as if_end and
                    %% case_end, or it this sequence does not include
                    %% any problematic instructions.
                    Dict = Dict0#{Seq => L},
                    share_1(Is, Safe, Dict, Lbls0, [], [[Lbl|Seq]|Acc]);
                false ->
                    %% The sequence includes an inappropriate instruction
                    %% that may case beam_validator to complain about
                    %% an ambiguous try/catch state.
                    share_1(Is, Safe, Dict0, Lbls0, [], [[Lbl|Seq]|Acc])
            end
    end;
share_1([{func_info,_,_,_}|_]=Is0, _Safe, _, Lbls, [], Acc0) ->
    %% Replace jumps to jumps with a jump to the final destination
    %% (jump threading). This optimization is done in the main
    %% optimization pass of this module, but we do it here too because
    %% it can give more opportunities for sharing code.
    F = case Lbls =:= #{} of
            true ->
                fun lists:reverse/2;
            false ->
                fun(Is, Acc) ->
                        beam_utils:replace_labels(Is, Acc, Lbls,
                                                  fun(Old) -> Old end)
                end
        end,
    foldl(F, Is0, Acc0);
share_1([{'catch',_,_}=I|Is], Safe, Dict, _Lbls0, Seq, Acc) ->
    %% Disable the jump threading optimization because it may be unsafe.
    share_1(Is, Safe, Dict, #{}, [I|Seq], Acc);
share_1([{'try',_,_}=I|Is], Safe, Dict, _Lbls, Seq, Acc) ->
    %% Disable the jump threading optimization because it may be unsafe.
    share_1(Is, Safe, Dict, #{}, [I|Seq], Acc);
share_1([{jump,{f,To}}=I,{label,From}=Lbl|Is], Safe, Dict0, Lbls0, _Seq, Acc) ->
    Lbls = Lbls0#{From => To},
    share_1(Is, Safe, Dict0, Lbls, [], [[Lbl,I]|Acc]);
share_1([I|Is], Safe, Dict, Lbls, Seq, Acc) ->
    case is_unreachable_after(I) of
	false ->
	    share_1(Is, Safe, Dict, Lbls, [I|Seq], Acc);
	true ->
	    share_1(Is, Safe, Dict, Lbls, [I], Acc)
    end.

unambigous_exit_call([{call_ext,A,{extfunc,M,F,A}}|Is]) ->
    case erl_bifs:is_exit_bif(M, F, A) of
        true ->
            %% beam_validator requires that the size of the stack
            %% frame is unambigously known when a function is called.
            %%
            %% That means that we must be careful when sharing function
            %% calls.
            %%
            %% In practice, it seems that only exit BIFs can
            %% potentially be shared in an unsafe way, and only in
            %% rare circumstances. (See the undecided_allocation_1/1
            %% function in beam_jump_SUITE.)
            %%
            %% To ensure that the frame size is unambigous, only allow
            %% sharing of a call to exit BIFs if the call is followed
            %% by an instruction that indicates the size of the stack
            %% frame (that is almost always the case in real-world
            %% code).
            case Is of
                [{deallocate,_}|_] -> true;
                [return] -> true;
                _ -> false
            end;
        false ->
            true
    end;
unambigous_exit_call([_|Is]) ->
    unambigous_exit_call(Is);
unambigous_exit_call([]) -> true.

%% If the label has a scope set, assign it to any line instruction
%% in the sequence.
maybe_add_scope(Seq, L, Safe) ->
    case Safe of
        #{L := Scope} -> add_scope(Seq, Scope);
        #{} -> Seq
    end.

add_scope([{line,Loc}=I|Is], Scope) ->
    case keymember(scope, 1, Loc) of
        false ->
            [{line,[{scope,Scope}|Loc]}|add_scope(Is, Scope)];
        true ->
            [I|add_scope(Is, Scope)]
    end;
add_scope([I|Is], Scope) ->
    [I|add_scope(Is, Scope)];
add_scope([], _Scope) -> [].

is_shareable([build_stacktrace|_]) -> false;
is_shareable([{case_end,_}|_]) -> false;
is_shareable([{'catch',_,_}|_]) -> false;
is_shareable([{catch_end,_}|_]) -> false;
is_shareable([if_end|_]) -> false;
is_shareable([{'try',_,_}|_]) -> false;
is_shareable([{try_case,_}|_]) -> false;
is_shareable([{try_end,_}|_]) -> false;
is_shareable([_|Is]) -> is_shareable(Is);
is_shareable([]) -> true.

%%
%% Classify labels according to where the instructions that branch to
%% the labels are located. Each label is assigned a set of scope
%% identifers (but usually just one). If two labels have different
%% scope identfiers, sharing a sequence that raises an exception
%% between the labels may not be safe, because one label is inside a
%% try/catch, and the other label is outside. Note that we don't care
%% where the labels themselves are located, only from where the
%% branches to them are located.
%%
%% If there is more than one scope in the function (that is, if there
%% try/catch or catch in the function), the scope identifiers will be
%% added to the line instructions. Recording the scope in the line
%% instructions makes beam_jump idempotent, ensuring that beam_jump
%% will not do any unsafe optimizations when when compiling from a .S
%% file.
%%

classify_labels(Is) ->
    classify_labels(Is, 0, #{}).

classify_labels([{'catch',_,_}|Is], Scope, Safe) ->
    classify_labels(Is, Scope+1, Safe);
classify_labels([{catch_end,_}|Is], Scope, Safe) ->
    classify_labels(Is, Scope+1, Safe);
classify_labels([{'try',_,_}|Is], Scope, Safe) ->
    classify_labels(Is, Scope+1, Safe);
classify_labels([{'try_end',_}|Is], Scope, Safe) ->
    classify_labels(Is, Scope+1, Safe);
classify_labels([{'try_case',_}|Is], Scope, Safe) ->
    classify_labels(Is, Scope+1, Safe);
classify_labels([{'try_case_end',_}|Is], Scope, Safe) ->
    classify_labels(Is, Scope+1, Safe);
classify_labels([I|Is], Scope, Safe0) ->
    Labels = instr_labels(I),
    Safe = foldl(fun(L, A) ->
                         case A of
                             #{L := [Scope]} -> A;
                             #{L := Other} -> A#{L => ordsets:add_element(Scope, Other)};
                             #{} -> A#{L => [Scope]}
                         end
                 end, Safe0, Labels),
    classify_labels(Is, Scope, Safe);
classify_labels([], Scope, Safe) ->
    case Scope of
        0 ->
            %% No try/catch or catch in this function. We don't
            %% need the collected information.
            #{};
        _ ->
            Safe
    end.

%% Eliminate all fallthroughs. Return the result reversed.

eliminate_fallthroughs([{label,L}=Lbl|Is], [I|_]=Acc) ->
    case is_unreachable_after(I) of
	false ->
	    %% Eliminate fallthrough.
	    eliminate_fallthroughs(Is, [Lbl,{jump,{f,L}}|Acc]);
	true ->
	    eliminate_fallthroughs(Is, [Lbl|Acc])
    end;
eliminate_fallthroughs([I|Is], Acc) ->
    eliminate_fallthroughs(Is, [I|Acc]);
eliminate_fallthroughs([], Acc) -> Acc.

%%%
%%% (2) Move short code sequences ending in an instruction that causes an exit
%%% to the end of the function.
%%%
%%% Implementation note: Since share/1 eliminated fallthroughs to labels,
%%% we don't have to test whether instructions before labels may fail through.
%%%
move(Is) ->
    move_1(Is, [], []).

move_1([I|Is], Ends, Acc0) ->
    case is_exit_instruction(I) of
	false ->
	    move_1(Is, Ends, [I|Acc0]);
	true ->
	    case extract_seq(Acc0, [I]) of
		no ->
		    move_1(Is, Ends, [I|Acc0]);
		{yes,End,Acc} ->
		    move_1(Is, [End|Ends], Acc)
	    end
    end;
move_1([], Ends, Acc) -> reverse(Acc, lists:append(reverse(Ends))).

extract_seq([{line,_}=Line|Is], Acc) ->
    extract_seq(Is, [Line|Acc]);
extract_seq([{block,_}=Bl|Is], Acc) ->
    extract_seq_1(Is, [Bl|Acc]);
extract_seq([{label,_}|_]=Is, Acc) ->
    extract_seq_1(Is, Acc);
extract_seq(_, _) -> no.

extract_seq_1([{line,_}=Line|Is], Acc) ->
    extract_seq_1(Is, [Line|Acc]);
extract_seq_1([{label,_},{func_info,_,_,_}|_], _) ->
    no;
extract_seq_1([{label,Lbl},{jump,{f,Lbl}}|_], _) ->
    %% Don't move a sequence which have a fallthrough entering it.
    no;
extract_seq_1([{label,_}=Lbl|Is], Acc) ->
    {yes,[Lbl|Acc],Is};
extract_seq_1(_, _) -> no.

%%%
%%% (3) (4) (5) (6) Jump and unreachable code optimizations.
%%%

-record(st,
	{
	  entry :: beam_asm:label(), %Entry label (must not be moved).
	  replace :: #{beam_asm:label() := beam_asm:label()}, %Labels to replace.
	  labels :: sets:set()         %Set of referenced labels.
	}).

opt(Is0, CLabel) ->
    find_fixpoint(fun(Is) ->
			  Lbls = initial_labels(Is),
			  St = #st{entry=CLabel,replace=#{},labels=Lbls},
			  opt(Is, [], St)
		  end, Is0).

find_fixpoint(OptFun, Is0) ->
    case OptFun(Is0) of
	Is0 -> Is0;
	Is -> find_fixpoint(OptFun, Is)
    end.

opt([{test,_,{f,L}=Lbl,_}=I|[{jump,{f,L}}|_]=Is], Acc, St) ->
    %% We have
    %%    Test Label Ops
    %%    jump Label
    %% The test instruction is not needed if the test is pure
    %% (it modifies neither registers nor bit syntax state).
    case beam_utils:is_pure_test(I) of
	false ->
	    %% Test is not pure; we must keep it.
	    opt(Is, [I|Acc], label_used(Lbl, St));
	true ->
	    %% The test is pure and its failure label is the same
	    %% as in the jump that follows -- thus it is not needed.
	    opt(Is, Acc, St)
    end;
opt([{test,Test0,{f,L}=Lbl,Ops}=I|[{jump,To}|Is]=Is0], Acc, St) ->
    case is_label_defined(Is, L) of
	false ->
	    opt(Is0, [I|Acc], label_used(Lbl, St));
	true ->
	    case invert_test(Test0) of
		not_possible ->
		    opt(Is0, [I|Acc], label_used(Lbl, St));
		Test ->
		    %% Invert the test and remove the jump.
		    opt([{test,Test,To,Ops}|Is], Acc, St)
	    end
    end;
opt([{test,_,{f,_}=Lbl,_}=I|Is], Acc, St) ->
    opt(Is, [I|Acc], label_used(Lbl, St));
opt([{test,_,{f,_}=Lbl,_,_,_}=I|Is], Acc, St) ->
    opt(Is, [I|Acc], label_used(Lbl, St));
opt([{select,_,_R,Fail,Vls}=I|Is], Acc, St) ->
    skip_unreachable(Is, [I|Acc], label_used([Fail|Vls], St));
opt([{label,From}=I,{label,To}|Is], Acc, #st{replace=Replace}=St) ->
    opt([I|Is], Acc, St#st{replace=Replace#{To => From}});
opt([{jump,{f,_}=X}|[{label,_},{jump,X}|_]=Is], Acc, St) ->
    opt(Is, Acc, St);
opt([{jump,{f,Lbl}}|[{label,Lbl}|_]=Is], Acc, St) ->
    opt(Is, Acc, St);
opt([{jump,{f,L}=Lbl}=I|Is], Acc0, St0) ->
    %% Replace all labels before this jump instruction into the
    %% location of the jump's target.
    {Acc,St} = collect_labels(Acc0, L, St0),
    skip_unreachable(Is, [I|Acc], label_used(Lbl, St));
%% Optimization: quickly handle some common instructions that don't
%% have any failure labels and where is_unreachable_after(I) =:= false.
opt([{block,_}=I|Is], Acc, St) ->
    opt(Is, [I|Acc], St);
opt([{call,_,_}=I|Is], Acc, St) ->
    opt(Is, [I|Acc], St);
opt([{deallocate,_}=I|Is], Acc, St) ->
    opt(Is, [I|Acc], St);
%% All other instructions.
opt([I|Is], Acc, #st{labels=Used0}=St0) ->
    Used = ulbl(I, Used0),
    St = St0#st{labels=Used},
    case is_unreachable_after(I) of
	true  -> skip_unreachable(Is, [I|Acc], St);
	false -> opt(Is, [I|Acc], St)
    end;
opt([], Acc, #st{replace=Replace0}) when Replace0 =/= #{} ->
    Replace = normalize_replace(maps:to_list(Replace0), Replace0, []),
    beam_utils:replace_labels(Acc, [], Replace, fun(Old) -> Old end);
opt([], Acc, #st{replace=Replace}) when Replace =:= #{} ->
    reverse(Acc).

normalize_replace([{From,To0}|Rest], Replace, Acc) ->
    case Replace of
        #{To0 := To} ->
            normalize_replace([{From,To}|Rest], Replace, Acc);
        _ ->
            normalize_replace(Rest, Replace, [{From,To0}|Acc])
    end;
normalize_replace([], _Replace, Acc) ->
    maps:from_list(Acc).

collect_labels(Is, Label, #st{entry=Entry,replace=Replace} = St) ->
    collect_labels_1(Is, Label, Entry, Replace, St).

collect_labels_1([{label,Entry}|_]=Is, _Label, Entry, Acc, St) ->
    %% Never move the entry label.
    {Is,St#st{replace=Acc}};
collect_labels_1([{label,L}|Is], Label, Entry, Acc, St) ->
    collect_labels_1(Is, Label, Entry, Acc#{L => Label}, St);
collect_labels_1(Is, _Label, _Entry, Acc, St) ->
    {Is,St#st{replace=Acc}}.

%% label_defined(Is, Label) -> true | false.
%%  Test whether the label Label is defined at the start of the instruction
%%  sequence, possibly preceeded by other label definitions.
%%
is_label_defined([{label,L}|_], L) -> true;
is_label_defined([{label,_}|Is], L) -> is_label_defined(Is, L);
is_label_defined(_, _) -> false.

%% invert_test(Test0) -> not_possible | Test

invert_test(is_ge) ->       is_lt;
invert_test(is_lt) ->       is_ge;
invert_test(is_eq) ->       is_ne;
invert_test(is_ne) ->       is_eq;
invert_test(is_eq_exact) -> is_ne_exact;
invert_test(is_ne_exact) -> is_eq_exact;
invert_test(_) ->           not_possible.

%% skip_unreachable([Instruction], St).
%%  Remove all instructions (including definitions of labels
%%  that have not been referenced yet) up to the next
%%  referenced label, then call opt/3 to optimize the rest
%%  of the instruction sequence.
%%
skip_unreachable([{label,L}|_Is]=Is0, [{jump,{f,L}}|Acc], St) ->
    opt(Is0, Acc, St);
skip_unreachable([{label,L}|Is]=Is0, Acc, St) ->
    case is_label_used(L, St) of
	true  -> opt(Is0, Acc, St);
	false -> skip_unreachable(Is, Acc, St)
    end;
skip_unreachable([_|Is], Acc, St) ->
    skip_unreachable(Is, Acc, St);
skip_unreachable([], Acc, St) ->
    opt([], Acc, St).

%% Add one or more label to the set of used labels.

label_used({f,L}, St) -> St#st{labels=sets:add_element(L,St#st.labels)};
label_used([H|T], St0) -> label_used(T, label_used(H, St0));
label_used([], St) -> St;
label_used(_Other, St) -> St.

%% Test if label is used.

is_label_used(L, St) ->
    sets:is_element(L, St#st.labels).

%% is_unreachable_after(Instruction) -> boolean()
%%  Test whether the code after Instruction is unreachable.

-spec is_unreachable_after(instruction()) -> boolean().

is_unreachable_after({func_info,_M,_F,_A}) -> true;
is_unreachable_after(return) -> true;
is_unreachable_after({jump,_Lbl}) -> true;
is_unreachable_after({select,_What,_R,_Lbl,_Cases}) -> true;
is_unreachable_after({loop_rec_end,_}) -> true;
is_unreachable_after({wait,_}) -> true;
is_unreachable_after(I) -> is_exit_instruction(I).

%% is_exit_instruction(Instruction) -> boolean()
%%  Test whether the instruction Instruction always
%%  causes an exit/failure.

-spec is_exit_instruction(instruction()) -> boolean().

is_exit_instruction(if_end) -> true;
is_exit_instruction({case_end,_}) -> true;
is_exit_instruction({try_case_end,_}) -> true;
is_exit_instruction({badmatch,_}) -> true;
is_exit_instruction(_) -> false.

%% remove_unused_labels(Instructions0) -> Instructions
%%  Remove all unused labels. Also remove unreachable
%%  instructions following labels that are removed.

-spec remove_unused_labels([instruction()]) -> [instruction()].

remove_unused_labels(Is) ->
    Used0 = initial_labels(Is),
    Used = foldl(fun ulbl/2, Used0, Is),
    rem_unused(Is, Used, []).

rem_unused([{label,Lbl}=I|Is0], Used, [Prev|_]=Acc) ->
    case sets:is_element(Lbl, Used) of
	false ->
	    Is = case is_unreachable_after(Prev) of
		     true -> drop_upto_label(Is0);
		     false -> Is0
		 end,
	    rem_unused(Is, Used, Acc);
	true ->
	    rem_unused(Is0, Used, [I|Acc])
    end;
rem_unused([I|Is], Used, Acc) ->
    rem_unused(Is, Used, [I|Acc]);
rem_unused([], _, Acc) -> reverse(Acc).

initial_labels(Is) ->
    initial_labels(Is, []).

initial_labels([{line,_}|Is], Acc) ->
    initial_labels(Is, Acc);
initial_labels([{label,Lbl}|Is], Acc) ->
    initial_labels(Is, [Lbl|Acc]);
initial_labels([{func_info,_,_,_},{label,Lbl}|_], Acc) ->
    sets:from_list([Lbl|Acc], [{version, 2}]).

drop_upto_label([{label,_}|_]=Is) -> Is;
drop_upto_label([_|Is]) -> drop_upto_label(Is);
drop_upto_label([]) -> [].

%% unshare([Instruction]) -> [Instruction].
%%  Replace a jump to a return sequence (a `return` instruction
%%  optionally preced by a `deallocate` instruction) with the return
%%  sequence. This always saves execution time and may also save code
%%  space (depending on the architecture). Eliminating `jump`
%%  instructions also gives beam_trim more opportunities to trim the
%%  stack.

unshare(Is) ->
    Short = unshare_collect_short(Is, #{}),
    unshare_short(Is, Short).

unshare_collect_short([{label,L},return|Is], Map) ->
    unshare_collect_short(Is, Map#{L=>[return]});
unshare_collect_short([{label,L},{deallocate,_}=D,return|Is], Map) ->
    %% `deallocate` and `return` are combined into one instruction by
    %% the loader.
    unshare_collect_short(Is, Map#{L=>[D,return]});
unshare_collect_short([_|Is], Map) ->
    unshare_collect_short(Is, Map);
unshare_collect_short([], Map) -> Map.

unshare_short([{jump,{f,F}}=I|Is], Map) ->
    case Map of
        #{F:=Seq} ->
            Seq ++ unshare_short(Is, Map);
        #{} ->
            [I|unshare_short(Is, Map)]
    end;
unshare_short([I|Is], Map) ->
    [I|unshare_short(Is, Map)];
unshare_short([], _Map) -> [].

%% ulbl(Instruction, UsedCerlSet) -> UsedCerlSet'
%%  Update the cerl_set UsedCerlSet with any function-local labels
%%  (i.e. not with labels in call instructions) referenced by
%%  the instruction Instruction.
%%
%%  NOTE: This function does NOT look for labels inside blocks.

ulbl(I, Used) ->
    case instr_labels(I) of
        [] ->
            Used;
        [Lbl] ->
            sets:add_element(Lbl, Used);
        [_|_]=L ->
            ulbl_list(L, Used)
    end.

ulbl_list([L|Ls], Used) ->
    ulbl_list(Ls, sets:add_element(L, Used));
ulbl_list([], Used) -> Used.

-spec instr_labels(Instruction) -> Labels when
      Instruction :: instruction(),
      Labels :: [beam_asm:label()].

instr_labels({test,_,Fail,_}) ->
    do_instr_labels(Fail);
instr_labels({test,_,Fail,_,_,_}) ->
    do_instr_labels(Fail);
instr_labels({select,_,_,Fail,Vls}) ->
    do_instr_labels_list(Vls, do_instr_labels(Fail));
instr_labels({'try',_,Lbl}) ->
    do_instr_labels(Lbl);
instr_labels({'catch',_,Lbl}) ->
    do_instr_labels(Lbl);
instr_labels({jump,Lbl}) ->
    do_instr_labels(Lbl);
instr_labels({loop_rec,Lbl,_}) ->
    do_instr_labels(Lbl);
instr_labels({loop_rec_end,Lbl}) ->
    do_instr_labels(Lbl);
instr_labels({wait,Lbl}) ->
    do_instr_labels(Lbl);
instr_labels({wait_timeout,Lbl,_To}) ->
    do_instr_labels(Lbl);
instr_labels({bif,_Name,Lbl,_As,_R}) ->
    do_instr_labels(Lbl);
instr_labels({gc_bif,_Name,Lbl,_Live,_As,_R}) ->
    do_instr_labels(Lbl);
instr_labels({bs_init,Lbl,_,_,_,_}) ->
    do_instr_labels(Lbl);
instr_labels({bs_put,Lbl,_,_}) ->
    do_instr_labels(Lbl);
instr_labels({put_map,Lbl,_Op,_Src,_Dst,_Live,_List}) ->
    do_instr_labels(Lbl);
instr_labels({get_map_elements,Lbl,_Src,_List}) ->
    do_instr_labels(Lbl);
instr_labels({bs_start_match4,Fail,_,_,_}) ->
    case Fail of
        {f,L} -> [L];
        {atom,_} -> []
    end;
instr_labels(_) ->
    [].

do_instr_labels({f,0}) -> [];
do_instr_labels({f,F}) -> [F].

do_instr_labels_list([{f,F}|T], Acc) ->
    do_instr_labels_list(T, [F|Acc]);
do_instr_labels_list([_|T], Acc) ->
    do_instr_labels_list(T, Acc);
do_instr_labels_list([], Acc) -> Acc.
