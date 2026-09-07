#!/usr/bin/env node
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {derive,target,registrationAbsent}=require('./test-fixtures/callback-internal-scenarios.cjs');
for(const kind of ['returned','unanswered']) {
    const source=fs.readFileSync(path.join(__dirname,'sip-tests/callback-'+kind+'.xml'),'utf8');
    const output=derive(source,kind);
    assert.equal(output.replace('acceptance1001@','\\+12025550101@').replace('127\\.0\\.0\\.20','127\\.0\\.0\\.30')
        .replace('\n      <ereg regexp=".*" search_in="hdr" header="Via:" occurrence="2" check_it="true" assign_to="invite_upstream_via"/>','').replaceAll('\n      Via: [$invite_upstream_via]',''),source);
    assert.throws(()=>derive(output,kind));
    assert.throws(()=>derive(source+source,kind));
}
assert.equal(target('internal'),'acceptance1001');assert.equal(target(),'\\+12025550101');
assert.throws(()=>target('auto'));
assert(registrationAbsent({status:0,stdout:'error: 500 - AOR not found in location table\n',stderr:''}));
for(const r of [{status:null,stdout:'',stderr:''},{status:1,stdout:'error: 500 - AOR not found in location table',stderr:''},
    {status:0,stdout:'error: 500 - RPC method not found',stderr:''},{status:0,stdout:'',stderr:''},
    {status:0,stdout:'Address: sip:acceptance1001@127.0.0.30:16060',stderr:''},
    {status:0,stdout:'error: 500 - AOR not found in location table',stderr:'transport error'}]) assert(!registrationAbsent(r));
console.log('PASS internal-only scenario derivation, strict mode and absent-registration semantic checks; no I/O beyond sources');
