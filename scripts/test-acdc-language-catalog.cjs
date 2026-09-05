#!/usr/bin/env node
'use strict';
const assert=require('node:assert/strict');
const {catalog,locales}=require('./acdc-language-catalog.cjs');
const he=require('./acdc-hebrew-phonemes.cjs');
const {options,wave}=require('./generate-acdc-language-prompts.cjs');
const fixed=catalog('en-us').prompts.filter(p=>p.kind==='fixed').map(p=>p.id);
assert.equal(fixed.length,29);
for(const locale of locales) {
  const pack=catalog(locale),ids=new Set(pack.prompts.map(p=>p.id));
  assert.equal(ids.size,pack.prompts.length);
  assert.deepEqual(pack.prompts.filter(p=>p.kind==='fixed').map(p=>p.id),fixed);
  for(const p of pack.prompts) {
    assert(/^[a-z0-9_-]+$/.test(p.id)&&p.text.length>0&&!p.text.includes('{key}'));
    if(locale==='he-il')assert(/^\[\[[a-zA-Z0-9 ',?.]+\]\]$/.test(p.synthesis_text),'Hebrew must bypass broken Unicode/numeric dictionary');
  }
  if(['ar-sa','he-il'].includes(locale)) {
    assert.equal(pack.prompts.filter(p=>p.kind==='number').length,2998);
    assert(ids.has('acdc-number-and'));
    for(const n of [...Array.from({length:10000},(_,i)=>i),999999999]) {
      const groups=n===0?[0]:[Math.floor(n/1000000)*1000000,Math.floor((n%1000000)/1000)*1000,n%1000].filter(Boolean);
      assert.equal(groups.reduce((a,b)=>a+b,0),n);
      groups.forEach(v=>assert(ids.has('acdc-number-'+v),'Missing exact numeric chunk '+v));
    }
  } else assert.equal(pack.prompts.length,29);
}
assert.throws(()=>catalog('he'));assert.throws(()=>catalog('fa-ir'));
assert.equal(he.number(80),"Smon'im");assert.equal(he.number(30),"SloS'im");
assert.notEqual(he.number(80),he.number(30));
assert.equal(he.number(4),"aRba?'a");assert.equal(he.number(100),"me?'a");
assert.equal(he.number(121),"me?'a esR'im veeX'ad");
assert.equal(he.number(101),"me?'a veeX'ad");
assert(he.prompt('acdc-queue-the_estimated_wait_time_is').includes("meSo'aR"));
assert.equal(he.number(1000),"'elef");assert.equal(he.number(2000),"alp'ajim");
assert.equal(he.number(1000000),"milj'on");assert.equal(he.number(2000000),"Snei milj'on");
for(const n of [-1,1001,1000000000,NaN])assert.throws(()=>he.number(n));
assert.throws(()=>options(['--locale','he','--dry-run']));
for(const dir of ['/','/etc/kazoo','/var/www/html/monster-ui','/usr/share/kazoo-freeswitch'])
  assert.throws(()=>options(['--output-dir',dir,'--verify-only']));
assert.throws(()=>options(['--output-dir','/tmp/acdc/preview']));
const b=Buffer.alloc(44+16000);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);
b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(8000,24);
b.writeUInt32LE(16000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(16000,40);
for(let i=0;i<8000;i++)b.writeInt16LE(Math.round(5000*Math.sin(2*Math.PI*440*i/8000)),44+i*2);
assert.equal(wave(b).duration_seconds,1);
assert.throws(()=>wave(b.subarray(0,b.length-2)));
const silent=Buffer.from(b);silent.fill(0,44);assert.throws(()=>wave(silent));
const stereo=Buffer.from(b);stereo.writeUInt16LE(2,22);assert.throws(()=>wave(stereo));
const clipped=Buffer.from(b);clipped.writeInt16LE(32767,44);assert.throws(()=>wave(clipped));
console.log('PASS5locale catalog,20k numeric coverage, Hebrew80/30 anddual forms, closed generation paths and WAV failure gates; native listening not asserted');
