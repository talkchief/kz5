'use strict';
// Pure shell-function mocks; no protected-file reads, API, SIP, signals or services.
const test=require('node:test'),assert=require('node:assert/strict'),cp=require('node:child_process'),path=require('node:path');
const candidate=path.join(__dirname,'run-live-test-agents.sh');
function shell(body){return cp.spawnSync('/usr/bin/bash',['-c','source "$1"\n'+body,'phone-startup-mock',candidate],
 {encoding:'utf8',timeout:5000,maxBuffer:65536,env:{PATH:'/usr/bin:/usr/sbin:/bin',LANG:'C'}});}
function passes(body){const r=shell(body);assert.equal(r.status,0,r.stderr+'\n'+r.stdout);return r.stdout.trim().split('\n').filter(Boolean);}
const lifecycle=`
log() { :; }
command() { [[ $1 == -v ]]; }
python3() { return 0; }
sipp() { [[ $1 == -v ]] || exit 99; printf '%s\\n' 'SIPp v3.7.7-TLS-PCAP-SHA256'; }
load_state() { STATE='{}'; }
prepare_runtime() { :; }
wait_for_dependencies() { printf '%s\\n' read_ready; }
owned_helper() { [[ $1 == verify_phones ]] || exit 99; printf '%s\\n' verify_phones; }
rm() { [[ $1 == -f && $2 == -- && $3 == "$RUNTIME_DIR/"* ]] || exit 99; }
mark_phone_run() { printf '%s\\n' marker_written; }
phone_run_marker_matches() { return 0; }
start_phones() { printf '%s\\n' phones_started; }
stop_phones() { printf '%s\\n' own_children_stopped; }
contact_present() { return 0; }
deregister_phones() { printf '%s\\n' exact_contacts_deregistered; }
systemd-notify() { [[ $1 == --ready ]] || exit 99; printf '%s\\n' ready; }
report_phone_health() { :; }
clear_fixture_calls() { printf '%s\\n' forbidden_call_hangup >&2; exit 99; }
cleanup_resources() { printf '%s\\n' forbidden_status_cleanup >&2; exit 99; }
sleep() { exit "$mock_exit"; }
`;
for(const status of [0,13])test('cold start and '+(status?'failure':'normal stop')+' preserve operator statuses and roster without a prior marker',()=>{
 const r=shell(lifecycle+`\nmock_exit=${status}\nrun_service`);
 assert.equal(r.status,status,r.stderr);assert.deepEqual(r.stdout.trim().split('\n'),[
  'read_ready','verify_phones','marker_written','phones_started','ready','own_children_stopped','verify_phones','exact_contacts_deregistered']);
});
test('failed readiness cannot authenticate, start phones or clean up status',()=>{
 const r=shell(lifecycle+'\nwait_for_dependencies() { return 1; }\nrun_service');assert.equal(r.status,1);assert.equal(r.stdout,'');
});
test('failed initial phone ownership cannot start phones or invoke cleanup',()=>{
 const r=shell(lifecycle+'\nowned_helper() { return 1; }\nrun_service');assert.equal(r.status,1);assert.equal(r.stdout,'read_ready\n');
});
test('successful but slow contact lookups cannot bypass the shared registration deadline',()=>{
 const r=shell(lifecycle+`\nSECONDS=0
die() { printf '%s\\n' "$*" >&2; exit 1; }
contact_present() { SECONDS=$((SECONDS+5)); return 0; }
run_service`);
 assert.equal(r.status,1,r.stderr);
 assert.match(r.stderr,/did not register before startup deadline/);
 assert.ok(!r.stdout.split('\n').includes('ready'));
 assert.match(r.stdout,/exact_contacts_deregistered/);
});
test('a late successful contact proof cannot publish service readiness',()=>{
 const r=shell(lifecycle+`\nSECONDS=0
die() { printf '%s\\n' "$*" >&2; exit 1; }
contact_present() { SECONDS=$((SECONDS+61)); return 0; }
run_service`);
 assert.equal(r.status,1,r.stderr);
 assert.match(r.stderr,/contact proof arrived after startup deadline/);
 assert.ok(!r.stdout.split('\n').includes('ready'));
 assert.match(r.stdout,/exact_contacts_deregistered/);
});
test('post-stop retries prior marked contacts after a later dependency failure without status or call commands',()=>{
 const out=passes(lifecycle+`\nwait_for_dependencies() { return 1; }
if (run_service); then exit 99; fi
cleanup_phones`);
 assert.deepEqual(out,['verify_phones','exact_contacts_deregistered']);
});
test('dependency wait retries only read probes and succeeds after delayed readiness',()=>{
 passes(`
log() { :; }
owned_helper() { exit 99; }
start_phones() { exit 99; }
probe_count=0
dependencies_ready() { probe_count=$((probe_count+1)); ((probe_count == 3)); }
sleep() { [[ $1 == 5 ]] || exit 99; SECONDS=$((SECONDS+5)); }
SECONDS=0
wait_for_dependencies
[[ $probe_count == 3 && $SECONDS == 10 ]]
`);
});
test('dependency wait reaches a finite deadline without authentication or SIP',()=>{
 passes(`
log() { :; }
owned_helper() { exit 99; }
start_phones() { exit 99; }
probe_count=0
dependencies_ready() { probe_count=$((probe_count+1)); return 1; }
sleep() { [[ $1 == 5 ]] || exit 99; SECONDS=$((SECONDS+5)); }
SECONDS=0
if wait_for_dependencies; then exit 98; fi
((probe_count > 1 && probe_count < 50 && SECONDS <= 240))
`);
});
const probes=`
curl() { [[ $* == "-q --noproxy * --proto =http --connect-timeout 2 --max-time 3 --silent --output /dev/null --write-out %{http_code} --request GET http://127.0.0.1:8000/v2/user_auth" ]] || return 99; printf '%s' "$http_code"; }
timeout() { [[ $1 == 3 ]] || return 99; if [[ $2 == kamcmd && $3 == core.version && $# == 3 ]]; then printf '%s' "$kam_version";
 elif [[ $2 == "$FS_CLI" && $3 == -x && $4 == 'module_exists mod_kazoo' && $# == 4 ]]; then printf '%s' "$fs_ready"; else return 99; fi; }
http_code=405
kam_version=kamailio
fs_ready=true
`;
test('actual dependency function uses only fixed unauthenticated/local read probes',()=>{passes(probes+'\ndependencies_ready');});
for(const [name,change]of [['redirect','http_code=302'],['forbidden','http_code=403'],['API unavailable','http_code=503'],['unexpected success','http_code=200'],['foreign registrar','kam_version=other'],['missing module','fs_ready=false'],
 ['HTTP transport failure','curl() { return 1; }'],['local RPC transport failure','timeout() { return 1; }']])
 test('dependency '+name+' is not accepted',()=>{passes(probes+'\n'+change+'\nif dependencies_ready; then exit 99; fi');});
test('routine cleanup without a started-phone marker performs no operation',()=>{
 passes('phone_run_marker_matches() { return 1; }\nowned_helper() { exit 99; }\nderegister_phones() { exit 99; }\ncleanup_phones');
});
test('routine cleanup refuses SIP effects when ownership is unavailable and never changes status or hangs up calls',()=>{
 passes(`
log() { :; }
phone_run_marker_matches() { return 0; }
owned_helper() { [[ $1 == verify_phones ]] || exit 99; return 1; }
deregister_phones() { exit 99; }
clear_fixture_calls() { exit 99; }
cleanup_resources() { exit 99; }
rm() { exit 99; }
if cleanup_phones; then exit 98; fi
`);
});
test('failed exact deregistration retains retry evidence and preserves all status/call resources',()=>{
 passes(`
log() { :; }
phone_run_marker_matches() { return 0; }
owned_helper() { [[ $1 == verify_phones ]] || exit 99; }
deregister_phones() { return 1; }
clear_fixture_calls() { exit 99; }
cleanup_resources() { exit 99; }
rm() { exit 99; }
if cleanup_phones; then exit 98; fi
`);
});
