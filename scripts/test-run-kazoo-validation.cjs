'use strict';
// Fixed-path transport is replaced only inside a sourced test shell. No public
// test switch, manager override, live cgroup, service or workload is exercised.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
const source=path.resolve(__dirname,'run-kazoo-validation.sh');
const sandbox=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-validation-mocks-'));
fs.chmodSync(sandbox,0o700);
const lock=path.join(sandbox,'validation.lock'),capture=path.join(sandbox,'capture.cjs'),log=path.join(sandbox,'argv.jsonl');
const cwd=path.join(sandbox,'working directory with spaces'),nonce='01234567-89ab-cdef-0123-456789abcdef';
fs.mkdirSync(cwd,{mode:0o700});fs.writeFileSync(lock,'',{mode:0o600});
fs.writeFileSync(capture,'#!/usr/bin/node\nconst fs=require("node:fs");fs.appendFileSync(process.env.TEST_LOG,JSON.stringify(process.argv.slice(2))+"\\n",{mode:0o600});\n',{mode:0o700});
const mocks=String.raw`
source "$TEST_SOURCE"
validation_host() { return "${'${'}TEST_HOST_STATUS:-0}"; }
validation_account_home() { [[ ${'${'}TEST_HOME_STATUS:-0} == 0 ]] || return 1; printf '%s\n' /root; }
validation_prepare_lock() {
    [[ $1 == /run && $2 == /run/kazoo-validation ]] || return 98
    printf '%s\n' "$TEST_LOCK"
}
validation_flock() {
    "$TEST_CAPTURE" flock "$@"
    [[ $1 == --unlock ]] || return "${'${'}TEST_LOCK_STATUS:-0}"
}
validation_mem_available() {
    [[ $1 == /proc/meminfo ]] || return 98
    "$TEST_CAPTURE" memory "$1"
    printf '%s\n' "$TEST_AVAILABLE"
}
validation_nonce() { printf '%s\n' "$TEST_NONCE"; }
validation_transport() { "$TEST_CAPTURE" transport "$@"; return "${'${'}TEST_EXIT:-0}"; }
validation_main "$@"
`;
const environment={PATH:'/usr/bin:/bin',LC_ALL:'C',TEST_SOURCE:source,TEST_LOCK:lock,TEST_CAPTURE:capture,TEST_LOG:log,TEST_NONCE:nonce,
    TEST_AVAILABLE:String(8192*1024),NODE_OPTIONS:'--max-old-space-size=48'};
let cases=0;
function run(args,extra={}) {
    fs.writeFileSync(log,'',{mode:0o600});
    const result=cp.spawnSync('/usr/bin/bash',['-c',mocks,'validation-test',...args],
        {env:{...environment,...extra},cwd,encoding:'utf8',timeout:5000,maxBuffer:1024*1024});
    if(result.error)throw result.error;
    const events=fs.readFileSync(log,'utf8').trim().split('\n').filter(Boolean).map(x=>JSON.parse(x));
    cases++;return {...result,events};
}
function direct(body,args=[]) {
    const result=cp.spawnSync('/usr/bin/bash',['-c','source "$1"; shift; '+body,'validation-test',source,...args],
        {env:{PATH:'/usr/bin:/bin',LC_ALL:'C'},encoding:'utf8',timeout:3000,maxBuffer:65536});
    if(result.error)throw result.error;
    cases++;return result;
}
function noTransport(result,status) {
    assert.equal(result.status,status,result.stderr);
    assert(!result.events.some(e=>e[0]==='transport'));
}
function literalExecArguments(argv) {
    // A paired dollar is systemd's literal-dollar encoding. Refuse every
    // unpaired dollar here: it could otherwise trigger manager expansion.
    return argv.map(argument=>{
        let decoded='';
        for(let index=0;index<argument.length;index++) {
            const value=argument[index];
            if(value==='$')assert.equal(argument[++index],'$','Unescaped dollar reached systemd ExecStart');
            decoded+=value;
        }
        return decoded;
    });
}
try {
    const payload=['/usr/bin/printf','%s\n','with spaces','line\nbreak','--user','$(not-a-command)','synthetic-sensitive-fixture',
        '${KAZOO_ARGV_LITERAL_8D1F}','$KAZOO_ARGV_LITERAL_8D1F','$$','$$$','before${KAZOO_ARGV_LITERAL_8D1F}after',
        '${KAZOO_ARGV_LITERAL_8D1F:-synthetic-default}','quoted "$literal"','backslash\\$literal','%n',''];
    const result=run(['--',...payload]);
    assert.equal(result.status,0,result.stderr);assert.equal(result.stdout,'');assert.equal(result.stderr,'');
    const rawLaunch=result.events.find(e=>e[0]==='transport');assert(rawLaunch);
    const boundary=rawLaunch.indexOf('--');
    const launch=[...rawLaunch.slice(0,boundary+1),...literalExecArguments(rawLaunch.slice(boundary+1))];
    assert.deepEqual(launch.slice(-payload.length),payload,'Workload argv must stay byte-for-byte distinct arguments after systemd expansion');
    assert.equal(launch[1],'900');
    const delimiter=launch.indexOf('--'),options=launch.slice(2,delimiter),wrapped=launch.slice(delimiter+1),program=wrapped.slice(5);
    assert.deepEqual(wrapped.slice(0,5),['/usr/bin/env','-i','PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin','LANG=C','HOME=/root']);
    assert.deepEqual(options,[
        '--system','--no-ask-password','--quiet','--wait','--pipe','--collect','--service-type=exec','--slice=system.slice',
        '--unit=kazoo-validation-'+nonce+'.service','--description=Kazoo bounded validation','--working-directory='+cwd,
        '--property=MemoryAccounting=yes','--property=MemoryMax=384M','--property=MemorySwapMax=0',
        '--property=OOMPolicy=kill','--property=LimitCORE=0','--property=CPUAccounting=yes','--property=CPUQuota=50%',
        '--property=CPUQuotaPeriodSec=100ms','--property=TasksAccounting=yes','--property=TasksMax=128',
        '--property=RuntimeMaxSec=900s','--property=TimeoutStartSec=15s','--property=TimeoutStopSec=10s',
        '--property=KillMode=control-group','--property=SendSIGKILL=yes','--property=Delegate=no','--property=ProtectControlGroups=yes'
    ]);
    assert.deepEqual(program.slice(0,8),['/usr/bin/flock','--exclusive','--nonblock','--conflict-exit-code','75',lock,'/usr/bin/bash','-c']);
    assert(!program.includes('--no-fork'),'Service flock parent must retain ownership when payload closes inherited descriptors');
    assert(program[8].includes('validation_limits "$unit" "$memory_bytes" /proc/self/cgroup /sys/fs/cgroup'));
    assert(program[8].includes('validation_require_memory "$required_kib" /proc/meminfo'));
    assert(program[8].includes('exec -- "$@"'));
    assert.deepEqual(program.slice(9,13),['kazoo-validation-worker','kazoo-validation-'+nonce+'.service',String(384*1024*1024),String((384+768)*1024)]);
    assert.deepEqual(result.events.map(e=>e[0]),['flock','memory','flock','transport']);
    assert.deepEqual(result.events[0].slice(1,5),['--exclusive','--nonblock','--conflict-exit-code','75']);
    assert.equal(result.events[2][1],'--unlock');
    assert.equal(result.events[0][5],result.events[2][2]);

    const inline=['/usr/bin/bash','-c',String.raw`KAZOO_ARGV_TEST_HOST_8D1F=127.0.0.1; KAZOO_ARGV_TEST_PORT_8D1F=5984; printf '%s\n' "http://${'${'}KAZOO_ARGV_TEST_HOST_8D1F}:${'${'}KAZOO_ARGV_TEST_PORT_8D1F}/synthetic"`];
    const inlineResult=run(['--',...inline]);assert.equal(inlineResult.status,0,inlineResult.stderr);
    const inlineRaw=inlineResult.events.find(e=>e[0]==='transport');
    const inlineDecoded=literalExecArguments(inlineRaw.slice(inlineRaw.indexOf('--')+1));
    assert.deepEqual(inlineDecoded.slice(-inline.length),inline);
    const synthetic=cp.spawnSync(inline[0],inlineDecoded.slice(-inline.length+1),
        {env:{PATH:'/usr/bin:/bin',LANG:'C'},encoding:'utf8',timeout:3000,maxBuffer:1024});
    assert.equal(synthetic.status,0,synthetic.stderr);
    assert.equal(synthetic.stdout,'http://127.0.0.1:5984/synthetic\n');

    for(const status of [37,75,124,137])assert.equal(run(['--','/usr/bin/true'],{TEST_EXIT:String(status)}).status,status);
    noTransport(run(['--','/usr/bin/true'],{TEST_LOCK_STATUS:'75'}),75);
    noTransport(run(['--','/usr/bin/true'],{TEST_HOST_STATUS:'77'}),77);
    noTransport(run(['--','/usr/bin/true'],{TEST_HOME_STATUS:'1'}),69);
    const cleanHome=run(['--','/usr/bin/true'],{HOME:'/synthetic-untrusted-home'});
    assert.equal(cleanHome.status,0);
    assert(cleanHome.events.find(e=>e[0]==='transport').includes('HOME=/root'));
    assert(!JSON.stringify(cleanHome.events).includes('/synthetic-untrusted-home'));
    noTransport(run(['--','/usr/bin/true'],{TEST_AVAILABLE:String((384+768)*1024-1)}),69);
    assert.equal(run(['--','/usr/bin/true'],{TEST_AVAILABLE:String((384+768)*1024)}).status,0);
    const minimum=run(['--memory-mib','128','--reserve-mib','512','--runtime-sec','10','--','/usr/bin/true'],
        {TEST_AVAILABLE:String((128+512)*1024)});
    assert.equal(minimum.status,0);const minLaunch=minimum.events.find(e=>e[0]==='transport');
    assert(minLaunch.includes('--property=MemoryMax=128M'));assert(minLaunch.includes('--property=RuntimeMaxSec=10s'));
    assert(minLaunch.includes(String((128+512)*1024)));
    assert.equal(run(['--reserve-mib','4096','--runtime-sec','1800','--','/usr/bin/true']).status,0);
    // Longer foreground work is an explicit opt-in, not a new default or
    // opportunity to relax any service property, lock or admission check.
    for(const seconds of ['1801','3599','3600']) {
        const extended=run(['--runtime-sec',seconds,'--',...payload]);
        assert.equal(extended.status,0,extended.stderr);
        const extendedRaw=extended.events.find(e=>e[0]==='transport');
        assert.equal(extendedRaw[1],seconds);
        const extendedBoundary=extendedRaw.indexOf('--');
        assert.deepEqual(extendedRaw.slice(2,extendedBoundary),options.map(option=>
            option==='--property=RuntimeMaxSec=900s'?'--property=RuntimeMaxSec='+seconds+'s':option));
        assert.deepEqual(literalExecArguments(extendedRaw.slice(extendedBoundary+1)),wrapped);
        assert.deepEqual(extended.events.map(e=>e[0]),['flock','memory','flock','transport']);
    }
    noTransport(run(['--runtime-sec','3600','--','/usr/bin/true'],{TEST_LOCK_STATUS:'75'}),75);
    noTransport(run(['--runtime-sec','3600','--','/usr/bin/true'],{TEST_AVAILABLE:String((384+768)*1024-1)}),69);
    assert.equal(run(['--runtime-sec','3600','--','/usr/bin/true'],{TEST_EXIT:'124'}).status,124);
    const invalid=[[],['/usr/bin/true'],['--'],['--','true'],['--','/nonexistent/command'],['--user'],['--scope'],
        ['--host','remote'],['--machine','container'],['--runner','/usr/bin/true'],['--property','MemoryMax=infinity'],
        ['--memory-mib'],['--memory-mib','128','--memory-mib','128','--','/usr/bin/true']];
    for(const [flag,values] of [['--memory-mib',['127','385','0128','128M','1e3','-1','999999999999999','128;false','']],
        ['--reserve-mib',['511','4097','0']],['--runtime-sec',['9','3601','9999','03600','3600s','infinity','0','-1','1e3','3600;false']]])
        for(const value of values)invalid.push([flag,value,'--','/usr/bin/true']);
    invalid.push(['--runtime-sec','1800','--runtime-sec','3600','--','/usr/bin/true']);
    for(const args of invalid)noTransport(run(args),64);
    const secretFailure=run(['--synthetic-sensitive-fixture','--','/usr/bin/true']);
    noTransport(secretFailure,64);assert(!secretFailure.stderr.includes('synthetic-sensitive-fixture'));
    const help=run(['--help']);assert.equal(help.status,0);assert.equal(help.events.length,0);

    const memfile=path.join(sandbox,'meminfo');
    for(const [contents,expected] of [
        ['MemTotal: 4000000 kB\nMemFree: 1 kB\nMemAvailable: 12345 kB\n','12345\n'],
        ['MemAvailable: 0 kB\n','0\n'],['MemFree: 12345 kB\n',null],
        ['MemAvailable: 1 kB\nMemAvailable: 2 kB\n',null],['MemAvailable: 5 MB\n',null],
        ['MemAvailable: -1 kB\n',null],['MemAvailable: 1234567890123 kB\n',null],['MemAvailable: 1 kB extra\n',null]
    ]) {
        fs.writeFileSync(memfile,contents,{mode:0o600});const r=direct('validation_mem_available "$1"',[memfile]);
        if(expected===null)assert.notEqual(r.status,0);else{assert.equal(r.status,0,r.stderr);assert.equal(r.stdout,expected);}
    }
    const unit='kazoo-validation-'+nonce+'.service',cg=path.join(sandbox,'cgroups'),member=path.join(sandbox,'membership');
    const limits=path.join(cg,'system.slice',unit);fs.mkdirSync(limits,{recursive:true,mode:0o700});
    const defaults={'memory.max':String(384*1024*1024),'memory.swap.max':'0','memory.oom.group':'1','pids.max':'128','cpu.max':'50000 100000'};
    function resetLimits(){for(const [key,val]of Object.entries(defaults))fs.writeFileSync(path.join(limits,key),val+'\n',{mode:0o600});fs.writeFileSync(member,'0::/system.slice/'+unit+'\n',{mode:0o600});}
    function limitsCheck(){return direct('validation_limits "$1" "$2" "$3" "$4"',[unit,String(384*1024*1024),member,cg]);}
    resetLimits();assert.equal(limitsCheck().status,0);
    for(const [key,value]of [['memory.max','max'],['memory.max',String(512*1024*1024)],['memory.swap.max','max'],
        ['memory.oom.group','0'],['pids.max','129'],['cpu.max','60000 100000'],['cpu.max','max 100000'],['cpu.max','50000 100000 extra']]){
        resetLimits();fs.writeFileSync(path.join(limits,key),value+'\n');assert.notEqual(limitsCheck().status,0,key);
    }
    for(const content of ['0::/\n','0::/user.slice/'+unit+'\n','0::/system.slice/other.service\n','0::/system.slice/'+unit+'\n0::/\n']){
        resetLimits();fs.writeFileSync(member,content);assert.notEqual(limitsCheck().status,0);
    }
    // Only private test filesystem paths; no /run lock or live cgroup creation.
    const parent=path.join(sandbox,'protected-parent'),directory=path.join(parent,'kazoo-validation');
    fs.mkdirSync(parent,{mode:0o700});
    const created=direct('validation_prepare_lock "$1" "$2"',[parent,directory]);
    assert.equal(created.status,0,created.stderr);const createdLock=path.join(directory,'validation.lock');
    assert.equal(created.stdout,createdLock+'\n');assert.equal(fs.statSync(createdLock).mode&0o777,0o600);
    const inode=fs.statSync(createdLock).ino;
    assert.equal(direct('validation_prepare_lock "$1" "$2"',[parent,directory]).status,0);
    assert.equal(fs.statSync(createdLock).ino,inode,'Rerun must retain the same lock inode');
    for(const [file,mode]of [[parent,0o777],[directory,0o755],[createdLock,0o644]]){
        const old=fs.statSync(file).mode&0o777;fs.chmodSync(file,mode);
        assert.notEqual(direct('validation_prepare_lock "$1" "$2"',[parent,directory]).status,0);fs.chmodSync(file,old);
    }
    fs.writeFileSync(createdLock,'do not truncate');
    assert.notEqual(direct('validation_prepare_lock "$1" "$2"',[parent,directory]).status,0);
    assert.equal(fs.readFileSync(createdLock,'utf8'),'do not truncate');fs.writeFileSync(createdLock,'');
    const hardlink=path.join(directory,'another-link');fs.linkSync(createdLock,hardlink);
    assert.notEqual(direct('validation_prepare_lock "$1" "$2"',[parent,directory]).status,0);fs.unlinkSync(hardlink);
    const linkedParent=path.join(sandbox,'linked-parent');fs.symlinkSync(parent,linkedParent);
    assert.notEqual(direct('validation_prepare_lock "$1" "$2"',[linkedParent,path.join(linkedParent,'kazoo-validation')]).status,0);
    fs.unlinkSync(createdLock);fs.symlinkSync(lock,createdLock);
    assert.notEqual(direct('validation_prepare_lock "$1" "$2"',[parent,directory]).status,0);
    assert.notEqual(direct('validation_stat(){ printf "%s\\n" "1000:0:700:directory:1:0"; }; validation_secure_directory "$1" 700',[directory]).status,0);
    const script=fs.readFileSync(source,'utf8');
    // Execute the actual transport body with only its fixed-path timeout
    // invocation replaced by a private argv recorder. Never call systemd.
    const transportMatches=[...script.matchAll(/^validation_transport\(\) \{[\s\S]*?^\}/gm)];
    assert.equal(transportMatches.length,1);
    const transportDefinition=transportMatches[0][0];
    assert.equal(transportDefinition.split('/usr/bin/timeout').length,2);
    const capturedTransport=transportDefinition.replace('/usr/bin/timeout','validation_timeout_capture');
    for(const seconds of ['900','1800','3600']) {
        const transport=direct('validation_timeout_capture() { printf "%s\\0" "$@"; };\n'+capturedTransport+
            '\nvalidation_transport "$@"',[seconds,'--system','--','/usr/bin/true']);
        assert.equal(transport.status,0,transport.stderr);
        assert.deepEqual(transport.stdout.split('\0').slice(0,-1),[
            '--signal=TERM','--kill-after=10s',String(Number(seconds)+45)+'s',
            '/usr/bin/env','-i','PATH=/usr/bin:/bin','LANG=C',
            'SYSTEMD_LOG_LEVEL=err','SYSTEMD_LOG_TARGET=console','SYSTEMD_BUS_TIMEOUT=15s',
            '/usr/bin/systemd-run','--system','--','/usr/bin/true']);
    }
    assert(script.includes('/usr/bin/timeout --signal=TERM --kill-after=10s "$((runtime+45))s"'));
    assert(script.includes('/usr/bin/systemd-run "$@"'));
    assert(script.includes('/usr/bin/env -i PATH=/usr/bin:/bin LANG=C'));
    assert(script.includes('SYSTEMD_LOG_LEVEL=err SYSTEMD_LOG_TARGET=console SYSTEMD_BUS_TIMEOUT=15s'));
    assert(!/\beval\b|--setenv|--user\b|--host=|--machine=|--scope\b/.test(script));
    console.log(JSON.stringify({result:'PASS',cases,exact_argv:true,systemd_literal_dollars:true,service_held_lock:true,
        memory_admission_twice:true,effective_cgroup_fail_closed:true,actual_systemd_calls:0,live_workloads:0}));
} finally {
    // Exact mkdtemp-owned directory only; it contains synthetic test fixtures.
    fs.rmSync(sandbox,{recursive:true,force:true});
}
