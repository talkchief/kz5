%%% Acknowledged, retry-safe persistence for ACDC statistics snapshots.
%%% This Source Code Form is subject to the Mozilla Public License, v. 2.0.
-module(acdc_stats_archive).
-export([save/1, same_document/2, select/2]).
-include("acdc.hrl").

-spec save(dict:dict()) -> [{binary(), binary()}].
save(Groups) ->
    lists:append([save_account(Account, Docs) || {Account, Docs} <- dict:to_list(Groups)]).

-spec save_account(binary(), kz_json:objects()) -> [{binary(), binary()}].
save_account(Account, Docs) ->
    Db = acdc_stats_util:db_name(Account),
    Result = try kz_datamgr:save_docs(Db, Docs)
             catch _:_ -> {'error', 'save_exception'}
             end,
    Saved = case Result of
        {'ok', Replies} when is_list(Replies) ->
            [{Account, kz_doc:id(Doc)} || Doc <- Docs, acknowledged(Db, Doc, Replies)];
        _ -> []
    end,
    case length(Saved) =:= length(Docs) of
        'true' -> 'ok';
        'false' -> lager:error("ACDC archive account=~s persisted=~B pending=~B; unsaved records remain retryable"
                               ,[Account, length(Saved), length(Docs)-length(Saved)])
    end,
    Saved.

-spec acknowledged(binary(), kz_json:object(), kz_json:objects()) -> boolean().
acknowledged(Db, Doc, Replies) ->
    Id = kz_doc:id(Doc),
    Matching = [R || R <- Replies, kz_json:get_first_defined([<<"id">>, <<"_id">>], R) =:= Id],
    case Matching of
        [R] ->
            case kz_json:get_value(<<"error">>, R) of
                'undefined' -> kz_json:get_value(<<"ok">>, R, 'true') =/= 'false'
                    andalso kz_term:is_ne_binary(kz_json:get_first_defined([<<"rev">>, <<"_rev">>], R));
                <<"conflict">> ->
                    %% Retrying a write whose ACK was lost is safe only if the
                    %% current database document is the exact same snapshot.
                    existing_snapshot(Db, Id, Doc);
                _ -> 'false'
            end;
        _ -> 'false'
    end.

-spec existing_snapshot(binary(), binary(), kz_json:object()) -> boolean().
existing_snapshot(Db, Id, Doc) ->
    try kz_datamgr:open_doc(Db, Id) of
        {'ok', Existing} -> same_document(Doc, Existing);
        _ -> 'false'
    catch _:_ -> 'false'
    end.

-spec same_document(kz_json:object(), kz_json:object()) -> boolean().
same_document(A, B) ->
    Ignore = [<<"_rev">>, <<"pvt_created">>, <<"pvt_modified">>],
    kz_json:are_equal(kz_json:delete_keys(Ignore, A), kz_json:delete_keys(Ignore, B)).

-spec select(atom(), ets:match_spec()) -> list().
select(Table, Match) ->
    try ets:select(Table, Match)
    catch 'error':'badarg' ->
        %% A periodic worker can be scheduled after shutdown has started. The
        %% synchronous shutdown path uses snapshots captured by the owner.
        lager:debug("archive table ~p is no longer available", [Table]),
        []
    end.
