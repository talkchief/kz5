#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const {inspectInstalled}=require('./verify-monster-build-dependencies.cjs');
// These fixtures test placement and policy, not the third-party semver parser.
// The real pinned comparator is exercised by the full installed-tree gate.
const comparator={validRange:v=>/^\^?\d+\.\d+\.\d+$/.test(v),satisfies:(v,r)=>{
    const actual=v.split('.').map(Number),expected=r.replace(/^\^/,'').split('.').map(Number);
    return r[0]==='^'?actual[0]===expected[0]&&(actual[1]>expected[1]||actual[1]===expected[1]&&actual[2]>=expected[2]):v===r;
}};
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'monster-dependency-fixtures-'));let count=0;
function put(root,name,data){const target=path.join(root,name,'package.json');fs.mkdirSync(path.dirname(target),{recursive:true,mode:0o700});fs.writeFileSync(target,JSON.stringify(data),{mode:0o600});}
function fixture(name,deps){const root=path.join(temp,name);put(root,'',{name:'fixture',version:'1.0.0',overrides:{'glob-parent':'5.1.2',json5:'1.0.2'},devDependencies:deps});return root;}
function test(name,fn){fn();count++;console.log('PASS '+name);}
try{
    test('misplaced gulp yargs cannot fall back to incompatible root yargs',()=>{
        const root=fixture('misplaced',{gulp:'^4.0.0',yargs:'^17.0.0'});
        put(root,'node_modules/gulp',{name:'gulp',version:'4.0.2',dependencies:{'gulp-cli':'^2.2.0'}});
        put(root,'node_modules/gulp/node_modules/gulp-cli',{name:'gulp-cli',version:'2.3.0',dependencies:{yargs:'^7.1.0'}});
        put(root,'node_modules/yargs',{name:'yargs',version:'17.7.2'});
        const r=inspectInstalled(root,comparator);assert.equal(r.error_count,1);assert.equal(r.errors[0].name,'yargs');
        put(root,'node_modules/gulp/node_modules/yargs',{name:'yargs',version:'7.1.2'});
        assert.equal(inspectInstalled(root,comparator).status,'passed');
    });
    test('real forced-package is-glob range is not waived by its parent override',()=>{
        const root=fixture('stale-range',{'glob-parent':'^3.1.0'});
        put(root,'node_modules/glob-parent',{name:'glob-parent',version:'5.1.2',dependencies:{'is-glob':'^4.0.1'}});
        put(root,'node_modules/glob-parent/node_modules/is-glob',{name:'is-glob',version:'3.1.0'});
        const bad=inspectInstalled(root,comparator);assert.equal(bad.error_count,1);assert.equal(bad.errors[0].name,'is-glob');
        put(root,'node_modules/glob-parent/node_modules/is-glob',{name:'is-glob',version:'4.0.3'});
        const good=inspectInstalled(root,comparator);assert.equal(good.status,'passed');assert.equal(good.explicit_overrides.length,1);
    });
    test('missing required dependency fails but absent optional dependency is explicit',()=>{
        const root=fixture('missing',{app:'^1.0.0'});put(root,'node_modules/app',{name:'app',version:'1.0.0',dependencies:{needed:'^1.0.0'},optionalDependencies:{optional:'^1.0.0'}});
        const r=inspectInstalled(root,comparator);assert.equal(r.error_count,1);assert.equal(r.errors[0].name,'needed');assert.equal(r.errors[0].kind,'missing_required');
    });
    test('only reviewed exact json5/glob-parent overrides can alter declared ranges',()=>{
        const root=fixture('overrides',{json5:'^2.0.0'});put(root,'node_modules/json5',{name:'json5',version:'1.0.2'});
        assert.equal(inspectInstalled(root,comparator).status,'passed');
        put(root,'node_modules/json5',{name:'json5',version:'2.0.0'});assert.equal(inspectInstalled(root,comparator).status,'failed');
        const pkg=JSON.parse(fs.readFileSync(path.join(root,'package.json')));pkg.overrides.yargs='17.7.2';put(root,'',pkg);assert.throws(()=>inspectInstalled(root,comparator),/reviewed exact overrides/);
        delete pkg.overrides.yargs;pkg.overrides.json5='2.0.0';put(root,'',pkg);assert.throws(()=>inspectInstalled(root,comparator),/reviewed exact overrides/);
    });
    test('linked or external package source is rejected without loading package code',()=>{
        const root=fixture('linked',{app:'^1.0.0'}),external=fixture('external',{});fs.mkdirSync(path.join(root,'node_modules'),{mode:0o700});fs.symlinkSync(external,path.join(root,'node_modules/app'));
        assert.throws(()=>inspectInstalled(root,comparator),/Linked package manifest/);
    });
    console.log('PASS '+count+' installed dependency fixture groups');
}finally{fs.rmSync(temp,{recursive:true,force:true});}
