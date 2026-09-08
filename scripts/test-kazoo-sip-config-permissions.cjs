'use strict';
const fs=require('node:fs'),cp=require('node:child_process'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
const validation=source.match(/^validate_config_directory\(\) \{[\s\S]*?^\}/m)[0];
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-sip-permissions-'));
try {
  for(const role of ['freeswitch','kamailio']) {
    const root=path.join(tmp,role), config=root+'/config', build=root+'/build';
    const from=build+'/kazoo-configs-'+role+'/'+role;
    fs.mkdirSync(from+'/nested',{recursive:true,mode:0o700});
    fs.chmodSync(from,0o700);
    fs.writeFileSync(from+'/nested/template.cfg','public source template',{mode:0o600});
    fs.writeFileSync(from+'/nested/helper.sh','#!/bin/sh\nexit 0\n',{mode:0o700});
    fs.mkdirSync(config+'/'+role,{recursive:true,mode:0o700});
    fs.writeFileSync(config+'/deployment.env','fixture secret',{mode:0o600});
    fs.writeFileSync(config+'/'+role+'/.erlang.cookie','fixture secret',{mode:0o400});
    fs.mkdirSync(config+'/'+role+'/local.d',{mode:0o700});
    fs.writeFileSync(config+'/'+role+'/local.d/custom.cfg','private custom config',{mode:0o600});
    const full=source.match(new RegExp('^configure_kazoo_'+role+'\\(\\) \\{[\\s\\S]*?^\\}','m'))[0];
    const end=role==='freeswitch' ? full.indexOf('    configure_freeswitch_logging') : full.indexOf('    if [[ $DRY_RUN');
    assert(end>0);
    const script=`set -euo pipefail\numask 077\nKAZOO_CONFIG_DIR=${config}\nKAZOO_BUILD_ROOT=${build}\nFREESWITCH_CONFIG_REF=fixture\nKAMAILIO_CONFIG_REF=fixture\nSCRIPT_DIR=${__dirname}\nrun(){ "$@"; }\nsync_git(){ :; }\napply_required_source_patch(){ :; }\ndie(){ echo "$*" >&2; exit 1; }\n${validation}\n${full.slice(0,end)}}\nconfigure_kazoo_${role}\n`;
    const r=cp.spawnSync('/usr/bin/bash',['-c',script],{encoding:'utf8'});
    assert.equal(r.status,0,r.stderr);
    for(const directory of [config,config+'/'+role,config+'/'+role+'/nested'])assert.equal(fs.statSync(directory).mode&0o777,0o755,directory);
    assert.equal(fs.statSync(config+'/'+role+'/nested/template.cfg').mode&0o777,0o644);
    assert.equal(fs.statSync(config+'/'+role+'/nested/helper.sh').mode&0o777,0o755);
    assert.equal(fs.statSync(config+'/deployment.env').mode&0o777,0o600);
    assert.equal(fs.statSync(config+'/'+role+'/.erlang.cookie').mode&0o777,0o400);
    assert.equal(fs.statSync(config+'/'+role+'/local.d/custom.cfg').mode&0o777,0o600);
  }
  console.log('PASS actual standalone SIP config-copy prefixes under umask077, readable source templates/executables, untouched credentials/custom files.');
} finally {fs.rmSync(tmp,{recursive:true,force:true});}
