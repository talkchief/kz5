'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const helper=require('./official-kazoo-prompt-manifest.cjs');
const row=(name,mode='100644')=>`${mode} blob ${'a'.repeat(40)}\tkazoo-core/en/us/${name}\0`;
assert.deepEqual(helper.parseTree(Buffer.from(row('a.wav')+row('nested/ignored.wav')+row('notes.txt'))),{keys:['en-us/a']});
for(const bytes of ['',row('a.wav')+row('a.wav'),row('a.wav','120000'),row('unsafe name.wav'),row('a.wav').slice(0,-1)])
    assert.throws(()=>helper.parseTree(Buffer.from(bytes)));
let requests=0;
const output=helper.manifest('/private/kazoo-sounds','b'.repeat(40),(cmd,args,opts)=>{
    requests++;assert.equal(cmd,'git');assert.deepEqual(args,['-C','/private/kazoo-sounds','ls-tree','-rz','b'.repeat(40),'--','kazoo-core/en/us/']);
    assert.equal(opts.timeout,15000);return Buffer.from(row('a.wav'));
});
assert.deepEqual(output,{keys:['en-us/a']});assert.equal(requests,1);
for(const ref of ['HEAD','main','--help','0'.repeat(39)])assert.throws(()=>helper.manifest('/private/source',ref));
const real=helper.manifest(process.env.KAZOO_TEST_SOUNDS_REPO || '/usr/local/src/kazoo5-installer/kazoo-sounds','c82a707d9f06cf8160891aa57025ee606806bd0b');
assert.equal(real.keys.length,175);
assert(!real.keys.some(id=>id.includes('acdc-callback-')||id==='en-us/acdc-queue-your-current-position-is'));
for(const id of ['agent-invalid_choice','menu-invalid_entry','cf-enter_number'])assert(real.keys.includes('en-us/'+id));
const installer=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
const section=installer.slice(installer.indexOf('install_kazoo_prompts() ('),installer.indexOf('\nverify_kazoo_prompts()'));
assert(section.includes('official-kazoo-prompt-manifest.cjs'));assert(section.includes('git -C "$KAZOO_BUILD_ROOT/kazoo-sounds" show'));
assert(!section.includes('find "$source_dir"'));assert(!section.includes('install -m 0644 "$source_dir/$file"'));
assert(section.includes('select(.error == "not_found"'));assert(!/DELETE|db_delete|del_doc/.test(section));
console.log('PASS exact pinned175 names, 17 ignored/generated exclusions, three official auxiliary dependencies, tree/parser/ref negatives and immutable-blob import selection; no live writes');
