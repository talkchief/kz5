#!/usr/bin/env node
'use strict';
// Pure local regression. No provider, credentials, audio, subprocesses or files
// written. The parent resource guard retains stdout (including the receipt).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');
const sourcePath = path.join(__dirname, 'acdc-cardinal-catalog.cjs');
const pinned = [__filename, sourcePath];
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const before = Object.fromEntries(pinned.map(file => [file, hash(file)]));
const c = require(sourcePath), groups = [];
let compositions = 0;
function report(name) { groups.push(name); console.log('PASS ' + name); }
const expectedCode = code => error => error instanceof c.CardinalError && error.code === code;
const byKey = new Map(c.PROMPTS.map(entry => [entry.locale + '/' + entry.id, entry]));
function entries(number, locale) {
  const result = c.compose(number, locale); compositions++;
  assert.equal(result.catalog_version, c.VERSION); assert.equal(result.locale, locale);
  assert.equal(result.number, number); assert(Object.isFrozen(result)); assert(Object.isFrozen(result.token_ids));
  assert(result.token_ids.length >= 1 && result.token_ids.length <= c.MAX_TOKENS);
  const resultEntries = result.token_ids.map(id => {
    const entry = byKey.get(locale + '/' + id); assert(entry, 'every token must have an exact same-locale catalog entry'); return entry;
  });
  // Independent numeric interpretation: multipliers and descending scale
  // boundaries, not the compositor's decimal splitting or language branches.
  let total = 0, subtotal = 0, priorScale = Infinity;
  for (const entry of resultEntries) {
    if (entry.kind === 'number') subtotal += entry.value;
    else if (entry.kind === 'hundred-multiplier') {
      assert(subtotal >= 1 && subtotal <= 9); subtotal *= entry.value;
    } else if (entry.kind === 'scale') {
      assert(entry.value < priorScale); priorScale = entry.value;
      if (!subtotal) assert(locale === 'es-es' && entry.value === 1000);
      total += (subtotal || 1) * entry.value; subtotal = 0;
    } else assert.equal(entry.kind, 'conjunction');
  }
  assert.equal(total + subtotal, number, 'token semantics must preserve the entire integer');
  assert.equal(resultEntries.some(entry => entry.value === 0), number === 0, 'zero cannot leak into nonzero groups');
  for (let i = 0; i < resultEntries.length; i++) {
    const entry = resultEntries[i];
    if (entry.kind === 'conjunction') {
      assert.equal(locale, 'es-es');
      assert(resultEntries[i - 1].value >= 30 && resultEntries[i - 1].value <= 90);
      assert.equal(resultEntries[i - 1].value % 10, 0);
      assert(resultEntries[i + 1].value >= 1 && resultEntries[i + 1].value <= 9);
    }
  }
  return resultEntries;
}
try {
  assert.equal(c.VERSION, 'acdc-cardinal-v1'); assert.equal(c.MAX_NUMBER, 999999999);
  assert.equal(c.PROMPTS.length, 84); assert.equal(c.plan('en-us').length, 31); assert.equal(c.plan('es-es').length, 53);
  assert.equal(byKey.size, 84); assert(Object.isFrozen(c)); assert(Object.isFrozen(c.PROMPTS));
  assert.deepEqual(c.REQUIRED_LOCALES, ['en-us', 'he-il', 'fr-fr', 'es-es', 'ar-sa']);
  assert.deepEqual(c.IMPLEMENTED_LOCALES, ['en-us', 'es-es']);
  for (const entry of c.PROMPTS) {
    assert(Object.isFrozen(entry)); assert.equal(entry.catalog_version, c.VERSION);
    assert.equal(entry.id, c.VERSION + '-' + entry.role); assert(!/[0-9]/.test(entry.transcript));
    assert(['number', 'hundred-multiplier', 'scale', 'conjunction'].includes(entry.kind));
  }
  report('versioned immutable exact31 EN +53 ES inventory; all five locales remain required');
  const golden = {
    'en-us': [[0, 'zero'], [1, 'one'], [19, 'nineteen'], [21, 'twenty one'], [40, 'forty'],
      [100, 'one hundred'], [101, 'one hundred one'], [110, 'one hundred ten'], [121, 'one hundred twenty one'],
      [1000, 'one thousand'], [1001, 'one thousand one'], [101000, 'one hundred one thousand'],
      [1000000, 'one million'], [1001001, 'one million one thousand one'],
      [999999999, 'nine hundred ninety nine million nine hundred ninety nine thousand nine hundred ninety nine']],
    'es-es': [[0, 'cero'], [1, 'uno'], [16, 'dieciséis'], [21, 'veintiuno'], [22, 'veintidós'], [23, 'veintitrés'],
      [26, 'veintiséis'], [29, 'veintinueve'], [31, 'treinta y uno'], [100, 'cien'], [101, 'ciento uno'],
      [121, 'ciento veintiuno'], [131, 'ciento treinta y uno'], [200, 'doscientos'], [500, 'quinientos'],
      [700, 'setecientos'], [900, 'novecientos'], [1000, 'mil'], [1001, 'mil uno'], [11000, 'once mil'],
      [21000, 'veintiún mil'], [31000, 'treinta y un mil'], [100000, 'cien mil'], [101000, 'ciento un mil'],
      [121000, 'ciento veintiún mil'], [131000, 'ciento treinta y un mil'], [1000000, 'un millón'],
      [2000000, 'dos millones'], [21000000, 'veintiún millones'], [101000000, 'ciento un millones'],
      [1001001, 'un millón mil uno'], [121121121, 'ciento veintiún millones ciento veintiún mil ciento veintiuno'],
      [999999999, 'novecientos noventa y nueve millones novecientos noventa y nueve mil novecientos noventa y nueve']]
  };
  for (const [locale, cases] of Object.entries(golden)) for (const [number, text] of cases) {
    entries(number, locale); assert.equal(c.transcript(number, locale), text, `${locale}/${number}`);
  }
  report('48 explicit transcript goldens including apocope, irregular hundreds, zero and maximum');
  for (const locale of c.IMPLEMENTED_LOCALES) for (let number = 0; number <= 999; number++) {
    for (const scale of [1, 1000, 1000000]) {
      const result = entries(number * scale, locale), words = result.map(entry => entry.transcript);
      if (locale === 'es-es' && number) {
        const numeric = result.filter(entry => entry.kind === 'number');
        if (scale !== 1) {
          assert(!words.includes('uno') && !words.includes('veintiuno'));
          if (number % 10 === 1 && number % 100 !== 11 && !(number === 1 && scale === 1000)) {
            assert(['un', 'veintiún'].includes(numeric.at(-1).transcript));
          }
          if (scale === 1000000) assert.equal(result.at(-1).transcript, number === 1 ? 'millón' : 'millones');
        } else assert(!words.includes('un') && !words.includes('veintiún'));
        if (number >= 100 && number < 200) assert.equal(numeric[0].transcript, number === 100 ? 'cien' : 'ciento');
      }
    }
  }
  report('6000 exhaustive0..999 group/context cases with semantic and Spanish morphology checks');
  const boundaries = [0, 1, 2, 10, 11, 19, 20, 21, 29, 30, 31, 99, 100, 101, 110, 121, 199, 200, 500, 700, 900, 999];
  for (const locale of c.IMPLEMENTED_LOCALES) {
    for (const million of boundaries) for (const thousand of boundaries) for (const unit of boundaries) {
      entries(million * 1000000 + thousand * 1000 + unit, locale);
    }
    for (let group = 0; group <= 999; group++) {
      entries(group * 1000000 + ((group * 37) % 1000) * 1000 + ((group * 91) % 1000), locale);
    }
    assert.equal(c.tokens(999999999, locale).length, c.MAX_TOKENS);
  }
  report('21296 three-group boundary cross-products +2000 mixed cases; strict14-token bound');
  for (const number of [-1, 1000000000, 1.5, NaN, Infinity, -Infinity, '1', null, undefined, true, 1n, {}, []]) {
    for (const locale of c.IMPLEMENTED_LOCALES) assert.throws(() => c.compose(number, locale), expectedCode('CARDINAL_NUMBER_OUT_OF_RANGE'));
  }
  for (const locale of ['fr-fr', 'ar-sa', 'he-il']) {
    assert.throws(() => c.compose(1, locale), expectedCode('CARDINAL_LANGUAGE_NOT_IMPLEMENTED'));
    assert.throws(() => c.plan(locale), expectedCode('CARDINAL_LANGUAGE_NOT_IMPLEMENTED'));
  }
  for (const locale of [undefined, null, 'en', 'EN-US', 'en_us', 'es', 'de-de', {}, ['en-us']]) {
    assert.throws(() => c.compose(1, locale), expectedCode('CARDINAL_LANGUAGE_UNSUPPORTED'));
  }
  const copy = c.plan(); copy[0].transcript = 'not retained'; copy.pop(); assert.equal(c.plan().length, 84);
  assert.equal(c.transcript(0, 'en-us'), 'zero');
  assert.throws(() => c.tokens(1, 'en-us').push('unknown'), TypeError);
  report('invalid ranges/locales fail closed; no aliases/defaults or caller mutation');
  const isolated = {module: {exports: {}}};
  vm.runInNewContext(fs.readFileSync(sourcePath, 'utf8'), isolated, {timeout: 1000, filename: sourcePath});
  assert.equal(isolated.module.exports.transcript(999999999, 'es-es'), c.transcript(999999999, 'es-es'));
  assert.equal(isolated.module.exports.plan().length, 84);
  report('entire module imports/composes in VM without require/process/files/network/provider globals');
} finally {
  const after = Object.fromEntries(pinned.map(file => [file, hash(file)]));
  assert.deepEqual(after, before, 'source pins stable, including on failure');
  console.log(JSON.stringify({schema_version: 1, stage: groups.length === 6 ? 'complete' : 'incomplete',
    passed_groups: groups, compositions_checked: compositions, sources_sha256: after,
    artifact_generation: false, native_acceptance: false, full_five_locale_ready: false}));
}
