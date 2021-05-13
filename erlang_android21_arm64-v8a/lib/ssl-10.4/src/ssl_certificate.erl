%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2007-2020 All Rights Reserved.
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

%%----------------------------------------------------------------------
%% Purpose: Help funtions for handling certificat verification.
%% The path validation defined in ssl_handshake.erl that mainly
%% calls functions in this module is described in RFC 3280. 
%%----------------------------------------------------------------------

-module(ssl_certificate).

-include("ssl_handshake.hrl").
-include("ssl_alert.hrl").
-include("ssl_internal.hrl").
-include_lib("public_key/include/public_key.hrl"). 

-export([trusted_cert_and_paths/4,
	 certificate_chain/3,
	 certificate_chain/4,
	 file_to_certificats/2,
	 file_to_crls/2,
	 validate/3,
	 is_valid_extkey_usage/2,
	 is_valid_key_usage/2,
	 select_extension/2,
	 extensions_list/1,
	 public_key_type/1,
	 foldl_db/3
	]).
 
%%====================================================================
%% Internal application API
%%====================================================================

%%--------------------------------------------------------------------
-spec trusted_cert_and_paths([der_cert()], db_handle(), certdb_ref(), fun()) ->
				   [{der_cert() | unknown_ca | invalid_issuer | selfsigned_peer, [der_cert()]}].
%%
%% Description: Construct input to public_key:pkix_path_validation/3,
%% If the ROOT cert is not found {bad_cert, unknown_ca} will be returned
%% instead of the ROOT cert to be handled as a path validation error
%% by the verify_fun. 
%% Returns {RootCert | RootCertRelatedError, Path} 
%% Note: Path = lists:reverse(Chain) -- Root, that is on the peer cert 
%% always comes first in the chain but last in the path.
%%--------------------------------------------------------------------
trusted_cert_and_paths([Peer] = Chain,  CertDbHandle, CertDbRef, PartialChainHandler) ->
    OtpCert = public_key:pkix_decode_cert(Peer, otp),
    case public_key:pkix_is_self_signed(OtpCert) of
        true ->
            [{selfsigned_peer, [Peer]}];
        false ->
            [handle_incomplete_chain(Chain, PartialChainHandler, {unknown_ca, [Peer]},
                                     CertDbHandle, CertDbRef)]
    end;
trusted_cert_and_paths(Chain,  CertDbHandle, CertDbRef, PartialChainHandler) ->
    %% Construct possible certificate paths from the chain certificates.
    %% If the chain contains extraneous certificates there could be
    %% more than one possible path such chains might be used to phase out 
    %% an old certificate. 
    Paths = paths(Chain, CertDbHandle),
    lists:map(fun(Path) ->
                      case handle_partial_chain(Path, PartialChainHandler, CertDbHandle, CertDbRef) of
                          {unknown_ca, _} = Result ->
                              handle_incomplete_chain(Chain, 
                                                      PartialChainHandler, 
                                                      Result,
                                                      CertDbHandle, CertDbRef);
                          Result ->
                              Result
                      end
              end, Paths).
%%--------------------------------------------------------------------
-spec certificate_chain(undefined | binary() | #'OTPCertificate'{} , db_handle(), certdb_ref() | {extracted, list()}) ->
			  {error, no_cert} | {ok, der_cert() | undefined, [der_cert()]}.
%%
%% Description: Return the certificate chain to send to peer.
%%--------------------------------------------------------------------
certificate_chain(undefined, _, _) ->
    {error, no_cert};
certificate_chain(OwnCert, CertDbHandle, CertsDbRef) when is_binary(OwnCert) ->
    ErlCert = public_key:pkix_decode_cert(OwnCert, otp),
    certificate_chain(ErlCert, OwnCert, CertDbHandle, CertsDbRef, [OwnCert], []);
certificate_chain(OwnCert, CertDbHandle, CertsDbRef) ->
    DerCert = public_key:pkix_encode('OTPCertificate', OwnCert, otp),
    certificate_chain(OwnCert, DerCert, CertDbHandle, CertsDbRef, [DerCert], []).

%%--------------------------------------------------------------------
-spec certificate_chain(undefined | binary() | #'OTPCertificate'{} , db_handle(), certdb_ref() | {extracted, list()}, [der_cert()]) ->
			  {error, no_cert} | {ok, der_cert() | undefined, [der_cert()]}.
%%
%% Description: Create certificate chain with certs from 
%%--------------------------------------------------------------------
certificate_chain(Cert, CertDbHandle, CertsDbRef, Candidates) when is_binary(Cert) ->
    ErlCert = public_key:pkix_decode_cert(Cert, otp),
    certificate_chain(ErlCert, Cert, CertDbHandle, CertsDbRef, [Cert], Candidates);
certificate_chain(Cert, CertDbHandle, CertsDbRef, Candidates) ->
    DerCert = public_key:pkix_encode('OTPCertificate', Cert, otp),
    certificate_chain(Cert, DerCert, CertDbHandle, CertsDbRef, [DerCert], Candidates).
%%--------------------------------------------------------------------
-spec file_to_certificats(binary(), term()) -> [der_cert()].
%%
%% Description: Return list of DER encoded certificates.
%%--------------------------------------------------------------------
file_to_certificats(File, DbHandle) ->
    {ok, List} = ssl_manager:cache_pem_file(File, DbHandle),
    [Bin || {'Certificate', Bin, not_encrypted} <- List].

%%--------------------------------------------------------------------
-spec file_to_crls(binary(), term()) -> [der_cert()].
%%
%% Description: Return list of DER encoded certificates.
%%--------------------------------------------------------------------
file_to_crls(File, DbHandle) ->
    {ok, List} = ssl_manager:cache_pem_file(File, DbHandle),
    [Bin || {'CertificateList', Bin, not_encrypted} <- List].

%%--------------------------------------------------------------------
-spec validate(term(), {extension, #'Extension'{}} | {bad_cert, atom()} | valid | valid_peer,
	       term()) -> {valid, term()} |
			  {fail, tuple()} |
			  {unknown, term()}.
%%
%% Description:  Validates ssl/tls specific extensions
%%--------------------------------------------------------------------
validate(_,{extension, #'Extension'{extnID = ?'id-ce-extKeyUsage',
				    extnValue = KeyUse}}, UserState = #{role := Role}) ->
    case is_valid_extkey_usage(KeyUse, Role) of
	true ->
	    {valid, UserState};
	false ->
	    {fail, {bad_cert, invalid_ext_key_usage}}
    end;
validate(_, {extension, _}, UserState) ->
    {unknown, UserState};
validate(_, {bad_cert, _} = Reason, _) ->
    {fail, Reason};
validate(Cert, valid, UserState) ->
    case verify_sign(Cert, UserState) of
        true ->
            case maps:get(cert_ext, UserState, undefined) of
                undefined ->
                    {valid, UserState};
                _ ->
                    verify_cert_extensions(Cert, UserState)
            end;
        false ->
            {fail, {bad_cert, invalid_signature}}
    end;
validate(Cert, valid_peer, UserState = #{role := client, server_name := Hostname, 
                                         customize_hostname_check := Customize}) when Hostname =/= disable ->
    case verify_hostname(Hostname, Customize, Cert, UserState) of
        {valid, UserState} ->
            validate(Cert, valid, UserState);
        Error ->
            Error
    end;
validate(Cert, valid_peer, UserState) ->    
    validate(Cert, valid, UserState).

%%--------------------------------------------------------------------
-spec is_valid_key_usage(list(), term()) -> boolean().
%%
%% Description: Checks if Use is a valid key usage.
%%--------------------------------------------------------------------
is_valid_key_usage(KeyUse, Use) ->
    lists:member(Use, KeyUse).
 
%%--------------------------------------------------------------------
-spec select_extension(term(), list()) -> undefined | #'Extension'{}.
%%
%% Description: Selects the extension identified by Id if present in
%% a list of extensions.
%%--------------------------------------------------------------------
select_extension(_, []) ->
    undefined;
select_extension(Id, [#'Extension'{extnID = Id} = Extension | _]) ->
    Extension;
select_extension(Id, [_ | Extensions]) ->
    select_extension(Id, Extensions).

%%--------------------------------------------------------------------
-spec extensions_list(asn1_NOVALUE | list()) -> list().
%%
%% Description: Handles that 
%%--------------------------------------------------------------------
extensions_list(asn1_NOVALUE) ->
    [];
extensions_list(Extensions) ->
    Extensions.

%%--------------------------------------------------------------------
-spec public_key_type(term()) -> rsa | dsa | ec.
%%
%% Description:
%%--------------------------------------------------------------------
public_key_type(?'rsaEncryption') ->
    rsa;
public_key_type(?'id-dsa') ->
    dsa;
public_key_type(?'id-ecPublicKey') ->
    ec.

%%--------------------------------------------------------------------
-spec foldl_db(fun(), db_handle() | {extracted, list()}, list()) ->
 {ok, term()} | issuer_not_found.
%%
%% Description:
%%--------------------------------------------------------------------
foldl_db(IsIssuerFun, CertDbHandle, []) ->
    ssl_pkix_db:foldl(IsIssuerFun, issuer_not_found, CertDbHandle);
foldl_db(IsIssuerFun, _, [_|_] = ListDb) ->
    lists:foldl(IsIssuerFun, issuer_not_found, ListDb).

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
certificate_chain(OtpCert, BinCert, CertDbHandle, CertsDbRef, Chain, ListDb) ->
    IssuerAndSelfSigned = 
	case public_key:pkix_is_self_signed(OtpCert) of
	    true ->
		{public_key:pkix_issuer_id(OtpCert, self), true};
	    false  ->
		{public_key:pkix_issuer_id(OtpCert, other), false}
	end,
    
    case IssuerAndSelfSigned of 
	{_, true = SelfSigned} ->
	    do_certificate_chain(CertDbHandle, CertsDbRef, Chain, ignore, ignore, SelfSigned, ListDb);
	{{error, issuer_not_found}, SelfSigned} ->
	    case find_issuer(OtpCert, BinCert, CertDbHandle, CertsDbRef, ListDb) of
		{ok, {SerialNr, Issuer}} ->
		    do_certificate_chain(CertDbHandle, CertsDbRef, Chain,
					 SerialNr, Issuer, SelfSigned, ListDb);
		_ ->
		    %% Guess the the issuer must be the root
		    %% certificate. The verification of the
		    %% cert chain will fail if guess is
		    %% incorrect.
		    {ok, undefined, lists:reverse(Chain)}
	    end;
	{{ok, {SerialNr, Issuer}}, SelfSigned} -> 
	    do_certificate_chain(CertDbHandle, CertsDbRef, Chain, SerialNr, Issuer, SelfSigned, ListDb)
    end.
  
do_certificate_chain(_, _, [RootCert | _] = Chain, _, _, true, _) ->	  
    {ok, RootCert, lists:reverse(Chain)};		      

do_certificate_chain(CertDbHandle, CertsDbRef, Chain, SerialNr, Issuer, _, ListDb) ->
    case ssl_manager:lookup_trusted_cert(CertDbHandle, CertsDbRef,
						SerialNr, Issuer) of
	{ok, {IssuerCert, ErlCert}} ->
	    ErlCert = public_key:pkix_decode_cert(IssuerCert, otp),
	    certificate_chain(ErlCert, IssuerCert, 
			      CertDbHandle, CertsDbRef, [IssuerCert | Chain], ListDb);
	_ ->
	    %% The trusted cert may be obmitted from the chain as the
	    %% counter part needs to have it anyway to be able to
	    %% verify it.
	    {ok, undefined, lists:reverse(Chain)}		      
    end.


find_issuer(OtpCert, BinCert, CertDbHandle, CertsDbRef, ListDb) ->
    IsIssuerFun =
	fun({_Key, {_Der, #'OTPCertificate'{} = ErlCertCandidate}}, Acc) ->
		case public_key:pkix_is_issuer(OtpCert, ErlCertCandidate) of
		    true ->
			case verify_cert_signer(BinCert, ErlCertCandidate#'OTPCertificate'.tbsCertificate) of
			    true ->
				throw(public_key:pkix_issuer_id(ErlCertCandidate, self));
			    false ->
				Acc
			end;
		    false ->
			Acc
		end;
	   (_, Acc) ->
		Acc
	end,

    Result = case is_reference(CertsDbRef) of
		 true ->
		     do_find_issuer(IsIssuerFun, CertDbHandle, ListDb); 
		 false ->
		     {extracted, CertsData} = CertsDbRef,
		     DB = [Entry || {decoded, Entry} <- CertsData],
		     do_find_issuer(IsIssuerFun, CertDbHandle, DB)
	     end,
    case Result of
        issuer_not_found ->
	    {error, issuer_not_found};
	Result ->
	    Result
    end.

do_find_issuer(IssuerFun, CertDbHandle, CertDb) ->
    try 
	foldl_db(IssuerFun, CertDbHandle, CertDb)
    catch
	throw:{ok, _} = Return ->
	    Return
    end.
	
is_valid_extkey_usage(KeyUse, client) ->
    %% Client wants to verify server
    is_valid_key_usage(KeyUse,?'id-kp-serverAuth');
is_valid_extkey_usage(KeyUse, server) ->
    %% Server wants to verify client
    is_valid_key_usage(KeyUse, ?'id-kp-clientAuth').

verify_cert_signer(BinCert, SignerTBSCert) ->
    PublicKey = public_key(SignerTBSCert#'OTPTBSCertificate'.subjectPublicKeyInfo),
    public_key:pkix_verify(BinCert, PublicKey).

public_key(#'OTPSubjectPublicKeyInfo'{algorithm = #'PublicKeyAlgorithm'{algorithm = ?'id-ecPublicKey',
									parameters = Params},
				      subjectPublicKey = Point}) ->
    {Point, Params};
public_key(#'OTPSubjectPublicKeyInfo'{algorithm = #'PublicKeyAlgorithm'{algorithm = ?'id-Ed25519'},
				      subjectPublicKey = Point}) ->
    {Point, {namedCurve, ?'id-Ed25519'}};
public_key(#'OTPSubjectPublicKeyInfo'{algorithm = #'PublicKeyAlgorithm'{algorithm = ?'id-Ed448'},
				      subjectPublicKey = Point}) ->
    {Point, {namedCurve, ?'id-Ed448'}};
public_key(#'OTPSubjectPublicKeyInfo'{algorithm = #'PublicKeyAlgorithm'{algorithm = ?'rsaEncryption'}, 
				      subjectPublicKey = Key}) ->
    Key;
public_key(#'OTPSubjectPublicKeyInfo'{algorithm = #'PublicKeyAlgorithm'{algorithm = ?'id-RSASSA-PSS',
                                                                        parameters = Params}, 
				      subjectPublicKey = Key}) ->
    {Key, Params};
public_key(#'OTPSubjectPublicKeyInfo'{algorithm = #'PublicKeyAlgorithm'{algorithm = ?'id-dsa',
									parameters = {params, Params}},
				      subjectPublicKey = Key}) ->
    {Key, Params}.

other_issuer(OtpCert, BinCert, CertDbHandle, CertDbRef) ->
    case public_key:pkix_issuer_id(OtpCert, other) of
	{ok, IssuerId} ->
	    {other, IssuerId};
	{error, issuer_not_found} ->
	    case find_issuer(OtpCert, BinCert, CertDbHandle, CertDbRef, []) of
		{ok, IssuerId} ->
		    {other, IssuerId};
		Other ->
		    Other
	    end
    end.

verify_hostname({fallback, Hostname}, Customize, Cert, UserState) when is_list(Hostname) ->
    case public_key:pkix_verify_hostname(Cert, [{dns_id, Hostname}], Customize) of
        true ->
            {valid, UserState};
        false ->
            case public_key:pkix_verify_hostname(Cert, [{ip, Hostname}], Customize) of
                true ->
                    {valid, UserState};
                false ->
                    {fail, {bad_cert, hostname_check_failed}}
            end
    end;

verify_hostname({fallback, Hostname}, Customize, Cert, UserState) ->
    case public_key:pkix_verify_hostname(Cert, [{ip, Hostname}], Customize) of
        true ->
            {valid, UserState};
        false ->
            {fail, {bad_cert, hostname_check_failed}}
    end;

verify_hostname(Hostname, Customize, Cert, UserState) ->
    case public_key:pkix_verify_hostname(Cert, [{dns_id, Hostname}], Customize) of
        true ->
            {valid, UserState};
        false ->
            {fail, {bad_cert, hostname_check_failed}}
    end.

verify_cert_extensions(Cert, #{cert_ext := CertExts} =  UserState) ->
    Id = public_key:pkix_subject_id(Cert),
    Extensions = maps:get(Id, CertExts, []),
    verify_cert_extensions(Cert, UserState, Extensions, #{}).

verify_cert_extensions(Cert, UserState, [], _) ->
    {valid, UserState#{issuer => Cert}};
verify_cert_extensions(Cert, #{ocsp_responder_certs := ResponderCerts,
                               ocsp_state := OscpState,
                               issuer := Issuer} = UserState, [#certificate_status{response = OcspResponsDer} | Exts], Context) ->
    #{ocsp_nonce := Nonce} = OscpState,
    case public_key:pkix_ocsp_validate(Cert, Issuer, OcspResponsDer, ResponderCerts, Nonce) of
        valid ->
            verify_cert_extensions(Cert, UserState, Exts, Context);
        {bad_cert, _} = Status ->
            {fail, Status}
    end;
verify_cert_extensions(Cert, UserState, [_|Exts], Context) ->
    %% Skip unknow extensions!
    verify_cert_extensions(Cert, UserState, Exts, Context).

verify_sign(_, #{version := {_, Minor}}) when Minor < 3 ->
    %% This verification is not applicable pre TLS-1.2 
    true; 
verify_sign(Cert, #{signature_algs := SignAlgs,
                    signature_algs_cert := undefined}) ->
    is_supported_signature_algorithm(Cert, SignAlgs); 
verify_sign(Cert, #{signature_algs_cert := SignAlgs}) ->
    is_supported_signature_algorithm(Cert, SignAlgs).

is_supported_signature_algorithm(#'OTPCertificate'{signatureAlgorithm = 
                                                       #'SignatureAlgorithm'{algorithm = ?'id-dsa-with-sha1'}}, [{_,_}|_] = SignAlgs) ->   
    lists:member({sha, dsa}, SignAlgs);
is_supported_signature_algorithm(#'OTPCertificate'{signatureAlgorithm = SignAlg}, [{_,_}|_] = SignAlgs) ->   
    Scheme = ssl_cipher:signature_algorithm_to_scheme(SignAlg),
    {Hash, Sign, _ } = ssl_cipher:scheme_to_components(Scheme),
    lists:member({pre_1_3_hash(Hash), pre_1_3_sign(Sign)}, SignAlgs);
is_supported_signature_algorithm(#'OTPCertificate'{signatureAlgorithm = SignAlg}, SignAlgs) ->   
    Scheme = ssl_cipher:signature_algorithm_to_scheme(SignAlg),
    lists:member(Scheme, SignAlgs).

pre_1_3_sign(rsa_pkcs1) ->
    rsa;
pre_1_3_sign(Other) ->
    Other.
pre_1_3_hash(sha1) ->
    sha;
pre_1_3_hash(Hash) ->
    Hash.

paths(Chain, CertDbHandle) ->
    paths(Chain, Chain, CertDbHandle, []).

paths([Root], _, _, Path) ->
    [[Root | Path]];
paths([Cert1, Cert2 | Rest], Chain, CertDbHandle, Path) ->
    case public_key:pkix_is_issuer(Cert1, Cert2) of
        true ->
            %% Chain orded so far
            paths([Cert2 | Rest], Chain, CertDbHandle, [Cert1 | Path]);
        false ->
            %% Chain is unorded and/or contains extraneous certificates
            unorded_or_extraneous(Chain, CertDbHandle)
    end.

unorded_or_extraneous([Peer | UnorderedChain], CertDbHandle) ->
    ChainCandidates = extraneous_chains(UnorderedChain),
    lists:map(fun(Candidate) ->
                      path_candidate(Peer, Candidate, CertDbHandle)
              end,
              ChainCandidates).

path_candidate(Peer, ChainCandidateCAs, CertDbHandle) ->
    {ok,  ExtractedCerts} = ssl_pkix_db:extract_trusted_certs({der, ChainCandidateCAs}),
    %% certificate_chain/4 will make sure the chain is ordered
    case certificate_chain(Peer, CertDbHandle, ExtractedCerts, []) of
        {ok, undefined, Chain} ->
            lists:reverse(Chain);
        {ok, Root, Chain} ->
            [Root | lists:reverse(Chain)]
    end.

handle_partial_chain([IssuerCert| Rest] = Path, PartialChainHandler, CertDbHandle, CertDbRef) ->
    case public_key:pkix_is_self_signed(IssuerCert) of
        true -> %% IssuerCert = ROOT (That is ROOT was included in chain)
            {ok, {SerialNr, IssuerId}} = public_key:pkix_issuer_id(IssuerCert, self),
            case ssl_manager:lookup_trusted_cert(CertDbHandle, CertDbRef, SerialNr, IssuerId) of
                {ok, {IssuerCert, _}} -> %% Match sent ROOT to trusted ROOT 
                    maybe_shorten_path(Path, PartialChainHandler, {IssuerCert, Rest});
                {ok, _} -> %% Did not match trusted ROOT
                    maybe_shorten_path(Path, PartialChainHandler, {invalid_issuer, Path});
                _ ->
                    maybe_shorten_path(Path, PartialChainHandler, {unknown_ca, Path})
            end;
        false ->
            OTPCert = public_key:pkix_decode_cert(IssuerCert, otp),
            case other_issuer(OTPCert, IssuerCert, CertDbHandle, CertDbRef) of
                {other, {SerialNr, IssuerId}} ->
                    case ssl_manager:lookup_trusted_cert(CertDbHandle, CertDbRef, SerialNr, IssuerId) of
                        {ok, {NewIssuerCert, _}} ->  
                            case public_key:pkix_is_self_signed(NewIssuerCert) of
                                true -> %% NewIssuerCert is a trusted ROOT cert
                                    maybe_shorten_path([NewIssuerCert | Path], PartialChainHandler, {NewIssuerCert, Path});
                                false ->
                                    maybe_shorten_path([NewIssuerCert | Path], PartialChainHandler, 
                                                       {unknown_ca, [NewIssuerCert | Path]})
                            end;
                        _ ->
                            maybe_shorten_path(Path, PartialChainHandler, {unknown_ca, Path})
                    end;
                {error, issuer_not_found} ->
                    maybe_shorten_path(Path, PartialChainHandler, {unknown_ca, Path})
            end
    end. 

maybe_shorten_path(Path, PartialChainHandler, Default) ->
    %% This function might shorthen the
    %% certificate path to be validated with
    %% public_key:pkix_path_validation by letting
    %% the user put its trust in an intermidate cert
    %% from the certifcate chain sent by the peer.
    try PartialChainHandler(Path) of
        {trusted_ca, Root} ->
            new_trusteded_path(Root, Path, Default);
        unknown_ca ->
            Default
    catch _:_ ->
            Default
    end.

new_trusteded_path(DerCert, [DerCert | Chain], _) ->
    {DerCert, Chain};
new_trusteded_path(DerCert, [_ | Rest], Default) ->
    new_trusteded_path(DerCert, Rest, Default);
new_trusteded_path(_, [], Default) ->
    %% User did not pick a cert present 
    %% in the cert chain so ignore
    Default.

handle_incomplete_chain([PeerCert| _] = Chain0, PartialChainHandler, Default, CertDbHandle, CertDbRef) ->
    %% We received an incomplete chain, that is not all certs expected to be present are present. 
    %% See if we have the certificates to rebuild it. 
    case certificate_chain(PeerCert, CertDbHandle, CertDbRef) of
        {ok, _, [PeerCert | _] = Chain} when Chain =/= Chain0 -> %% Chain candidate found          
            case lists:prefix(Chain0, Chain) of 
                true ->
                    handle_partial_chain(lists:reverse(Chain), PartialChainHandler, CertDbHandle, CertDbRef);
                false ->
                    Default
            end;
        _  ->
            Default
    end.

extraneous_chains(Certs) ->
    %% If some certs claim to be the same cert that is have the same
    %% subject field we should create a list of possible chain certs
    %% for each such cert. Only one chain, if any, should be
    %% verifiable using available ROOT certs.
    Subjects = [{subject(Cert), Cert} || Cert <- Certs],
    Duplicates = find_duplicates(Subjects),
    %% Number of certs with duplicates (same subject) has been limited
    %% to 4 and the maximum number of combinations is limited to 16.
    build_candidates(Duplicates, 4, 16).

build_candidates(Map, Duplicates, Combinations) ->
    Subjects = maps:keys(Map),
    build_candidates(Subjects, Map, Duplicates, 1, Combinations, []).
%%
build_candidates([], _, _, _, _, Acc) ->
    Acc;
build_candidates([H|T], Map, Duplicates, Combinations, Max, Acc0) ->
    case maps:get(H, Map) of
	{Certs, Counter} when Counter > 1 andalso
                              Duplicates > 0 andalso
                              Counter * Combinations =< Max ->
	    case Acc0 of
		[] ->
		    Acc = [[Cert] || Cert <- Certs],
		    build_candidates(T, Map, Duplicates - 1, Combinations * Counter, Max, Acc);
		_Else ->
		    Acc = [[Cert|L] || Cert <- Certs, L <- Acc0],
		    build_candidates(T, Map, Duplicates - 1, Combinations * Counter, Max, Acc)
		end;
	{[Cert|_Throw], _Counter} ->
	    case Acc0 of
		[] ->
		    Acc = [[Cert]],
		    build_candidates(T, Map, Duplicates, Combinations, Max, Acc);
		_Else ->
		    Acc = [[Cert|L] || L <- Acc0],
		    build_candidates(T, Map, Duplicates, Combinations, Max, Acc)
	    end
    end.

find_duplicates(Chain) ->
    find_duplicates(Chain, #{}).
%%
find_duplicates([], Acc) ->
    Acc;
find_duplicates([{Subject, Cert}|T], Acc) ->
    case maps:get(Subject, Acc, none) of
	none ->
	    find_duplicates(T, Acc#{Subject => {[Cert], 1}});
	{Certs, Counter} ->
	    find_duplicates(T, Acc#{Subject => {[Cert|Certs], Counter + 1}})
    end.

subject(Cert) ->
    {_Serial,Subject} = public_key:pkix_subject_id(Cert),
    Subject.

