'use strict';

// Pure authoring-time building block. No files, provider, native SAY, playback,
// account lookup or runtime fallback. AR remains required, not implemented.
const VERSION = 'acdc-cardinal-v1';
const MAX_NUMBER = 999999999;
const MAX_TOKENS = 14;
const MAX_TOKENS_BY_LOCALE = Object.freeze({'en-us': 14, 'es-es': 14, 'fr-fr': 8, 'he-il': 11});
const REQUIRED_LOCALES = Object.freeze(['en-us', 'he-il', 'fr-fr', 'es-es', 'ar-sa']);
const IMPLEMENTED_LOCALES = Object.freeze(['en-us', 'es-es', 'fr-fr', 'he-il']);
// This is NOT a masculine counted-place or ordinal grammar. Existing queue
// introductions require a separate context review; this module changes none.
const HEBREW_CONTEXT = 'abstract-number-label-feminine';
const heMasculine = [null, 'אֶחָד', 'שְׁנַיִם', 'שְׁלוֹשָׁה', 'אַרְבָּעָה', 'חֲמִשָּׁה',
  'שִׁשָּׁה', 'שִׁבְעָה', 'שְׁמוֹנָה', 'תִּשְׁעָה', 'עֲשָׂרָה', 'אַחַד עָשָׂר',
  'שְׁנֵים עָשָׂר', 'שְׁלוֹשָׁה עָשָׂר', 'אַרְבָּעָה עָשָׂר', 'חֲמִשָּׁה עָשָׂר',
  'שִׁשָּׁה עָשָׂר', 'שִׁבְעָה עָשָׂר', 'שְׁמוֹנָה עָשָׂר', 'תִּשְׁעָה עָשָׂר'];
const heJoinedMasculine = [null, 'וְאֶחָד', 'וּשְׁנַיִם', 'וּשְׁלוֹשָׁה', 'וְאַרְבָּעָה',
  'וַחֲמִשָּׁה', 'וְשִׁשָּׁה', 'וְשִׁבְעָה', 'וּשְׁמוֹנָה', 'וְתִשְׁעָה', 'וַעֲשָׂרָה',
  'וְאַחַד עָשָׂר', 'וּשְׁנֵים עָשָׂר', 'וּשְׁלוֹשָׁה עָשָׂר', 'וְאַרְבָּעָה עָשָׂר',
  'וַחֲמִשָּׁה עָשָׂר', 'וְשִׁשָּׁה עָשָׂר', 'וְשִׁבְעָה עָשָׂר', 'וּשְׁמוֹנָה עָשָׂר', 'וְתִשְׁעָה עָשָׂר'];
const heFeminine = [null, 'אַחַת', 'שְׁתַּיִם', 'שָׁלוֹשׁ', 'אַרְבַּע', 'חָמֵשׁ', 'שֵׁשׁ',
  'שֶׁבַע', 'שְׁמוֹנֶה', 'תֵּשַׁע', 'עֶשֶׂר', 'אַחַת עֶשְׂרֵה', 'שְׁתֵּים עֶשְׂרֵה',
  'שְׁלוֹשׁ עֶשְׂרֵה', 'אַרְבַּע עֶשְׂרֵה', 'חֲמֵשׁ עֶשְׂרֵה', 'שֵׁשׁ עֶשְׂרֵה',
  'שְׁבַע עֶשְׂרֵה', 'שְׁמוֹנֶה עֶשְׂרֵה', 'תְּשַׁע עֶשְׂרֵה'];
const heJoinedFeminine = [null, 'וְאַחַת', 'וּשְׁתַּיִם', 'וְשָׁלוֹשׁ', 'וְאַרְבַּע', 'וְחָמֵשׁ',
  'וְשֵׁשׁ', 'וְשֶׁבַע', 'וּשְׁמוֹנֶה', 'וְתֵשַׁע', 'וְעֶשֶׂר', 'וְאַחַת עֶשְׂרֵה',
  'וּשְׁתֵּים עֶשְׂרֵה', 'וּשְׁלוֹשׁ עֶשְׂרֵה', 'וְאַרְבַּע עֶשְׂרֵה', 'וַחֲמֵשׁ עֶשְׂרֵה',
  'וְשֵׁשׁ עֶשְׂרֵה', 'וּשְׁבַע עֶשְׂרֵה', 'וּשְׁמוֹנֶה עֶשְׂרֵה', 'וּתְשַׁע עֶשְׂרֵה'];
const heTens = ['עֶשְׂרִים', 'שְׁלוֹשִׁים', 'אַרְבָּעִים', 'חֲמִשִּׁים', 'שִׁשִּׁים',
  'שִׁבְעִים', 'שְׁמוֹנִים', 'תִּשְׁעִים'];
const heJoinedTens = ['וְעֶשְׂרִים', 'וּשְׁלוֹשִׁים', 'וְאַרְבָּעִים', 'וַחֲמִשִּׁים',
  'וְשִׁשִּׁים', 'וְשִׁבְעִים', 'וּשְׁמוֹנִים', 'וְתִשְׁעִים'];
const heHundreds = ['מֵאָה', 'מָאתַיִם', 'שְׁלוֹשׁ מֵאוֹת', 'אַרְבַּע מֵאוֹת',
  'חֲמֵשׁ מֵאוֹת', 'שֵׁשׁ מֵאוֹת', 'שְׁבַע מֵאוֹת', 'שְׁמוֹנֶה מֵאוֹת', 'תְּשַׁע מֵאוֹת'];
const heJoinedHundreds = ['וּמֵאָה', 'וּמָאתַיִם', 'וּשְׁלוֹשׁ מֵאוֹת', 'וְאַרְבַּע מֵאוֹת',
  'וַחֲמֵשׁ מֵאוֹת', 'וְשֵׁשׁ מֵאוֹת', 'וּשְׁבַע מֵאוֹת', 'וּשְׁמוֹנֶה מֵאוֹת', 'וּתְשַׁע מֵאוֹת'];
const heThousands = ['אֶלֶף', 'אַלְפַּיִם', 'שְׁלוֹשֶׁת אֲלָפִים', 'אַרְבַּעַת אֲלָפִים',
  'חֲמֵשֶׁת אֲלָפִים', 'שֵׁשֶׁת אֲלָפִים', 'שִׁבְעַת אֲלָפִים', 'שְׁמוֹנַת אֲלָפִים',
  'תִּשְׁעַת אֲלָפִים', 'עֲשֶׂרֶת אֲלָפִים'];
const heJoinedThousands = ['וְאֶלֶף', 'וְאַלְפַּיִם', 'וּשְׁלוֹשֶׁת אֲלָפִים',
  'וְאַרְבַּעַת אֲלָפִים', 'וַחֲמֵשֶׁת אֲלָפִים', 'וְשֵׁשֶׁת אֲלָפִים',
  'וְשִׁבְעַת אֲלָפִים', 'וּשְׁמוֹנַת אֲלָפִים', 'וְתִשְׁעַת אֲלָפִים', 'וַעֲשֶׂרֶת אֲלָפִים'];
const enSmall = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
  'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const enTens = ['twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
const esSmall = ['cero', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve',
  'diez', 'once', 'doce', 'trece', 'catorce', 'quince', 'dieciséis', 'diecisiete', 'dieciocho', 'diecinueve',
  'veinte', 'veintiuno', 'veintidós', 'veintitrés', 'veinticuatro', 'veinticinco', 'veintiséis',
  'veintisiete', 'veintiocho', 'veintinueve'];
const esTens = ['treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa'];
const esHundreds = ['cien', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos',
  'seiscientos', 'setecientos', 'ochocientos', 'novecientos'];
const frSmall = ['zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf',
  'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize'];
const frTens = ['vingt', 'trente', 'quarante', 'cinquante', 'soixante'];
const FRENCH_SCALED_TAILS = Object.freeze([6, 8, 10, 18, 26, 28, 36, 38, 46, 48,
  56, 58, 66, 68, 70, 78, 86, 88, 90, 98]);
function frenchSmall(number) {
  if (number < 17) return frSmall[number];
  if (number < 20) return `dix-${frSmall[number - 10]}`;
  if (number < 70) {
    const decade = frTens[Math.floor(number / 10) - 2], unit = number % 10;
    return decade + (unit === 1 ? ' et un' : unit ? `-${frSmall[unit]}` : '');
  }
  if (number < 80) return number === 71 ? 'soixante et onze' : `soixante-${frenchSmall(number - 60)}`;
  return number === 80 ? 'quatre-vingts' : `quatre-vingt-${frenchSmall(number - 80)}`;
}
const records = [];
function add(locale, role, transcript, kind, value, scale) {
  records.push(Object.freeze({catalog_version: VERSION, locale, id: `${VERSION}-${role}`,
    role, transcript, kind, ...(value === undefined ? {} : {value}), ...(scale === undefined ? {} : {scale})}));
}
enSmall.forEach((word, n) => add('en-us', `number-${n}`, word, 'number', n));
enTens.forEach((word, n) => add('en-us', `number-${(n + 2) * 10}`, word, 'number', (n + 2) * 10));
add('en-us', 'hundred', 'hundred', 'hundred-multiplier', 100);
add('en-us', 'thousand', 'thousand', 'scale', 1000);
add('en-us', 'million', 'million', 'scale', 1000000);
esSmall.forEach((word, n) => add('es-es', `number-${n}`, word, 'number', n));
esTens.forEach((word, n) => add('es-es', `number-${(n + 3) * 10}`, word, 'number', (n + 3) * 10));
esHundreds.forEach((word, n) => add('es-es', `number-${(n + 1) * 100}`, word, 'number', (n + 1) * 100));
add('es-es', 'hundred-continuation', 'ciento', 'number', 100);
add('es-es', 'before-scale-1', 'un', 'number', 1);
add('es-es', 'before-scale-21', 'veintiún', 'number', 21);
add('es-es', 'and', 'y', 'conjunction');
add('es-es', 'thousand', 'mil', 'scale', 1000);
add('es-es', 'million', 'millón', 'scale', 1000000);
add('es-es', 'millions', 'millones', 'scale', 1000000);
for (let number = 0; number < 100; number++) add('fr-fr', `terminal-${number}`, frenchSmall(number), 'number', number);
for (let hundreds = 1; hundreds <= 9; hundreds++) {
  const prefix = hundreds === 1 ? 'cent' : `${frSmall[hundreds]} cent`;
  add('fr-fr', `hundreds-${hundreds}`, prefix + (hundreds > 1 ? 's' : ''), 'number', hundreds * 100);
  add('fr-fr', `hundred-one-${hundreds}`, `${prefix} un`, 'number', hundreds * 100 + 1);
}
for (const scale of [1000, 1000000]) for (const number of FRENCH_SCALED_TAILS) {
  add('fr-fr', `scaled-tail-${scale}-${number}`,
    `${frenchSmall(number)} ${scale === 1000 ? 'mille' : 'millions'}`, 'scaled-tail', number, scale);
}
add('fr-fr', 'thousand', 'mille', 'scale', 1000);
add('fr-fr', 'million', 'million', 'scale', 1000000);
add('fr-fr', 'millions', 'millions', 'scale', 1000000);
function hebrewRecord(role, text, kind, value, scale, joined = false) {
  records.push(Object.freeze({catalog_version: VERSION, locale: 'he-il', id: `${VERSION}-${role}`,
    role, transcript: text, kind, value, ...(scale === undefined ? {} : {scale}),
    grammatical_context: HEBREW_CONTEXT, joined}));
}
hebrewRecord('number-0', 'אֶפֶס', 'number', 0);
for (let number = 1; number <= 19; number++) {
  // Unjoined masculine1/2 are unreachable: scales have exact singular/dual
  // phrases; larger coefficients use the attached-conjunction forms.
  if (number >= 3) hebrewRecord(`masculine-${number}`, heMasculine[number], 'number', number);
  hebrewRecord(`joined-masculine-${number}`, heJoinedMasculine[number], 'number', number, undefined, true);
  hebrewRecord(`feminine-${number}`, heFeminine[number], 'number', number);
  hebrewRecord(`joined-feminine-${number}`, heJoinedFeminine[number], 'number', number, undefined, true);
}
for (const [role, base, joined, multiplier, kind, scale] of [
  ['tens', heTens, heJoinedTens, 10, 'number', undefined],
  ['hundreds', heHundreds, heJoinedHundreds, 100, 'number', undefined],
  ['thousands', heThousands, heJoinedThousands, 1, 'whole-scale', 1000]
]) base.forEach((word, index) => {
  const value = (index + (role === 'tens' ? 2 : 1)) * multiplier;
  hebrewRecord(`${role}-${value}`, word, kind, value, scale);
  hebrewRecord(`joined-${role}-${value}`, joined[index], kind, value, scale, true);
});
hebrewRecord('million', 'מִילְיוֹן', 'whole-scale', 1, 1000000);
hebrewRecord('two-million', 'שְׁנֵי מִילְיוֹן', 'whole-scale', 2, 1000000);
const PROMPTS = Object.freeze(records);
const lookup = new Map(PROMPTS.map(entry => [`${entry.locale}/${entry.id}`, entry]));

class CardinalError extends Error {
  constructor(code) { super(code); this.name = 'CardinalError'; this.code = code; }
}
function assertLocale(locale) {
  if (!IMPLEMENTED_LOCALES.includes(locale)) {
    throw new CardinalError(REQUIRED_LOCALES.includes(locale)
      ? 'CARDINAL_LANGUAGE_NOT_IMPLEMENTED' : 'CARDINAL_LANGUAGE_UNSUPPORTED');
  }
}
function assertNumber(number) {
  if (!Number.isInteger(number) || number < 0 || number > MAX_NUMBER) {
    throw new CardinalError('CARDINAL_NUMBER_OUT_OF_RANGE');
  }
}
function englishGroup(number) {
  const roles = [], hundreds = Math.floor(number / 100), rest = number % 100;
  if (hundreds) roles.push(`number-${hundreds}`, 'hundred');
  if (rest >= 20) {
    roles.push(`number-${Math.floor(rest / 10) * 10}`);
    if (rest % 10) roles.push(`number-${rest % 10}`);
  } else if (rest) roles.push(`number-${rest}`);
  return roles;
}
function spanishGroup(number, beforeScale) {
  const roles = [], hundreds = Math.floor(number / 100), rest = number % 100;
  if (hundreds) roles.push(hundreds === 1 && rest ? 'hundred-continuation' : `number-${hundreds * 100}`);
  function small(value) {
    return beforeScale && (value === 1 || value === 21) ? `before-scale-${value}` : `number-${value}`;
  }
  if (rest >= 30) {
    roles.push(`number-${Math.floor(rest / 10) * 10}`);
    if (rest % 10) roles.push('and', small(rest % 10));
  } else if (rest) roles.push(small(rest));
  return roles;
}
function frenchGroup(number, scale) {
  if (number === 1 && scale === 1000) return ['thousand'];
  const roles = [], hundreds = Math.floor(number / 100), rest = number % 100;
  if (hundreds && rest === 1) roles.push(`hundred-one-${hundreds}`);
  else {
    if (hundreds) roles.push(`hundreds-${hundreds}`);
    if (scale !== 1 && FRENCH_SCALED_TAILS.includes(rest)) {
      // This one recording includes the scale: never append it again.
      roles.push(`scaled-tail-${scale}-${rest}`); return roles;
    }
    if (rest) roles.push(`terminal-${rest}`);
  }
  if (scale !== 1) roles.push(scale === 1000 ? 'thousand' : number === 1 ? 'million' : 'millions');
  return roles;
}
function hebrewAtoms(number, gender) {
  const atoms = [], hundreds = Math.floor(number / 100), rest = number % 100;
  if (hundreds) atoms.push([`hundreds-${hundreds * 100}`]);
  if (rest >= 20) {
    atoms.push([`tens-${Math.floor(rest / 10) * 10}`]);
    if (rest % 10) atoms.push([`${gender}-${rest % 10}`]);
  } else if (rest) atoms.push([`${gender}-${rest}`]);
  return atoms;
}
function hebrewAdd(atoms) {
  // Conjoin the last additive term, not every token or every scale word.
  // Scale coefficients are separate additive expressions. If a compound
  // scale is the final outer term its first recording also carries vav.
  return atoms.flatMap((atom, index) => index && index === atoms.length - 1
    ? [`joined-${atom[0]}`, ...atom.slice(1)] : atom);
}
function hebrewScale(coefficient, scale) {
  if (scale === 1000 && coefficient <= 10) return [`thousands-${coefficient}`];
  if (scale === 1000000 && coefficient <= 2) return [coefficient === 1 ? 'million' : 'two-million'];
  return [...hebrewAdd(hebrewAtoms(coefficient, 'masculine')), scale === 1000 ? 'thousands-1' : 'million'];
}
function hebrewNumber(number) {
  if (!number) return ['number-0'];
  const atoms = [];
  for (const scale of [1000000, 1000]) {
    const coefficient = Math.floor(number / scale) % 1000;
    if (coefficient) atoms.push(hebrewScale(coefficient, scale));
  }
  atoms.push(...hebrewAtoms(number % 1000, 'feminine'));
  return hebrewAdd(atoms);
}
function compose(number, locale) {
  assertLocale(locale); assertNumber(number);
  const roles = [];
  if (locale === 'he-il') roles.push(...hebrewNumber(number));
  else if (number === 0) roles.push(locale === 'fr-fr' ? 'terminal-0' : 'number-0');
  for (const scale of [1000000, 1000, 1]) {
    const coefficient = Math.floor(number / scale) % 1000;
    if (!coefficient) continue;
    if (locale === 'en-us') {
      roles.push(...englishGroup(coefficient));
      if (scale !== 1) roles.push(scale === 1000 ? 'thousand' : 'million');
    } else if (locale === 'es-es') {
      // A thousand has no spoken coefficient one: mil, never un mil.
      if (!(scale === 1000 && coefficient === 1)) roles.push(...spanishGroup(coefficient, scale !== 1));
      if (scale === 1000) roles.push('thousand');
      if (scale === 1000000) roles.push(coefficient === 1 ? 'million' : 'millions');
    } else if (locale === 'fr-fr') roles.push(...frenchGroup(coefficient, scale));
  }
  const token_ids = roles.map(role => `${VERSION}-${role}`);
  if (!token_ids.length || token_ids.length > MAX_TOKENS_BY_LOCALE[locale]
      || token_ids.some(id => !lookup.has(`${locale}/${id}`))) {
    throw new CardinalError('CARDINAL_CATALOG_INVARIANT');
  }
  return Object.freeze({catalog_version: VERSION, locale, number: number === 0 ? 0 : number,
    token_ids: Object.freeze(token_ids)});
}
function tokens(number, locale) { return compose(number, locale).token_ids; }
function transcript(number, locale) {
  const entries = tokens(number, locale).map(id => lookup.get(`${locale}/${id}`));
  return entries.map((entry, index) => {
    if (locale !== 'fr-fr') return entry.transcript;
    // Silent orthographic s is retained in immutable recording transcripts.
    // Written full cardinals drop it before another numeral (including mille),
    // but retain it before the noun millions. No WAV is transformed here.
    const next = entries[index + 1];
    if (entry.role.startsWith('hundreds-') && next && (next.kind === 'number'
        || next.kind === 'scaled-tail' || next.kind === 'scale' && next.value === 1000)) {
      return entry.transcript.replace(/cents$/, 'cent');
    }
    if (entry.role === 'terminal-80' && next && next.kind === 'scale' && next.value === 1000) {
      return entry.transcript.replace(/vingts$/, 'vingt');
    }
    return entry.transcript;
  }).join(' ');
}
function plan(locale) {
  if (locale !== undefined) assertLocale(locale);
  return PROMPTS.filter(entry => locale === undefined || entry.locale === locale).map(entry => ({...entry}));
}
module.exports = Object.freeze({VERSION, MAX_NUMBER, MAX_TOKENS, MAX_TOKENS_BY_LOCALE, REQUIRED_LOCALES,
  IMPLEMENTED_LOCALES, FRENCH_SCALED_TAILS, HEBREW_CONTEXT, PROMPTS, CardinalError, compose, tokens, transcript, plan});
