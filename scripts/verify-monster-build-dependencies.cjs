#!/usr/bin/env node
'use strict';
// Required runtime/development dependency edges, not a security/peer audit.
const fs=require('node:fs'),path=require('node:path'),Module=require('node:module');
const assert=require('node:assert/strict');
const EXPECTED_OVERRIDES={'glob-parent':'5.1.2',json5:'1.0.2'};
function manifest(directory){
    const file=path.join(directory,'package.json'),st=fs.lstatSync(file);
    assert(st.isFile()&&st.nlink===1&&st.size<=1024*1024,'Invalid package manifest');
    assert.equal(fs.realpathSync(file),file,'Linked package manifest is not supported');
    return JSON.parse(fs.readFileSync(file,'utf8'));
}
function inspectInstalled(source,semver){
    source=path.resolve(source);assert.equal(fs.realpathSync(source),source,'Linked source is not supported');
    const root=manifest(source),pending=[source],seen=new Set(),errors=[],overridden=[];
    assert.deepEqual(root.overrides,EXPECTED_OVERRIDES,'Only the two reviewed exact overrides are allowed');
    function locate(from,name){
        assert(/^(?:@[a-z0-9._~-]+\/)?[a-z0-9._~-]+$/i.test(name),'Invalid dependency name');
        for(const directory of Module._nodeModulePaths(from)){
            if(!directory.startsWith(source+path.sep))continue;
            const candidate=path.join(directory,name);
            if(fs.existsSync(path.join(candidate,'package.json')))return candidate;
        }
        return null;
    }
    while(pending.length){
        const from=pending.shift();if(seen.has(from))continue;seen.add(from);
        assert(seen.size<=5000,'Dependency traversal limit exceeded');
        const pkg=manifest(from),deps={...pkg.dependencies,...(from===source?pkg.devDependencies:{}),...pkg.optionalDependencies};
        for(const [name,declared]of Object.entries(deps)){
            const optional=Object.prototype.hasOwnProperty.call(pkg.optionalDependencies||{},name),to=locate(from,name);
            if(!to){if(!optional)errors.push({from:path.relative(source,from)||'.',name,kind:'missing_required'});continue;}
            const target=manifest(to),expected=Object.prototype.hasOwnProperty.call(EXPECTED_OVERRIDES,name)?EXPECTED_OVERRIDES[name]:declared;
            const safeRange=typeof declared==='string'&&/^[0-9a-z.^~<>=|*+ -]{1,160}$/i.test(declared);
            const item={from:path.relative(source,from)||'.',name,declared:safeRange?declared:'unsupported_range',expected:expected!==declared?expected:(safeRange?declared:'unsupported_range'),actual:target.version,to:path.relative(source,to)};
            if(expected!==declared)overridden.push(item);
            if(typeof expected!=='string'||!semver.validRange(expected)||!semver.satisfies(target.version,expected))errors.push({...item,kind:'unsatisfied_required_range'});
            pending.push(to);
        }
    }
    return {status:errors.length?'failed':'passed',scope:'required dependency/devDependency/available-optional edges; peer compatibility and security are separate',nodes:seen.size,error_count:errors.length,errors:errors.slice(0,200),errors_complete:errors.length<=200,explicit_overrides:overridden};
}
function verify(source){
    source=path.resolve(source);manifest(path.join(source,'node_modules/semver'));
    return inspectInstalled(source,require(path.join(source,'node_modules/semver')));
}
if(require.main===module){
    try{assert.equal(process.argv.length,3,'Provide exactly one private source directory');const result=verify(process.argv[2]);console.log(JSON.stringify(result,null,2));process.exitCode=result.status==='passed'?0:1;}
    catch(error){console.error('FAIL installed Monster dependency verification: '+(error.code||error.name));process.exitCode=1;}
}
module.exports={inspectInstalled,verify};
