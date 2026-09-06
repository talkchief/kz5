#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const {pinnedRef,capture,bundledRuntimeFiles}=require('./gemini-runtime-inputs.cjs');
const directory=fs.mkdtempSync(path.join(os.tmpdir(),'gemini-runtime-inputs-'));
try {
  const installer=path.join(directory,'installer'),patch=path.join(directory,'patch'),source=path.join(directory,'test.erl');
  const pin='a'.repeat(40),installerText='ACDC_REF=${ACDC_REF:-'+pin+'}\nUNRELATED=value\n';
  fs.writeFileSync(installer,installerText);fs.writeFileSync(patch,'patch-v1');fs.writeFileSync(source,'test-v1');
  const inputs={installer,patch,mapText:'verified165-map-v1',files:[['test',source]]};
  const initial=capture(inputs);
  assert.equal(pinnedRef(installerText),pin);
  fs.writeFileSync(installer,installerText.replace('value','another-value'));
  assert.equal(capture(inputs),initial,'Unrelated installer edits must not invalidate the actual input receipt');
  fs.writeFileSync(installer,installerText.replace(pin,'b'.repeat(40)));
  assert.notEqual(capture(inputs),initial,'Changing the pinned source must invalidate the receipt');
  fs.writeFileSync(installer,installerText);fs.writeFileSync(patch,'patch-v2');
  assert.notEqual(capture(inputs),initial,'Changing aggregate source must invalidate the receipt');
  fs.writeFileSync(patch,'patch-v1');
  assert.notEqual(capture({...inputs,mapText:'verified165-map-v2'}),initial,'Changing verified asset identity must invalidate the receipt');
  fs.writeFileSync(source,'test-v2');
  assert.notEqual(capture(inputs),initial,'Changing a compiled test input must invalidate the receipt');
  assert.throws(()=>pinnedRef(installerText+installerText),/one literal/);
  assert.throws(()=>pinnedRef('ACDC_REF=$(untrusted)\n'),/one literal/);
  assert.throws(()=>capture({...inputs,files:[['missing',path.join(directory,'absent')]]}),/ENOENT/);
  for(const name of ['src','include','priv','test']) {
    const sub=path.join(directory,'applications/acdc',name);fs.mkdirSync(sub,{recursive:true});
    fs.writeFileSync(path.join(sub,'fixture'),name+'-v1');
  }
  const runtimeInputs={...inputs,files:bundledRuntimeFiles(directory).map(p=>[p,path.join(directory,p)])};
  assert.equal(runtimeInputs.files.length,3);
  const runtimeBefore=capture(runtimeInputs);
  fs.writeFileSync(path.join(directory,'applications/acdc/test/fixture'),'unrelated-test-edit');
  assert.equal(capture(runtimeInputs),runtimeBefore,'Uncompiled bundled tests must not invalidate runtime replay');
  fs.writeFileSync(path.join(directory,'applications/acdc/src/fixture'),'runtime-edit');
  assert.notEqual(capture(runtimeInputs),runtimeBefore,'Runtime source edits must invalidate the receipt');
  fs.symlinkSync(source,path.join(directory,'applications/acdc/src/symlink'));
  assert.throws(()=>bundledRuntimeFiles(directory),/Symlinked/);
  console.log('PASS freshness: unrelated installer changes preserved; pin, patch, verified map and test changes rejected; malformed/missing inputs fail closed');
  console.log('PASS runtime scope: bundled test edits excluded; runtime edits and symlinks rejected');
} finally {
  // Only the exact private directory created above is removed.
  fs.rmSync(directory,{recursive:true});
}
