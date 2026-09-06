%%% SPDX-License-Identifier: MPL-2.0
%%% Account-scoped queue editor. Catalog reads are bounded; writes are a
%%% revision-checked saga, NOT a CouchDB cross-document transaction.
-module(cb_acdc_queue_editor).
-export([get/2, validate_write/2, execute/1]).
-ifdef(TEST).
-export([scoped/4, authorized/1, strict_route/2, roster_plan/3,
         digest/1, operation_id/3, public_catalog/2, valid_manifest/1,
         required_prompts/0, merge_patch/2, check_body/1, verified_manifest_media/1,
         language_selection_ready/2, manifest_path/3, system_media_state/2]).
-endif.
-include_lib("crossbar/src/crossbar.hrl").
-include_lib("kernel/include/file.hrl").
-define(LIMIT, 500).
-define(CAT, <<"acdc.queues">>).
-define(FLAG, <<"talkchief-acdc-managed">>).
-define(QFLAG, <<"talkchief-acdc-queue:">>).

-spec get(cb_context:context(), binary() | 'undefined') -> cb_context:context().
get(Context, QueueId) ->
    guarded(Context, fun() ->
        require_authorized(Context),
        _ = permit(Context, <<"queues">>, case QueueId of undefined -> []; _ -> [QueueId] end, ?HTTP_GET),
        Queue = load_queue(Context, QueueId),
        {Catalog, Internal} = catalogs(Context),
        Data = editor_data(Queue, Catalog, Internal),
        Relevant = kz_json:get_list_value([<<"callflows">>, <<"routes">>], Data, []),
        Permitted = lists:all(fun(R) -> authorized(scoped(Context, <<"callflows">>, [kz_json:get_value(<<"id">>, R)], ?HTTP_GET)) end, Relevant),
        SafeData = case Permitted of
                       true -> Data;
                       false -> kz_json:set_values([{[<<"callflows">>, <<"routes">>], []},
                                                    {[<<"catalogs">>, <<"callflows">>], catalog_state(false, <<"forbidden">>, 0)}], Data)
                   end,
        success(SafeData, Context)
    end).

%% Fail closed. No save is allowed during validation, including roster edits.
-spec validate_write(cb_context:context(), binary() | 'undefined') -> cb_context:context().
validate_write(Context, QueueId) ->
    guarded(Context, fun() -> prepare_write(Context, QueueId) end).

-spec execute(cb_context:context()) -> cb_context:context().
execute(Context) ->
    guarded(Context, fun() -> execute_plan(Context, cb_context:fetch(Context, editor_plan)) end).

guarded(Context, Fun) ->
    try Fun()
    catch
        throw:{editor_error, Code, Message, Details} -> error(Code, Message, Details, Context);
        throw:{editor_context, Failed} -> Failed;
        _Class:_Reason:_Stack ->
            %% Never return a document, token, or provider exception to the client.
            error(503, <<"queue_editor_unavailable">>, kz_json:new(), Context)
    end.

fail(Code, Message) -> fail(Code, Message, kz_json:new()).
fail(Code, Message, Details) -> throw({editor_error, Code, Message, Details}).
need(true, _, _) -> ok;
need(false, Code, Message) -> fail(Code, Message).
success(Data, Context) ->
    cb_context:setters(Context, [{fun cb_context:set_resp_status/2, success},
                                {fun cb_context:set_resp_data/2, Data},
                                {fun cb_context:set_resp_etag/2, undefined}]).
error(Code, Message, Details, Context) ->
    cb_context:set_resp_data(cb_context:add_system_error(Code, Message, Details, Context), Details).

%% Reapply scopes and ALL stop decisions for each embedded resource. A token
%% authorized for /queues does not thereby gain access to /users or /callflows.
scoped(Context, Resource, Params, Verb) ->
    Account = cb_context:account_id(Context),
    Nouns = [{Resource, Params}, {<<"accounts">>, [Account]}],
    Path = iolist_to_binary([<<"/">>, cb_context:api_version(Context), <<"/accounts/">>,
                            Account, <<"/">>, Resource,
                            [[<<"/">>, P] || P <- Params]]),
    cb_context:setters(Context, [{fun cb_context:set_req_nouns/2, Nouns},
                                {fun cb_context:set_raw_path/2, Path},
                                {fun cb_context:set_req_verb/2, Verb},
                                {fun cb_context:set_query_string/2, kz_json:new()},
                                {fun cb_context:set_resp_status/2, success},
                                {fun cb_context:set_doc/2, kz_json:new()},
                                {fun cb_context:set_req_data/2, kz_json:new()}]).

authorized(Context) ->
    [{Resource, Params}|_] = cb_context:req_nouns(Context),
    Global = crossbar_bindings:pmap(api_util:create_event_name(Context, <<"authorize">>), Context),
    Module = crossbar_bindings:pmap(api_util:create_event_name(Context, <<"authorize.", Resource/binary>>),
                                   [Context|Params]),
    NoStop = lists:all(fun(true) -> true; (false) -> true; ({true, _}) -> true;
                          ({false, _}) -> true; (_) -> false end, Global ++ Module),
    Allowed = lists:any(fun(true) -> true; ({true, _}) -> true; (_) -> false end, Global ++ Module),
    NoStop andalso Allowed andalso scopes_allowed(Context, Resource).

scopes_allowed(Context, Resource) ->
    case {cb_context:auth_token_type(Context),
          kz_json:get_ne_binary_value(<<"method">>, cb_context:auth_doc(Context))} of
        {'x-auth-token', Method} when is_binary(Method) ->
            Scopes = crossbar_bindings:pmap(api_util:create_event_name(Context, <<"allowed_scopes.", Resource/binary>>), Method),
            lists:all(fun(Required) when is_list(Required) -> kz_auth_scope:all(cb_context:auth_token(Context), Required);
                         (_) -> false end, Scopes);
        _ -> true
    end.

require_authorized(Context) ->
    need(id(cb_context:account_id(Context)) andalso cb_context:is_authenticated(Context), 403, <<"forbidden">>),
    need(authorized(Context), 403, <<"forbidden">>).
permit(Context, Resource, Params, Verb) ->
    Sub = scoped(Context, Resource, Params, Verb),
    need(authorized(Sub), 403, <<"queue_editor_resource_forbidden">>), Sub.

load_queue(_Context, undefined) -> kz_json:new();
load_queue(Context, QueueId) ->
    need(id(QueueId), 404, <<"queue_not_found">>),
    case kz_datamgr:open_doc(cb_context:db_name(Context), QueueId) of
        {ok, Doc} -> need(scoped_doc(Doc, Context, <<"queue">>), 404, <<"queue_not_found">>), Doc;
        {error, not_found} -> fail(404, <<"queue_not_found">>);
        _ -> fail(503, <<"queue_unavailable">>)
    end.

scoped_doc(Doc, Context, Type) ->
    kz_doc:type(Doc) =:= Type andalso kz_doc:account_id(Doc) =:= cb_context:account_id(Context)
        andalso not kz_doc:is_deleted(Doc) andalso not kz_doc:is_soft_deleted(Doc).

catalogs(Context) ->
    Specs = [{<<"users">>, <<"user">>}, {<<"media">>, <<"media">>}, {<<"callflows">>, <<"callflow">>}],
    {Values, Internal, States} = lists:foldl(fun({Resource, Type}, {V, I, S}) ->
        Allowed = authorized(scoped(Context, Resource, [], ?HTTP_GET)),
        {Docs, State} = catalog(Context, Type, Allowed),
        {kz_json:set_value(Resource, public_catalog(Type, Docs), V),
         maps:put(Resource, Docs, I), kz_json:set_value(Resource, State, S)}
    end, {kz_json:new(), #{}, kz_json:new()}, Specs),
    {Numbers, NumberState} = numbers(Context),
    {Manifest, Media, MediaState} = system_media(Context),
    Catalog = kz_json:set_values([{<<"numbers">>, Numbers}, {<<"system_media">>, Media},
                                  {<<"language_capabilities">>, Manifest},
                                  {<<"catalogs">>, kz_json:set_values([{<<"numbers">>, NumberState},
                                                                      {<<"system_media">>, MediaState}], States)}], Values),
    {Catalog, Internal}.

catalog(_Context, _Type, false) -> {[], catalog_state(false, <<"forbidden">>, 0)};
catalog(Context, Type, true) ->
    Options = [{startkey, [Type]}, {endkey, [Type, kz_json:new()]},
               include_docs, {limit, ?LIMIT + 1}, {reduce, false}],
    case kz_datamgr:get_results(cb_context:db_name(Context), <<"crossbar_listings/by_type_id">>, Options) of
        {ok, Rows} when length(Rows) =< ?LIMIT ->
            Docs = [kz_json:get_json_value(<<"doc">>, Row) || Row <- Rows],
            case lists:all(fun(Doc) -> scoped_doc(Doc, Context, Type) end, Docs) of
                true -> {Docs, catalog_state(true, <<"complete">>, length(Docs))};
                false -> {[], catalog_state(false, <<"invalid_scope">>, 0)}
            end;
        {ok, _} -> {[], catalog_state(false, <<"limit_exceeded">>, 0)};
        _ -> {[], catalog_state(false, <<"unavailable">>, 0)}
    end.

catalog_state(Complete, Reason, Count) ->
    kz_json:from_list([{<<"complete">>, Complete}, {<<"reason">>, Reason},
                       {<<"count">>, Count}, {<<"limit">>, ?LIMIT}]).

public_catalog(Type, Docs) ->
    Keys = case Type of
               <<"user">> -> [<<"name">>, <<"first_name">>, <<"last_name">>, <<"enabled">>];
               <<"media">> -> [<<"name">>, <<"language">>, <<"media_type">>, <<"media_source">>];
               <<"callflow">> -> [<<"name">>, <<"numbers">>, <<"patterns">>, <<"flags">>, <<"flow">>]
           end,
    [project(Doc, Keys) || Doc <- Docs].
project(Doc, Keys) ->
    kz_json:from_list([{<<"id">>, kz_doc:id(Doc)} | [{K, V} || K <- Keys,
                        (V = kz_json:get_value(K, Doc)) =/= undefined]]).

numbers(Context) ->
    case authorized(scoped(Context, <<"phone_numbers">>, [], ?HTTP_GET)) of
        false -> {[], catalog_state(false, <<"forbidden">>, 0)};
        true ->
            case kz_datamgr:get_results(cb_context:db_name(Context), <<"phone_numbers/crossbar_listing">>,
                                       [{limit, ?LIMIT + 1}, {reduce, false}]) of
                {ok, Rows} when length(Rows) =< ?LIMIT ->
                    Data = [kz_json:from_list([{<<"number">>, kz_json:get_value(<<"id">>, Row)},
                                               {<<"state">>, <<"in_service">>}]) || Row <- Rows,
                            kz_json:get_value([<<"value">>, <<"assigned_to">>], Row) =:= cb_context:account_id(Context),
                            kz_json:get_value([<<"value">>, <<"state">>], Row) =:= <<"in_service">>],
                    {Data, catalog_state(true, <<"complete">>, length(Data))};
                {ok, _} -> {[], catalog_state(false, <<"limit_exceeded">>, 0)};
                _ -> {[], catalog_state(false, <<"unavailable">>, 0)}
            end
    end.

locales() -> [<<"en-us">>, <<"ar-sa">>, <<"he-il">>, <<"es-es">>, <<"fr-fr">>].
required_prompts() ->
    [<<"acdc-callback-offer-", (integer_to_binary(N))/binary>> || N <- lists:seq(0, 9)] ++
    [<<"acdc-callback-", S/binary>> || S <- [<<"menu-current">>, <<"menu-alternate">>, <<"number-readback">>,
                                            <<"confirmation">>, <<"success">>, <<"returned-confirmation">>]] ++
    [<<"acdc-queue-", S/binary>> || S <- [<<"your-current-position-is">>, <<"you_are_at_position">>, <<"in_the_queue">>,
        <<"increase_in_call_volume">>, <<"the_estimated_wait_time_is">>, <<"less_than_1_minute">>,
        <<"about_5_minutes">>, <<"about_10_minutes">>, <<"about_15_minutes">>, <<"about_30_minutes">>,
        <<"about_45_minutes">>, <<"about_1_hour">>, <<"at_least_1_hour">>]].

system_media(Context) ->
    %% This corresponds to existing authenticated GET /media, not arbitrary
    %% tenant media. Only the fixed ACDC catalog is fetched, in one batch.
    Global = cb_context:set_account_id(scoped(Context, <<"media">>, [], ?HTTP_GET), undefined),
    System = cb_context:setters(Global, [{fun cb_context:set_req_nouns/2, [{<<"media">>, []}]},
                                        {fun cb_context:set_raw_path/2, <<"/v2/media">>}]),
    case authorized(System) of
        false -> {null, [], catalog_state(false, <<"forbidden">>, 0)};
        true ->
            try
                {Manifest, Media} = verified_manifest_media(read_manifest()),
                {Manifest, Media, system_media_state(Manifest, Media)}
            catch _:_ -> {null, [], catalog_state(false, <<"unverified_language_manifest">>, 0)} end
    end.

-spec system_media_state(kz_json:object(), list()) -> kz_json:object().
system_media_state(Manifest, Media) ->
    case kz_json:get_value(<<"backend_mode">>, Manifest) of
        <<"legacy">> ->
            Required = legacy_official_ids() ++ acdc_gemini_prompts:callback_media_ids(<<"en-us">>),
            Present = [kz_json:get_value(<<"id">>, M) || M <- Media],
            case Required -- Present of
                [] -> catalog_state(true, <<"complete">>, length(Media));
                Missing -> kz_json:set_value(<<"missing_prompt_ids">>, Missing,
                    catalog_state(false, <<"english_media_prerequisites_incomplete">>, length(Media)))
            end;
        _ -> catalog_state(true, <<"complete">>, length(Media))
    end.

verified_manifest_media(Manifest) ->
    true = valid_manifest(Manifest),
    case kz_json:get_value(<<"backend_mode">>, Manifest) of
        <<"legacy">> -> verified_legacy_media(Manifest);
        undefined -> verified_full_media(Manifest)
    end.

%% The deployed English baseline resolves fixed defaults to immutable Gemini
%% media, not obsolete canonical callback aliases. Keep its official legacy
%% phrases/auxiliary branches and all 42 callback prerequisites (32 fixed plus
%% ten recorded telephone digits) in one bounded batch.
%% This does not promote the all-false multilingual capability manifest.
verified_legacy_media(Manifest) ->
    Official = legacy_official_ids(),
    Ids = Official ++ acdc_gemini_prompts:callback_media_ids(<<"en-us">>),
    {Docs, Media} = verified_media(Ids),
    Canonical = [M || M <- Media, lists:member(kz_json:get_value(<<"id">>, M), Official)],
    {Manifest, Canonical ++ acdc_gemini_prompts:verified_callback_media(<<"en-us">>, Docs)}.

legacy_official_ids() ->
    [<<"en-us/", (legacy_prompt(P))/binary>> || P <- required_prompts(),
         legacy_prompt(P) =/= P] ++
        [<<"en-us/agent-invalid_choice">>, <<"en-us/menu-invalid_entry">>, <<"en-us/cf-enter_number">>].

legacy_prompt(<<"acdc-queue-your-current-position-is">> = P) -> P;
legacy_prompt(<<"acdc-queue-", S/binary>>) -> <<"queue-", S/binary>>;
legacy_prompt(P) -> P.

verified_media(Ids) ->
    {ok, Rows} = kz_datamgr:open_docs(<<"system_media">>, Ids),
    true = lists:sort([kz_json:get_value(<<"id">>, R, kz_json:get_value(<<"key">>, R)) || R <- Rows]) =:= lists:sort(Ids),
    Docs = [Doc || Row <- Rows, (Doc = kz_json:get_json_value(<<"doc">>, Row)) =/= undefined,
                   lists:member(kz_doc:id(Doc), Ids), kz_doc:type(Doc) =:= <<"media">>, attached(Doc)],
    Media = [kz_json:set_values([{<<"language">>, hd(binary:split(kz_doc:id(D), <<"/">>))},
                                 {<<"has_attachments">>, true}], project(D, [<<"name">>])) || D <- Docs],
    {Docs, Media}.

verified_full_media(Manifest) ->
    Ids = [<<L/binary, "/", P/binary>> || L <- locales(), P <- required_prompts()],
    {Docs, Media} = verified_media(Ids),
    Keys = [<<"ready">>, <<"position">>, <<"wait_time">>, <<"callback">>, <<"native_speaker_review">>,
            <<"numbers">>, <<"number_range">>, <<"numeric_prompt_count">>, <<"required_prompt_ids">>,
            <<"source_catalog_sha256">>, <<"installed_media_sha256">>],
    Languages = lists:foldl(fun(L, Acc) ->
        All = lists:all(fun(P) -> lists:any(fun(D) -> kz_doc:id(D) =:= <<L/binary, "/", P/binary>> end, Docs) end, required_prompts()),
        Original = kz_json:get_json_value([<<"languages">>, L], Manifest),
        Entry = kz_json:from_list([{K, V} || K <- Keys, (V = kz_json:get_value(K, Original)) =/= undefined]),
        Flags = [{K, All andalso kz_json:is_true(K, Entry)} || K <- [<<"ready">>, <<"position">>, <<"wait_time">>, <<"callback">>]],
        kz_json:set_value(L, kz_json:set_values(Flags, Entry), Acc)
    end, kz_json:new(), locales()),
    {kz_json:from_list([{<<"schema_version">>, 1}, {<<"generated_at">>, kz_json:get_value(<<"generated_at">>, Manifest)},
                        {<<"languages">>, Languages}]), Media}.

attached(Doc) ->
    not kz_doc:is_deleted(Doc) andalso not kz_doc:is_soft_deleted(Doc)
        andalso lists:any(fun(N) -> kz_doc:attachment_length(Doc, N, 0) > 0 end, kz_doc:attachment_names(Doc)).

read_manifest() ->
    %% Reading editor data must not persist a filesystem-dependent default.
    Path = manifest_path(kapps_config:get_ne_binary(?CAT, <<"editor_language_capabilities_path">>),
                         fun file:read_link_info/1,
                         os:getenv("KAZOO_ACDC_EDITOR_CAPABILITIES")),
    true = filename:pathtype(Path) =:= absolute,
    protected_parent(filename:dirname(Path)),
    {ok, Before = #file_info{type = regular, uid = 0, mode = Mode, size = Size}} = file:read_link_info(Path),
    true = Mode band 8#022 =:= 0 andalso Size > 0 andalso Size =< 131072,
    {ok, Bytes} = file:read_file(Path), {ok, After} = file:read_link_info(Path),
    true = Before =:= After andalso byte_size(Bytes) =:= Size,
    Manifest = kz_json:decode(Bytes), true = valid_manifest(Manifest), Manifest.

-spec manifest_path(kz_term:api_binary(), fun((string()) -> term()), false | string()) -> string().
manifest_path(undefined, Probe, Environment) ->
    Legacy = "/var/www/html/monster-ui/apps/acdc/language-capabilities.json",
    case Probe(Legacy) of
        {error, enoent} ->
            case Environment of
                false -> "/etc/kazoo/acdc/language-capabilities.json";
                _ -> Environment
            end;
        %% Present, unreadable or unsafe legacy artifacts still go through the
        %% protected reader. Never bypass one with a less restrictive fallback.
        _ -> Legacy
    end;
manifest_path(Configured, _Probe, _Environment) -> binary_to_list(Configured).

protected_parent(Path) ->
    {ok, #file_info{type = directory, uid = 0, mode = Mode}} = file:read_link_info(Path),
    true = Mode band 8#022 =:= 0,
    case filename:dirname(Path) of Path -> ok; Parent -> protected_parent(Parent) end.

valid_manifest(M) ->
    kz_json:get_value(<<"schema_version">>, M) =:= 1
        andalso timestamp(kz_json:get_value(<<"generated_at">>, M))
        andalso lists:sort(kz_json:get_keys(kz_json:get_json_value(<<"languages">>, M, kz_json:new()))) =:= lists:sort(locales())
        andalso case kz_json:get_value(<<"backend_mode">>, M) of
            undefined -> lists:all(fun(L) -> valid_language(L, kz_json:get_json_value([<<"languages">>, L], M)) end, locales());
            <<"legacy">> -> valid_legacy_manifest(M);
            _ -> false
        end.

valid_legacy_manifest(M) ->
    Flags = [<<"ready">>, <<"position">>, <<"wait_time">>, <<"callback">>, <<"native_speaker_review">>],
    lists:sort(kz_json:get_keys(M)) =:= lists:sort([<<"schema_version">>, <<"backend_mode">>, <<"generated_at">>, <<"languages">>])
        andalso lists:all(fun(L) ->
            Entry = kz_json:get_json_value([<<"languages">>, L], M, kz_json:new()),
            lists:sort(kz_json:get_keys(Entry)) =:= lists:sort(Flags)
                andalso lists:all(fun(K) -> kz_json:get_value(K, Entry) =:= false end, Flags)
        end, locales()).

valid_language(L, E) ->
    Flags = [<<"ready">>, <<"position">>, <<"wait_time">>, <<"callback">>, <<"native_speaker_review">>],
    lists:all(fun(K) -> is_boolean(kz_json:get_value(K, E)) end, Flags) andalso
    (not kz_json:is_true(<<"ready">>, E) orelse
     (lists:all(fun(K) -> kz_json:is_true(K, E) end, [<<"position">>, <<"wait_time">>, <<"callback">>])
      andalso lists:sort(kz_json:get_list_value(<<"required_prompt_ids">>, E, [])) =:= lists:sort(required_prompts())
      andalso kz_json:get_value(<<"number_range">>, E) =:= [0, 999999999]
      andalso hex(kz_json:get_value(<<"source_catalog_sha256">>, E), 64)
      andalso hex(kz_json:get_value(<<"installed_media_sha256">>, E), 64)
      andalso case L =:= <<"ar-sa">> orelse L =:= <<"he-il">> of
                  true -> kz_json:get_value(<<"numbers">>, E) =:= <<"prerecorded">> andalso kz_json:get_value(<<"numeric_prompt_count">>, E) =:= 2999;
                  false -> kz_json:get_value(<<"numbers">>, E) =:= <<"native_say">> andalso kz_json:get_value(<<"numeric_prompt_count">>, E) =:= 0
              end)).

timestamp(V) when is_binary(V) ->
    re:run(V, <<"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$">>, [{capture, none}]) =:= match;
timestamp(_) -> false.

editor_data(Queue, Catalog, Internal) ->
    QueueId = kz_doc:id(Queue), Users = maps:get(<<"users">>, Internal), Routes = maps:get(<<"callflows">>, Internal),
    Roster = [kz_doc:id(U) || U <- Users, lists:member(QueueId, kz_json:get_list_value(<<"queues">>, U, []))],
    FullRoutes = public_catalog(<<"callflow">>, Routes),
    Summaries = [kz_json:delete_key(<<"flow">>, R) || R <- FullRoutes],
    Relevant = [R || R <- FullRoutes, references(kz_json:get_json_value(<<"flow">>, R), QueueId)],
    Revisions = kz_json:from_list([{<<"queue">>, default(kz_doc:revision(Queue), null)},
                                  {<<"users">>, revisions(Users)}, {<<"callflows">>, revisions(Routes)}]),
    kz_json:set_values([{<<"queue">>, kz_json:set_value(<<"agents">>, Roster, kz_doc:public_fields(Queue))},
                        {<<"roster">>, Roster}, {<<"revisions">>, Revisions},
                        {<<"callflows">>, kz_json:from_list([{<<"summaries">>, Summaries}, {<<"routes">>, Relevant}])}], Catalog).
revisions(Docs) -> kz_json:from_list([{kz_doc:id(D), kz_doc:revision(D)} || D <- Docs]).
default(undefined, D) -> D;
default(V, _) -> V.
references(_Flow, undefined) -> false;
references(Flow, QueueId) ->
    (kz_json:get_value(<<"module">>, Flow) =:= <<"acdc_member">> andalso kz_json:get_value([<<"data">>, <<"id">>], Flow) =:= QueueId)
        orelse lists:any(fun(Child) -> references(Child, QueueId) end,
                          element(1, kz_json:get_values(kz_json:get_json_value(<<"children">>, Flow, kz_json:new())))).

id(V) -> hex(V, 32).
hex(V, N) when is_binary(V), byte_size(V) =:= N ->
    lists:all(fun(C) -> (C >= $0 andalso C =< $9) orelse (C >= $a andalso C =< $f) end, binary_to_list(V));
hex(_, _) -> false.

%% Type-preserving canonical hash: kz_json:canonicalize/1 deliberately coerces
%% strings such as "true", so it is not suitable for idempotency identity.
digest(Value) -> kz_term:to_hex_binary(crypto:hash(sha256, kz_json:encode(sorted(Value)))).
sorted({Props}) -> {[{K, sorted(V)} || {K, V} <- lists:keysort(1, Props)]};
sorted(List) when is_list(List) -> [sorted(V) || V <- List];
sorted(Value) -> Value.
operation_id(Account, Owner, RequestId) ->
    <<"acdc_queue_editor_", (digest([Account, Owner, RequestId]))/binary>>.
owner(Context) ->
    digest([cb_context:auth_account_id(Context), default(cb_context:auth_user_id(Context), null),
            default(kz_json:get_value(<<"method">>, cb_context:auth_doc(Context)), null)]).

check_body(Body) ->
    need(kz_json:is_json_object(Body), 400, <<"editor_body_must_be_object">>),
    Allowed = [<<"queue">>, <<"roster">>, <<"route">>, <<"revisions">>, <<"request_id">>],
    need(lists:sort(kz_json:get_keys(Body)) =:= lists:sort(Allowed), 400, <<"editor_body_requires_exact_fields">>),
    need(id(kz_json:get_value(<<"request_id">>, Body)), 400, <<"invalid_request_id">>),
    Queue = kz_json:get_json_value(<<"queue">>, Body),
    need(kz_json:is_json_object(Queue) andalso byte_size(kz_json:encode(Queue)) =< 65536, 400, <<"invalid_queue_settings">>),
    need(lists:all(fun(<<"pvt_", _/binary>>) -> false; (<<"_", _/binary>>) -> false;
                      (<<"id">>) -> false; (<<"agents">>) -> false; (_) -> true end, kz_json:get_keys(Queue)),
         400, <<"queue_identity_and_roster_are_server_owned">>),
    need(kz_json:is_json_object(kz_json:get_value(<<"revisions">>, Body)), 400, <<"revision_snapshot_required">>),
    Roster = kz_json:get_value(<<"roster">>, Body),
    need(Roster =:= null orelse (is_list(Roster) andalso length(Roster) =< ?LIMIT
                               andalso lists:all(fun id/1, Roster) andalso length(lists:usort(Roster)) =:= length(Roster)),
         400, <<"invalid_roster">>),
    Route = kz_json:get_value(<<"route">>, Body),
    need(Route =:= null orelse (kz_json:is_json_object(Route) andalso kz_json:get_keys(Route) =:= [<<"extension">>]
                               andalso extension(kz_json:get_value(<<"extension">>, Route))), 400, <<"invalid_route_extension">>),
    ok.
extension(<<>>) -> true;
extension(V) when is_binary(V), byte_size(V) =< 32 ->
    re:run(V, <<"^\\+?[0-9*#]+$">>, [{capture, none}]) =:= match;
extension(_) -> false.

prepare_write(Context, QueueId) ->
    require_authorized(Context), Body = cb_context:req_data(Context), check_body(Body),
    Owner = owner(Context), OperationId = operation_id(cb_context:account_id(Context), Owner, kz_json:get_value(<<"request_id">>, Body)),
    Hash = digest([default(QueueId, null), cb_context:req_verb(Context), Body]),
    case kz_datamgr:open_doc(cb_context:db_name(Context), OperationId) of
        {ok, Receipt} ->
            need(kz_doc:type(Receipt) =:= <<"acdc_queue_editor_operation">>
                 andalso kz_doc:account_id(Receipt) =:= cb_context:account_id(Context)
                 andalso kz_json:get_value(<<"owner">>, Receipt) =:= Owner
                 andalso kz_json:get_value(<<"body_hash">>, Receipt) =:= Hash, 409, <<"request_id_reused_with_different_request">>),
            case kz_json:get_value(<<"state">>, Receipt) of
                <<"complete">> -> cb_context:store(success(kz_json:get_json_value(<<"result">>, Receipt), Context), editor_plan, {replay, Receipt});
                _ -> fail(409, <<"operation_incomplete_reload_before_recovery">>, operation_public(Receipt))
            end;
        {error, not_found} -> prepare_new(Context, QueueId, Body, Owner, OperationId, Hash);
        _ -> fail(503, <<"operation_receipt_unavailable">>)
    end.

prepare_new(Context, QueueId, Body, Owner, OperationId, Hash) ->
    Original = load_queue(Context, QueueId),
    {Catalog, Internal} = catalogs(Context),
    ensure_catalog(Catalog, <<"users">>),
    Revisions = kz_json:get_json_value(<<"revisions">>, Body),
    need(kz_json:get_value(<<"queue">>, Revisions) =:= default(kz_doc:revision(Original), null), 409, <<"queue_revision_conflict_reload">>),
    Users = maps:get(<<"users">>, Internal), Routes = maps:get(<<"callflows">>, Internal),
    SavedId = case QueueId of undefined -> binary:part(digest([OperationId, <<"queue">>]), 0, 32); _ -> QueueId end,
    QueueBody = kz_json:get_json_value(<<"queue">>, Body),
    validate_selections(Original, QueueBody, Catalog, Users),
    QueueContext = queue_context(Context, QueueId, SavedId, QueueBody, Original),
    UserDocs = case kz_json:get_value(<<"roster">>, Body) of
                   null -> [];
                   Roster ->
                       _ = permit(Context, <<"queues">>, [SavedId, <<"roster">>], ?HTTP_POST),
                       need(digest(kz_json:get_value(<<"users">>, Revisions)) =:= digest(revisions(Users)), 409, <<"roster_revision_conflict_reload">>),
                       roster_plan(SavedId, Users, Roster)
               end,
    RoutePlan = case kz_json:get_value(<<"route">>, Body) of
                    null -> preserve;
                    RouteBody ->
                        ensure_catalog(Catalog, <<"callflows">>),
                        need(digest(kz_json:get_value(<<"callflows">>, Revisions)) =:= digest(revisions(Routes)), 409, <<"route_revision_conflict_reload">>),
                        route_plan(Context, SavedId, OperationId, kz_json:get_value(<<"name">>, cb_context:doc(QueueContext)),
                                   kz_json:get_value(<<"extension">>, RouteBody), Routes)
                end,
    Reservations = reservation_plan(Context, SavedId, OperationId, RoutePlan, Routes),
    Remaining = case Reservations of
                    [] -> [<<"queue">>, <<"roster">>, <<"route">>];
                    _ -> [<<"reserve_extensions">>, <<"queue">>, <<"roster">>, <<"route">>, <<"finalize_extensions">>]
                end,
    Receipt = kz_doc:update_pvt_parameters(kz_json:from_list([
                    {<<"_id">>, OperationId}, {<<"owner">>, Owner}, {<<"body_hash">>, Hash},
                    {<<"queue_id">>, SavedId}, {<<"state">>, <<"running">>}, {<<"phase">>, <<"prepared">>},
                    {<<"committed">>, []}, {<<"in_flight">>, []}, {<<"remaining">>, Remaining}]),
                  cb_context:db_name(Context), [{account_id, cb_context:account_id(Context)}, {type, <<"acdc_queue_editor_operation">>}]),
    Plan = #{queue => QueueContext, create => QueueId =:= undefined, users => UserDocs,
             route => RoutePlan, reservations => Reservations, receipt => Receipt, body => Body},
    cb_context:store(cb_context:set_resp_status(Context, success), editor_plan, Plan).

ensure_catalog(Catalog, Key) ->
    need(kz_json:is_true([<<"catalogs">>, Key, <<"complete">>], Catalog), 503, <<"editor_catalog_incomplete">>).

queue_context(Context, QueueId, SavedId, Body, Original) ->
    case QueueId of
        undefined ->
            Sub = permit(Context, <<"queues">>, [], ?HTTP_PUT),
            Valid = cb_queues:validate(cb_context:set_req_data(Sub, Body)),
            validated(Valid), cb_context:set_doc(Valid, kz_doc:set_id(cb_context:doc(Valid), SavedId));
        _ ->
            %% Validate a full merge, then retain the exact originally observed
            %% revision: a racing change is a conflict, never silently overwritten.
            Sub = permit(Context, <<"queues">>, [QueueId], ?HTTP_PATCH),
            Valid = cb_queues:validate(cb_context:set_req_data(Sub, Body), QueueId),
            validated(Valid), cb_context:set_doc(Valid, kz_doc:set_revision(cb_context:doc(Valid), kz_doc:revision(Original)))
    end.
validated(Context) ->
    case cb_context:resp_status(Context) of success -> ok; _ -> throw({editor_context, Context}) end.

merge_patch(Target, Patch) ->
    kz_json:foldl(fun(Key, null, Acc) -> kz_json:delete_key(Key, Acc);
                    (Key, Value, Acc) ->
                        case kz_json:is_json_object(Value) of
                            true -> kz_json:set_value(Key, merge_patch(kz_json:get_json_value(Key, Acc, kz_json:new()), Value), Acc);
                            false -> kz_json:set_value(Key, Value, Acc)
                        end
                 end, Target, Patch).

%% Match the UI's explicitly declared legacy-English contract, without turning
%% its all-false multilingual flags into a full-pack readiness claim. Missing,
%% incomplete or forbidden catalogs cannot authorize a new language selection.
-spec language_selection_ready(any(), kz_json:object()) -> boolean().
language_selection_ready(Language, Catalog) ->
    Manifest = kz_json:get_json_value(<<"language_capabilities">>, Catalog, kz_json:new()),
    Complete = kz_json:is_true([<<"catalogs">>, <<"system_media">>, <<"complete">>], Catalog),
    case Complete andalso lists:member(Language, locales()) andalso valid_manifest(Manifest) of
        false -> false;
        true ->
            case kz_json:get_value(<<"backend_mode">>, Manifest) of
                <<"legacy">> ->
                    Ids = [kz_json:get_value(<<"id">>, M)
                           || M <- kz_json:get_list_value(<<"system_media">>, Catalog, []),
                              kz_json:get_value(<<"language">>, M) =:= <<"en-us">>,
                              kz_json:is_true(<<"has_attachments">>, M)],
                    Language =:= <<"en-us">> andalso
                        lists:all(fun(Id) -> lists:member(Id, Ids) end, legacy_official_ids())
                        andalso acdc_gemini_prompts:callback_media_complete(<<"en-us">>,
                            kz_json:get_list_value(<<"system_media">>, Catalog, []));
                undefined -> kz_json:is_true([<<"languages">>, Language, <<"ready">>], Manifest)
            end
    end.

validate_selections(Original, Patch, Catalog, Users) ->
    Next = merge_patch(kz_doc:public_fields(Original), Patch),
    Authority = kz_json:get_value([<<"callback">>, <<"outbound_authority">>], Next),
    ChangedAuthority = Authority =/= kz_json:get_value([<<"callback">>, <<"outbound_authority">>], Original),
    case ChangedAuthority andalso kz_json:is_true([<<"callback">>, <<"enabled">>], Next) of
        true ->
            UserId = kz_json:get_value(<<"id">>, Authority),
            need(kz_json:get_value(<<"type">>, Authority) =:= <<"user">> andalso
                 lists:any(fun(U) -> kz_doc:id(U) =:= UserId andalso not kz_json:is_false(<<"enabled">>, U) end, Users),
                 400, <<"callback_authority_must_be_enabled_account_user">>);
        false -> ok
    end,
    Language = kz_json:get_value([<<"announcements">>, <<"language">>], Next),
    case Language =/= undefined andalso Language =/= kz_json:get_value([<<"announcements">>, <<"language">>], Original) of
        true -> need(language_selection_ready(Language, Catalog),
                     400, <<"language_not_verified_ready">>);
        false -> ok
    end,
    lists:foreach(fun(Key) ->
        Value = kz_json:get_value(Key, Next),
        case Value =/= undefined andalso Value =/= <<>> andalso Value =/= kz_json:get_value(Key, Original) of
            false -> ok;
            true ->
                ensure_catalog(Catalog, <<"media">>),
                AccountIds = [kz_json:get_value(<<"id">>, M) || M <- kz_json:get_list_value(<<"media">>, Catalog, [])],
                SystemIds = [lists:last(binary:split(kz_json:get_value(<<"id">>, M), <<"/">>, [global]))
                             || M <- kz_json:get_list_value(<<"system_media">>, Catalog, [])],
                need(lists:member(Value, AccountIds ++ SystemIds), 400, <<"media_selection_not_in_catalog">>)
        end
    end, [<<"moh">>, <<"announce">>]),
    NumberPath = [<<"callback">>, <<"outbound_caller_id">>, <<"number">>],
    Number = kz_json:get_value(NumberPath, Next),
    case Number =/= undefined andalso Number =/= kz_json:get_value(NumberPath, Original) of
        true -> ensure_catalog(Catalog, <<"numbers">>),
                need(lists:any(fun(N) -> kz_json:get_value(<<"number">>, N) =:= Number end,
                               kz_json:get_list_value(<<"numbers">>, Catalog, [])), 400, <<"caller_id_not_owned_in_service">>);
        false -> ok
    end.

roster_plan(QueueId, Users, Requested) ->
    need(id(QueueId) andalso is_list(Requested) andalso length(Requested) =< ?LIMIT
         andalso lists:all(fun id/1, Requested) andalso length(lists:usort(Requested)) =:= length(Requested), 400, <<"invalid_roster">>),
    Known = [kz_doc:id(U) || U <- Users],
    need(lists:all(fun(Id) -> lists:member(Id, Known) end, Requested), 400, <<"roster_contains_unknown_user">>),
    lists:filtermap(fun(User) ->
        Queues = kz_json:get_value(<<"queues">>, User, []),
        need(is_list(Queues) andalso lists:all(fun is_binary/1, Queues), 409, <<"invalid_existing_roster_preserved">>),
        Before = lists:member(QueueId, Queues), After = lists:member(kz_doc:id(User), Requested),
        case {Before, After} of
            {false, true} -> need(not kz_json:is_false(<<"enabled">>, User), 400, <<"cannot_assign_disabled_user">>),
                             {true, kz_json:set_value(<<"queues">>, [QueueId|Queues], User)};
            {true, false} -> {true, kz_json:set_value(<<"queues">>, lists:delete(QueueId, Queues), User)};
            _ -> false
        end
    end, Users).

strict_route(Route, QueueId) ->
    Numbers = kz_json:get_value(<<"numbers">>, Route), Flow = kz_json:get_json_value(<<"flow">>, Route, kz_json:new()),
    Data = kz_json:get_json_value(<<"data">>, Flow, kz_json:new()),
    Children = kz_json:get_json_value(<<"children">>, Flow, kz_json:new()),
    id(default(kz_doc:id(Route), kz_json:get_value(<<"id">>, Route)))
        andalso is_list(Numbers) andalso length(Numbers) =:= 1 andalso extension(hd(Numbers)) andalso hd(Numbers) =/= <<>>
        andalso kz_json:get_value(<<"flags">>, Route) =:= [?FLAG, <<?QFLAG/binary, QueueId/binary>>]
        andalso lists:sort(kz_json:get_keys(Flow)) =:= lists:sort([<<"module">>, <<"data">>, <<"children">>])
        andalso kz_json:get_value(<<"module">>, Flow) =:= <<"acdc_member">>
        andalso kz_json:get_keys(Data) =:= [<<"id">>] andalso kz_json:get_value(<<"id">>, Data) =:= QueueId
        andalso kz_json:is_empty(Children) andalso kz_json:get_value(<<"patterns">>, Route, []) =:= [].

route_plan(Context, QueueId, OperationId, Name, Extension, Routes) ->
    Owned = [R || R <- Routes, strict_route(R, QueueId)],
    need(length(Owned) =< 1, 409, <<"multiple_managed_routes_preserved">>),
    Existing = case Owned of [] -> undefined; [R] -> R end,
    %% A removed route is soft-deleted for recovery. A later new operation must
    %% use a new stable ID, not overwrite that tombstone without its revision.
    RouteId = case Existing of undefined -> binary:part(digest([<<"acdc_managed_route">>, QueueId, OperationId]), 0, 32); _ -> kz_doc:id(Existing) end,
    case {Existing, Extension} of
        {undefined, <<>>} -> preserve;
        {_, <<>>} ->
            Sub = permit(Context, <<"callflows">>, [RouteId], ?HTTP_DELETE),
            {delete, cb_context:store(cb_context:set_doc(Sub, Existing), db_doc, Existing)};
        _ ->
            need(not lists:any(fun(R) -> kz_doc:id(R) =/= RouteId andalso lists:member(Extension, kz_json:get_list_value(<<"numbers">>, R, [])) end, Routes),
                 409, <<"extension_already_in_use">>),
            Route = kz_json:set_values([{<<"name">>, <<Name/binary, " (ACDC)">>}, {<<"numbers">>, [Extension]}, {<<"patterns">>, []},
                        {<<"flags">>, [?FLAG, <<?QFLAG/binary, QueueId/binary>>]},
                        {<<"flow">>, kz_json:from_list([{<<"module">>, <<"acdc_member">>},
                                {<<"data">>, kz_json:from_list([{<<"id">>, QueueId}])}, {<<"children">>, kz_json:new()}])}],
                       case Existing of undefined -> kz_json:new(); _ -> kz_doc:public_fields(Existing) end),
            case Existing of
                undefined ->
                    Sub = permit(Context, <<"callflows">>, [], ?HTTP_PUT),
                    Valid = cb_callflows:validate(cb_context:set_req_data(Sub, Route)), validated(Valid),
                    {create, cb_context:set_doc(Valid, kz_doc:set_id(cb_context:doc(Valid), RouteId))};
                _ ->
                    Sub = permit(Context, <<"callflows">>, [RouteId], ?HTTP_POST),
                    Valid = cb_callflows:validate(cb_context:set_req_data(Sub, Route), RouteId), validated(Valid),
                    {update, cb_context:set_doc(Valid, kz_doc:set_revision(cb_context:doc(Valid), kz_doc:revision(Existing)))}
            end
    end.

%% A durable account-local extension index closes races between aggregate
%% writers for DIFFERENT queues. These are not expiring locks: an unresolved
%% operation retains its reservation and receipt for explicit recovery. Direct
%% legacy callflow writers do not participate and remain outside this guard.
%% At most the old and target extension are read/claimed, in deterministic order.
reservation_plan(_Context, _QueueId, _OperationId, preserve, _Routes) -> [];
reservation_plan(Context, QueueId, OperationId, {Action, RouteContext}, Routes) ->
    Route = cb_context:doc(RouteContext), RouteId = kz_doc:id(Route),
    Existing = case [R || R <- Routes, kz_doc:id(R) =:= RouteId] of [] -> undefined; [R] -> R end,
    Old = case Existing of undefined -> []; _ -> kz_json:get_list_value(<<"numbers">>, Existing) end,
    Target = case Action of delete -> []; _ -> kz_json:get_list_value(<<"numbers">>, Route) end,
    Extensions = lists:usort(Old ++ Target),
    need(length(Extensions) =< 2 andalso lists:all(fun extension/1, Extensions), 409, <<"invalid_managed_route_extensions">>),
    [{reservation_doc(Context, QueueId, RouteId, OperationId, Extension, Existing), lists:member(Extension, Target)}
     || Extension <- Extensions].

reservation_doc(Context, QueueId, RouteId, OperationId, Extension, Existing) ->
    Account = cb_context:account_id(Context), Db = cb_context:db_name(Context),
    ExistingRevision = case Existing of undefined -> null; _ -> kz_doc:revision(Existing) end,
    Id = <<"acdc_queue_extension_", (digest([Account, Extension]))/binary>>,
    Current = case kz_datamgr:open_doc(Db, Id) of
                  {error, not_found} -> kz_json:from_list([{<<"_id">>, Id}]);
                  {ok, D} ->
                      need(scoped_doc(D, Context, <<"acdc_queue_extension">>)
                           andalso kz_json:get_value(<<"extension">>, D) =:= Extension,
                           409, <<"extension_reservation_identity_conflict">>),
                      Released = kz_json:get_value(<<"state">>, D) =:= <<"released">>,
                      Assigned = Existing =/= undefined andalso kz_json:get_value(<<"state">>, D) =:= <<"assigned">>
                          andalso kz_json:get_value(<<"queue_id">>, D) =:= QueueId
                          andalso kz_json:get_value(<<"route_id">>, D) =:= RouteId
                          andalso kz_json:get_value(<<"route_revision">>, D) =:= kz_doc:revision(Existing)
                          andalso lists:member(Extension, kz_json:get_list_value(<<"numbers">>, Existing, [])),
                      need(Released orelse Assigned, 409, <<"extension_reserved_reload_or_recover">>), D;
                  _ -> fail(503, <<"extension_reservation_unavailable">>)
              end,
    kz_doc:update_pvt_parameters(kz_json:set_values([{<<"extension">>, Extension}, {<<"queue_id">>, QueueId},
        {<<"route_id">>, RouteId}, {<<"operation_id">>, OperationId}, {<<"state">>, <<"reserved">>},
        {<<"route_revision">>, ExistingRevision}], Current),
        Db, [{account_id, Account}, {type, <<"acdc_queue_extension">>}]).

reserve_extensions(_Context, [], Receipt) -> {[], Receipt};
reserve_extensions(Context, Plans, Receipt0) ->
    Ids = [kz_doc:id(D) || {D, _} <- Plans],
    Receipt1 = phase(Context, Receipt0, <<"reserve_extensions">>, Ids),
    {Claimed, Receipt2} = lists:foldl(fun({Doc, Target}, {Acc, Receipt}) ->
        case kz_datamgr:save_doc(cb_context:db_name(Context), Doc) of
            {ok, Saved} ->
                %% Persist each confirmed claim before starting another one.
                %% A lost reply still leaves its exact ID in in_flight.
                Claims = kz_json:get_list_value(<<"extension_claims">>, Receipt, []),
                Claim = kz_json:from_list([{<<"id">>, kz_doc:id(Saved)}, {<<"extension">>, kz_json:get_value(<<"extension">>, Saved)},
                                          {<<"revision">>, kz_doc:revision(Saved)}]),
                Next = persist_receipt(Context, kz_json:set_value(<<"extension_claims">>, Claims ++ [Claim], Receipt)),
                {Acc ++ [{Saved, Target}], Next};
            {error, conflict} -> fail(409, <<"extension_reservation_conflict_no_settings_written">>);
            _ -> fail(503, <<"extension_reservation_outcome_unknown">>)
        end
    end, {[], Receipt1}, Plans),
    {Claimed, committed(Context, Receipt2, <<"reserve_extensions">>, Ids)}.

finalize_extensions(_Context, [], _SavedRoute, Receipt) -> Receipt;
finalize_extensions(Context, Claims, SavedRoute, Receipt0) ->
    Revision = kz_doc:revision(SavedRoute),
    need(is_binary(Revision), 503, <<"saved_route_revision_unavailable">>),
    Ids = [kz_doc:id(D) || {D, _} <- Claims],
    Receipt1 = phase(Context, Receipt0, <<"finalize_extensions">>, Ids),
    lists:foreach(fun({Doc, Target}) ->
        State = case Target of true -> <<"assigned">>; false -> <<"released">> end,
        Final = kz_json:set_values([{<<"state">>, State}, {<<"route_revision">>, Revision}], Doc),
        case kz_datamgr:save_doc(cb_context:db_name(Context), Final) of
            {ok, _} -> ok;
            _ -> fail(503, <<"extension_finalization_requires_recovery">>)
        end
    end, Claims),
    committed(Context, Receipt1, <<"finalize_extensions">>, Ids).

%% The receipt itself is the unique CAS claim. There is no process lock or lease
%% to expire/reacquire while an earlier writer might still be running. A crashed
%% or ambiguous operation remains explicit and requires a fresh editor read;
%% it is never automatically replayed over documents changed by another writer.
execute_plan(Context, {replay, Receipt}) -> success(kz_json:get_json_value(<<"result">>, Receipt), Context);
execute_plan(Context, Plan) when is_map(Plan) ->
    Db = cb_context:db_name(Context),
    case kz_datamgr:save_doc(Db, maps:get(receipt, Plan)) of
        {error, conflict} -> fail(409, <<"request_already_claimed_retry_identical_request">>);
        {error, _} -> fail(503, <<"operation_claim_failed_no_settings_written">>);
        {ok, Receipt} ->
            %% Once claimed, ALL failures carry the persisted operation identity.
            try execute_claimed(Context, Plan, Receipt)
            catch _:_ ->
                Current = case kz_datamgr:open_doc(Db, kz_doc:id(Receipt)) of {ok, R} -> R; _ -> Receipt end,
                fail(409, <<"operation_incomplete_reload_before_recovery">>, operation_public(Current))
            end
    end.

execute_claimed(Context, Plan, Receipt0) ->
    QueueContext = maps:get(queue, Plan), QueueId = kz_doc:id(cb_context:doc(QueueContext)),
    {Claims, ReservedReceipt} = reserve_extensions(Context, maps:get(reservations, Plan), Receipt0),
    Receipt1 = phase(Context, ReservedReceipt, <<"queue">>, [QueueId]),
    SavedContext = case maps:get(create, Plan) of true -> cb_queues:put(QueueContext); false -> cb_queues:post(QueueContext, QueueId) end,
    validated(SavedContext),
    Receipt2 = committed(Context, Receipt1, <<"queue">>, [QueueId]),
    Users = maps:get(users, Plan), UserIds = [kz_doc:id(U) || U <- Users],
    Receipt3 = phase(Context, Receipt2, <<"roster">>, UserIds),
    case Users of
        [] -> ok;
        _ ->
            Updated = [kz_doc:update_pvt_parameters(U, cb_context:db_name(Context), [{account_id, cb_context:account_id(Context)}]) || U <- Users],
            case kz_datamgr:save_docs(cb_context:db_name(Context), Updated) of
                {ok, Results} ->
                    Good = [kz_doc:id(R) || R <- Results, kz_json:is_json_object(R),
                             kz_json:get_value(<<"error">>, R) =:= undefined,
                             is_binary(kz_doc:revision(R)), byte_size(kz_doc:revision(R)) > 0,
                             lists:member(kz_doc:id(R), UserIds)],
                    case length(Results) =:= length(UserIds) andalso lists:sort(Good) =:= lists:sort(UserIds) of
                        true -> ok;
                        false ->
                            _ = record_partial(Context, Receipt3, Good),
                            fail(409, <<"roster_partial_write">>)
                    end;
                _ -> fail(503, <<"roster_write_outcome_unknown">>)
            end
    end,
    Receipt4 = committed(Context, Receipt3, <<"roster">>, UserIds),
    Route = maps:get(route, Plan),
    RouteIds = case Route of preserve -> []; {_, RC} -> [kz_doc:id(cb_context:doc(RC))] end,
    Receipt5 = phase(Context, Receipt4, <<"route">>, RouteIds),
    SavedRouteContext = case Route of
        preserve -> undefined;
        {create, RC1} -> cb_callflows:put(RC1);
        {update, RC1} -> cb_callflows:post(RC1, kz_doc:id(cb_context:doc(RC1)));
        {delete, RC1} -> delete_route_cas(RC1)
    end,
    SavedRoute = case SavedRouteContext of undefined -> undefined; _ -> validated(SavedRouteContext), cb_context:doc(SavedRouteContext) end,
    Receipt6 = finalize_extensions(Context, Claims, SavedRoute, committed(Context, Receipt5, <<"route">>, RouteIds)),
    Result = kz_json:from_list([{<<"queue_id">>, QueueId}, {<<"operation_id">>, kz_doc:id(Receipt6)},
                  {<<"state">>, <<"complete">>}, {<<"atomic">>, false},
                  {<<"roster_preserved">>, kz_json:get_value(<<"roster">>, maps:get(body, Plan)) =:= null},
                  {<<"route_preserved">>, kz_json:get_value(<<"route">>, maps:get(body, Plan)) =:= null},
                  {<<"reload_required">>, true}]),
    _ = persist_receipt(Context, kz_json:set_values([{<<"state">>, <<"complete">>}, {<<"phase">>, <<"complete">>},
                                                    {<<"result">>, Result}], Receipt6)),
    success(Result, Context).

delete_route_cas(Context) ->
    %% crossbar_doc:delete/1 refreshes the current revision before its default
    %% soft-delete. That is unsuitable here: a route changed after validation
    %% must conflict. Save the tombstone against our exact observed revision,
    %% preserving the full original route for recovery and using normal save
    %% hooks. Number assignment tracking happens only after the CAS succeeds.
    Doc = cb_context:doc(Context),
    Saved = crossbar_doc:save(cb_context:set_doc(Context, kz_doc:set_soft_deleted(Doc, true))),
    validated(Saved),
    Account = cb_context:account_id(Context),
    Unassigned = [{N, undefined} || N <- kz_json:get_list_value(<<"numbers">>, Doc, []),
                                   knm_converters:is_reconcilable(N, Account)],
    Updates = cb_modules_util:apply_assignment_updates(Unassigned, Context),
    cb_modules_util:log_assignment_updates(Updates), Saved.

phase(Context, Receipt, Phase, Ids) ->
    persist_receipt(Context, kz_json:set_values([{<<"phase">>, Phase}, {<<"in_flight">>, Ids}], Receipt)).
committed(Context, Receipt, Phase, Ids) ->
    Before = kz_json:get_list_value(<<"committed">>, Receipt, []),
    Entry = kz_json:from_list([{<<"phase">>, Phase}, {<<"ids">>, Ids}]),
    Remaining = lists:delete(Phase, kz_json:get_list_value(<<"remaining">>, Receipt, [])),
    persist_receipt(Context, kz_json:set_values([{<<"committed">>, Before ++ [Entry]}, {<<"in_flight">>, []},
                                                {<<"remaining">>, Remaining}], Receipt)).
record_partial(Context, Receipt, Good) ->
    Before = kz_json:get_list_value(<<"committed">>, Receipt, []),
    Entry = kz_json:from_list([{<<"phase">>, <<"roster_partial">>}, {<<"ids">>, Good}]),
    persist_receipt(Context, kz_json:set_values([{<<"state">>, <<"partial">>}, {<<"committed">>, Before ++ [Entry]}], Receipt)).
persist_receipt(Context, Receipt) ->
    case kz_datamgr:save_doc(cb_context:db_name(Context), Receipt) of
        {ok, Saved} -> Saved;
        _ -> fail(503, <<"operation_receipt_update_failed">>)
    end.
operation_public(Receipt) ->
    kz_json:from_list([{<<"operation_id">>, kz_doc:id(Receipt)}, {<<"queue_id">>, kz_json:get_value(<<"queue_id">>, Receipt)},
                       {<<"state">>, kz_json:get_value(<<"state">>, Receipt)}, {<<"phase">>, kz_json:get_value(<<"phase">>, Receipt)},
                       {<<"committed">>, kz_json:get_value(<<"committed">>, Receipt, [])},
                       {<<"in_flight">>, kz_json:get_value(<<"in_flight">>, Receipt, [])},
                       {<<"remaining">>, kz_json:get_value(<<"remaining">>, Receipt, [])},
                       {<<"extension_claims">>, kz_json:get_value(<<"extension_claims">>, Receipt, [])},
                       {<<"atomic">>, false}, {<<"reload_required">>, true}]).
