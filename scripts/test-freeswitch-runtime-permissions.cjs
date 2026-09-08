'use strict';
const fs=require('node:fs'),cp=require('node:child_process'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-fs-runtime-modes-'));
try {
  fs.chmodSync(tmp,0o755);
  const root=tmp+'/runtime';
  for(const dir of ['bin','lib/freeswitch/mod','etc','var']) fs.mkdirSync(root+'/'+dir,{recursive:true,mode:0o700});
  fs.writeFileSync(root+'/bin/freeswitch','#!/bin/sh\nexit 0\n',{mode:0o755});
  fs.writeFileSync(root+'/lib/freeswitch/mod/example.so','fixture',{mode:0o755});
  fs.writeFileSync(root+'/etc/secret','private',{mode:0o600});
  const extract=name=>source.match(new RegExp('^'+name+'\\(\\) \\{[\\s\\S]*?^\\}','m'))[0];
  const functions=(extract('validate_config_directory')+'\n'+extract('prepare_freeswitch_runtime_permissions')).replaceAll('/usr/local/freeswitch',root);
  const script=`set -euo pipefail\numask 077\nrun(){ "$@"; }\ndie(){ echo "$*" >&2; exit 1; }\n${functions}\nprepare_freeswitch_runtime_permissions\n`;
  let r=cp.spawnSync('/usr/bin/bash',['-c',script],{encoding:'utf8'});
  assert.equal(r.status,0,r.stderr);
  r=cp.spawnSync('/usr/bin/setpriv',['--reuid=65534','--regid=65534','--clear-groups',root+'/bin/freeswitch'],{encoding:'utf8'});
  assert.equal(r.status,0,r.stderr);
  assert.equal(fs.statSync(root+'/etc').mode&0o777,0o700);
  assert.equal(fs.statSync(root+'/etc/secret').mode&0o777,0o600);
  assert.equal(fs.statSync(root+'/var').mode&0o777,0o700);
  fs.renameSync(root+'/lib',root+'/original-lib'); fs.symlinkSync(root+'/original-lib',root+'/lib');
  r=cp.spawnSync('/usr/bin/bash',['-c',script],{encoding:'utf8'});
  assert.notEqual(r.status,0,'symlink runtime directory must be rejected');
  assert.match(source,/\(umask 022; make install\)\n    \)\n    freeswitch_build_fingerprint/);
  console.log('PASS actual runtime directory repair, non-root execution, private paths unchanged and symlink rejection.');
} finally { fs.rmSync(tmp,{recursive:true,force:true}); }
