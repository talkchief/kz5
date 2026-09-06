'use strict';

// Pure authoring-time building block. No files, provider, native SAY, playback,
// account lookup or runtime fallback. FR/HE/AR remain required, not implemented.
const VERSION = 'acdc-cardinal-v1';
const MAX_NUMBER = 999999999;
const MAX_TOKENS = 14;
const REQUIRED_LOCALES = Object.freeze(['en-us', 'he-il', 'fr-fr', 'es-es', 'ar-sa']);
const IMPLEMENTED_LOCALES = Object.freeze(['en-us', 'es-es']);
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
const records = [];
function add(locale, role, transcript, kind, value) {
  records.push(Object.freeze({catalog_version: VERSION, locale, id: `${VERSION}-${role}`,
    role, transcript, kind, ...(value === undefined ? {} : {value})}));
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
function compose(number, locale) {
  assertLocale(locale); assertNumber(number);
  const roles = [];
  if (number === 0) roles.push('number-0');
  for (const scale of [1000000, 1000, 1]) {
    const coefficient = Math.floor(number / scale) % 1000;
    if (!coefficient) continue;
    if (locale === 'en-us') {
      roles.push(...englishGroup(coefficient));
      if (scale !== 1) roles.push(scale === 1000 ? 'thousand' : 'million');
    } else {
      // A thousand has no spoken coefficient one: mil, never un mil.
      if (!(scale === 1000 && coefficient === 1)) roles.push(...spanishGroup(coefficient, scale !== 1));
      if (scale === 1000) roles.push('thousand');
      if (scale === 1000000) roles.push(coefficient === 1 ? 'million' : 'millions');
    }
  }
  const token_ids = roles.map(role => `${VERSION}-${role}`);
  if (!token_ids.length || token_ids.length > MAX_TOKENS
      || token_ids.some(id => !lookup.has(`${locale}/${id}`))) {
    throw new CardinalError('CARDINAL_CATALOG_INVARIANT');
  }
  return Object.freeze({catalog_version: VERSION, locale, number: number === 0 ? 0 : number,
    token_ids: Object.freeze(token_ids)});
}
function tokens(number, locale) { return compose(number, locale).token_ids; }
function transcript(number, locale) {
  return tokens(number, locale).map(id => lookup.get(`${locale}/${id}`).transcript).join(' ');
}
function plan(locale) {
  if (locale !== undefined) assertLocale(locale);
  return PROMPTS.filter(entry => locale === undefined || entry.locale === locale).map(entry => ({...entry}));
}
module.exports = Object.freeze({VERSION, MAX_NUMBER, MAX_TOKENS, REQUIRED_LOCALES,
  IMPLEMENTED_LOCALES, PROMPTS, CardinalError, compose, tokens, transcript, plan});
