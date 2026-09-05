#!/usr/bin/env bash
# Mock-only regression: no sockets, API requests or registration changes.
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=run-live-test-agents.sh
source "$script_dir/run-live-test-agents.sh"
test_dir=$(mktemp -d /tmp/kazoo-sipp-bind-args.XXXXXX)
cleanup_test() {
    local port
    for ((port=17100; port<=17129; port++)); do
        rm -f -- "$test_dir/$port.args"
    done
    rmdir -- "$test_dir"
}
trap cleanup_test EXIT
# Consumed by the sourced start_phone/deregister_phones functions.
# shellcheck disable=SC2034
STATE='{"sip_proxy_host":"127.0.0.1","sip_proxy_port":5060}'
write_input() { :; }
sipp() {
    local arguments=("$@") index port=
    for ((index=0; index<${#arguments[@]}; index++)); do
        [[ ${arguments[index]} != -p ]] || port=${arguments[index+1]}
    done
    [[ $port =~ ^171[0-2][0-9]$ ]]
    printf '%s\0' "$@" >"$test_dir/$port.args"
}
start_phone 1
wait "${PHONE_PIDS[0]}"
node - "$test_dir/17100.args" <<'NODE'
const fs=require('node:fs'),assert=require('node:assert/strict');
const args=fs.readFileSync(process.argv[2]).toString().split('\0');
for(const [flag,value] of [['-ci','127.0.0.40'],['-i','127.0.0.40'],['-mi','127.0.0.40'],['-p','17100'],['-min_rtp_port','46000'],['-max_rtp_port','46001']]) {
  assert.equal(args.filter(a=>a===flag).length,1);assert.equal(args[args.indexOf(flag)+1],value);
}
NODE
timeout() { shift; "$@"; }
deregister_phones
node - "$test_dir" <<'NODE'
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
for(let port=17100;port<=17129;port++) {
 const args=fs.readFileSync(path.join(process.argv[2],port+'.args')).toString().split('\0');
 for(const [flag,value] of [['-ci','127.0.0.40'],['-i','127.0.0.40'],['-p',String(port)]]) {
  assert.equal(args.filter(a=>a===flag).length,1);assert.equal(args[args.indexOf(flag)+1],value);
 }
}
NODE
printf '%s\n' 'PASS loopback control binding: persistent phone and 30 deregistration invocations; SIP/RTP unchanged; mock only'
