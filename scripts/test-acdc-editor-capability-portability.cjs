'use strict';
// Extract and execute only changed helpers with shell doubles. No source of
// deployment.env, real Node helper, capabilities, database or systemd access.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const assert=require('node:assert/strict');
const candidate=process.env.KAZOO_EDITOR_PORTABILITY_CANDIDATE;
const source=fs.readFileSync(path.join(candidate || __dirname,'install-kazoo5.sh'),'utf8');
const helper=source.match(/^install_acdc_editor_capabilities\(\) \{[\s\S]*?^\}/m)[0];
const apps=source.match(/^install_kazoo_apps\(\) \{[\s\S]*?^\}/m)[0];
const setup=`set -Eeuo pipefail
DRY_RUN=false
SCRIPT_DIR=/private/repo/scripts
KAZOO_CONFIG_DIR=/private/custom-kazoo
log() { :; }
die() { exit 77; }
`;
function run(body){const r=cp.spawnSync('/bin/bash',['--noprofile','--norc','-s'],{
    input:setup+body,env:{PATH:'/usr/bin:/bin',LANG:'C'},encoding:'utf8',timeout:5000});
    assert.ifError(r.error);return r;
}
let r=run(helper+'\nnode() { printf "%s\\n" "$@"; }\ninstall_acdc_editor_capabilities\n');
assert.equal(r.status,0);assert.deepEqual(r.stdout.trim().split('\n'),[
    '/private/repo/scripts/ensure-acdc-language-capabilities.cjs','--config-root','/private/custom-kazoo']);
r=run(helper+'\nnode() { exit 76; }\ninstall_acdc_editor_capabilities\n');assert.equal(r.status,76);
r=run(helper+'\nnode() { return 1; }\ninstall_acdc_editor_capabilities\n');assert.equal(r.status,77);
r=run(helper+'\nDRY_RUN=true\nnode() { exit 76; }\ninstall_acdc_editor_capabilities\n');assert.equal(r.status,0);
// Exact current apps sequence. The fixed sleep became the datastore/bootstrap
// readiness gates, and the toolchain, broker preflight (before the build and again
// before the restart), call-forward pack, catalog receiver, DNS default and
// prerecorded finalization steps were added since this oracle was written.
const operations=['install_nodejs_toolchain','acdc_broker_upgrade_preflight','install_call_forward_confirmation_pack',
    'install_acdc_language_packs','install_acdc_editor_capabilities','build_kazoo',
    'install_kazoo_systemd_units','install_sup_cli','install_monster_catalog_receiver',
    'acdc_broker_upgrade_preflight','service_enable_restart','wait_kazoo_datastore_ready',
    'persist_kazoo_apps_config','wait_kazoo_bootstrap_ready','ensure_master_account','configure_kazoo_api_modules',
    'ensure_dns_validation_disabled','install_kazoo_prompts','activate_acdc_voice_mappings',
    'finalize_acdc_prerecorded_capabilities','verify_kazoo_apps'];
r=run(apps+'\n'+[...new Set(operations)].map(name=>`${name}() { printf '%s\\n' '${name}'; }`).join('\n')+'\ninstall_kazoo_apps\n');
assert.equal(r.status,0,r.stderr);assert.deepEqual(r.stdout.trim().split('\n'),operations);
assert(operations.indexOf('install_acdc_editor_capabilities')<operations.indexOf('build_kazoo'),'Capabilities must be installed before the build');
const units=source.split('write_file 0644 /etc/systemd/system/kazoo-apps.service <<EOF')[1];
const appsUnit=units.split('\nEOF')[0],ecallUnit=units.split('write_file 0644 /etc/systemd/system/kazoo-ecallmgr.service <<EOF')[1].split('\nEOF')[0];
assert(appsUnit.includes('Environment=KAZOO_ACDC_EDITOR_CAPABILITIES=${KAZOO_CONFIG_DIR}/acdc/language-capabilities.json'));
assert(!ecallUnit.includes('KAZOO_ACDC_EDITOR_CAPABILITIES'));
const backend=fs.readFileSync(candidate ? path.join(candidate,'cb_acdc_queue_editor.erl') :
    path.join(__dirname,'../applications/acdc/src/cb_acdc_queue_editor.erl'),'utf8');
assert(backend.includes('kapps_config:get_ne_binary(?CAT, <<"editor_language_capabilities_path">>)'));
assert(!backend.includes('get_ne_binary(?CAT, <<"editor_language_capabilities_path">>,'));
assert(backend.includes('os:getenv("KAZOO_ACDC_EDITOR_CAPABILITIES")'));
assert(backend.includes('true = filename:pathtype(Path) =:= absolute'));
console.log('PASS memory-only installer custom-root argv, dry-run, failure propagation, prebuild ordering, apps-only environment and non-persisting backend getter');
