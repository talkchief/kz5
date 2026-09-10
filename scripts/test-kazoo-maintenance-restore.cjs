'use strict';
// Compile/exercise the actual escript's pure validation functions, no RPC/network.
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const file=path.join(__dirname,'kazoo-maintenance-restore.escript'),bytes=fs.readFileSync(file);
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-maintenance-restore-tests-'));
fs.chmodSync(dir,0o700);
const source=bytes.toString().replace(/^#!.*\n/,'').replace('-mode(compile).',
    '-module(kazoo_maintenance_restore_validation).\n-export([main/1,validate_agent/1,private_file/3,private_parent/1]).');
fs.writeFileSync(path.join(dir,'kazoo_maintenance_restore_validation.erl'),source,{mode:0o600});
fs.writeFileSync(path.join(dir,'private.json'),'{}',{mode:0o600});
const evalCode=`
M=kazoo_maintenance_restore_validation,
A=#{<<"account_id">> => <<"11111111111111111111111111111111">>,
    <<"agent_id">> => <<"22222222222222222222222222222222">>,
    <<"state">> => <<"ready">>, <<"pause_until_unix_ms">> => 0,
    <<"queues">> => [], <<"document_revision">> => <<"1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>},
Q= <<"33333333333333333333333333333333">>,
Good=[A,A#{<<"queues">> := [Q]},A#{<<"state">> := <<"paused">>,<<"pause_until_unix_ms">> := <<"infinity">>},
      A#{<<"state">> := <<"paused">>,<<"pause_until_unix_ms">> := 1},
      A#{<<"state">> := <<"paused">>,<<"pause_until_unix_ms">> := erlang:system_time(millisecond)+600000}],
lists:foreach(fun(X)->M:validate_agent(X) end,Good),
Bad=[A#{<<"state">> := <<"busy">>},A#{<<"state">> := <<"paused">>},
     A#{<<"pause_until_unix_ms">> := 1},A#{<<"queues">> := [Q,Q]},A#{<<"queues">> := [<<"bad">>]},
     A#{<<"queues">> := Q},A#{<<"document_revision">> := <<"unknown">>},A#{<<"account_id">> := <<"bad">>},
     A#{<<"agent_id">> := <<"bad">>},A#{extra => true},maps:remove(<<"state">>,A),
     A#{<<"state">> := <<"paused">>,<<"pause_until_unix_ms">> := -1},
     A#{<<"state">> := <<"paused">>,<<"pause_until_unix_ms">> := 1.5}],
lists:foreach(fun(X)->{'EXIT',_}=(catch M:validate_agent(X)) end,Bad),
Dir=os:getenv("KAZOO_RESTORE_TEST_DIR"),File=filename:join(Dir,"private.json"),
M:private_parent(Dir),<<"{}">>=M:private_file(File,8#600,512),
ok=file:change_mode(File,8#644),{'EXIT',_}=(catch M:private_file(File,8#600,512)),
ok=file:change_mode(File,8#600),Link=filename:join(Dir,"link"),ok=file:make_symlink(File,Link),
{'EXIT',_}=(catch M:private_file(Link,8#600,512)),
Hard=filename:join(Dir,"hard"),ok=file:make_link(File,Hard),
{'EXIT',_}=(catch M:private_file(File,8#600,512)),ok=file:delete(Hard),
{'EXIT',_}=(catch M:private_file(File,8#600,1)),
ok=file:change_mode(Dir,8#755),{'EXIT',_}=(catch M:private_parent(Dir)),ok=file:change_mode(Dir,8#700),
io:format("RESTORE_VALIDATION_PASS valid=5 invalid=13 file_guards=5~n"),halt(0).
`;
try{
    cp.execFileSync('erlc',['-Werror','-o',dir,path.join(dir,'kazoo_maintenance_restore_validation.erl')],{stdio:'pipe'});
    const output=cp.execFileSync('erl',['+S','1:1','+SDcpu','1','+SDio','1','+A','1','-noshell','-pa',dir,'-eval',evalCode],
        {encoding:'utf8',timeout:30000,env:{...process.env,KAZOO_RESTORE_TEST_DIR:dir},stdio:'pipe'});
    assert(output.includes('RESTORE_VALIDATION_PASS'));
    assert.equal(crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),crypto.createHash('sha256').update(bytes).digest('hex'));
    console.log(JSON.stringify({status:'PASS',valid_checkpoints:5,invalid_checkpoints:13,file_guards:5,evidence:dir,no_rpc:true}));
}catch(error){
    // This fixture contains no credentials; retain compiler diagnostics locally.
    fs.writeFileSync(path.join(dir,'failure.log'),Buffer.concat([Buffer.from(error.stdout||''),Buffer.from(error.stderr||'')]),{mode:0o600});
    console.error('RESTORE_VALIDATION_FAILED evidence='+dir);process.exitCode=1;
}
