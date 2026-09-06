#!/usr/bin/env node
'use strict';
// Actual release WAVs; fake CouchDB only. Provider access is forbidden.
const assert=require('node:assert/strict'),path=require('node:path'),crypto=require('node:crypto');
const https=require('node:https');
https.request=()=>{throw Error('Provider/network access is forbidden in the offline release test');};
const samples=require('./generate-acdc-gemini-samples.cjs');
samples.readProtectedKey=()=>{throw Error('Provider credentials are forbidden in the offline release test');};
const importer=require('./import-acdc-gemini-voices.cjs');
const {validateReceipt}=require('./validate-acdc-gemini-receipt.cjs');
const mappings=require('./refresh-acdc-gemini-mappings.cjs');
const fixed=path.join(__dirname,'assets/acdc-gemini-fixed-20260905');
const completion=path.join(__dirname,'assets/acdc-gemini-completion-20260905');
const supplemental=path.join(__dirname,'assets/acdc-gemini-supplemental-20260906');
const revision='1-'+'b'.repeat(32),clone=x=>JSON.parse(JSON.stringify(x));
async function main() {
  const old=importer.loadPlan(fixed,completion,samples.LOCALES);
  const plan=importer.loadPlan(fixed,completion,samples.LOCALES,supplemental);
  assert.equal(old.length,165);assert.equal(plan.length,210);
  for(const prior of old) {
    const now=plan.find(p=>p.id===prior.id);assert(now);
    assert.equal(now.sha256,prior.sha256);assert.deepEqual(now.bytes,prior.bytes);
  }
  for(const locale of samples.LOCALES) {
    const group=plan.filter(p=>p.locale===locale);assert.equal(group.length,42);
    for(const suffix of ['unavailable','invalid-entry','enter-number'])
      assert(group.some(p=>p.canonical_id==='acdc-callback-'+suffix));
    for(let n=0;n<10;n++)assert(group.some(p=>p.canonical_id==='acdc-number-'+n));
  }
  const docs=new Map(),legacy={customer_recording:true};docs.set('en-us/agent-invalid_choice',legacy);
  let writes=0;
  const client=async(method,resource,body)=>{
    if(method==='POST') {
      assert.equal(resource,'_all_docs?include_docs=true&attachments=true');assert(body.keys.length<=10);
      return {status:200,body:{rows:body.keys.map(key=>docs.has(key)?{key,id:key,doc:clone(docs.get(key))}:{key,error:'not_found'})}};
    }
    assert.equal(method,'PUT');assert.equal(resource,encodeURIComponent(body._id));
    assert.equal(body._rev,undefined);assert(!docs.has(body._id));
    const doc=clone(body);doc._rev=revision;
    for(const attachment of Object.values(doc._attachments))
      attachment.digest='md5-'+crypto.createHash('md5').update(Buffer.from(attachment.data,'base64')).digest('base64');
    docs.set(doc._id,doc);writes++;return {status:201,body:{ok:true,id:doc._id,rev:revision}};
  };
  const installed=await importer.install(plan,client,true);
  assert.equal(writes,210);assert.equal(validateReceipt(installed,plan),true);
  const checked=await importer.install(plan,client,false);
  assert.equal(writes,210);assert.equal(checked.created,0);assert.equal(checked.preserved,210);
  assert.equal(validateReceipt(checked,plan),true);assert.equal(docs.get('en-us/agent-invalid_choice'),legacy);
  assert.throws(()=>validateReceipt(checked,old));
  assert.throws(()=>validateReceipt({...checked,verified:165},plan));
  assert.throws(()=>validateReceipt({...checked,runtime_ready:true},plan));
  assert.equal(mappings.expectedDocuments(plan,checked,importer,validateReceipt).length,210);
  assert.equal(mappings.validateResult('{ok,{ok,{gemini_mapping_verified,check,210,420,0,no_database_writes}}}','check',210),0);
  assert.equal(mappings.validateResult('{ok,{ok,{gemini_mapping_verified,activate,210,420,420,no_database_writes}}}','activate',210),420);
  assert.throws(()=>mappings.validateResult('{ok,{ok,{gemini_mapping_verified,check,165,330,0,no_database_writes}}}','check',210));
  assert.throws(()=>mappings.validateResult('{ok,{ok,{gemini_mapping_verified,check,210,420,1,no_database_writes}}}','check',210));
  console.log('PASS210 actual release assets,42 per locale,165 unchanged originals, create-only/idempotent import, exact receipt and mapping counts; no provider/credentials/live database');
}
main().catch(e=>{console.error(e.stack);process.exitCode=1;});
