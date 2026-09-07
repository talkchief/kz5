%% Read-only, fixed native application inventory request. Invoke with exactly
%% [{'MediaNode', 'validated_freeswitch_node@host'}] via file:script/2.
%% Compatibility evidence only: this does not stop startup dispatch or prove
%% an intercept/call. Deploy the native media module before the eCallMgr code.
try
    true = is_atom(MediaNode),
    NodeBytes = atom_to_binary(MediaNode, utf8),
    true = byte_size(NodeBytes) =< 255,
    match = re:run(NodeBytes, <<"\\A[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+\\z">>, [{capture, none}]),
    %% The pinned native API has its own request timeout; SUP and the local
    %% caller add outer bounds. No retry or alternate node/command is attempted.
    {ok, Bytes} = freeswitch:api(MediaNode, show, <<"application as json">>),
    true = is_binary(Bytes) andalso byte_size(Bytes) > 0 andalso byte_size(Bytes) =< 1048576,
    %% decode/1 logs malformed input bytes; unsafe_decode throws for our fixed
    %% catch instead, keeping remote response content out of diagnostics.
    Object = kz_json:unsafe_decode(Bytes),
    UniqueObject = fun(Value) ->
        true = kz_json:is_json_object(Value),
        Keys = kz_json:get_keys(Value),
        true = length(Keys) =:= length(lists:usort(Keys)),
        true = lists:all(fun erlang:is_binary/1, Keys)
    end,
    UniqueObject(Object),
    Rows = kz_json:get_value(<<"rows">>, Object),
    true = is_list(Rows) andalso length(Rows) > 0 andalso length(Rows) =< 4096,
    lists:foreach(fun(Row) ->
        UniqueObject(Row),
        Name = kz_json:get_value(<<"name">>, Row),
        Owner = kz_json:get_value(<<"ikey">>, Row),
        true = is_binary(Name) andalso byte_size(Name) > 0,
        true = is_binary(Owner) andalso byte_size(Owner) > 0
    end, Rows),
    [Intercept] = [R || R <- Rows, kz_json:get_value(<<"name">>, R) =:= <<"kz_intercept">>],
    <<"mod_kazoo">> = kz_json:get_value(<<"ikey">>, Intercept),
    ecallmgr_atomic_media_verified
catch _:_ -> {error, ecallmgr_atomic_media_unverified} end.
