#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const {install} = require('./install-acdc-cardinal-pack.cjs');

async function main() {
  let calls = [];
  const good = {mode: 'VERIFY_ONLY', count: 31, verified: 31, created: 0,
    intro_installed_verified: true, map_sha256: 'expected-map'};
  const plan = {renderMap: () => 'header', summary: () => ({count: 31, map_sha256: 'expected-map'}),
    install: async (_client, write) => { calls.push(write); return {...good}; }};
  assert.equal((await install('--plan', plan, null, () => 'header')).mode, 'PLAN_ONLY_NO_DATABASE_ACCESS');
  assert.deepEqual(calls, []);
  assert.deepEqual(await install('--import', plan, {}, () => 'header'), good);
  assert.deepEqual(calls, [true, false]);
  calls = [];
  await install('--verify-only', plan, {}, () => 'header');
  assert.deepEqual(calls, [false]);
  calls = [];
  await assert.rejects(install('--import', plan, {}, () => 'wrong'), /map mismatch/);
  assert.deepEqual(calls, []);
  let reads = 0;
  await assert.rejects(install('--verify-only', plan, {}, () => ++reads === 1 ? 'header' : 'drift'), /map changed/);
  await assert.rejects(install('--import', {...plan, install: async () => { throw new Error('ambiguous'); }}, {}, () => 'header'), /ambiguous/);
  for (const bad of [{verified: 30}, {created: 1}, {intro_installed_verified: false},
    {map_sha256: 'different'}, {mode: 'IMPORT'}, {count: 32}]) {
    await assert.rejects(install('--verify-only', {...plan, install: async () => ({...good, ...bad})}, {}, () => 'header'), /invalid cardinal receipt/);
  }
  await assert.rejects(install('--all', plan, {}, () => 'header'), /invalid mode/);
  process.stdout.write('PASS 13 cardinal installer adapter cases; no provider, database, source or service writes\n');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
