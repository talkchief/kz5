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
  let total = 0, subtotal = 0, priorScale = Infinity, priorArabicCoefficient = 0;
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
    } else if (entry.kind === 'whole-scale') {
      assert.equal(locale, 'he-il'); assert([1000, 1000000].includes(entry.scale));
      assert(entry.scale < priorScale); priorScale = entry.scale;
      if (subtotal) assert.equal(entry.value, 1, 'only singular scale recording can close a preceding coefficient');
      total += (subtotal || entry.value) * entry.scale; subtotal = 0;
    } else if (entry.kind === 'additive-scale' || entry.kind === 'additive-scale-tail') {
      assert.equal(locale, 'ar-sa'); assert([1000, 1000000].includes(entry.scale));
      assert(entry.scale <= priorScale, 'Arabic explicit scaled sums still descend');
      if (entry.scale === priorScale) {
        assert(priorArabicCoefficient >= 100 && priorArabicCoefficient % 100 === 0);
        assert(entry.value < 100, 'same-scale continuation can only be the remainder after whole hundreds');
      }
      if (entry.kind === 'additive-scale-tail') {
        assert(entry.value >= 20 && entry.value <= 90 && entry.value % 10 === 0);
        assert(subtotal >= 0 && subtotal <= 9, 'decade tail closes only its preceding unit');
      } else assert.equal(subtotal, 0, 'whole scale phrase cannot consume unscaled material');
      total += (subtotal + entry.value) * entry.scale; subtotal = 0;
      priorScale = entry.scale; priorArabicCoefficient = entry.value;
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
  assert.equal(c.PROMPTS.length, 584); assert.equal(c.plan('en-us').length, 31); assert.equal(c.plan('es-es').length, 53);
  assert.equal(c.plan('fr-fr').length, 161);
  assert.equal(c.plan('he-il').length, 131);
  assert.equal(c.plan('ar-sa').length, 208);
  assert.equal(byKey.size, 584); assert(Object.isFrozen(c)); assert(Object.isFrozen(c.PROMPTS));
  assert.deepEqual(c.REQUIRED_LOCALES, ['en-us', 'he-il', 'fr-fr', 'es-es', 'ar-sa']);
  assert.deepEqual(c.IMPLEMENTED_LOCALES, ['en-us', 'es-es', 'fr-fr', 'he-il', 'ar-sa']);
  assert.deepEqual([...c.IMPLEMENTED_LOCALES].sort(), [...c.REQUIRED_LOCALES].sort());
  assert.deepEqual(c.MAX_TOKENS_BY_LOCALE, {'en-us': 14, 'es-es': 14, 'fr-fr': 8, 'he-il': 11, 'ar-sa': 9});
  assert(Object.isFrozen(c.MAX_TOKENS_BY_LOCALE));
  for (const entry of c.PROMPTS) {
    assert(Object.isFrozen(entry)); assert.equal(entry.catalog_version, c.VERSION);
    assert.equal(entry.id, c.VERSION + '-' + entry.role); assert(!/[0-9]/.test(entry.transcript));
    assert(['number', 'hundred-multiplier', 'scale', 'conjunction', 'scaled-tail', 'whole-scale',
      'additive-scale', 'additive-scale-tail'].includes(entry.kind));
  }
  report('versioned immutable exact31 EN +53 ES +161 FR +131 HE +208 AR inventory; all five pure grammars present');
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
  // Separately authored plain consonantal reference, not imported word tables.
  // Stripping niqqud is for assertions only; it is NOT modern full spelling or
  // an authoring transform. Production preserves each vocalized transcript.
  const bare = text => text.replace(/[\u0591-\u05bd\u05bf-\u05c2\u05c4-\u05c5\u05c7]/g, '');
  const heF = ['אפס', 'אחת', 'שתים', 'שלוש', 'ארבע', 'חמש', 'שש', 'שבע', 'שמונה', 'תשע',
    'עשר', 'אחת עשרה', 'שתים עשרה', 'שלוש עשרה', 'ארבע עשרה', 'חמש עשרה', 'שש עשרה',
    'שבע עשרה', 'שמונה עשרה', 'תשע עשרה'];
  const heM = ['אפס', 'אחד', 'שנים', 'שלושה', 'ארבעה', 'חמשה', 'ששה', 'שבעה', 'שמונה', 'תשעה',
    'עשרה', 'אחד עשר', 'שנים עשר', 'שלושה עשר', 'ארבעה עשר', 'חמשה עשר', 'ששה עשר',
    'שבעה עשר', 'שמונה עשר', 'תשעה עשר'];
  const heDecades = ['עשרים', 'שלושים', 'ארבעים', 'חמשים', 'ששים', 'שבעים', 'שמונים', 'תשעים'];
  const heCenturies = ['מאה', 'מאתים', 'שלוש מאות', 'ארבע מאות', 'חמש מאות', 'שש מאות',
    'שבע מאות', 'שמונה מאות', 'תשע מאות'];
  const heK = ['אלף', 'אלפים', 'שלושת אלפים', 'ארבעת אלפים', 'חמשת אלפים', 'ששת אלפים',
    'שבעת אלפים', 'שמונת אלפים', 'תשעת אלפים', 'עשרת אלפים'];
  const hePlan = c.plan('he-il');
  assert.equal(c.HEBREW_CONTEXT, 'abstract-number-label-feminine');
  assert.equal(hePlan.filter(entry => entry.joined).length, 65);
  assert.equal(hePlan.filter(entry => entry.role.startsWith('masculine-')).length, 17);
  assert.equal(hePlan.filter(entry => entry.role.startsWith('feminine-')).length, 19);
  assert.equal(hePlan.filter(entry => entry.kind === 'whole-scale').length, 22);
  for (const entry of hePlan) {
    assert.equal(entry.grammatical_context, c.HEBREW_CONTEXT);
    assert.equal(typeof entry.joined, 'boolean');
    assert.equal(entry.role.startsWith('joined-'), entry.joined);
    assert(/[\u05b0-\u05bc]/.test(entry.transcript), 'exact vocalized authoring text');
    assert(!['and', 'masculine-1', 'masculine-2', 'joined-number-0'].includes(entry.role));
    if (entry.joined) assert(/^(?:וְ|וּ|וַ)/.test(entry.transcript), 'attached full-word ve/u/va, not a generic phoneme clip');
  }
  for (let number = 0; number < 20; number++) assert.equal(bare(c.transcript(number, 'he-il')), heF[number]);
  const heVocalized = [
    [1, 'אַחַת'], [2, 'שְׁתַּיִם'], [8, 'שְׁמוֹנֶה'], [12, 'שְׁתֵּים עֶשְׂרֵה'],
    [21, 'עֶשְׂרִים וְאַחַת'], [22, 'עֶשְׂרִים וּשְׁתַּיִם'], [25, 'עֶשְׂרִים וְחָמֵשׁ'],
    [28, 'עֶשְׂרִים וּשְׁמוֹנֶה'], [29, 'עֶשְׂרִים וְתֵשַׁע'],
    [115, 'מֵאָה וַחֲמֵשׁ עֶשְׂרֵה'], [117, 'מֵאָה וּשְׁבַע עֶשְׂרֵה'],
    [119, 'מֵאָה וּתְשַׁע עֶשְׂרֵה'], [120, 'מֵאָה וְעֶשְׂרִים'],
    [130, 'מֵאָה וּשְׁלוֹשִׁים'], [150, 'מֵאָה וַחֲמִשִּׁים'],
    [10000, 'עֲשֶׂרֶת אֲלָפִים'], [11000, 'אַחַד עָשָׂר אֶלֶף'],
    [12000, 'שְׁנֵים עָשָׂר אֶלֶף'], [22000, 'עֶשְׂרִים וּשְׁנַיִם אֶלֶף'],
    [25000, 'עֶשְׂרִים וַחֲמִשָּׁה אֶלֶף'], [8000, 'שְׁמוֹנַת אֲלָפִים'],
    [8000000, 'שְׁמוֹנָה מִילְיוֹן'], [2000000, 'שְׁנֵי מִילְיוֹן'],
    [1000700, 'מִילְיוֹן וּשְׁבַע מֵאוֹת'], [1010000, 'מִילְיוֹן וַעֲשֶׂרֶת אֲלָפִים']
  ];
  for (const [number, text] of heVocalized) { entries(number, 'he-il'); assert.equal(c.transcript(number, 'he-il'), text); }
  const heGolden = [
    [0, 'אפס'], [101, 'מאה ואחת'], [121, 'מאה עשרים ואחת'], [1000, 'אלף'],
    [1001, 'אלף ואחת'], [1002, 'אלף ושתים'], [1010, 'אלף ועשר'], [1011, 'אלף ואחת עשרה'],
    [1100, 'אלף ומאה'], [1120, 'אלף מאה ועשרים'], [1121, 'אלף מאה עשרים ואחת'],
    [2000, 'אלפים'], [2500, 'אלפים וחמש מאות'], [3000, 'שלושת אלפים'],
    [101000, 'מאה ואחד אלף'], [102000, 'מאה ושנים אלף'], [103000, 'מאה ושלושה אלף'],
    [111000, 'מאה ואחד עשר אלף'], [120000, 'מאה ועשרים אלף'], [121000, 'מאה עשרים ואחד אלף'],
    [200356, 'מאתים אלף שלוש מאות חמשים ושש'], [1000000, 'מיליון'],
    [1001000, 'מיליון ואלף'], [1002000, 'מיליון ואלפים'], [1003000, 'מיליון ושלושת אלפים'],
    [1001001, 'מיליון אלף ואחת'], [1020000, 'מיליון ועשרים אלף'],
    [1021000, 'מיליון ועשרים ואחד אלף'], [1101000, 'מיליון ומאה ואחד אלף'],
    [1101001, 'מיליון מאה ואחד אלף ואחת'], [21000000, 'עשרים ואחד מיליון'],
    [101000000, 'מאה ואחד מיליון'], [121121121, 'מאה עשרים ואחד מיליון מאה עשרים ואחד אלף מאה עשרים ואחת'],
    [999999999, 'תשע מאות תשעים ותשעה מיליון תשע מאות תשעים ותשעה אלף תשע מאות תשעים ותשע']
  ];
  for (const [number, text] of heGolden) { entries(number, 'he-il'); assert.equal(bare(c.transcript(number, 'he-il')), text); }
  report(`${heVocalized.length} Hebrew vocalized +${heGolden.length} full-number goldens; exact131 roles, gender and attached-vav forms`);
  function heReferenceParts(number, words) {
    const parts = [];
    if (number >= 100) parts.push(heCenturies[Math.floor(number / 100) - 1]);
    const remainder = number % 100;
    if (remainder >= 20) {
      parts.push(heDecades[Math.floor(remainder / 10) - 2]);
      if (remainder % 10) parts.push(words[remainder % 10]);
    } else if (remainder) parts.push(words[remainder]);
    return parts;
  }
  const heReferenceJoin = parts => parts.map((part, index) => index && index === parts.length - 1 ? 'ו' + part : part).join(' ');
  function heReference(number) {
    const parts = [];
    for (const [scale, scaleWord] of [[1000000, 'מיליון'], [1000, 'אלף']]) {
      const count = Math.floor(number / scale) % 1000;
      if (!count) continue;
      if (scale === 1000 && count <= 10) parts.push(heK[count - 1]);
      else if (scale === 1000000 && count <= 2) parts.push(count === 1 ? 'מיליון' : 'שני מיליון');
      else parts.push(heReferenceJoin(heReferenceParts(count, heM)) + ' ' + scaleWord);
    }
    parts.push(...heReferenceParts(number % 1000, heF));
    return heReferenceJoin(parts) || 'אפס';
  }
  const reachableHebrew = new Set();
  function heCheck(number) {
    const result = entries(number, 'he-il'); result.forEach(entry => reachableHebrew.add(entry.id));
    assert.equal(bare(c.transcript(number, 'he-il')), heReference(number), 'independent full-group Hebrew reference');
    assert(!result[0].joined, 'number cannot start with conjunction');
    // Gender is contextual: masculine belongs to a not-yet-closed scale;
    // feminine belongs to the terminal group, never an earlier coefficient.
    for (let index = 0; index < result.length; index++) {
      const entry = result[index], followingScale = result.slice(index + 1).find(token => token.kind === 'whole-scale');
      if (entry.role.includes('masculine-')) assert(followingScale);
      if (entry.role.includes('feminine-')) assert.equal(followingScale, undefined);
    }
  }
  for (let number = 0; number <= 999; number++) {
    for (const scale of [1, 1000, 1000000]) heCheck(number * scale);
    // Force outer conjunction on standalone terminal forms and on every
    // thousand coefficient; also test a following terminal suppresses it.
    heCheck(1000000 + number); heCheck(1000000 + number * 1000); heCheck(1000001 + number * 1000);
  }
  assert.deepEqual([...reachableHebrew].sort(), hePlan.map(entry => entry.id).sort(), 'all131 recordings reachable; no speculative extra clips');
  report('6000 exhaustive Hebrew group/scale/outer-join cases; independent semantics/text, exact gender and all131-role reachability');
  const heBoundaries = [0, 1, 2, 3, 8, 10, 11, 12, 19, 20, 21, 22, 99, 100, 101, 102, 111, 120, 121, 200, 900, 999];
  for (const million of heBoundaries) for (const thousand of heBoundaries) for (const unit of heBoundaries) {
    heCheck(million * 1000000 + thousand * 1000 + unit);
  }
  for (let group = 0; group <= 999; group++) heCheck(group * 1000000 + ((group * 37) % 1000) * 1000 + ((group * 91) % 1000));
  assert.equal(c.tokens(999999999, 'he-il').length, 11);
  report('10648 Hebrew boundary cross-products +1000 mixed cases; nested conjunctions and strict11-token bound');
  // Independent Arabic spelling/reference tables. Full pointed goldens below
  // separately check construct endings and hamzat al-wasl; plain spelling is
  // not used to claim pronunciation or approved pausal delivery.
  const arBare = text => text.replace(/[\u064b-\u065f\u0670]/g, '');
  const arWords = ['صفر', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة',
    'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر'];
  const arDecades = ['عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
  const arCenturies = ['مئة', 'مئتان', 'ثلاثمئة', 'أربعمئة', 'خمسمئة', 'ستمئة', 'سبعمئة', 'ثمانمئة', 'تسعمئة'];
  const arScaleHundreds = ['مئة', 'مئتا', 'ثلاثمئة', 'أربعمئة', 'خمسمئة', 'ستمئة', 'سبعمئة', 'ثمانمئة', 'تسعمئة'];
  const arPlan = c.plan('ar-sa');
  assert.equal(c.ARABIC_CONTEXT, 'msa-masculine-nominative-number-label');
  assert.equal(c.ARABIC_DELIVERY, 'pausal-chunks');
  assert.equal(arPlan.filter(entry => entry.joined).length, 99);
  assert.equal(arPlan.filter(entry => entry.kind === 'number').length, 73);
  assert.equal(arPlan.filter(entry => entry.kind === 'additive-scale').length, 103);
  assert.equal(arPlan.filter(entry => entry.kind === 'additive-scale-tail').length, 32);
  for (const entry of arPlan) {
    assert.equal(entry.grammatical_context, c.ARABIC_CONTEXT);
    assert.equal(entry.recording_delivery, 'pausal-chunks');
    assert.equal(entry.authoring_status, 'provisional-needs-language-review');
    assert.equal(entry.joined, entry.role.startsWith('joined-'));
    assert(/[\u064b-\u0652]/.test(entry.transcript));
    assert(!['and', 'joined-number-0'].includes(entry.role));
    assert(!entry.role.startsWith('joined-scale-1000000-hundred-'), 'unreachable million-hundred join omitted');
    if (entry.joined) assert(entry.transcript.startsWith('وَ'));
  }
  for (let number = 0; number < 20; number++) assert.equal(arBare(c.transcript(number, 'ar-sa')), arWords[number]);
  const arPointed = [
    [0, 'صِفْر'], [1, 'وَاحِد'], [2, 'اِثْنَان'], [11, 'أَحَدَ عَشَر'], [12, 'اِثْنَا عَشَر'],
    [22, 'اِثْنَان وَعِشْرُون'], [102, 'مِئَة وَاثْنَان'], [112, 'مِئَة وَاثْنَا عَشَر'],
    [1000, 'أَلْف'], [2000, 'أَلْفَان'], [3000, 'ثَلَاثَةُ آلَاف'], [8000, 'ثَمَانِيَةُ آلَاف'],
    [10000, 'عَشَرَةُ آلَاف'], [11000, 'أَحَدَ عَشَرَ أَلْفًا'], [12000, 'اِثْنَا عَشَرَ أَلْفًا'],
    [13000, 'ثَلَاثَةَ عَشَرَ أَلْفًا'], [20000, 'عِشْرُونَ أَلْفًا'], [100000, 'مِئَةُ أَلْف'],
    [101000, 'مِئَةُ أَلْف وَأَلْف'], [102000, 'مِئَةُ أَلْف وَأَلْفَان'],
    [103000, 'مِئَةُ أَلْف وَثَلَاثَةُ آلَاف'], [200000, 'مِئَتَا أَلْف'],
    [300000, 'ثَلَاثُمِئَةِ أَلْف'], [800000, 'ثَمَانِمِئَةِ أَلْف'],
    [2000000, 'مِلْيُونَان'], [3000000, 'ثَلَاثَةُ مَلَايِين'],
    [12000000, 'اِثْنَا عَشَرَ مِلْيُونًا'], [200000000, 'مِئَتَا مِلْيُون']
  ];
  for (const [number, text] of arPointed) { entries(number, 'ar-sa'); assert.equal(c.transcript(number, 'ar-sa'), text); }
  const arGolden = [
    [19, 'تسعة عشر'], [21, 'واحد وعشرون'], [99, 'تسعة وتسعون'], [100, 'مئة'], [101, 'مئة وواحد'],
    [120, 'مئة وعشرون'], [121, 'مئة وواحد وعشرون'], [200, 'مئتان'], [999, 'تسعمئة وتسعة وتسعون'],
    [1001, 'ألف وواحد'], [1002, 'ألف واثنان'], [1011, 'ألف وأحد عشر'], [1012, 'ألف واثنا عشر'],
    [1100, 'ألف ومئة'], [1200, 'ألف ومئتان'], [2001, 'ألفان وواحد'], [3001, 'ثلاثة آلاف وواحد'],
    [21000, 'واحد وعشرون ألفا'], [22000, 'اثنان وعشرون ألفا'], [100001, 'مئة ألف وواحد'],
    [101001, 'مئة ألف وألف وواحد'], [102002, 'مئة ألف وألفان واثنان'],
    [110000, 'مئة ألف وعشرة آلاف'], [111000, 'مئة ألف وأحد عشر ألفا'],
    [112000, 'مئة ألف واثنا عشر ألفا'], [120000, 'مئة ألف وعشرون ألفا'],
    [124000, 'مئة ألف وأربعة وعشرون ألفا'], [201000, 'مئتا ألف وألف'], [202000, 'مئتا ألف وألفان'],
    [1000000, 'مليون'], [1001000, 'مليون وألف'], [1001001, 'مليون وألف وواحد'],
    [1200000, 'مليون ومئتا ألف'], [2002000, 'مليونان وألفان'], [3003000, 'ثلاثة ملايين وثلاثة آلاف'],
    [21000000, 'واحد وعشرون مليونا'], [101000000, 'مئة مليون ومليون'],
    [102000000, 'مئة مليون ومليونان'], [201000000, 'مئتا مليون ومليون'],
    [202000000, 'مئتا مليون ومليونان'],
    [121121121, 'مئة مليون وواحد وعشرون مليونا ومئة ألف وواحد وعشرون ألفا ومئة وواحد وعشرون'],
    [999999999, 'تسعمئة مليون وتسعة وتسعون مليونا وتسعمئة ألف وتسعة وتسعون ألفا وتسعمئة وتسعة وتسعون']
  ];
  for (const [number, text] of arGolden) { entries(number, 'ar-sa'); assert.equal(arBare(c.transcript(number, 'ar-sa')), text); }
  report(`${arPointed.length} Arabic pointed +${arGolden.length} full-number goldens; exact208 provisional roles and whole scale morphology`);
  function arReference(number) {
    const phrases = [];
    for (const [scale, singular, dual, plural] of [[1000000, 'مليون', 'مليونان', 'ملايين'],
      [1000, 'ألف', 'ألفان', 'آلاف'], [1, '', '', '']]) {
      const group = Math.floor(number / scale) % 1000, hundreds = Math.floor(group / 100), rest = group % 100;
      if (hundreds) phrases.push(scale === 1 ? arCenturies[hundreds - 1] : arScaleHundreds[hundreds - 1] + ' ' + singular);
      if (!rest) continue;
      if (scale !== 1 && rest <= 2) phrases.push(rest === 1 ? singular : dual);
      else if (rest < 20) phrases.push(arWords[rest] + (scale === 1 ? '' : ' ' + (rest <= 10 ? plural : singular + 'ا')));
      else {
        if (rest % 10) phrases.push(arWords[rest % 10]);
        phrases.push(arDecades[Math.floor(rest / 10) - 2] + (scale === 1 ? '' : ' ' + singular + 'ا'));
      }
    }
    return phrases.map((phrase, index) => index ? 'و' + phrase : phrase).join(' ') || 'صفر';
  }
  const reachableArabic = new Set();
  function arCheck(number) {
    const result = entries(number, 'ar-sa'); result.forEach(entry => reachableArabic.add(entry.id));
    assert.equal(arBare(c.transcript(number, 'ar-sa')), arReference(number));
    for (let index = 0; index < result.length; index++) {
      assert.equal(result[index].joined, index > 0, 'every later additive term has attached whole-recording wa');
      if (result[index].kind === 'additive-scale-tail' && index && result[index - 1].kind === 'number') {
        assert(result[index - 1].value >= 1 && result[index - 1].value <= 9, 'only an Arabic unit precedes the whole decade/scale tail');
      }
    }
  }
  for (let number = 0; number <= 999; number++) {
    for (const scale of [1, 1000, 1000000]) arCheck(number * scale);
    arCheck(1000000 + number); arCheck(1000000 + number * 1000); arCheck(1000001 + number * 1000);
  }
  assert.deepEqual([...reachableArabic].sort(), arPlan.map(entry => entry.id).sort(), 'all208 proposed recordings reachable');
  report('6000 exhaustive Arabic group/scale/join cases; exact repeated-scale semantics, singular/dual/plural and all208-role reachability');
  const arBoundaries = [0, 1, 2, 3, 8, 10, 11, 12, 19, 20, 21, 22, 99, 100, 101, 102, 110, 111, 120, 200, 201, 999];
  for (const million of arBoundaries) for (const thousand of arBoundaries) for (const unit of arBoundaries) {
    arCheck(million * 1000000 + thousand * 1000 + unit);
  }
  for (let group = 0; group <= 999; group++) arCheck(group * 1000000 + ((group * 37) % 1000) * 1000 + ((group * 91) % 1000));
  assert.equal(c.tokens(999999999, 'ar-sa').length, 9);
  report('10648 Arabic boundary cross-products +1000 mixed cases; complete range and strict9-token bound, not audio acceptance');
  for (const number of [-1, 1000000000, 1.5, NaN, Infinity, -Infinity, '1', null, undefined, true, 1n, {}, []]) {
    for (const locale of c.IMPLEMENTED_LOCALES) assert.throws(() => c.compose(number, locale), expectedCode('CARDINAL_NUMBER_OUT_OF_RANGE'));
  }
  for (const locale of [undefined, null, 'en', 'EN-US', 'en_us', 'es', 'de-de', {}, ['en-us']]) {
    assert.throws(() => c.compose(1, locale), expectedCode('CARDINAL_LANGUAGE_UNSUPPORTED'));
  }
  const copy = c.plan(); copy[0].transcript = 'not retained'; copy.pop(); assert.equal(c.plan().length, 584);
  assert.equal(c.transcript(0, 'en-us'), 'zero');
  assert.throws(() => c.tokens(1, 'en-us').push('unknown'), TypeError);
  report('invalid ranges/locales fail closed; no aliases/defaults or caller mutation');
  const isolated = {module: {exports: {}}};
  vm.runInNewContext(fs.readFileSync(sourcePath, 'utf8'), isolated, {timeout: 1000, filename: sourcePath});
  assert.equal(isolated.module.exports.transcript(999999999, 'es-es'), c.transcript(999999999, 'es-es'));
  assert.equal(isolated.module.exports.transcript(999999999, 'fr-fr'), c.transcript(999999999, 'fr-fr'));
  assert.equal(isolated.module.exports.transcript(999999999, 'he-il'), c.transcript(999999999, 'he-il'));
  assert.equal(isolated.module.exports.transcript(999999999, 'ar-sa'), c.transcript(999999999, 'ar-sa'));
  assert.equal(isolated.module.exports.plan().length, 584);
  report('entire module imports/composes in VM without require/process/files/network/provider globals');
} finally {
  const after = Object.fromEntries(pinned.map(file => [file, hash(file)]));
  assert.deepEqual(after, before, 'source pins stable, including on failure');
  console.log(JSON.stringify({schema_version: 1, stage: groups.length === 15 ? 'complete' : 'incomplete',
    passed_groups: groups, compositions_checked: compositions, sources_sha256: after,
    artifact_generation: false, native_acceptance: false, full_five_locale_ready: false}));
}
