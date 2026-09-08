'use strict';
// Actual-source regression: no live server, credentials or browser required.
const assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const vm = require('node:vm'), cp = require('node:child_process');
const input = process.argv[2];
assert(input, 'Supply pinned Monster UI src/js/lib/monster.ui.js');
const before = fs.readFileSync(input, 'utf8');
const patch = path.join(__dirname, 'patches/monster-ui-dialog-resize-lifecycle.patch');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'monster-dialog-lifecycle.'));
const target = path.join(scratch, 'src/js/lib/monster.ui.js');
function resize(source, alive) {
    const match = source.match(/var setDialogSizes = (function\(\) \{[\s\S]*?)\n\t\t\tvar windowResizeHandler/);
    assert(match, 'Actual resize implementation not found');
    let options = 0, writes = 0;
    const dialog = {height:()=>100,width:()=>100,offset:()=>({top:24}),css:()=>{writes++;}};
    const body = {data:key=>key === 'ui-dialog' && alive ? {} : undefined,
        css:()=>{writes++;},height:()=>80,dialog:()=>{assert(alive,'destroyed dialog accessed');options++;}};
    const context = {getFullDialog:()=>dialog,$window:{height:()=>800,width:()=>1200},
        $dialogBody:body,$scrollableContainer:body,dialogPosition:['center',24],
        dialogLastWidth:0,windowLastWidth:0};
    vm.runInNewContext('(' + match[1].trim().replace(/;$/, '') + ')()', context);
    return {options,writes};
}
function close(source) {
    const block = source.split('var strictOptions = {')[1].split('//Default options')[0];
    assert(block, 'Actual close implementation not found');
    const actions=[];
    const body={find:()=>[],removeClass:()=>actions.push('body-cleaned')};
    const resizeHandler=()=>{};resizeHandler.cancel=()=>actions.push('cancel');
    const options=vm.runInNewContext('({' + block.trim().replace(/;$/, '' ) + ')', {
        getDialogAppendTo:()=>({}),isPersistent:false,dialogPosition:['center',24],
        $body:body,_:{some:()=>false,isFunction:value=>typeof value==='function'},
        $window:{off:()=>actions.push('unbind')},windowResizeHandler:resizeHandler,
        $:()=>({remove:()=>actions.push('popover-removed')}),
        $dialogBody:{dialog:()=>actions.push('destroy'),remove:()=>actions.push('remove')},
        onClose:()=>actions.push('callback')
    });
    options.close();return actions;
}
try {
    fs.mkdirSync(path.dirname(target), {recursive:true});
    fs.writeFileSync(target, before);
    assert.throws(()=>resize(before,false), /destroyed dialog accessed/);
    assert(!close(before).includes('cancel'));
    cp.execFileSync('git',['apply','--check',patch],{cwd:scratch});
    cp.execFileSync('git',['apply',patch],{cwd:scratch});
    cp.execFileSync('git',['apply','--reverse','--check',patch],{cwd:scratch});
    const after=fs.readFileSync(target,'utf8');
    assert.deepEqual(resize(after,false),{options:0,writes:0});
    assert.deepEqual(resize(after,true),{options:1,writes:3});
    const actions=close(after);
    assert(actions.indexOf('cancel') < actions.indexOf('destroy'));
    assert(actions.indexOf('unbind') < actions.indexOf('cancel'));
    assert(actions.includes('callback'));
    const installer=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
    assert(installer.includes('monster-ui-dialog-resize-lifecycle.patch:patches/monster-ui-dialog-resize-lifecycle.patch'));
    assert(installer.includes('apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-dialog-resize-lifecycle.patch"'));
    console.log('PASS before/after resize, active dialog layout, close cancellation order, callback preservation, patch replay and installer fingerprint');
} finally {
    fs.rmSync(scratch,{recursive:true,force:true});
}
