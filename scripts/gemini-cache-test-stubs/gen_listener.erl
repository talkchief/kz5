-module(gen_listener).
-export([call/3]).
call(Module, {add_mapping, <<"system_media">> = Db, Doc}, 5000) ->
    N = case get(writes) of undefined -> 0; Value -> Value end,
    put(writes, N + 1),
    Prompt = kz_json:get_value(<<"prompt_id">>, Doc),
    Language = kz_json:get_value(<<"language">>, Doc),
    Id = kz_json:get_value(<<"_id">>, Doc),
    Key = <<Db/binary, "/", Prompt/binary>>,
    Path = <<"/system_media/", (kz_http_util:urlencode(Id))/binary>>,
    true = ets:insert(Module, {media_map, Key, Db, Prompt, kz_json:from_list([{Language, Path}])}),
    ok.
