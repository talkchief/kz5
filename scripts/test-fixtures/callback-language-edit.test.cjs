'use strict';
const assert=require('node:assert/strict');
const {patchBody,deadlinePatchBody,restoredGuard,installedMediaHeaders}=require('./callback-language-edit.cjs');
assert.equal(installedMediaHeaders('fixture','synthetic').accept,'application/json');
assert.throws(()=>installedMediaHeaders('bad:user','synthetic'));
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
const timed={...editor,queue:{...editor.queue,callback:{confirmation_timeout:15,retry_delay:15}}};
const timedOriginal=copy(timed),short=deadlinePatchBody(timed,3,timed.revisions.queue);
assert.deepEqual(short.queue,{callback:{confirmation_timeout:3}});
assert.equal(short.roster,null);assert.equal(short.route,null);assert.deepEqual(short.revisions,timed.revisions);
assert.deepEqual(timed,timedOriginal);
const edited={...timed,queue:{...timed.queue,callback:{...timed.queue.callback,confirmation_timeout:3}}};
assert.deepEqual(deadlinePatchBody(edited,15,edited.revisions.queue).queue,{callback:{confirmation_timeout:15}});
assert.throws(()=>deadlinePatchBody(timed,3,'stale'));
assert.throws(()=>deadlinePatchBody(timed,15,timed.revisions.queue));
assert.throws(()=>deadlinePatchBody(edited,3,edited.revisions.queue));
assert.throws(()=>deadlinePatchBody(timed,4,timed.revisions.queue));
assert.throws(()=>deadlinePatchBody({...timed,queue:{...timed.queue,name:'Customer Queue'}},3,timed.revisions.queue));
console.log('PASS callback language edit: narrow revision-bound patch, immutable inputs, conditional restore and uncertain-outcome refusal');
console.log('PASS callback deadline edit: only exact fixture timeout15->3->15, revision and prior-value guards');
