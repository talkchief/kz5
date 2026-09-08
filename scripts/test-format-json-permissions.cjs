'use strict';
const fs=require('node:fs'),cp=require('node:child_process'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-json-mode-'));
try {
  for(const mode of [0o600,0o640,0o644]) {
    const file=path.join(tmp,mode+'.json');
    fs.writeFileSync(file,'{"z":1,"a":2}',{mode});
    const r=cp.spawnSync('/usr/bin/bash',['-c','umask 077; exec /usr/bin/python3 "$1" "$2"','fixture',path.join(__dirname,'format-json.py'),file],{encoding:'utf8'});
    assert.equal(r.status,0,r.stderr); assert.equal(fs.statSync(file).mode&0o777,mode);
    assert.equal(fs.readFileSync(file,'utf8'),'{\n    "a": 2,\n    "z": 1\n}\n');
  }
  console.log('PASS JSON formatting preserves public and private file modes under umask077.');
} finally {fs.rmSync(tmp,{recursive:true,force:true});}
