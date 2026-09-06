#!/usr/bin/env node
'use strict';
// Real temporary files and extracted shell hooks only; no network or services.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process'),owned=require('./deploy-owned-monster.cjs');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'monster-owner-binding.'));
const installer=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
const state=path.join(root,'state'),web=path.join(root,'web'),other=path.join(root,'other');
let groups=0;
const test=(name,fn)=>{fn();groups++;console.log('PASS '+name);};
const hooks=name=>{const found=installer.match(new RegExp('^'+name+'\\(\\) \\{[\\s\\S]*?^\\}','m'));assert(found,'Missing actual hook');return found[0];};
function run(code,target=web,fingerprint='fixture') {
    const result=spawnSync('bash',['-c','set -euo pipefail\ndie(){ printf "%s\\n" "$*" >&2; exit 1; }\n'+code],
        {encoding:'utf8',env:{...process.env,SCRIPT_DIR:__dirname,MONSTER_UI_WEB_ROOT:target,state,FIXTURE_FINGERPRINT:fingerprint}});
    assert(!result.error);return result;
}
function verify(target=web,fingerprint='fixture') {
    const code=hooks('verify_monster_ui_owned').replace('/usr/local/share/kazoo5-installer/monster-ui-owned/owned.json',path.join(state,'owned.json'));
    return run(code+'\nverify_monster_ui_owned "$FIXTURE_FINGERPRINT"',target,fingerprint);
}
try {
    for(const dir of [state,web,other])fs.mkdirSync(dir,{mode:0o700});
    const content={'index.html':'same index','js/main.js':'same main','js/config.js':'same config','css/style.css':'same style','build-config.json':'{"preloadedApps":["core"]}'};
    for(const dir of [web,other])for(const [name,bytes]of Object.entries(content)) {
        const file=path.join(dir,name);fs.mkdirSync(path.dirname(file),{recursive:true,mode:0o700});fs.writeFileSync(file,bytes,{mode:0o600});
    }
    const hashes=owned.snapshot(web),owner={version:1,status:'complete',web,inputs:{fingerprint_sha256:owned.hash('fixture\n')},
        configuration_sha256:hashes['js/config.js'],files:Object.fromEntries(Object.entries(hashes).filter(([name])=>name!=='js/config.js'))};
    fs.writeFileSync(path.join(state,'owned.json'),JSON.stringify(owner),{mode:0o600});
    test('verified result reports the exact validated ownership web path',()=>assert.equal(owned.verify(path.join(state,'owned.json')).web,web));
    test('matching configured web root and input fingerprint pass',()=>assert.equal(verify().status,0));
    test('different configured web root fails even with identical complete files and fingerprint',()=>{
        assert.deepEqual(owned.snapshot(web),owned.snapshot(other));assert.notEqual(verify(other).status,0);
    });
    test('wrong fingerprint still fails for the correct web root',()=>assert.notEqual(verify(web,'different').status,0));
    test('early installer precheck rejects the wrong web root before source/build actions',()=>{
        const install=hooks('install_monster_ui'),match=install.match(/    if \[\[ -e \$state\/owned\.json \]\]; then[\s\S]*?\n    fi/);
        assert(match,'Missing actual early ownership precheck');
        const code=match[0]+'\nprintf "passed-early-precheck\\n"';
        assert.equal(run(code).status,0);const rejected=run(code,other);assert.notEqual(rejected.status,0);assert(!rejected.stdout.includes('passed-early-precheck'));
    });
    test('actual content mismatch still fails for the owned configured web root',()=>{
        fs.appendFileSync(path.join(web,'js/main.js'),'changed');assert.notEqual(verify().status,0);
    });
    console.log(JSON.stringify({status:'PASS',groups,scope:'temporary filesystem and shell fixtures only; no live deployment'}));
} finally {fs.rmSync(root,{recursive:true,force:true});}
