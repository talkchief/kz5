#!/usr/bin/env node
'use strict';
// Installer adapter for checked-in audio only. No provider key or synthesis.
const fs = require('node:fs');
const path = require('node:path');
const {openPlan} = require('./import-acdc-gemini-cardinals.cjs');
const {couchClient} = require('./import-acdc-language-packs.cjs');
const APPROVAL = 'd5cd6e9713c30745ac06220c76a5996277b4766f6e1bfcc0620887c058e1e71e';

function checkedHeader(filename) {
  const fd = fs.openSync(filename, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  try {
    const stat = fs.fstatSync(fd);
    if (!stat.isFile() || stat.nlink !== 1 || (stat.mode & 0o022) || stat.size > 65536) {
      throw new Error('invalid checked-in cardinal map');
    }
    return fs.readFileSync(fd, 'utf8');
  } finally { fs.closeSync(fd); }
}

async function install(mode, plan, client, header) {
  if (!['--plan', '--import', '--verify-only'].includes(mode)) throw new Error('invalid mode');
  const expected = plan.renderMap();
  if (header() !== expected) throw new Error('cardinal source map mismatch');
  if (mode === '--plan') return {...plan.summary(), mode: 'PLAN_ONLY_NO_DATABASE_ACCESS'};
  if (mode === '--import') await plan.install(client, true);
  // A separate complete fresh byte readback is required after any writes.
  const receipt = await plan.install(client, false);
  if (header() !== expected) throw new Error('cardinal source map changed');
  if (receipt.mode !== 'VERIFY_ONLY' || receipt.count !== 31 || receipt.verified !== 31 ||
      receipt.created !== 0 || receipt.intro_installed_verified !== true ||
      receipt.map_sha256 !== plan.summary().map_sha256) throw new Error('invalid cardinal receipt');
  return receipt;
}

async function main(args) {
  if (args.length !== 1 || !['--plan', '--import', '--verify-only'].includes(args[0])) {
    throw new Error('one explicit mode is required');
  }
  const plan = openPlan({locale: 'en-us',
    cardinalDirectory: path.join(__dirname, 'assets/acdc-gemini-cardinals-20260907'),
    introFile: path.join(__dirname, 'assets/acdc-gemini-fixed-20260905/en-us/acdc-queue-your-current-position-is.telephony-8000.wav'),
    approvalSha256: APPROVAL});
  const client = args[0] === '--plan' ? null : couchClient(process.env);
  const header = () => checkedHeader(path.join(__dirname, '../applications/acdc/src/acdc_cardinal_map.hrl'));
  const receipt = await install(args[0], plan, client, header);
  process.stdout.write(JSON.stringify(receipt, null, 2) + '\n');
}
module.exports = {install, main};
if (require.main === module) main(process.argv.slice(2)).catch(() => {
  console.error('Checked-in cardinal installation failed safely; no runtime readiness claim.');
  process.exitCode = 1;
});
