-module(kz_datamgr).
-export([open_doc/2, open_doc/3]).
open_doc(Db, Id) -> open_doc(Db, Id, []).
open_doc(<<"system_media">>, Id, _Options) ->
    Key = {reads, Id}, N = case get(Key) of undefined -> 1; Value -> Value + 1 end,
    put(Key, N),
    Doc = maps:get(Id, get(docs)),
    case get(race) of
        {Id, N} -> {ok, kz_json:set_value(<<"_rev">>, <<"2-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>, Doc)};
        _ -> {ok, Doc}
    end.
