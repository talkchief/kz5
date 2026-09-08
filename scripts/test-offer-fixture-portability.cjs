'use strict';
// Extract real shell functions; use synthetic state/systemd replies only.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {spawnSync}=require('node:child_process');
const source=fs.readFileSync(process.argv[2]||path.join(__dirname,'test-acdc-callback-offer-calls.sh'),'utf8');
const q=s=>"'"+s.replaceAll("'","'\\''")+"'";
function fn(name){const m=source.match(new RegExp('^'+name+'\\(\\) \\{\\n[\\s\\S]*?^\\}','m'));assert(m);return m[0];}
const legacy='7807ad61761269a1ccec833dde63f621',selected='8'.repeat(32);
function prepare(account,args=[],ambient='9'.repeat(32)) {
    const input=`set -Eeuo pipefail
SCRIPT_DIR=${q(__dirname)} offer_fixture=/fixture offer_audio=/audio offer_scenario=/scenario
offer_allow_absent_master_test_phones=false STATE_FILE=/etc/kazoo/acceptance-secrets.env
export KAZOO_CALLBACK_TEST_ACCOUNT_ID=${ambient}
die(){ exit 65; }; log(){ printf '%s %s\\n' "$KAZOO_CALLBACK_TEST_ACCOUNT_ID" "$offer_allow_absent_master_test_phones"; }
load_state(){ declare -gA STATE=([ACCEPTANCE_ACCOUNT_ID]=${account} [ACCEPTANCE_SIP_PROXY_HOST]=127.0.0.1); }
validate_state(){ :; }; resolve_local_ip(){ LOCAL_IP=127.0.0.20; }; ensure_sipp(){ :; }
node(){ :; }; sox(){ :; }; tcpdump(){ :; }; ip(){ printf 'local 127.0.0.1 dev lo src 127.0.0.1\\n'; }
${fn('offer_main')}
offer_main --prepare-only ${args.map(q).join(' ')}
`;
    return spawnSync('bash',['-s'],{input,encoding:'utf8'});
}
const changed=prepare(selected,['--fixture-account',selected,'--allow-absent-master-test-phones']);
assert.equal(changed.status,0,'Explicit new offer fixture must pass: '+changed.stderr);
assert.equal(changed.stdout.trim(),selected+' true');
assert.equal(prepare(legacy).stdout.trim(),legacy+' false','Ambient account must not change selection');
assert.equal(prepare(selected).status,65);
for(const args of [['--fixture-account'],['--fixture-account','bad'],
    ['--fixture-account',selected,'--fixture-account',selected]])assert.equal(prepare(selected,args).status,65);
const units=['kazoo-apps','kazoo-ecallmgr','kazoo-freeswitch','kazoo-kamailio','kazoo-live-test-agents'];
function snapshot(allowAbsent,absent=true,failedCore=false) {
    const states=units.map((u,i)=>({Id:u+'.service',LoadState:i===4&&absent?'not-found':'loaded',
        ActiveState:i===4&&absent?'inactive':failedCore&&i===0?'failed':'active',
        SubState:i===4&&absent?'dead':'running',MainPID:i===4&&absent?'0':String(i+100),NRestarts:'0'}));
    const rendered=states.map(s=>Object.entries(s).map(([k,v])=>k+'='+v).join('\n')).join('\n\n');
    const input=`set -Eeuo pipefail
SCRIPT_DIR=${q(__dirname)} offer_allow_absent_master_test_phones=${allowAbsent}
offer_services=(couchdb rabbitmq-server haproxy nginx kazoo-apps kazoo-ecallmgr kazoo-freeswitch kazoo-kamailio kazoo-live-test-agents)
systemctl(){
 if [[ $1 == show && $2 == kazoo-apps && $3 == kazoo-ecallmgr ]]; then printf '%s\\n' ${q(rendered)};
 elif [[ $1 == is-active ]]; then [[ $3 != kazoo-live-test-agents || ${absent} == false ]];
 else printf '%s\\n' 'MainPID=100' 'NRestarts=0' 'ActiveState=active'; fi
}
${fn('offer_service_snapshot')}
offer_service_snapshot
`;
    return spawnSync('bash',['-s'],{input,encoding:'utf8'});
}
assert.equal(snapshot(true).status,0);
assert.notEqual(snapshot(false).status,0);
assert.notEqual(snapshot(true,true,true).status,0);
assert.equal(snapshot(false,false).status,0);
assert(source.includes('exec {offer_lock_fd}<>/etc/kazoo/monitor-acceptance.lock'));
assert(source.indexOf('preflight "$STATE_FILE"')<source.indexOf('register_caller offer'));
console.log('PASS offer fixture explicit selection, ambient isolation, exact service scope and registration/lock wiring; no live I/O');
