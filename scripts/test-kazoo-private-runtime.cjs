'use strict';
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),path=require('node:path'),os=require('node:os');
const root=path.resolve(__dirname,'..');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-private-runtime-'));
try {
  const defaults=fs.readFileSync(root+'/rel/dev.vm.args','utf8').match(/^-kernel inet_dist_use_interface .+$/m)[0].split(/\s+/);
  const configured=['-kernel','inet_dist_use_interface','{10,20,0,13}'];
  const native=args=>cp.spawnSync('erl',['+S','1:1','+SDcpu','1','+SDio','1','+A','1','-noshell',...args,'-eval','io:format("~p",[application:get_env(kernel,inet_dist_use_interface)]),halt().'],{encoding:'utf8',timeout:15000});
  for(const launcher of ['apps','ecallmgr']) {
    const source=fs.readFileSync(root+'/scripts/dev-start-'+launcher+'.sh','utf8');
    const tail=source.slice(source.indexOf('exec erl \\\n'));
    assert(tail.includes('-kernel inet_dist_use_interface "$DIST_TUPLE"'));
    const args=tail.indexOf('-kernel inet_dist_use_interface')<tail.indexOf('-args_file') ? [...configured,...defaults] : [...defaults,...configured];
    const r=native(args); assert.equal(r.status,0,r.stderr); assert.equal(r.stdout,'{ok,{10,20,0,13}}',launcher);
  }
  assert.equal(native([...defaults,...configured]).stdout,'{ok,{127,0,0,1}}','pre-fix control');
  const source=fs.readFileSync(root+'/scripts/install-kazoo5.sh','utf8');
  const setup=source.match(/^configure_kazoo\(\) \{[\s\S]*?^\}/m)[0];
  fs.mkdirSync(tmp+'/config',{mode:0o700}); fs.writeFileSync(tmp+'/config/deployment.env','fixture-only',{mode:0o600});
  const script=`set -euo pipefail
KAZOO_HOSTNAME=fixture.invalid
KAZOO_CONFIG_DIR=${tmp}/config
KAZOO_ROOT=${tmp}/runtime
KAZOO_BUILD_ROOT=${tmp}/build
KAZOO_CORE_CONFIG_REF=fixture
KAZOO_AMQP_URI=fixture
KAZOO_COUCHDB_HOST=fixture
KAZOO_COUCHDB_PORT=5984
KAZOO_COUCHDB_USER=fixture
KAZOO_COUCHDB_PASSWORD=fixture
KAZOO_COOKIE=fixture
getent() { return 0; }
sync_git() { :; }
reject_secret_symlink() { [[ ! -L "$1" ]]; }
run() { if [[ "$1 $2" == 'install -d' ]]; then "$@"; else :; fi; }
write_file() { /usr/bin/cat >/dev/null; }
warn() { :; }
${setup}
configure_kazoo
`;
  const r=cp.spawnSync('/usr/bin/bash',['-c',script],{encoding:'utf8'}); assert.equal(r.status,0,r.stderr);
  assert.equal(fs.statSync(tmp+'/config').mode&0o777,0o755);
  assert.equal(fs.statSync(tmp+'/config/core').mode&0o777,0o755);
  assert.equal(fs.statSync(tmp+'/config/deployment.env').mode&0o777,0o600);
  console.log('PASS native OTP private-address precedence for both launchers, pre-fix control, umask-077 config traversal and unchanged secret mode.');
} finally {fs.rmSync(tmp,{recursive:true,force:true});}
