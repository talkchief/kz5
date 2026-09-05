-module(acdc_editor_manifest_path_tests).
-include_lib("eunit/include/eunit.hrl").

explicit_path_wins_without_legacy_probe_test() ->
    %% Missing, relative and invalid operator paths are returned to the strict
    %% protected reader, never replaced with a default that hides the failure.
    lists:foreach(fun(Path) ->
        ?assertEqual(binary_to_list(Path), cb_acdc_queue_editor:manifest_path(
            Path, fun(_) -> error(unexpected_legacy_probe) end, "/custom/acdc/language-capabilities.json"))
    end, [<<"/protected/custom.json">>, <<"/missing/custom.json">>, <<"relative.json">>]).

legacy_artifact_or_error_is_not_bypassed_test() ->
    Legacy = "/var/www/html/monster-ui/apps/acdc/language-capabilities.json",
    lists:foreach(fun(Result) ->
        ?assertEqual(Legacy, cb_acdc_queue_editor:manifest_path(undefined,
            fun(Path) -> ?assertEqual(Legacy, Path), Result end, "/custom/acdc/language-capabilities.json"))
    end, [{ok, regular}, {ok, symlink}, {error, eacces}, {error, enotdir}, {error, eio}]).

missing_webroot_uses_apps_owned_default_test() ->
    ?assertEqual("/etc/kazoo/acdc/language-capabilities.json",
        cb_acdc_queue_editor:manifest_path(undefined, fun(_) -> {error, enoent} end, false)).

missing_webroot_uses_explicit_service_config_root_test() ->
    ?assertEqual("/private/custom-kazoo/acdc/language-capabilities.json",
        cb_acdc_queue_editor:manifest_path(undefined, fun(_) -> {error, enoent} end,
            "/private/custom-kazoo/acdc/language-capabilities.json")).

bad_environment_is_not_silently_replaced_test() ->
    %% The existing absolute-path/protected-parent checks in read_manifest reject
    %% these values. Selection does not guess another configuration root.
    lists:foreach(fun(Value) ->
        ?assertEqual(Value, cb_acdc_queue_editor:manifest_path(undefined,
            fun(_) -> {error, enoent} end, Value))
    end, ["", "relative.json"]).
