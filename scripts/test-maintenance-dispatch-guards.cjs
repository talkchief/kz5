'use strict';
// Compile the actual three escript predicates, not a JavaScript equivalent.
const fs=require('fs'),cp=require('child_process'),os=require('os'),path=require('path'),assert=require('assert/strict');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-dispatch-guards-'));
fs.chmodSync(root,0o700);
const names=['snapshot','queues','restore'];
let predicate;
for(const name of names){
    const source=fs.readFileSync(__dirname+'/kazoo-maintenance-'+name+'.escript','utf8');
    const match=source.match(/validate_dispatch\(#\{[\s\S]*? -> ok\./);assert(match);
    if(predicate)assert.equal(match[0],predicate);else predicate=match[0];
    assert(source.includes('rpc(N,gen_server,call,[P,maintenance_dispatch_state,2000])'));
    assert(source.split('dispatch_drained(N,').length>=4,'Must check before/after work observation');
    const module='maintenance_dispatch_'+name;
    fs.writeFileSync(root+'/'+module+'.erl',source.replace(/^#!.*\n/,'').replace('-mode(compile).',
        '-module('+module+').\n-export([main/1,validate_dispatch/1]).'),{mode:0o600});
    cp.execFileSync('erlc',['-Werror','-o',root,root+'/'+module+'.erl'],{stdio:'pipe'});
}
const evalCode=`
Good=#{pending_dispatches=>0,failed_dispatches=>0,admission_fence_proven=>false,complete_cluster_drain_proven=>false},
Bad=[Good#{pending_dispatches:=1},Good#{failed_dispatches:=1},Good#{pending_dispatches:=-1},
     Good#{pending_dispatches:=0.0},Good#{pending_dispatches:=undefined},
     Good#{admission_fence_proven:=true},Good#{complete_cluster_drain_proven:=true},
     maps:remove(failed_dispatches,Good),Good#{extra=>false},{error,unsupported},{badrpc,timeout},undefined],
lists:foreach(fun(M)->ok=M:validate_dispatch(Good),
    lists:foreach(fun(B)->{'EXIT',_}=(catch M:validate_dispatch(B)) end,Bad)
    end,[maintenance_dispatch_snapshot,maintenance_dispatch_queues,maintenance_dispatch_restore]),
io:format("DISPATCH_GUARDS_PASS valid=3 refused=36~n"),halt(0).`;
const output=cp.execFileSync('erl',['+S','1:1','+SDcpu','1','+SDio','1','+A','1','-pa',root,'-noshell','-eval',evalCode],
    {encoding:'utf8',timeout:30000,stdio:'pipe'});
assert(output.includes('DISPATCH_GUARDS_PASS'));
const installer=fs.readFileSync(__dirname+'/install-kazoo5.sh','utf8');
assert(installer.includes('apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-listener-dispatch-inventory.patch"'));
console.log(JSON.stringify({status:'PASS',valid:3,refused:36,evidence:root,installer_patch_required:true}));
