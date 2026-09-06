'use strict';
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),a=require('node:assert/strict'),cp=require('node:child_process');
const source=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
const match=source.match(/write_file 0755 \/usr\/local\/bin\/sup <<'EOF'\n([\s\S]*?)\nEOF/);
a(match,'Actual installer SUP wrapper not found');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-sup-alias.'));
try {
 fs.mkdirSync(path.join(dir,'core/sup'),{recursive:true});
 fs.writeFileSync(path.join(dir,'core/sup/sup'),'#!/bin/bash\nprintf "%s\\0" "$@"\n',{mode:0o700});
 fs.writeFileSync(path.join(dir,'config.ini'),'test fixture only\n',{mode:0o600});
 fs.writeFileSync(path.join(dir,'wrapper.sh'),match[1]+'\n',{mode:0o700});
 const cases=[
  [['kapps_controller','kapps'],['kapps_controller','running_apps']],
  [['-n','ecallmgr','kapps_controller','kapps'],['-n','ecallmgr','kapps_controller','running_apps']],
  [['-e','kapps_controller','kapps'],['-e','kapps_controller','running_apps']],
  [['kazoo_maintenance','syslog_level','debug'],['kazoo_maintenance','syslog_level','debug']],
  [['kapps_controller','running_apps'],['kapps_controller','running_apps']],
  [['kapps_controller','kapps','unexpected'],['kapps_controller','kapps','unexpected']],
  [['other','kapps'],['other','kapps']],
  [['kapps_config','get','kapps_controller','kapps'],['kapps_config','get','kapps_controller','kapps']],
  [['-n','kazoo_apps','kapps_config','get','kapps_controller','kapps'],['-n','kazoo_apps','kapps_config','get','kapps_controller','kapps']],
  [['-s','true','-t','20','kapps_controller','kapps'],['-s','true','-t','20','kapps_controller','running_apps']],
  [['--node=kazoo_apps','--erl_term_args=false','kapps_controller','kapps'],['--node=kazoo_apps','--erl_term_args=false','kapps_controller','running_apps']],
  [['--','kapps_controller','kapps'],['--','kapps_controller','running_apps']],
  [['-n','kapps_controller','kapps'],['-n','kapps_controller','kapps']],
  [[],[]],
  [['--help'],['--help']]
 ];
 for(const [args,expected] of cases){
  const r=cp.spawnSync('/usr/bin/bash',[path.join(dir,'wrapper.sh'),...args],{encoding:'utf8',timeout:5000,env:{PATH:'/usr/bin:/bin',KAZOO_ROOT:dir,KAZOO_CONFIG:path.join(dir,'config.ini')}});
  a.equal(r.status,0,r.stderr);const actual=r.stdout.split('\0');actual.pop();
  if(actual[0]==='-s'&&actual[1]==='true')actual.splice(0,2);
  a.deepEqual(actual,expected);
 }
 console.log('PASS '+cases.length+' actual SUP wrapper argument cases; no RPC or live configuration');
} finally {fs.rmSync(dir,{recursive:true,force:true});}
