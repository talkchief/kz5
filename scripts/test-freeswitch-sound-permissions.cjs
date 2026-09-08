'use strict';
const fs=require('node:fs'),cp=require('node:child_process'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-sound-modes-'));
try {
  fs.chmodSync(tmp,0o755);
  const build=tmp+'/build', destination=tmp+'/sounds', manifest=tmp+'/sounds.manifest';
  fs.mkdirSync(destination,{mode:0o755});
  for(const locale of ['en/us','es/es','fr/fr','music']) {
    const from=build+'/kazoo-sounds/freeswitch/'+locale;
    fs.mkdirSync(from,{recursive:true,mode:0o700});
    fs.writeFileSync(from+'/new.wav','fixture new audio',{mode:0o600});
    fs.writeFileSync(from+'/existing.wav','upstream audio',{mode:0o600});
    fs.mkdirSync(destination+'/'+locale,{recursive:true,mode:0o755});
    fs.writeFileSync(destination+'/'+locale+'/existing.wav','customer audio',{mode:0o644});
  }
  const functions=['install_freeswitch_sounds','verify_freeswitch_sounds'].map(name=>source.match(new RegExp('^'+name+'\\(\\) \\{[\\s\\S]*?^\\}','m'))[0]).join('\n').replaceAll('/usr/share/kazoo-freeswitch/sounds',destination).replaceAll('/usr/local/share/kazoo5-installer/freeswitch-sounds.manifest',manifest);
  const script=`set -euo pipefail\numask 077\nDRY_RUN=false\nKAZOO_BUILD_ROOT=${build}\nprepare_kazoo_sounds(){ :; }\nrun(){ "$@"; }\nwrite_file(){ /usr/bin/install -m "$1" /dev/stdin "$2"; }\nlog(){ :; }\ndie(){ echo "$*" >&2; exit 1; }\nrunuser(){ shift 3; /usr/bin/setpriv --reuid=65534 --regid=65534 --clear-groups "$@"; }\n${functions}\n`;
  let r=cp.spawnSync('/usr/bin/bash',['-c',script+'install_freeswitch_sounds\n'],{encoding:'utf8'});
  assert.equal(r.status,0,r.stderr);
  for(const locale of ['en/us','es/es','fr/fr','music']) {
    assert.equal(fs.readFileSync(destination+'/'+locale+'/existing.wav','utf8'),'customer audio');
    assert.equal(fs.statSync(destination+'/'+locale+'/new.wav').mode&0o777,0o644);
  }
  fs.chmodSync(destination+'/en/us/new.wav',0o600);
  r=cp.spawnSync('/usr/bin/bash',['-c',script+'verify_freeswitch_sounds\n'],{encoding:'utf8'});
  assert.notEqual(r.status,0); assert.match(r.stderr,/service user cannot read/);
  console.log('PASS actual sound install under umask077, customer audio preservation, and unprivileged service-read rejection.');
} finally {fs.rmSync(tmp,{recursive:true,force:true});}
