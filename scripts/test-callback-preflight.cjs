'use strict';
// Extract actual candidate shell functions; all SUP/API/service effects mocked.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),a=require('node:assert/strict'),test=require('node:test'),os=require('node:os'),crypto=require('node:crypto');
const fixture=fs.readFileSync(path.join(__dirname,'test-acdc-callback-fixture.sh'),'utf8');
const calls=fs.readFileSync(path.join(__dirname,'test-acdc-callback-calls.sh'),'utf8');
const retry=fs.readFileSync(path.join(__dirname,'test-acdc-callback-retry.sh'),'utf8');
function fn(source,name){const m=source.match(new RegExp('^'+name+'\\(\\) \\{[\\s\\S]*?^\\}','m'));a.ok(m,name);return m[0];}
const beamDir=fs.mkdtempSync(path.join(os.tmpdir(),'callback-preflight-test.'));
const beamPath=path.join(beamDir,'stepswitch_maintenance.beam');
fs.writeFileSync(beamPath,'test-only fake metadata target');
fs.mkdirSync(path.join(beamDir,'scripts'));
fs.mkdirSync(path.join(beamDir,'applications/stepswitch/ebin'),{recursive:true});
const layoutPath=beamDir+'/scripts/../applications/stepswitch/ebin/stepswitch_maintenance.beam';
fs.writeFileSync(layoutPath,'test-only real-layout metadata target');
fs.mkdirSync(path.join(beamDir,'linked'));
const symlinkPath=path.join(beamDir,'linked/stepswitch_maintenance.beam');
fs.symlinkSync(beamPath,symlinkPath);
fs.mkdirSync(path.join(beamDir,'wrong-linked'));
fs.writeFileSync(path.join(beamDir,'other.beam'),'wrong target');
const wrongSymlinkPath=path.join(beamDir,'wrong-linked/stepswitch_maintenance.beam');
fs.symlinkSync(path.join(beamDir,'other.beam'),wrongSymlinkPath);
test.after(()=>fs.rmSync(beamDir,{recursive:true,force:true}));
function setup(mode='ok',missingHome=false,source=fixture){
  const functions=['fixture_die','fixture_sup_preflight','reload_local_resources','setup_fixture'].map(n=>fn(source,n)).join('\n');
  const env={PATH:'/usr/bin:/bin',LANG:'C',MODE:mode,MOCK_BEAM:beamPath,MOCK_LAYOUT:layoutPath,MOCK_SYMLINK:symlinkPath,MOCK_WRONG_SYMLINK:wrongSymlinkPath};if(!missingHome)env.HOME=os.userInfo().homedir;
  return cp.spawnSync('/usr/bin/bash',['-c',`set -Eeuo pipefail
${functions}
exec 3>&1
trace(){ printf '%s\\n' "$*" >&3; }
timeout(){
  if [[ $1 == 5 && $2 == readlink && $3 == -e && $4 == -- ]]; then
    [[ $MODE != readlink-failed ]] || return 1
    [[ $MODE != readlink-timeout ]] || return 124
    command readlink -e -- "$5"; return $?
  fi
  [[ $2 == sup && $3 == -e ]] || exit 95
  if [[ $4 == stepswitch_maintenance && $5 == module_info && $6 == module && $1 == 15 ]]; then
    # Actual SUP: successful non-ok results from *_maintenance exit 2.
    printf 'stepswitch_maintenance\\n'; return 2
  fi
  if [[ $4 == code && $5 == which && $6 == stepswitch_maintenance && $1 == 15 ]]; then
    case $MODE in
      transport) printf 'fake-secret-token\\n' >&2; return 3 ;;
      unexpected) printf 'fake-secret-token\\n'; return 0 ;;
      non-existing) printf 'non_existing\\n'; return 0 ;;
      preloaded) printf 'preloaded\\n'; return 0 ;;
      embedded) printf 'embedded\\n'; return 0 ;;
      missing-file) printf '\"/absent/stepswitch_maintenance.beam\"\\n'; return 0 ;;
      wrong-module) printf '\"/tmp/other.beam\"\\n'; return 0 ;;
      relative) printf '\"relative/stepswitch_maintenance.beam\"\\n'; return 0 ;;
      multiline) printf '\"/tmp/stepswitch_maintenance.beam\"\\nfake-secret-token\\n'; return 0 ;;
      traversal) printf '\"/tmp/../tmp/stepswitch_maintenance.beam\"\\n'; return 0 ;;
      real-layout) printf '\"%s\"\\n' "$MOCK_LAYOUT"; return 0 ;;
      symlink) printf '\"%s\"\\n' "$MOCK_SYMLINK"; return 0 ;;
      wrong-symlink) printf '\"%s\"\\n' "$MOCK_WRONG_SYMLINK"; return 0 ;;
      *) printf '\"%s\"\\n' "$MOCK_BEAM"; return 0 ;;
    esac
  fi
  [[ $1 == 20 && $4 == stepswitch_maintenance && $5 == reload_resources ]] || exit 96
  trace resource-reload
  case $MODE in reload-failed) printf 'fake-secret-cookie\\n' >&2;return 4;;reload-unexpected) printf 'fake-secret-cookie\\n';;*)printf 'ok\\n';;esac
}
FIXTURE_STAGE=initialization
FIXTURE_ACCOUNT_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
ACCEPTANCE_ACCOUNT_ID=$FIXTURE_ACCOUNT_ID
FIXTURE_ORIGINAL_QUEUE='{"id":"retained-original"}'
ENCODED_OUTBOUND_CALLER_ID=owned-outbound
OUTBOUND_CALLER_ID=owned-outbound
ENCODED_CALLBACK_NUMBER=owned-return
CALLBACK_NUMBER=owned-return
ACTION=setup
save_fixture_state(){ trace snapshot; }
create_owned_number(){ trace "number $1"; }
create_local_resource(){ trace resource; }
configure_acceptance_queue(){ trace queue; }
verify_fixture(){ trace verification; }
api_request(){ trace unexpected-api;exit 91; }
setup_fixture
[[ $FIXTURE_ORIGINAL_QUEUE == '{"id":"retained-original"}' ]]
`],{env,encoding:'utf8',timeout:3000,maxBuffer:8192});
}
test('missing HOME uses actual SUP connectivity and preserves setup order',()=>{
  const r=setup('ok',true);a.equal(r.status,0,r.stderr);a.deepEqual(r.stdout.trim().split('\n'),['snapshot','number owned-outbound','number owned-return','resource','queue','resource-reload','verification']);
  const failed=setup('transport',true);a.equal(failed.status,1);a.equal(failed.stdout,'');a.match(failed.stderr,/reason=sup-connectivity/);
});
test('SUP transport failure fails before fixture writes and redacts raw output',()=>{
  const r=setup('transport');a.equal(r.status,1);a.equal(r.stdout,'');a.match(r.stderr,/stage=sup-preflight.*reason=sup-connectivity/);a.doesNotMatch(r.stderr,/fake-secret/);
});
test('unexpected successful SUP reply is not connectivity proof',()=>{
  const r=setup('unexpected');a.equal(r.status,1);a.equal(r.stdout,'');a.match(r.stderr,/reason=sup-unexpected-reply/);a.doesNotMatch(r.stderr,/fake-secret/);
});
test('successful prerequisite preserves setup order and original snapshot',()=>{
  const r=setup();a.equal(r.status,0,r.stderr);a.deepEqual(r.stdout.trim().split('\n'),['snapshot','number owned-outbound','number owned-return','resource','queue','resource-reload','verification']);
});
test('previous maintenance module_info preflight fails with real SUP exit-2 semantics',()=>{
  const previous=fixture.replace('sup -e code which stepswitch_maintenance','sup -e stepswitch_maintenance module_info module');
  const r=setup('ok',false,previous);a.equal(r.status,1);a.equal(r.stdout,'');a.match(r.stderr,/reason=sup-connectivity/);
});
for(const mode of ['non-existing','preloaded','embedded','missing-file','wrong-module','relative','multiline','traversal','wrong-symlink','readlink-failed','readlink-timeout'])test('reject '+mode+' metadata reply before setup writes',()=>{
  const r=setup(mode);a.equal(r.status,1);a.equal(r.stdout,'');a.match(r.stderr,/reason=sup-unexpected-reply/);a.doesNotMatch(r.stderr,/fake-secret/);
});
for(const mode of ['real-layout','symlink'])test('accept canonical regular target from '+mode+' metadata',()=>{
  const r=setup(mode);a.equal(r.status,0,r.stderr);a.equal(r.stdout.trim().split('\n').at(-1),'verification');
});
for(const mode of ['reload-failed','reload-unexpected'])test(mode+' reports exact stage, retains partial fixture and prints no raw SUP output',()=>{
  const r=setup(mode);a.equal(r.status,1);a.match(r.stderr,/stage=setup-resource-reload/);a.doesNotMatch(r.stderr,/fake-secret/);
  a.equal(r.stdout.trim().split('\n').at(-1),'resource-reload');a.doesNotMatch(r.stdout,/verification|delete|cleanup|cancel/);
});
test('standalone preflight returns before credential/account/fixture loading or auth',()=>{
  const script=`set -Eeuo pipefail
${fn(fixture,'fixture_die')}
${fn(fixture,'main_fixture')}
parse_fixture_args(){ ACTION=preflight; }
fixture_sup_preflight(){ printf 'preflight\\n'; }
fixture_log(){ :; }
load_acceptance_state(){ printf 'unexpected-load\\n';exit 90; }
load_fixture_state(){ printf 'unexpected-state\\n';exit 90; }
authenticate_master(){ printf 'unexpected-auth\\n';exit 90; }
main_fixture preflight
`;
  const r=cp.spawnSync('/usr/bin/bash',['-c',script],{encoding:'utf8',timeout:3000});a.equal(r.status,0,r.stderr);a.equal(r.stdout,'preflight\n');
});
for(const [source,name]of [[calls,'run_callback_acceptance'],[retry,'retry_run']])test(name+' checks prerequisite before agent mutation or fixture setup',()=>{
  const script=`set -Eeuo pipefail
${fn(source,name)}
callback_fixture(){ [[ $1 == preflight ]] || { printf 'unexpected-fixture\\n';exit 91; };exit 73; }
agent_status(){ printf 'unexpected-agent\\n';exit 92; }
retry_snapshot(){ printf 'unexpected-native-read\\n';exit 93; }
${name}
`;
  const r=cp.spawnSync('/usr/bin/bash',['-c',script],{encoding:'utf8',timeout:3000});a.equal(r.status,73,r.stderr);a.equal(r.stdout,'');
});
test('no retained callback or cleanup policy was altered',()=>{
  const baseline={
    cleanup_fixture:'be23b1b60e365cccfad2e4bd64586e359d1859bfbd7d9b56edb93d262b701534',
    cancel_original_callback:'a3132007dad62069b1977558ac83f18b0e003c6d73d951d436d956b7db0c08aa',
    fixture_assert_quiescent:'a3cb74b4623724766aa12ece1fa3fd9fd1531394574d150e0c1f36e8f9aa7929',
    retry_cleanup:'4a68ee271be1879262e53841863c42297f77b62546577ef061ea03b49558e4cf'
  };
  for(const [name,digest]of Object.entries(baseline))a.equal(crypto.createHash('sha256').update(fn(name==='retry_cleanup'?retry:fixture,name)).digest('hex'),digest);
});
test('caller prerequisite failure remains terminal even in a conditional shell context',()=>{
  for(const [source,name]of [[calls,'run_callback_acceptance'],[retry,'retry_run']]){
    const script=`set -Eeuo pipefail
${fn(source,name)}
callback_fixture(){ return 73; }
die(){ exit 74; }
agent_status(){ printf 'unexpected-agent\\n';exit 92; }
retry_snapshot(){ printf 'unexpected-native-read\\n';exit 93; }
if ${name}; then exit 0; fi
`;
    const r=cp.spawnSync('/usr/bin/bash',['-c',script],{encoding:'utf8',timeout:3000});a.equal(r.status,74,r.stderr);a.equal(r.stdout,'');
  }
});
