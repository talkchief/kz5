-module(media_map).
-export([prompt_path/3]).
prompt_path(Db, Prompt, Language) ->
    [{media_map, _, _, _, Languages}] = ets:lookup(?MODULE, <<Db/binary, "/", Prompt/binary>>),
    kz_json:get_value(Language, Languages).
