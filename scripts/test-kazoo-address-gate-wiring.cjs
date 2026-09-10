'use strict';
const fs=require('node:fs'),cp=require('node:child_process'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-address-unit-'));
try {
  const names=['service_local_addresses','install_service_address_gate','verify_service_address_gate','service_enable_restart','validate_config_directory'];
  const functions='install_service_maintenance_fence(){ :; }\n'+names.map(name=>source.match(new RegExp('^'+name+'\\(\\) \\{[\\s\\S]*?^\\}','m'))[0]).join('\n').replaceAll('/usr/local/libexec',tmp+'/libexec').replaceAll('/etc/systemd/system',tmp+'/units');
  const script=`set -euo pipefail\nSCRIPT_DIR=${__dirname}\nKAZOO_COUCHDB_BIND=10.1.0.41\nKAZOO_RABBITMQ_BIND=10.1.0.42\nKAZOO_HAPROXY_BIND=10.1.0.43\nKAZOO_ERLANG_DIST_IP=10.1.0.44\nKAZOO_PUBLIC_IP=46.225.31.248\nrun(){ "$@"; }\nwrite_file(){ mkdir -p "$(dirname "$2")"; install -m "$1" /dev/stdin "$2"; }\ndie(){ echo "$*" >&2; exit 1; }\nsystemctl(){
  if [[ $1 == show ]]; then
    if [[ \${BAD_GATE:-false} == true ]]; then echo 'argv[]=wrong'; else
      printf 'argv[]=%s ;' "$(sed -n 's/^ExecStartPre=//p' '${tmp}/units/'"$2"'.d/30-kazoo-local-address.conf')"
    fi
  else echo "$*" >> '${tmp}/systemctl.calls'; fi
}\n${functions}\n`;
  const roles={'couchdb.service':'10.1.0.41','rabbitmq-server.service':'10.1.0.42','haproxy.service':'10.1.0.43','kazoo-apps.service':'10.1.0.44','kazoo-ecallmgr.service':'10.1.0.44','kazoo-freeswitch.service':'10.1.0.44','kazoo-kamailio.service':'46.225.31.248'};
  for(const [unit,address] of Object.entries(roles)) {
    const r=cp.spawnSync('/usr/bin/bash',['-c',script+`service_enable_restart ${unit}\nverify_service_address_gate ${unit}\n`],{encoding:'utf8'});
    assert.equal(r.status,0,r.stderr);
    assert(fs.readFileSync(tmp+'/units/'+unit+'.d/30-kazoo-local-address.conf','utf8').includes('--timeout 120 '+address+'\n'));
  }
  let r=cp.spawnSync('/usr/bin/bash',['-c',script+'BAD_GATE=true verify_service_address_gate haproxy.service'],{encoding:'utf8'});
  assert.notEqual(r.status,0);
  r=cp.spawnSync('/usr/bin/bash',['-c',script+'install_service_address_gate nginx.service'],{encoding:'utf8'});
  assert.equal(r.status,0); assert(!fs.existsSync(tmp+'/units/nginx.service.d'));
  const calls=fs.readFileSync(tmp+'/systemctl.calls','utf8').trim().split('\n');
  assert.equal(calls.length,21);
  assert.equal(calls[0],'daemon-reload'); assert.equal(calls[1],'enable couchdb.service');
  console.log('PASS seven actual installer address mappings, exact gate readback, wrong-gate rejection and unselected-role preservation.');
} finally {fs.rmSync(tmp,{recursive:true,force:true});}
