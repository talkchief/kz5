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
  assert(result.token_ids.length >= 1 && result.token_ids.length <= c.MAX_TOKENS_BY_LOCALE[locale]);
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
    } else if (entry.kind === 'scaled-tail') {
      assert.equal(locale, 'fr-fr'); assert([1000, 1000000].includes(entry.scale));
      assert(entry.value >= 1 && entry.value <= 99); assert(entry.scale < priorScale);
      priorScale = entry.scale; total += (subtotal + entry.value) * entry.scale; subtotal = 0;
    } else if (entry.kind === 'scale') {
      assert(entry.value < priorScale); priorScale = entry.value;
      if (!subtotal) assert(['es-es', 'fr-fr'].includes(locale) && entry.value === 1000);
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
  assert.equal(c.PROMPTS.length, 245); assert.equal(c.plan('en-us').length, 31); assert.equal(c.plan('es-es').length, 53);
  assert.equal(c.plan('fr-fr').length, 161);
  assert.equal(byKey.size, 245); assert(Object.isFrozen(c)); assert(Object.isFrozen(c.PROMPTS));
  assert.deepEqual(c.REQUIRED_LOCALES, ['en-us', 'he-il', 'fr-fr', 'es-es', 'ar-sa']);
  assert.deepEqual(c.IMPLEMENTED_LOCALES, ['en-us', 'es-es', 'fr-fr']);
  assert.deepEqual(c.MAX_TOKENS_BY_LOCALE, {'en-us': 14, 'es-es': 14, 'fr-fr': 8});
  assert(Object.isFrozen(c.MAX_TOKENS_BY_LOCALE));
  for (const entry of c.PROMPTS) {
    assert(Object.isFrozen(entry)); assert.equal(entry.catalog_version, c.VERSION);
    assert.equal(entry.id, c.VERSION + '-' + entry.role); assert(!/[0-9]/.test(entry.transcript));
    assert(['number', 'hundred-multiplier', 'scale', 'conjunction', 'scaled-tail'].includes(entry.kind));
  }
  report('versioned immutable exact31 EN +53 ES +161 FR inventory; all five locales remain required');
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
  for (const locale of ['en-us', 'es-es']) for (let number = 0; number <= 999; number++) {
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
  for (const locale of ['en-us', 'es-es']) {
    for (const million of boundaries) for (const thousand of boundaries) for (const unit of boundaries) {
      entries(million * 1000000 + thousand * 1000 + unit, locale);
    }
    for (let group = 0; group <= 999; group++) {
      entries(group * 1000000 + ((group * 37) % 1000) * 1000 + ((group * 91) % 1000), locale);
    }
    assert.equal(c.tokens(999999999, locale).length, c.MAX_TOKENS);
  }
  report('21296 three-group boundary cross-products +2000 mixed cases; strict14-token bound');
  // Independent literal0..99 table: does not call the catalog's French builder.
  const frWords = [
    'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf',
    'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize', 'dix-sept', 'dix-huit', 'dix-neuf',
    'vingt', 'vingt et un', 'vingt-deux', 'vingt-trois', 'vingt-quatre', 'vingt-cinq', 'vingt-six', 'vingt-sept', 'vingt-huit', 'vingt-neuf',
    'trente', 'trente et un', 'trente-deux', 'trente-trois', 'trente-quatre', 'trente-cinq', 'trente-six', 'trente-sept', 'trente-huit', 'trente-neuf',
    'quarante', 'quarante et un', 'quarante-deux', 'quarante-trois', 'quarante-quatre', 'quarante-cinq', 'quarante-six', 'quarante-sept', 'quarante-huit', 'quarante-neuf',
    'cinquante', 'cinquante et un', 'cinquante-deux', 'cinquante-trois', 'cinquante-quatre', 'cinquante-cinq', 'cinquante-six', 'cinquante-sept', 'cinquante-huit', 'cinquante-neuf',
    'soixante', 'soixante et un', 'soixante-deux', 'soixante-trois', 'soixante-quatre', 'soixante-cinq', 'soixante-six', 'soixante-sept', 'soixante-huit', 'soixante-neuf',
    'soixante-dix', 'soixante et onze', 'soixante-douze', 'soixante-treize', 'soixante-quatorze', 'soixante-quinze', 'soixante-seize', 'soixante-dix-sept', 'soixante-dix-huit', 'soixante-dix-neuf',
    'quatre-vingts', 'quatre-vingt-un', 'quatre-vingt-deux', 'quatre-vingt-trois', 'quatre-vingt-quatre', 'quatre-vingt-cinq', 'quatre-vingt-six', 'quatre-vingt-sept', 'quatre-vingt-huit', 'quatre-vingt-neuf',
    'quatre-vingt-dix', 'quatre-vingt-onze', 'quatre-vingt-douze', 'quatre-vingt-treize', 'quatre-vingt-quatorze', 'quatre-vingt-quinze', 'quatre-vingt-seize', 'quatre-vingt-dix-sept', 'quatre-vingt-dix-huit', 'quatre-vingt-dix-neuf'
  ];
  const frTailSet = [6, 8, 10, 18, 26, 28, 36, 38, 46, 48, 56, 58, 66, 68, 70, 78, 86, 88, 90, 98];
  assert.equal(frWords.length, 100); assert.deepEqual(c.FRENCH_SCALED_TAILS, frTailSet);
  assert(Object.isFrozen(c.FRENCH_SCALED_TAILS));
  const frPlan = c.plan('fr-fr');
  assert.equal(frPlan.filter(entry => entry.role.startsWith('terminal-')).length, 100);
  assert.equal(frPlan.filter(entry => entry.role.startsWith('hundreds-')).length, 9);
  assert.equal(frPlan.filter(entry => entry.role.startsWith('hundred-one-')).length, 9);
  assert.equal(frPlan.filter(entry => entry.kind === 'scaled-tail').length, 40);
  assert.equal(frPlan.filter(entry => entry.kind === 'scale').length, 3);
  for (let number = 0; number < 100; number++) {
    const entry = byKey.get(`fr-fr/${c.VERSION}-terminal-${number}`);
    assert.equal(entry.transcript, frWords[number]);
    assert.equal(c.transcript(number, 'fr-fr'), frWords[number]);
  }
  for (const scale of [1000, 1000000]) for (const number of frTailSet) {
    const entry = byKey.get(`fr-fr/${c.VERSION}-scaled-tail-${scale}-${number}`);
    assert.equal(entry.transcript, frWords[number] + (scale === 1000 ? ' mille' : ' millions'));
    assert.equal(entry.scale, scale); assert.equal(entry.value, number);
  }
  const frGolden = [[0, 'zéro'], [17, 'dix-sept'], [21, 'vingt et un'], [26, 'vingt-six'], [28, 'vingt-huit'],
    [61, 'soixante et un'], [70, 'soixante-dix'], [71, 'soixante et onze'], [72, 'soixante-douze'],
    [79, 'soixante-dix-neuf'], [80, 'quatre-vingts'], [81, 'quatre-vingt-un'], [88, 'quatre-vingt-huit'],
    [90, 'quatre-vingt-dix'], [91, 'quatre-vingt-onze'], [98, 'quatre-vingt-dix-huit'], [99, 'quatre-vingt-dix-neuf'],
    [100, 'cent'], [101, 'cent un'], [108, 'cent huit'], [111, 'cent onze'], [171, 'cent soixante et onze'],
    [180, 'cent quatre-vingts'], [181, 'cent quatre-vingt-un'], [200, 'deux cents'], [201, 'deux cent un'],
    [280, 'deux cent quatre-vingts'], [281, 'deux cent quatre-vingt-un'], [999, 'neuf cent quatre-vingt-dix-neuf'],
    [1000, 'mille'], [1001, 'mille un'], [6000, 'six mille'], [18000, 'dix-huit mille'],
    [26000, 'vingt-six mille'], [70000, 'soixante-dix mille'], [80000, 'quatre-vingt mille'],
    [106000, 'cent six mille'], [200000, 'deux cent mille'], [201000, 'deux cent un mille'],
    [280000, 'deux cent quatre-vingt mille'], [1000000, 'un million'], [6000000, 'six millions'],
    [26000000, 'vingt-six millions'], [80000000, 'quatre-vingts millions'], [200000000, 'deux cents millions'],
    [280000000, 'deux cent quatre-vingts millions'], [1001001, 'un million mille un'],
    [999999999, 'neuf cent quatre-vingt-dix-neuf millions neuf cent quatre-vingt-dix-neuf mille neuf cent quatre-vingt-dix-neuf']];
  for (const [number, text] of frGolden) { entries(number, 'fr-fr'); assert.equal(c.transcript(number, 'fr-fr'), text); }
  report(`${frGolden.length} French transcript goldens +100 literal short forms and exact161-role/context inventory`);
  function frReferenceGroup(number, scale) {
    if (!number) return 'zéro';
    if (number === 1 && scale === 1000) return 'mille';
    const hundreds = Math.floor(number / 100), rest = number % 100, words = [];
    if (hundreds) words.push(hundreds === 1 ? 'cent' : frWords[hundreds] + ' cent' + (!rest && scale !== 1000 ? 's' : ''));
    if (rest) words.push(rest === 80 && scale === 1000 ? 'quatre-vingt' : frWords[rest]);
    if (scale !== 1) words.push(scale === 1000 ? 'mille' : number === 1 ? 'million' : 'millions');
    return words.join(' ');
  }
  const reachableFrench = new Set();
  for (let number = 0; number <= 999; number++) for (const scale of [1, 1000, 1000000]) {
    const result = entries(number * scale, 'fr-fr'); result.forEach(entry => reachableFrench.add(entry.id));
    assert.equal(c.transcript(number * scale, 'fr-fr'), frReferenceGroup(number, scale));
    const rest = number % 100, hundreds = Math.floor(number / 100);
    assert.equal(result.some(entry => entry.kind === 'scaled-tail'), scale !== 1 && frTailSet.includes(rest));
    if (scale !== 1 && frTailSet.includes(rest)) {
      assert.equal(result.at(-1).id, `${c.VERSION}-scaled-tail-${scale}-${rest}`);
      assert.equal(result.filter(entry => entry.kind === 'scale').length, 0, 'embedded scale cannot be appended twice');
    }
    if (hundreds && rest === 1) assert.equal(result[0].role, `hundred-one-${hundreds}`);
    if (scale === 1 && number < 100) assert.equal(result.length, 1, 'whole short form, never digit spelling');
  }
  assert.deepEqual([...reachableFrench].sort(), frPlan.map(entry => entry.id).sort(), 'all161 roles reachable in supported grammar');
  report('3000 exhaustive French group/scale transcripts, contextual-tail selection, whole H01 and reachable catalog proof');
  const frBoundaries = [0, 1, 6, 8, 10, 11, 18, 21, 26, 70, 71, 80, 81, 88, 90, 98, 99, 100, 101, 200, 201, 999];
  for (const million of frBoundaries) for (const thousand of frBoundaries) for (const unit of frBoundaries) {
    const number = million * 1000000 + thousand * 1000 + unit; entries(number, 'fr-fr');
    const text = [[million, 1000000], [thousand, 1000], [unit, 1]].filter(([group]) => group)
      .map(([group, scale]) => frReferenceGroup(group, scale)).join(' ') || 'zéro';
    assert.equal(c.transcript(number, 'fr-fr'), text);
  }
  for (let group = 0; group <= 999; group++) {
    entries(group * 1000000 + ((group * 37) % 1000) * 1000 + ((group * 91) % 1000), 'fr-fr');
  }
  assert.equal(c.tokens(999999999, 'fr-fr').length, 8);
  report('10648 French boundary cross-products +1000 mixed cases; no cross-group plural damage and strict8-token bound');
  for (const number of [-1, 1000000000, 1.5, NaN, Infinity, -Infinity, '1', null, undefined, true, 1n, {}, []]) {
    for (const locale of c.IMPLEMENTED_LOCALES) assert.throws(() => c.compose(number, locale), expectedCode('CARDINAL_NUMBER_OUT_OF_RANGE'));
  }
  for (const locale of ['ar-sa', 'he-il']) {
    assert.throws(() => c.compose(1, locale), expectedCode('CARDINAL_LANGUAGE_NOT_IMPLEMENTED'));
    assert.throws(() => c.plan(locale), expectedCode('CARDINAL_LANGUAGE_NOT_IMPLEMENTED'));
  }
  for (const locale of [undefined, null, 'en', 'EN-US', 'en_us', 'es', 'de-de', {}, ['en-us']]) {
    assert.throws(() => c.compose(1, locale), expectedCode('CARDINAL_LANGUAGE_UNSUPPORTED'));
  }
  const copy = c.plan(); copy[0].transcript = 'not retained'; copy.pop(); assert.equal(c.plan().length, 245);
  assert.equal(c.transcript(0, 'en-us'), 'zero');
  assert.throws(() => c.tokens(1, 'en-us').push('unknown'), TypeError);
  report('invalid ranges/locales fail closed; no aliases/defaults or caller mutation');
  const isolated = {module: {exports: {}}};
  vm.runInNewContext(fs.readFileSync(sourcePath, 'utf8'), isolated, {timeout: 1000, filename: sourcePath});
  assert.equal(isolated.module.exports.transcript(999999999, 'es-es'), c.transcript(999999999, 'es-es'));
  assert.equal(isolated.module.exports.transcript(999999999, 'fr-fr'), c.transcript(999999999, 'fr-fr'));
  assert.equal(isolated.module.exports.plan().length, 245);
  report('entire module imports/composes in VM without require/process/files/network/provider globals');
} finally {
  const after = Object.fromEntries(pinned.map(file => [file, hash(file)]));
  assert.deepEqual(after, before, 'source pins stable, including on failure');
  console.log(JSON.stringify({schema_version: 1, stage: groups.length === 9 ? 'complete' : 'incomplete',
    passed_groups: groups, compositions_checked: compositions, sources_sha256: after,
    artifact_generation: false, native_acceptance: false, full_five_locale_ready: false}));
}
