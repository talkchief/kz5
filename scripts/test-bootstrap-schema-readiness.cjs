'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),cp=require('node:child_process');
const source=fs.readFileSync(__dirname+'/install-kazoo5.sh','utf8');
const hook=source.match(/^wait_kazoo_bootstrap_ready\(\) \{[\s\S]*?^\}/m)[0];
const rpc=hook.match(/rpc='([^']+)'/)[1];
assert(rpc.includes('kz_json_schema:load(S)'));
// Execute the real boolean/readiness expression with only external read calls
// substituted. No mock result can bypass the schema and module conjunction.
for(const [missing,modules,apps,expected] of [
 [null,'[cb_accounts,cb_users]','[{crossbar,[],[]}]','ready'],
 ['accounts','[cb_accounts,cb_users]','[{crossbar,[],[]}]','not_ready'],
 ['users','[cb_accounts,cb_users]','[{crossbar,[],[]}]','not_ready'],
 ['profile','[cb_accounts,cb_users]','[{crossbar,[],[]}]','not_ready'],
 [null,'[cb_accounts]','[{crossbar,[],[]}]','not_ready'],
 [null,'[cb_accounts,cb_users]','[]','not_ready'],
]) {
 let expression=rpc.replace('crossbar_bindings:modules_loaded()',modules)
  .replace('application:which_applications()',apps)
  .replace('kz_json_schema:load(S)',missing?`(case S of <<"${missing}">> -> {error,not_found}; _ -> {ok,{[]}} end)`:'{ok,{[]}}');
 const r=cp.spawnSync('erl',['+S','1:1','+A','1','-noshell','-eval',
  'R=('+expression.slice(0,-1)+'),io:format("~p",[R]),halt().'],
  {encoding:'utf8',timeout:10000,env:{PATH:'/usr/bin:/bin',ERL_CRASH_DUMP:'/dev/null'}});
 assert.ifError(r.error);assert.equal(r.status,0,r.stderr);assert.equal(r.stdout,expected);
}
console.log('PASS six actual Erlang bootstrap readiness states; no database or account writes');
