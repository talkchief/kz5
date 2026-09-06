#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const {execFileSync,spawnSync}=require('node:child_process');
const owned=require('./deploy-owned-monster.cjs'),build=require('./monster-build-inputs.cjs');
const {configure}=require('./configure-monster-runtime.cjs');
const project=path.resolve(process.env.KAZOO_TEST_PROJECT_ROOT||path.join(__dirname,'..'));
const installer=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'monster-installer-preserve.'));
const options={api:'http://fixture.invalid/v2/',socket:'same-origin',branding:'false',braintree:'false'};
const config=configure('define({operator:{keep:true},api:{}});',options);
let passed=0;
const test=(name,fn)=>{fn();passed++;console.log('PASS '+name);};
function write(file,bytes){fs.mkdirSync(path.dirname(file),{recursive:true,mode:0o755});fs.writeFileSync(file,bytes,{mode:0o644});}
function fixture(name){
    const root=path.join(temp,name),web=path.join(root,'web'),stage=path.join(root,'source/dist'),state=path.join(root,'registry/monster-ui-owned');
    [web,stage,state,path.join(root,'build')].forEach(p=>fs.mkdirSync(p,{recursive:true,mode:0o755}));
    for(const [file,bytes] of Object.entries({'index.html':'<html>fixture</html>','js/main.js':'old',
        'js/config.js':config,'css/style.css':'style','build-config.json':'{"preloadedApps":["core","acdc"]}',
        'apps/acdc/metadata/app.json':'{"name":"acdc"}'}))write(path.join(stage,file),bytes);
    return {root,web,stage,state,selected:['acdc'],inputs:{fingerprint_sha256:owned.hash('fixture-build\n')}};
}
function funcs(...names){return names.map(n=>{
    const m=installer.match(new RegExp('^'+n+'\\(\\) \\{[\\s\\S]*?^\\}', 'm'));
    assert(m,'Missing actual hook '+n);return m[0];
}).join('\n');}
const common='set -euo pipefail\ndie(){ printf "%s\\n" "$*" >&2; exit 1; }\nlog(){ :; }\nwrite_file(){ local mode=$1 target=$2; install -m "$mode" /dev/stdin "$target"; }\n';
function shell(code,env={},root=temp){
    return spawnSync('bash',['-c',common+code.replaceAll('/usr/local/share/kazoo5-installer',path.join(root,'registry'))],
        {encoding:'utf8',env:{...process.env,DRY_RUN:'false',SCRIPT_DIR:__dirname,...env}});
}
function succeeds(result){assert.equal(result.status,0,result.stderr);return result.stdout;}
try {
    test('actual installer hooks use owned output proof before compatibility marker and docs',()=>{
        const code=funcs('install_monster_ui');
        assert(!code.includes('rsync'));assert(code.includes('npm ci --ignore-scripts --no-audit --no-fund'));
        assert(code.includes('npm_config_jobs=1 MAKEFLAGS=-j1 npm rebuild node-sass re2'));
        assert(code.indexOf('npm ci --ignore-scripts --no-audit --no-fund')<code.indexOf('node "$SCRIPT_DIR/verify-monster-build-dependencies.cjs" "$source_dir"'));
        assert(code.indexOf('node "$SCRIPT_DIR/verify-monster-build-dependencies.cjs" "$source_dir"')<code.indexOf('npm_config_jobs=1 MAKEFLAGS=-j1 npm rebuild node-sass re2'));
        assert(code.includes('node "$SCRIPT_DIR/build-monster-production.cjs" "$source_dir"'));
        assert(!code.includes('./node_modules/.bin/gulp build-prod'));
        assert(code.indexOf('verify_monster_ui_owned "$expected_build"')<code.indexOf('write_file 0644 "$marker"'));
        assert(code.indexOf('deploy_monster_ui_owned')<code.lastIndexOf('    install_api_developer_docs\n'));
        assert(code.includes('workflow.lock'));assert(code.includes('trap '));
        const sync=funcs('sync_monster_ui_sources');assert(!sync.includes('checkout --'));assert(!sync.includes('rm -rf'));assert(!sync.includes('--delete'));
    });
    test('fingerprint covers all framework/Callflows CSS patches, lock and actual build hooks',()=>{
        const scripts=path.join(temp,'fingerprint/scripts');fs.mkdirSync(scripts,{recursive:true});
        for(const file of ['install-kazoo5.sh','deploy-owned-monster.cjs','monster-build-inputs.cjs','configure-monster-runtime.cjs','audit-monster-lock.cjs','verify-monster-build-dependencies.cjs','verify-monster-production-artifact.cjs','build-monster-production.cjs','monster-minifier-profile.cjs'])
            fs.copyFileSync(path.join(__dirname,file),path.join(scripts,file));
        write(path.join(scripts,'assets/monster-ui/package-lock.npm10.json'),fs.readFileSync(path.join(__dirname,'assets/monster-ui/package-lock.npm10.json')));
        write(path.join(scripts,'assets/monster-ui/minifier-profile.json'),fs.readFileSync(path.join(__dirname,'assets/monster-ui/minifier-profile.json')));
        const patches=['monster-ui-myaccount-transition.patch','monster-ui-branding-billing.patch','monster-ui-websocket-config.patch',
            'monster-ui-optional-integrations.patch','monster-ui-callflows-acdc-queue.patch','monster-ui-callflows-css-nesting.patch','monster-ui-npm-native-overrides.patch','monster-ui-isolated-minify.patch','monster-ui-preloaded-apps.patch'];
        for(const file of patches)write(path.join(scripts,'patches',file),fs.readFileSync(path.join(['monster-ui-npm-native-overrides.patch','monster-ui-isolated-minify.patch'].includes(file)?__dirname:path.join(project,'scripts'),'patches',file)));
        const env={SCRIPT_DIR:scripts,MONSTER_UI_REF:'a'.repeat(40),MONSTER_UI_NODE_MAJOR:'18',MONSTER_UI_LOCK_SHA256:'b'.repeat(64),
            MONSTER_UI_APPS_LIST:'callflows',MONSTER_UI_CALLFLOWS_REF:'c'.repeat(40),KAZOO_API_URL:options.api,
            MONSTER_UI_WEBSOCKET_URL:options.socket,MONSTER_UI_REMOTE_BRANDING:options.branding,MONSTER_UI_BRAINTREE:options.braintree};
        const code=funcs('monster_app_ref','monster_ui_build_fingerprint')+'\nmonster_ui_build_fingerprint\n';
        const original=succeeds(shell(code,env));assert(original.includes('node_actual='));assert(original.includes('npm_actual='));
        for(const file of patches){const target=path.join(scripts,'patches',file),bytes=fs.readFileSync(target);fs.appendFileSync(target,'\nchanged');
            assert.notEqual(succeeds(shell(code,env)),original,file+' must affect fingerprint');fs.writeFileSync(target,bytes);}
        for(const file of ['verify-monster-build-dependencies.cjs','verify-monster-production-artifact.cjs','build-monster-production.cjs','monster-minifier-profile.cjs','assets/monster-ui/minifier-profile.json']){const target=path.join(scripts,file),bytes=fs.readFileSync(target);fs.appendFileSync(target,'\n');
            assert.notEqual(succeeds(shell(code,env)),original,file+' must affect fingerprint');fs.writeFileSync(target,bytes);}
        assert.notEqual(succeeds(shell(code,{...env,MONSTER_UI_LOCK_SHA256:'d'.repeat(64)})),original);
        const lockFile=path.join(scripts,'assets/monster-ui/package-lock.npm10.json'),lockBytes=fs.readFileSync(lockFile);
        fs.appendFileSync(lockFile,'\n');assert.notEqual(succeeds(shell(code,env)),original);fs.writeFileSync(lockFile,lockBytes);
        const target=path.join(scripts,'install-kazoo5.sh'),bytes=fs.readFileSync(target,'utf8');
        fs.writeFileSync(target,bytes.replace('sync_monster_ui_sources() {','sync_monster_ui_sources() {\n    # reviewed build change'));
        assert.notEqual(succeeds(shell(code,env)),original);
        for(const file of ['verify-monster-production-artifact.cjs','patches/monster-ui-preloaded-apps.patch']){
            const target=path.join(scripts,file),bytes=fs.readFileSync(target);fs.unlinkSync(target);
            assert.notEqual(shell(code,env).status,0,'Missing fingerprint input must fail: '+file);write(target,bytes);
        }
        assert.notEqual(shell('sha256sum(){ return 7; }\n'+code,env).status,0,'Unreadable hash input must fail');
    });
    test('reviewed lock staging rejects changed source/artifact/package and does no dependency resolution',()=>{
        const root=path.join(temp,'lock-boundary');fs.mkdirSync(root,{mode:0o700});
        const cache=process.env.KAZOO_MONSTER_SOURCE_CACHE||'/usr/local/src/kazoo5-installer/monster-ui';
        const pin='7ef735eada6fd0e2b96c06f32c0bb868867f7d18';
        const original=execFileSync('git',['-C',cache,'show',pin+':package-lock.json']);
        const sourcePackage=execFileSync('git',['-C',cache,'show',pin+':package.json'],{encoding:'utf8'});
        write(path.join(root,'package-lock.json'),original);write(path.join(root,'package.json'),sourcePackage);
        const artifact=path.join(__dirname,'assets/monster-ui/package-lock.npm10.json');
        assert.throws(()=>build.prepareLock(root,artifact),/package compatibility patch/);
        const patched=sourcePackage.replace(/^[ \t]*"preinstall": "npx npm-force-resolutions",\n/m,'').replace('"resolutions": {','"overrides": {');
        write(path.join(root,'package.json'),patched);
        const bad=path.join(temp,'bad-lock.json');write(bad,Buffer.concat([fs.readFileSync(artifact),Buffer.from('\n')]));
        assert.throws(()=>build.prepareLock(root,bad),/Unexpected migrated/);
        write(path.join(root,'package-lock.json'),Buffer.concat([original,Buffer.from('\n')]));
        assert.throws(()=>build.prepareLock(root,artifact),/Unexpected original/);
        write(path.join(root,'package-lock.json'),original);
        const result=build.prepareLock(root,artifact);assert.equal(result.sha256,owned.hash(fs.readFileSync(artifact)));
        assert.deepEqual(fs.readFileSync(path.join(root,'package-lock.json')),fs.readFileSync(artifact));
        const receipt=JSON.parse(fs.readFileSync(path.join(root,'.kazoo-npm-lock-audit.json')));
        assert.equal(receipt.compatibility_verified,false);assert.equal(receipt.common_version_resolved_integrity_changes,2);
    });
    test('old source checkout is refused before git/reset/delete and remains identical',()=>{
        const dir=path.join(temp,'operator-source');write(path.join(dir,'operator.txt'),'keep');
        const before=owned.snapshot(dir);
        const r=shell('sync_git(){ die "must not reach git"; }\n'+funcs('sync_monster_ui_sources')+'\nsync_monster_ui_sources "$FIXTURE"',
            {FIXTURE:dir});assert.notEqual(r.status,0);assert(r.stderr.includes('Source target already exists'));
        assert.deepEqual(owned.snapshot(dir),before);
    });
    test('root preparation refuses symlink/writable ancestors without repair',()=>{
        const dir=path.join(temp,'writable');fs.mkdirSync(dir,{mode:0o777});fs.chmodSync(dir,0o777);
        assert.throws(()=>build.prepareRoots(path.join(dir,'new')),/Writable/);assert(!fs.existsSync(path.join(dir,'new')));
        const symlink=path.join(temp,'linked');fs.symlinkSync(dir,symlink);assert.throws(()=>build.prepareRoots(path.join(symlink,'new')),/Symlink/);
    });
    test('existing public config and operator fields are preserved; implicit migration refused',()=>{
        const f=fixture('config'),source=path.dirname(f.stage);
        write(path.join(f.web,'js/config.js'),config);write(path.join(source,'src/js/config.js'),'define({});');
        assert.equal(build.preserveConfig(f.web,source,options).status,'preserved_configuration');
        assert.equal(fs.readFileSync(path.join(source,'src/js/config.js'),'utf8'),config);
        fs.unlinkSync(path.join(source,'.kazoo-configuration-plan.json'));
        assert.throws(()=>build.preserveConfig(f.web,source,{...options,api:'https://different.invalid/v2/'}),/separate config migration/);
        assert.equal(fs.readFileSync(path.join(f.web,'js/config.js'),'utf8'),config);
    });
    test('explicit requested config transform preserves unknown fields and is bound to exact plan/receipt hashes',()=>{
        const f=fixture('config-migrate'),source=path.dirname(f.stage),nextOptions={...options,api:'https://fixture.invalid/v2/'};
        write(path.join(f.web,'js/config.js'),config);write(path.join(f.web,'apps/acdc/language-capabilities.json'),'runtime-keep');
        write(path.join(source,'src/js/config.js'),'define({});');
        assert.equal(build.preserveConfig(f.web,source,nextOptions,true).status,'staged_configuration_change');
        const transformed=fs.readFileSync(path.join(source,'src/js/config.js'));
        write(path.join(f.stage,'js/config.js'),transformed);
        const change=JSON.parse(fs.readFileSync(path.join(source,'.kazoo-configuration-plan.json')));
        assert.equal(change.before_sha256,owned.hash(config));assert.equal(change.after_sha256,owned.hash(transformed));
        assert(transformed.toString().includes('"keep": true'));
        const opts={...f,adopt_existing:true,configuration_change:change};
        const plan=owned.plan(opts);assert(plan.changes.includes('js/config.js'));
        const bad=Buffer.from(transformed.toString().replace('"keep": true','"keep": false'));
        write(path.join(f.stage,'js/config.js'),bad);
        assert.throws(()=>owned.plan({...opts,configuration_change:{...change,after_sha256:owned.hash(bad)}}),/exact requested transform/);
        write(path.join(f.stage,'js/config.js'),transformed);
        assert.throws(()=>owned.plan({...opts,configuration_change:{...change,before_sha256:'0'.repeat(64)}}),/hashes/);
        owned.apply(plan,owned.hash(owned.canonical(plan)),path.join(f.root,'migration-backup'));
        assert.equal(fs.readFileSync(path.join(f.web,'apps/acdc/language-capabilities.json'),'utf8'),'runtime-keep');
        const owner=JSON.parse(fs.readFileSync(path.join(f.state,'owned.json')));
        assert.deepEqual(owner.configuration_change,change);assert.equal(owned.verify(path.join(f.state,'owned.json')).status,'complete');
    });
    test('actual deployment hooks preserve operator apps, config, capability and docs; only owned stale selected files removed',()=>{
        const f=fixture('owned');
        for(const [p,b]of Object.entries({'apps/operator-private/app.js':'operator','apps/acdc/language-capabilities.json':'runtime-proof',
            'apis/index.html':'separately-managed-docs','js/config.js':config}))write(path.join(f.web,p),b);
        write(path.join(f.stage,'apps/acdc/obsolete.js'),'obsolete');
        const first=owned.plan({...f,adopt_existing:true});owned.apply(first,owned.hash(owned.canonical(first)),path.join(f.root,'adoption-backup'));
        fs.unlinkSync(path.join(f.stage,'apps/acdc/obsolete.js'));write(path.join(f.stage,'js/main.js'),'new');
        const saved=Object.fromEntries(['apps/operator-private/app.js','apps/acdc/language-capabilities.json','apis/index.html','js/config.js']
            .map(p=>[p,fs.readFileSync(path.join(f.web,p))]));
        const code='monster_ui_build_fingerprint(){ printf "%s\\n" fixture-build; }\n'+funcs('verify_monster_ui_owned','deploy_monster_ui_owned')+
            '\ndeploy_monster_ui_owned "$FIXTURE_SOURCE"\nverify_monster_ui_owned fixture-build\n';
        succeeds(shell(code,{MONSTER_UI_WEB_ROOT:f.web,KAZOO_BUILD_ROOT:path.join(f.root,'build'),MONSTER_UI_APPS_LIST:'acdc',FIXTURE_SOURCE:path.dirname(f.stage)},f.root));
        for(const [p,b]of Object.entries(saved))assert.deepEqual(fs.readFileSync(path.join(f.web,p)),b,p);
        assert(!fs.existsSync(path.join(f.web,'apps/acdc/obsolete.js')));assert.equal(fs.readFileSync(path.join(f.web,'js/main.js'),'utf8'),'new');
        const verify=funcs('verify_monster_ui_owned')+'\nverify_monster_ui_owned fixture-build\n';
        assert.notEqual(shell(verify.replace('fixture-build','wrong-fingerprint'),{},f.root).status,0);
        fs.appendFileSync(path.join(f.web,'js/main.js'),'operator-change');assert.notEqual(shell(verify,{},f.root).status,0);
    });
    test('actual deployment hook refuses unowned legacy web without claiming files or advancing marker',()=>{
        const f=fixture('legacy');write(path.join(f.web,'operator.txt'),'retain');const before=owned.snapshot(f.web);
        const code='monster_ui_build_fingerprint(){ printf "%s\\n" fixture-build; }\n'+funcs('verify_monster_ui_owned','deploy_monster_ui_owned')+
            '\ndeploy_monster_ui_owned "$FIXTURE_SOURCE"';
        const r=shell(code,{MONSTER_UI_WEB_ROOT:f.web,KAZOO_BUILD_ROOT:path.join(f.root,'build'),MONSTER_UI_APPS_LIST:'acdc',FIXTURE_SOURCE:path.dirname(f.stage)},f.root);
        assert.notEqual(r.status,0);assert.deepEqual(owned.snapshot(f.web),before);assert(!fs.existsSync(path.join(f.state,'owned.json')));
        assert(!fs.existsSync(path.join(f.root,'registry/monster-ui-build')));
    });
    test('fingerprint failure stops before deployment planning or web writes',()=>{
        const f=fixture('failed-fingerprint'),before=owned.snapshot(f.web);
        const code='monster_ui_build_fingerprint(){ printf "incomplete fingerprint\\n"; return 7; }\n'+funcs('deploy_monster_ui_owned')+'\ndeploy_monster_ui_owned "$FIXTURE_SOURCE"';
        const result=shell(code,{MONSTER_UI_WEB_ROOT:f.web,KAZOO_BUILD_ROOT:path.join(f.root,'build'),FIXTURE_SOURCE:path.dirname(f.stage)},f.root);
        assert.notEqual(result.status,0);assert.deepEqual(owned.snapshot(f.web),before);
        assert.deepEqual(fs.readdirSync(path.join(f.root,'build')),[]);assert(!fs.existsSync(path.join(f.state,'owned.json')));
    });
    test('actual catalog hook invokes only selected safe module and stops without printing error body',()=>{
        const calls=path.join(temp,'catalog-calls');
        const stub='monster_registration_available(){ return 0; }\nensure_master_account(){ :; }\nconfigure_kazoo_api_modules(){ :; }\nverify_monster_app_registration(){ :; }\n'+
            'timeout(){ shift 2; "$@"; }\nsup(){ printf "%s\\n" "$1 $2 $3" >> "$CALLS"; printf "%s\\n" "${SUP_RESULT:-preserved}"; }\n';
        const code=stub+funcs('register_monster_apps')+'\nregister_monster_apps\n',env={CALLS:calls,MONSTER_UI_APPS_LIST:'acdc,accounts',
            MONSTER_UI_WEB_ROOT:'/fixture/web',KAZOO_API_URL:options.api,MONSTER_UI_REGISTER_APPS:'true'};
        succeeds(shell(code,env));assert.deepEqual(fs.readFileSync(calls,'utf8').trim().split('\n'),['kazoo_monster_catalog init_app acdc','kazoo_monster_catalog init_app accounts']);
        fs.unlinkSync(calls);const bad=shell(code,{...env,SUP_RESULT:'{error,PRIVATE_BODY_MUST_NOT_PRINT}'});
        assert.notEqual(bad.status,0);assert(!bad.stdout.includes('PRIVATE_BODY'));assert(!bad.stderr.includes('PRIVATE_BODY'));
        assert.equal(fs.readFileSync(calls,'utf8').trim().split('\n').length,1);
    });
    console.log(JSON.stringify({status:'PASS',groups:passed,scope:'offline; no live files/services/catalog touched'}));
} finally {fs.rmSync(temp,{recursive:true,force:true});}
