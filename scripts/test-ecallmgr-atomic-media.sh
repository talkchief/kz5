#!/usr/bin/env bash
# Root-only serialized offline fixture: real checked-in Erlang script/JSON
# decoder, synthetic freeswitch API, and shell RPC stubs. No live node/service.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || exit 64
atomic_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
atomic_output=$(mktemp -d /tmp/kazoo-atomic-media-test.XXXXXX)
atomic_finish() {
    local result=$?
    trap - EXIT
    if ! sha256sum --check --status "$atomic_output/inputs.sha256"; then result=99; fi
    printf 'Atomic media fixture exit=%s; retained evidence: %s\n' "$result" "$atomic_output"
    exit "$result"
}
trap atomic_finish EXIT
sha256sum "$atomic_root/scripts/verify-ecallmgr-atomic-media.erl" \
    "$atomic_root/scripts/install-kazoo5.sh" "$atomic_root/scripts/test-ecallmgr-atomic-media.sh" \
    "$atomic_root/core/kazoo_stdlib/ebin/kz_json.beam" >"$atomic_output/inputs.sha256"
export ERL_LIBS="$atomic_root/deps:$atomic_root/core:$atomic_root/applications"
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP="$atomic_output/erl_crash.dump"
export ATOMIC_MEDIA_SCRIPT="$atomic_root/scripts/verify-ecallmgr-atomic-media.erl"
printf '%s\n' '-module(freeswitch).' '-export([api/3]).' \
    'api(Node, Command, Args) -> put(atomic_request, {Node, Command, Args}), get(atomic_response).' \
    >"$atomic_output/freeswitch.erl"
erlc -Werror -o "$atomic_output" "$atomic_output/freeswitch.erl"
erl -noshell -pa "$atomic_output" -eval '
    %% file:script uses erl_eval, not the compiler. Local named fun references
    %% are undef there even for BIFs; explicit erlang-qualified funs are valid.
    {ok,LocalTokens,_}=erl_scan:string("fun is_binary/1."),
    {ok,LocalForms}=erl_parse:parse_exprs(LocalTokens),
    ExitTag=list_to_atom("EXIT"),
    {ExitTag,{undef,_}}=(catch erl_eval:exprs(LocalForms,erl_eval:new_bindings())),
    Script=os:getenv("ATOMIC_MEDIA_SCRIPT"), Node=list_to_atom("freeswitch@media.example.invalid"),
    Good = <<"{\"rows\":[{\"name\":\"other\",\"ikey\":\"mod_other\"},{\"name\":\"kz_intercept\",\"ikey\":\"mod_kazoo\"}]}">>,
    Check=fun(Response,Expected) ->
        erase(atomic_request), put(atomic_response,Response),
        {ok,Expected}=file:script(Script,[{list_to_atom("MediaNode"),Node}]),
        {Node,show,<<"application as json">>}=get(atomic_request)
    end,
    Check({ok,Good},ecallmgr_atomic_media_verified),
    Bad=[{error,timeout},{error,nodedown},timeout,{ok,[]},{ok,<<>>},{ok,<<"not json">>},
        {ok,<<"{}">>},{ok,<<"{\"rows\":[]}">>},{ok,<<"{\"rows\":{}}">>},
        {ok,<<"{\"rows\":[null]}">>},
        {ok,<<"{\"rows\":[{\"name\":\"kz_intercept\",\"ikey\":\"mod_other\"}]}">>},
        {ok,<<"{\"rows\":[{\"name\":\"intercept\",\"ikey\":\"mod_kazoo\"}]}">>},
        {ok,<<"{\"rows\":[{\"name\":\"kz_intercept\"}]}">>},
        {ok,<<"{\"rows\":[{\"name\":\"kz_intercept\",\"ikey\":\"mod_kazoo\"},{\"name\":\"kz_intercept\",\"ikey\":\"mod_other\"}]}">>},
        {ok,<<"{\"rows\":[{\"name\":\"kz_intercept\",\"ikey\":\"mod_kazoo\",\"ikey\":\"mod_other\"}]}">>},
        {ok,<<"{\"rows\":[],\"rows\":[{\"name\":\"kz_intercept\",\"ikey\":\"mod_kazoo\"}]}">>},
        {ok,binary:copy(<<"x">>,1048577)},
        {ok,kz_json:encode(kz_json:from_list([{<<"rows">>,lists:duplicate(4097,kz_json:from_list([{<<"name">>,<<"x">>},{<<"ikey">>,<<"y">>}]))}]))}],
    lists:foreach(fun(R)->Check(R,{error,ecallmgr_atomic_media_unverified}) end,Bad),
    erase(atomic_request),
    {ok,{error,ecallmgr_atomic_media_unverified}}=file:script(Script,[{list_to_atom("MediaNode"),invalid_node}]),
    undefined=get(atomic_request),
    io:format("PASS ~B production-script cases with synthetic native API~n",[length(Bad)+2]), halt(0).
' >"$atomic_output/erlang.log" 2>&1

# Extract only the new shell gate; never source or execute installer main.
node - "$atomic_root/scripts/install-kazoo5.sh" "$atomic_output/gate.sh" <<'JS'
const fs=require('node:fs'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[2],'utf8');
const definitions=source.match(/^verify_ecallmgr_atomic_media\(\) \{\n[\s\S]*?^\}\n/gm);
assert.equal(definitions?.length,1);
const permissions=source.match(/^prepare_kazoo_runtime_artifact_permissions\(\) \{\n[\s\S]*?^\}\n/gm);
assert.equal(permissions?.length,1);
assert(source.includes('    verify_configured_freeswitch_nodes\n    verify_ecallmgr_atomic_media\n'));
fs.writeFileSync(process.argv[3],definitions[0]+permissions[0],{flag:'wx',mode:0o600});
JS
source "$atomic_output/gate.sh"
SCRIPT_DIR="$atomic_root/scripts"
DRY_RUN=false
log() { printf 'LOG %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; }
die() { printf '%s\n' 'FIXTURE-DIE' >&2; exit 65; }
freeswitch_nodes_to_manage() { printf '%s\n' "$atomic_nodes"; }
timeout() {
    [[ $1 == --signal=KILL && $2 == 20 && $3 == sup && $4 == -t && $5 == 15 &&
       $6 == -n && $7 == ecallmgr && $8 == -e && $9 == file && ${10} == script ]] || exit 91
    [[ ${11} == "\"$SCRIPT_DIR/verify-ecallmgr-atomic-media.erl\"" &&
       ${12} == "[{'MediaNode','freeswitch@"*"'}]" ]] || exit 91
    printf '%s\n' "${12}" >>"$atomic_output/rpc.log"
    case $atomic_reply in
        good) printf '%s\n' '{ok,ecallmgr_atomic_media_verified}' ;;
        bad) printf '%s\n' '{ok,{error,ecallmgr_atomic_media_unverified}}' ;;
        malformed) printf '%s\n' '{ok,ecallmgr_atomic_media_verified} extra' ;;
        unreachable) return 3 ;;
    esac
}
atomic_nodes=$'media-a.example.invalid\nfreeswitch@media-b.example.invalid'
atomic_reply=good
verify_ecallmgr_atomic_media >"$atomic_output/shell-good.log"
[[ $(wc -l <"$atomic_output/rpc.log") == 2 ]]
for atomic_reply in bad malformed unreachable; do
    atomic_status=0
    (verify_ecallmgr_atomic_media) >"$atomic_output/shell-$atomic_reply.log" 2>&1 || atomic_status=$?
    [[ $atomic_status == 65 ]]
done
atomic_reply=good
for atomic_nodes in "freeswitch@bad'node" 'freeswitch@host extra' $'host\nhost'; do
    atomic_status=0
    (verify_ecallmgr_atomic_media) >"$atomic_output/shell-invalid.log" 2>&1 || atomic_status=$?
    [[ $atomic_status == 65 ]]
done
atomic_nodes=''
verify_ecallmgr_atomic_media >"$atomic_output/shell-empty.log"
grep -Fq 'unverified' "$atomic_output/shell-empty.log"
DRY_RUN=true
verify_ecallmgr_atomic_media >"$atomic_output/shell-dry.log"
# Exercise permission repair in an empty private build tree, never shared src.
DRY_RUN=false
KAZOO_ROOT="$atomic_output/permission-root"
mkdir -p "$KAZOO_ROOT/core" "$KAZOO_ROOT/applications" "$KAZOO_ROOT/deps" "$KAZOO_ROOT/scripts"
SCRIPT_DIR="$KAZOO_ROOT/scripts"
cp -- "$atomic_root/scripts/verify-ecallmgr-atomic-media.erl" "$SCRIPT_DIR/verify-ecallmgr-atomic-media.erl"
chmod 0600 "$SCRIPT_DIR/verify-ecallmgr-atomic-media.erl"
prepare_kazoo_runtime_artifact_permissions
[[ $(stat -c %a "$SCRIPT_DIR/verify-ecallmgr-atomic-media.erl") == 644 ]]
mv -- "$SCRIPT_DIR/verify-ecallmgr-atomic-media.erl" "$KAZOO_ROOT/linked-script.fixture"
chmod 0600 "$KAZOO_ROOT/linked-script.fixture"
ln -s "$KAZOO_ROOT/linked-script.fixture" "$SCRIPT_DIR/verify-ecallmgr-atomic-media.erl"
atomic_status=0
(prepare_kazoo_runtime_artifact_permissions) >"$atomic_output/permission-linked.log" 2>&1 || atomic_status=$?
[[ $atomic_status == 65 && $(stat -c %a "$KAZOO_ROOT/linked-script.fixture") == 600 ]]
printf '%s\n' 'PASS atomic media shell scope, exact RPC token, failure, duplicate/unsafe nodes, empty-scope and dry-run fixtures'
