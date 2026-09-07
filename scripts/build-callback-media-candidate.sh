#!/usr/bin/env bash
# Offline focused production build. Does not load/install BEAMs or change services.
set -Eeuo pipefail
[[ $# == 0 ]] || { printf 'Usage: %s\n' "$0" >&2; exit 2; }
umask 077
callback_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
callback_build=$(mktemp -d /tmp/kazoo-callback-media-build.XXXXXX)
callback_complete=false
callback_pinned=false
callback_modules=(acdc_gemini_prompts cf_acdc_member acdc_callback_caller
    acdc_announcements acdc_announcements_sup acdc_callback_menu acdc_language
    kapi_acdc_callback)
cd "$callback_root"
mkdir "$callback_build/ebin"
callback_finish() {
    local result=$? stable=false
    trap - EXIT
    if [[ $callback_pinned == true ]] && sha256sum --status -c "$callback_build/inputs.sha256"; then
        stable=true
    else
        result=1
    fi
    [[ $callback_complete == true ]] || result=1
    printf '{"exit_code":%s,"complete":%s,"inputs_stable":%s,"production_modules":8,"tests":false,"deployment":false,"runtime_writes":false}\n' \
        "$result" "$callback_complete" "$stable" > "$callback_build/receipt.json"
    printf 'Callback production build exit %s; retained evidence: %s\n' "$result" "$callback_build"
    exit "$result"
}
trap callback_finish EXIT
callback_sources=()
for callback_module in "${callback_modules[@]}"; do
    callback_sources+=("applications/acdc/src/$callback_module.erl")
done
# Prepared local dependency/header bytes are inputs, not fresh dependency builds.
# Pin them, including the installed ACDC files, to detect concurrent replacement.
find deps core applications -type f \( -name '*.hrl' -o -path '*/ebin/*.beam' -o -path '*/ebin/*.app' \) \
    -print | LC_ALL=C sort -u > "$callback_build/dependencies.list"
mapfile -t callback_dependencies < "$callback_build/dependencies.list"
sha256sum -- scripts/build-callback-media-candidate.sh "${callback_sources[@]}" \
    "${callback_dependencies[@]}" > "$callback_build/inputs.sha256"
callback_pinned=true
export ERL_LIBS="$callback_root/deps:$callback_root/core:$callback_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -Werror +warn_missing_spec -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$callback_build/ebin" "${callback_sources[@]}"
export KAZOO_CALLBACK_CANDIDATE="$callback_build"
# Read BEAM metadata without loading the candidate into any running application.
erl -no_dot_erlang -noshell -eval '
    Dir=os:getenv("KAZOO_CALLBACK_CANDIDATE"),
    Mods=[acdc_gemini_prompts,cf_acdc_member,acdc_callback_caller,acdc_announcements,
          acdc_announcements_sup,acdc_callback_menu,acdc_language,kapi_acdc_callback],
    Metadata=[begin
        File=filename:join([Dir,"ebin",atom_to_list(M)++".beam"]),
        {ok,{M,[{compile_info,Info},{exports,Exports},{imports,Imports}]}}=
            beam_lib:chunks(File,[compile_info,exports,imports]),
        Options=proplists:get_value(options,Info,[]),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(_)->false end,Options),
        false=lists:member({test,0},Exports),
        {ok,{M,Digest}}=beam_lib:md5(File),
        #{module=>M,md5=>Digest,exports=>Exports,imports=>Imports}
    end || M<-Mods],
    ok=file:write_file(filename:join(Dir,"modules.term"),io_lib:format("~p.~n",[Metadata])),
    halt(0).
'
(cd "$callback_build" && sha256sum -- ebin/*.beam modules.term > artifacts.sha256)
callback_complete=true
