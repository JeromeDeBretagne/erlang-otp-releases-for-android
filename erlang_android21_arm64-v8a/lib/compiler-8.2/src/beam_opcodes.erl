-module(beam_opcodes).
%%  Warning: Do not edit this file.
%%  Auto-generated by 'beam_makeops'.

-export([format_number/0]).
-export([opcode/2,opname/1]).

-spec format_number() -> 0.
format_number() -> 0.

-spec opcode(atom(), 0..8) -> 1..180.
opcode(label, 1) -> 1;
opcode(func_info, 3) -> 2;
opcode(int_code_end, 0) -> 3;
opcode(call, 2) -> 4;
opcode(call_last, 3) -> 5;
opcode(call_only, 2) -> 6;
opcode(call_ext, 2) -> 7;
opcode(call_ext_last, 3) -> 8;
opcode(bif0, 2) -> 9;
opcode(bif1, 4) -> 10;
opcode(bif2, 5) -> 11;
opcode(allocate, 2) -> 12;
opcode(allocate_heap, 3) -> 13;
opcode(allocate_zero, 2) -> 14;
opcode(allocate_heap_zero, 3) -> 15;
opcode(test_heap, 2) -> 16;
opcode(init, 1) -> 17;
opcode(deallocate, 1) -> 18;
opcode(return, 0) -> 19;
opcode(send, 0) -> 20;
opcode(remove_message, 0) -> 21;
opcode(timeout, 0) -> 22;
opcode(loop_rec, 2) -> 23;
opcode(loop_rec_end, 1) -> 24;
opcode(wait, 1) -> 25;
opcode(wait_timeout, 2) -> 26;
%%opcode(m_plus, 4) -> 27;
%%opcode(m_minus, 4) -> 28;
%%opcode(m_times, 4) -> 29;
%%opcode(m_div, 4) -> 30;
%%opcode(int_div, 4) -> 31;
%%opcode(int_rem, 4) -> 32;
%%opcode(int_band, 4) -> 33;
%%opcode(int_bor, 4) -> 34;
%%opcode(int_bxor, 4) -> 35;
%%opcode(int_bsl, 4) -> 36;
%%opcode(int_bsr, 4) -> 37;
%%opcode(int_bnot, 3) -> 38;
opcode(is_lt, 3) -> 39;
opcode(is_ge, 3) -> 40;
opcode(is_eq, 3) -> 41;
opcode(is_ne, 3) -> 42;
opcode(is_eq_exact, 3) -> 43;
opcode(is_ne_exact, 3) -> 44;
opcode(is_integer, 2) -> 45;
opcode(is_float, 2) -> 46;
opcode(is_number, 2) -> 47;
opcode(is_atom, 2) -> 48;
opcode(is_pid, 2) -> 49;
opcode(is_reference, 2) -> 50;
opcode(is_port, 2) -> 51;
opcode(is_nil, 2) -> 52;
opcode(is_binary, 2) -> 53;
%%opcode(is_constant, 2) -> 54;
opcode(is_list, 2) -> 55;
opcode(is_nonempty_list, 2) -> 56;
opcode(is_tuple, 2) -> 57;
opcode(test_arity, 3) -> 58;
opcode(select_val, 3) -> 59;
opcode(select_tuple_arity, 3) -> 60;
opcode(jump, 1) -> 61;
opcode('catch', 2) -> 62;
opcode(catch_end, 1) -> 63;
opcode(move, 2) -> 64;
opcode(get_list, 3) -> 65;
opcode(get_tuple_element, 3) -> 66;
opcode(set_tuple_element, 3) -> 67;
%%opcode(put_string, 3) -> 68;
opcode(put_list, 3) -> 69;
%%opcode(put_tuple, 2) -> 70;
%%opcode(put, 1) -> 71;
opcode(badmatch, 1) -> 72;
opcode(if_end, 0) -> 73;
opcode(case_end, 1) -> 74;
opcode(call_fun, 1) -> 75;
%%opcode(make_fun, 3) -> 76;
opcode(is_function, 2) -> 77;
opcode(call_ext_only, 2) -> 78;
%%opcode(bs_start_match, 2) -> 79;
%%opcode(bs_get_integer, 5) -> 80;
%%opcode(bs_get_float, 5) -> 81;
%%opcode(bs_get_binary, 5) -> 82;
%%opcode(bs_skip_bits, 4) -> 83;
%%opcode(bs_test_tail, 2) -> 84;
%%opcode(bs_save, 1) -> 85;
%%opcode(bs_restore, 1) -> 86;
%%opcode(bs_init, 2) -> 87;
%%opcode(bs_final, 2) -> 88;
opcode(bs_put_integer, 5) -> 89;
opcode(bs_put_binary, 5) -> 90;
opcode(bs_put_float, 5) -> 91;
opcode(bs_put_string, 2) -> 92;
%%opcode(bs_need_buf, 1) -> 93;
opcode(fclearerror, 0) -> 94;
opcode(fcheckerror, 1) -> 95;
opcode(fmove, 2) -> 96;
opcode(fconv, 2) -> 97;
opcode(fadd, 4) -> 98;
opcode(fsub, 4) -> 99;
opcode(fmul, 4) -> 100;
opcode(fdiv, 4) -> 101;
opcode(fnegate, 3) -> 102;
opcode(make_fun2, 1) -> 103;
opcode('try', 2) -> 104;
opcode(try_end, 1) -> 105;
opcode(try_case, 1) -> 106;
opcode(try_case_end, 1) -> 107;
opcode(raise, 2) -> 108;
opcode(bs_init2, 6) -> 109;
%%opcode(bs_bits_to_bytes, 3) -> 110;
opcode(bs_add, 5) -> 111;
opcode(apply, 1) -> 112;
opcode(apply_last, 2) -> 113;
opcode(is_boolean, 2) -> 114;
opcode(is_function2, 3) -> 115;
%%opcode(bs_start_match2, 5) -> 116;
opcode(bs_get_integer2, 7) -> 117;
opcode(bs_get_float2, 7) -> 118;
opcode(bs_get_binary2, 7) -> 119;
opcode(bs_skip_bits2, 5) -> 120;
opcode(bs_test_tail2, 3) -> 121;
%%opcode(bs_save2, 2) -> 122;
%%opcode(bs_restore2, 2) -> 123;
opcode(gc_bif1, 5) -> 124;
opcode(gc_bif2, 6) -> 125;
%%opcode(bs_final2, 2) -> 126;
%%opcode(bs_bits_to_bytes2, 2) -> 127;
%%opcode(put_literal, 2) -> 128;
opcode(is_bitstr, 2) -> 129;
%%opcode(bs_context_to_binary, 1) -> 130;
opcode(bs_test_unit, 3) -> 131;
opcode(bs_match_string, 4) -> 132;
opcode(bs_init_writable, 0) -> 133;
opcode(bs_append, 8) -> 134;
opcode(bs_private_append, 6) -> 135;
opcode(trim, 2) -> 136;
opcode(bs_init_bits, 6) -> 137;
opcode(bs_get_utf8, 5) -> 138;
opcode(bs_skip_utf8, 4) -> 139;
opcode(bs_get_utf16, 5) -> 140;
opcode(bs_skip_utf16, 4) -> 141;
opcode(bs_get_utf32, 5) -> 142;
opcode(bs_skip_utf32, 4) -> 143;
opcode(bs_utf8_size, 3) -> 144;
opcode(bs_put_utf8, 3) -> 145;
opcode(bs_utf16_size, 3) -> 146;
opcode(bs_put_utf16, 3) -> 147;
opcode(bs_put_utf32, 3) -> 148;
opcode(on_load, 0) -> 149;
opcode(recv_mark, 1) -> 150;
opcode(recv_set, 1) -> 151;
opcode(gc_bif3, 7) -> 152;
opcode(line, 1) -> 153;
opcode(put_map_assoc, 5) -> 154;
opcode(put_map_exact, 5) -> 155;
opcode(is_map, 2) -> 156;
opcode(has_map_fields, 3) -> 157;
opcode(get_map_elements, 3) -> 158;
opcode(is_tagged_tuple, 4) -> 159;
opcode(build_stacktrace, 0) -> 160;
opcode(raw_raise, 0) -> 161;
opcode(get_hd, 2) -> 162;
opcode(get_tl, 2) -> 163;
opcode(put_tuple2, 2) -> 164;
opcode(bs_get_tail, 3) -> 165;
opcode(bs_start_match3, 4) -> 166;
opcode(bs_get_position, 3) -> 167;
opcode(bs_set_position, 2) -> 168;
opcode(swap, 2) -> 169;
opcode(bs_start_match4, 4) -> 170;
opcode(make_fun3, 3) -> 171;
opcode(init_yregs, 1) -> 172;
opcode(recv_marker_bind, 2) -> 173;
opcode(recv_marker_clear, 1) -> 174;
opcode(recv_marker_reserve, 1) -> 175;
opcode(recv_marker_use, 1) -> 176;
opcode(bs_create_bin, 6) -> 177;
opcode(call_fun2, 3) -> 178;
opcode(nif_start, 0) -> 179;
opcode(badrecord, 1) -> 180;
opcode(Name, Arity) -> erlang:error(badarg, [Name,Arity]).

-spec opname(1..180) -> {atom(),0..8}.
opname(1) -> {label,1};
opname(2) -> {func_info,3};
opname(3) -> {int_code_end,0};
opname(4) -> {call,2};
opname(5) -> {call_last,3};
opname(6) -> {call_only,2};
opname(7) -> {call_ext,2};
opname(8) -> {call_ext_last,3};
opname(9) -> {bif0,2};
opname(10) -> {bif1,4};
opname(11) -> {bif2,5};
opname(12) -> {allocate,2};
opname(13) -> {allocate_heap,3};
opname(14) -> {allocate_zero,2};
opname(15) -> {allocate_heap_zero,3};
opname(16) -> {test_heap,2};
opname(17) -> {init,1};
opname(18) -> {deallocate,1};
opname(19) -> {return,0};
opname(20) -> {send,0};
opname(21) -> {remove_message,0};
opname(22) -> {timeout,0};
opname(23) -> {loop_rec,2};
opname(24) -> {loop_rec_end,1};
opname(25) -> {wait,1};
opname(26) -> {wait_timeout,2};
opname(27) -> {m_plus,4};
opname(28) -> {m_minus,4};
opname(29) -> {m_times,4};
opname(30) -> {m_div,4};
opname(31) -> {int_div,4};
opname(32) -> {int_rem,4};
opname(33) -> {int_band,4};
opname(34) -> {int_bor,4};
opname(35) -> {int_bxor,4};
opname(36) -> {int_bsl,4};
opname(37) -> {int_bsr,4};
opname(38) -> {int_bnot,3};
opname(39) -> {is_lt,3};
opname(40) -> {is_ge,3};
opname(41) -> {is_eq,3};
opname(42) -> {is_ne,3};
opname(43) -> {is_eq_exact,3};
opname(44) -> {is_ne_exact,3};
opname(45) -> {is_integer,2};
opname(46) -> {is_float,2};
opname(47) -> {is_number,2};
opname(48) -> {is_atom,2};
opname(49) -> {is_pid,2};
opname(50) -> {is_reference,2};
opname(51) -> {is_port,2};
opname(52) -> {is_nil,2};
opname(53) -> {is_binary,2};
opname(54) -> {is_constant,2};
opname(55) -> {is_list,2};
opname(56) -> {is_nonempty_list,2};
opname(57) -> {is_tuple,2};
opname(58) -> {test_arity,3};
opname(59) -> {select_val,3};
opname(60) -> {select_tuple_arity,3};
opname(61) -> {jump,1};
opname(62) -> {'catch',2};
opname(63) -> {catch_end,1};
opname(64) -> {move,2};
opname(65) -> {get_list,3};
opname(66) -> {get_tuple_element,3};
opname(67) -> {set_tuple_element,3};
opname(68) -> {put_string,3};
opname(69) -> {put_list,3};
opname(70) -> {put_tuple,2};
opname(71) -> {put,1};
opname(72) -> {badmatch,1};
opname(73) -> {if_end,0};
opname(74) -> {case_end,1};
opname(75) -> {call_fun,1};
opname(76) -> {make_fun,3};
opname(77) -> {is_function,2};
opname(78) -> {call_ext_only,2};
opname(79) -> {bs_start_match,2};
opname(80) -> {bs_get_integer,5};
opname(81) -> {bs_get_float,5};
opname(82) -> {bs_get_binary,5};
opname(83) -> {bs_skip_bits,4};
opname(84) -> {bs_test_tail,2};
opname(85) -> {bs_save,1};
opname(86) -> {bs_restore,1};
opname(87) -> {bs_init,2};
opname(88) -> {bs_final,2};
opname(89) -> {bs_put_integer,5};
opname(90) -> {bs_put_binary,5};
opname(91) -> {bs_put_float,5};
opname(92) -> {bs_put_string,2};
opname(93) -> {bs_need_buf,1};
opname(94) -> {fclearerror,0};
opname(95) -> {fcheckerror,1};
opname(96) -> {fmove,2};
opname(97) -> {fconv,2};
opname(98) -> {fadd,4};
opname(99) -> {fsub,4};
opname(100) -> {fmul,4};
opname(101) -> {fdiv,4};
opname(102) -> {fnegate,3};
opname(103) -> {make_fun2,1};
opname(104) -> {'try',2};
opname(105) -> {try_end,1};
opname(106) -> {try_case,1};
opname(107) -> {try_case_end,1};
opname(108) -> {raise,2};
opname(109) -> {bs_init2,6};
opname(110) -> {bs_bits_to_bytes,3};
opname(111) -> {bs_add,5};
opname(112) -> {apply,1};
opname(113) -> {apply_last,2};
opname(114) -> {is_boolean,2};
opname(115) -> {is_function2,3};
opname(116) -> {bs_start_match2,5};
opname(117) -> {bs_get_integer2,7};
opname(118) -> {bs_get_float2,7};
opname(119) -> {bs_get_binary2,7};
opname(120) -> {bs_skip_bits2,5};
opname(121) -> {bs_test_tail2,3};
opname(122) -> {bs_save2,2};
opname(123) -> {bs_restore2,2};
opname(124) -> {gc_bif1,5};
opname(125) -> {gc_bif2,6};
opname(126) -> {bs_final2,2};
opname(127) -> {bs_bits_to_bytes2,2};
opname(128) -> {put_literal,2};
opname(129) -> {is_bitstr,2};
opname(130) -> {bs_context_to_binary,1};
opname(131) -> {bs_test_unit,3};
opname(132) -> {bs_match_string,4};
opname(133) -> {bs_init_writable,0};
opname(134) -> {bs_append,8};
opname(135) -> {bs_private_append,6};
opname(136) -> {trim,2};
opname(137) -> {bs_init_bits,6};
opname(138) -> {bs_get_utf8,5};
opname(139) -> {bs_skip_utf8,4};
opname(140) -> {bs_get_utf16,5};
opname(141) -> {bs_skip_utf16,4};
opname(142) -> {bs_get_utf32,5};
opname(143) -> {bs_skip_utf32,4};
opname(144) -> {bs_utf8_size,3};
opname(145) -> {bs_put_utf8,3};
opname(146) -> {bs_utf16_size,3};
opname(147) -> {bs_put_utf16,3};
opname(148) -> {bs_put_utf32,3};
opname(149) -> {on_load,0};
opname(150) -> {recv_mark,1};
opname(151) -> {recv_set,1};
opname(152) -> {gc_bif3,7};
opname(153) -> {line,1};
opname(154) -> {put_map_assoc,5};
opname(155) -> {put_map_exact,5};
opname(156) -> {is_map,2};
opname(157) -> {has_map_fields,3};
opname(158) -> {get_map_elements,3};
opname(159) -> {is_tagged_tuple,4};
opname(160) -> {build_stacktrace,0};
opname(161) -> {raw_raise,0};
opname(162) -> {get_hd,2};
opname(163) -> {get_tl,2};
opname(164) -> {put_tuple2,2};
opname(165) -> {bs_get_tail,3};
opname(166) -> {bs_start_match3,4};
opname(167) -> {bs_get_position,3};
opname(168) -> {bs_set_position,2};
opname(169) -> {swap,2};
opname(170) -> {bs_start_match4,4};
opname(171) -> {make_fun3,3};
opname(172) -> {init_yregs,1};
opname(173) -> {recv_marker_bind,2};
opname(174) -> {recv_marker_clear,1};
opname(175) -> {recv_marker_reserve,1};
opname(176) -> {recv_marker_use,1};
opname(177) -> {bs_create_bin,6};
opname(178) -> {call_fun2,3};
opname(179) -> {nif_start,0};
opname(180) -> {badrecord,1};
opname(Number) -> erlang:error(badarg, [Number]).
