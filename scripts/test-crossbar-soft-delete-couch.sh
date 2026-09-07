#!/usr/bin/env bash
# Explicit development-only local CouchDB mutation. No services or account data.
set -Eeuo pipefail
umask 077
[[ ( $# == 1 || ( $# == 2 && $2 == --baseline-driver ) ) && $1 == --owned-local-couchdb-probe ]] || exit 64
couch_mode=${2:-current}
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
couch_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$couch_root"
couch_output=$(mktemp -d /tmp/kazoo-soft-delete-couch.XXXXXX)
export KAZOO_COUCH_PROBE_OUTPUT="$couch_output"
export ERL_LIBS="$couch_root/deps:$couch_root/core:$couch_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP=/dev/null
couch_exit() {
    local couch_code=$?
    trap - EXIT
    if [[ -f "$couch_output/inputs.sha256" ]]; then
        sha256sum --status --check "$couch_output/inputs.sha256" || couch_code=99
    fi
    printf 'Local primary CAS probe exit %s; sanitized evidence: %s\n' "$couch_code" "$couch_output"
    exit "$couch_code"
}
trap couch_exit EXIT
[[ $(git -C applications/crossbar rev-parse HEAD) == 2ac862830f9b626d2170d08daf1991b0ca33dba7 ]]
[[ $(git -C core rev-parse HEAD) == 5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72 ]]
git -C applications/crossbar apply --reverse --check "$couch_root/scripts/patches/crossbar-soft-delete-revision.patch"
git -C core apply --reverse --check "$couch_root/scripts/patches/kazoo-couch-single-delete-result.patch"
couch_sources=(applications/crossbar/src/crossbar_doc.erl applications/crossbar/src/cb_context.erl
    applications/crossbar/src/crossbar_util.erl core/kazoo_documents/src/kz_doc.erl
    core/kazoo_stdlib/src/kz_json.erl core/kazoo_stdlib/src/kz_term.erl
    core/kazoo_stdlib/src/props.erl core/kazoo_stdlib/src/kz_time.erl
    core/kazoo_data/src/kzs_util.erl core/kazoo_schemas/src/kz_json_schema.erl
    core/kazoo_data/src/kz_datamgr.erl core/kazoo_data/src/kzs_doc.erl
    core/kazoo_couch/src/kz_couch_doc.erl core/kazoo_couch/src/kz_couch_util.erl
    core/kazoo_couch/src/kazoo_couch.erl)
couch_inputs=("${couch_sources[@]}" scripts/test-crossbar-soft-delete-couch.sh
    scripts/erlang-tests/crossbar_soft_delete_couch_probe.erl
    scripts/patches/crossbar-soft-delete-revision.patch
    scripts/patches/kazoo-couch-single-delete-result.patch scripts/install-kazoo5.sh)
/usr/bin/find core applications/crossbar/src deps/couchbeam/include -type f -name '*.hrl' | LC_ALL=C sort > "$couch_output/headers.list"
while IFS= read -r couch_header; do couch_inputs+=("$couch_header"); done < "$couch_output/headers.list"
while IFS= read -r couch_dependency; do couch_inputs+=("$couch_dependency"); done < <(
    /usr/bin/find deps/couchbeam/ebin deps/hackney/ebin deps/eini/ebin -type f \( -name '*.beam' -o -name '*.app' \) | LC_ALL=C sort)
sha256sum "${couch_inputs[@]}" > "$couch_output/inputs.sha256"
if [[ $couch_mode == --baseline-driver ]]; then
    mkdir "$couch_output/baseline"
    git -C core archive 5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72 kazoo_couch/src/kz_couch_doc.erl | tar -xf - -C "$couch_output/baseline"
    couch_sources[12]="$couch_output/baseline/kazoo_couch/src/kz_couch_doc.erl"
    sha256sum "${couch_sources[12]}" >> "$couch_output/inputs.sha256"
fi
printf '%s\n' 'Real local CouchDB primary CAS through native deletion/save modules; isolated BEAM, controlled routing/cache/publication, prebuilt dependencies. No HTTP resource/auth, AMQP/cache propagation, replication, failure injection or deployment proof. Retains a unique synthetic database and ownership marker; hard-deletes only two exact owned fixture documents after success.' | tee "$couch_output/scope.log"
erlc -Werror +debug_info -I applications/crossbar/src -I core/kazoo_couch/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$couch_output" "${couch_sources[@]}"
erlc -Werror +debug_info -o "$couch_output" scripts/erlang-tests/crossbar_soft_delete_couch_probe.erl
erl -noshell -pa "$couch_output" -eval '
    lists:foreach(fun(M) ->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join(os:getenv("KAZOO_COUCH_PROBE_OUTPUT"),atom_to_list(M)++".beam"),
        Expected=code:which(M),
        Options=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,Options)
    end,[crossbar_doc,cb_context,crossbar_util,kz_doc,kz_json,kz_term,props,kz_time,kzs_util,
         kz_json_schema,kz_datamgr,kzs_doc,kz_couch_doc,kz_couch_util,kazoo_couch]),
    lists:foreach(fun(App) ->
        {ok,[{application,App,Props}]}=file:consult(filename:join(["deps",atom_to_list(App),"ebin",atom_to_list(App)++".app"])),
        lists:foreach(fun(M) ->
            {module,M}=code:ensure_loaded(M),
            Expected=filename:absname(filename:join(["deps",atom_to_list(App),"ebin",atom_to_list(M)++".beam"])),
            Expected=filename:absname(code:which(M))
        end,proplists:get_value(modules,Props))
    end,[couchbeam,hackney,eini]),
    crossbar_soft_delete_couch_probe:run().' | tee "$couch_output/result.log"
