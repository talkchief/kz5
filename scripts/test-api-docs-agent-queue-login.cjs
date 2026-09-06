#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=process.argv.length===4&&process.argv[2]==='--root'?path.resolve(process.argv[3]):path.resolve(__dirname,'..');
assert(process.argv.length===2||(process.argv.length===4&&process.argv[2]==='--root'),'Usage: node test-api-docs-agent-queue-login.cjs [--root SOURCE_ROOT]');
const Ajv=require(path.join(root,'scripts/api-docs-tooling/node_modules/ajv'));
const Parser=require(path.join(root,'scripts/api-docs-tooling/node_modules/@apidevtools/swagger-parser'));
const {applyAgentQueueLogin}=require('./api-docs-agent-queue-login.cjs');
const route='/accounts/{ACCOUNT_ID}/agents/{USER_ID}/queue_status',spec=JSON.parse(fs.readFileSync(path.join(root,'scripts/assets/api-docs/openapi.json')));
// The generator creates this GET operation afresh before applying its overlay.
// Mirror that boundary even when testing an already-regenerated asset catalog.
spec.paths[route].get.parameters=spec.paths[route].get.parameters.filter(parameter=>
    parameter.in!=='query'||!['runtime_only','action','queue_id'].includes(parameter.name));
const before=JSON.parse(JSON.stringify(spec)),hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const result=applyAgentQueueLogin({spec,root}),ops=spec.paths[route],ajv=new Ajv({strict:false,validateFormats:false});
const compile=schema=>ajv.compile({components:spec.components,...schema}),schema=name=>compile({$ref:'#/components/schemas/'+name});
const id='0'.repeat(32),queue='1'.repeat(32),pending={account_id:id,agent_id:id,queue_id:queue,action:'login',runtime_only:true,state:'pending',confirmed:false,runtime_member:false,runtime_observed:false,agent_status:'unknown'};
const confirmed={...pending,state:'confirmed',confirmed:true,runtime_member:true,runtime_observed:true,agent_status:'paused'};
let groups=0,cases=0;
function group(name,fn){fn();groups++;console.log('PASS '+name);}
function accepts(validate,value){cases++;assert(validate(value),JSON.stringify(validate.errors));}
function rejects(validate,value){cases++;assert.equal(validate(value),false,'Accepted invalid schema fixture');}
async function main(){
    group('preserve unrelated routes, schemas, authorization and bind exact source',()=>{
        for(const [key,value]of Object.entries(before.paths))if(key!==route)assert.deepEqual(spec.paths[key],value);
        for(const [key,value]of Object.entries(before.components.schemas))assert.deepEqual(spec.components.schemas[key],value);
        for(const method of ['get','post']){
            assert.deepEqual(ops[method].security,before.paths[route][method].security);
            assert.equal(ops[method].operationId,before.paths[route][method].operationId);
            assert.equal(ops[method]['x-implementation-status'],'implemented-in-source; not-live-deployed');
            assert.equal(ops[method]['x-runtime-source-sha256'],hash(fs.readFileSync(path.join(root,'applications/acdc/src/cb_acdc_agent_queue.erl'))));
        }
        assert.equal(result.inputs.length,6);
        for(const row of result.inputs)assert.equal(row.sha256,hash(fs.readFileSync(row.file==='scripts/api-docs-agent-queue-login.cjs'?path.join(__dirname,'api-docs-agent-queue-login.cjs'):path.join(root,row.file))));
    });
    group('runtime-only and legacy request modes are disjoint',()=>{
        const validate=compile(ops.post.requestBody.content['application/json'].schema),data={runtime_only:true,action:'login',queue_id:queue};
        accepts(validate,{data});accepts(validate,{data:{action:'login',queue_id:queue}});accepts(validate,{data:{action:'logout',queue_id:queue}});
        for(const value of [{},{data:{}},{data:{...data,runtime_only:false}},{data:{...data,runtime_only:'true'}},{data:{...data,action:'logout'}},{data:{...data,queue_id:''}},{data:{...data,queue_id:'q'.repeat(129)}},{data:{...data,queue_id:1}}])rejects(validate,value);
        for(const key of ['action','queue_id']){const missing={...data};delete missing[key];rejects(validate,{data:missing});}
    });
    group('pending is not queue membership or global readiness',()=>{
        const validate=schema('AgentQueueRuntimeSnapshot');accepts(validate,pending);accepts(validate,{...pending,runtime_observed:true,agent_status:'ready'});
        for(const invalid of [{...pending,confirmed:true},{...pending,runtime_member:true},{...pending,state:'ready'},{...pending,runtime_only:false},{...pending,account_id:'foreign'},[]])rejects(validate,invalid);
        for(const key of Object.keys(pending)){const missing={...pending};delete missing[key];rejects(validate,missing);}
    });
    group('confirmation requires membership and observed proof, not agent availability',()=>{
        const validate=schema('AgentQueueRuntimeSnapshot');accepts(validate,confirmed);accepts(validate,{...confirmed,agent_status:'ringing'});
        for(const change of [{runtime_observed:false},{runtime_member:false},{confirmed:false},{action:'logout'},{state:'ready'}])rejects(validate,{...confirmed,...change});
    });
    group('POST acknowledgement cannot be a runtime observation or confirmation',()=>{
        const validate=compile(ops.post.responses['202'].content['application/json'].schema);accepts(validate,{data:pending});
        rejects(validate,{data:confirmed});rejects(validate,{data:{...pending,runtime_observed:true}});rejects(validate,{data:{...pending,agent_status:'ready'}});
        const read=compile(ops.get.responses['200'].content['application/json'].schema);accepts(read,{data:[queue]});accepts(read,{data:pending});accepts(read,{data:confirmed});
    });
    group('query opt-in, errors, timeout and non-cacheable handler are explicit',()=>{
        const query=ops.get.parameters.filter(p=>p.in==='query');assert.equal(query.length,3);assert.deepEqual(query.map(p=>p.name),['runtime_only','action','queue_id']);
        assert(query.every(p=>p.required!==true));assert.deepEqual(query[0].schema.enum,[true]);assert.deepEqual(query[1].schema.enum,['login']);
        assert.equal(query[2].schema['x-max-utf8-bytes'],128);
        for(const op of [ops.get,ops.post]){
            for(const status of ['400','403','404','503'])assert.equal(op.responses[status].headers['Cache-Control'].schema.enum[0],'no-store');
            for(const status of ['401','409'])assert.deepEqual(op.responses[status],before.paths[route][op===ops.get?'get':'post'].responses[status]);
            assert(op.description.includes('already in'));assert(op.description.includes('No roster/user/queue document is saved'));
        }
        assert(ops.get.description.includes('two seconds'));assert(ops.post.description.includes('Do not automatically repeat a POST'));
        assert(!ops.post.responses['200'].headers);assert.equal(ops.post.responses['202'].headers['Cache-Control'].schema.enum[0],'no-store');
    });
    group('source contract drift fails rather than generating stale claims',()=>{
        const file=path.join(__dirname,'api-docs-agent-queue-login.cjs'),module={exports:{}},fakeFs={...fs,readFileSync:(file,...args)=>{
            const value=fs.readFileSync(file,...args);return String(file).endsWith('/cb_acdc_agent_queue.erl')?Buffer.from(value.toString().replace('Validator, 2000)','Validator, 9999)')):value;
        }};
        vm.runInNewContext(fs.readFileSync(file,'utf8'),{module,exports:module.exports,__filename:file,require:name=>name==='node:fs'?fakeFs:require(name)});
        assert.throws(()=>module.exports.applyAgentQueueLogin({spec:JSON.parse(JSON.stringify(before)),root}),/source contract changed/);
        assert.throws(()=>applyAgentQueueLogin({spec:{paths:{},components:{schemas:{}}},root}),/operations are required/);
    });
    const fragment={openapi:'3.0.3',info:{title:'Source-reviewed queue login contract',version:'1.0.0'},paths:{[route]:ops},components:{securitySchemes:spec.components.securitySchemes,schemas:Object.fromEntries(Object.entries(spec.components.schemas).filter(([name])=>name==='CrossbarError'||name.startsWith('AgentQueue')))}};
    await Parser.validate(JSON.parse(JSON.stringify(fragment)),{resolve:{http:false},dereference:{circular:'ignore'}});groups++;console.log('PASS OpenAPI 3 route/schema validation with HTTP resolution disabled');
    group('main overlay includes the focused source-bound helper',()=>{
        assert(fs.readFileSync(path.join(__dirname,'api-docs-overlays.cjs'),'utf8').includes("inputs.push(...require('./api-docs-agent-queue-login.cjs').applyAgentQueueLogin({spec, root}).inputs)"));
    });
    console.log(JSON.stringify({result:'PASS',groups,schema_cases:cases,inputs:result.inputs,network:false,browser:false,live_writes:false}));
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;});
