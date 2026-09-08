'use strict';
const assert=require('node:assert/strict');
const {patchBody,restoredGuard}=require('./callback-language-edit.cjs');
const editor={queue:{id:'a'.repeat(32),name:'Acceptance Queue 2000',announcements:{language:'en-us',interval:30}},roster:['b'.repeat(32)],revisions:{queue:'1-'+'c'.repeat(32)}};
const copy=v=>JSON.parse(JSON.stringify(v));
const original=copy(editor),body=patchBody(editor,'fr-fr',editor.revisions.queue);
assert.deepEqual(body.queue,{announcements:{language:'fr-fr'}});
assert.equal(body.roster,null);assert.equal(body.route,null);assert.deepEqual(body.revisions,editor.revisions);
assert.match(body.request_id,/^[a-f0-9]{32}$/);assert.deepEqual(editor,original);
assert.throws(()=>patchBody(editor,'ar-sa',editor.revisions.queue));
assert.throws(()=>patchBody(editor,'fr-fr','stale'));
assert.throws(()=>patchBody({...editor,queue:{...editor.queue,name:'Customer Queue'}},'fr-fr',editor.revisions.queue));
const receipt={state:'edited',after:copy(editor)};
restoredGuard(copy(editor),receipt);
for(const changed of [
    {...editor,revisions:{queue:'2-'+'d'.repeat(32)}},
    {...editor,queue:{...editor.queue,name:'Changed'}},
    {...editor,roster:[]}
])assert.throws(()=>restoredGuard(changed,receipt));
assert.throws(()=>restoredGuard(editor,{...receipt,state:'edit_intent'}));
assert.throws(()=>restoredGuard(editor,{...receipt,state:'restore_intent'}));
console.log('PASS callback language edit: narrow revision-bound patch, immutable inputs, conditional restore and uncertain-outcome refusal');
