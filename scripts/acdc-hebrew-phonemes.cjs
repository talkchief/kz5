'use strict';

// Explicit fixed eSpeak phonemes bypass 1.52's broken Hebrew combining-mark
// handling and incorrect built-in number dictionary (80 was pronounced30).
// Hebrew source text remains in the catalog for review. These are synthetic
// draft recordings, not native-speaker-approved studio recordings.
const units = ["'efes", "eX'ad", "Sn'ajim", "SloS'a", "aRba?'a", "XamiS'a", "SiS'a", "Siv?'a", "Smon'a", "tiS?'a"];
const teens = ["asaR'a", "aX'ad as'aR", "Sneim as'aR", "SloS'a as'aR", "aRba?'a as'aR", "XamiS'a as'aR", "SiS'a as'aR", "Siv?'a as'aR", "Smon'a as'aR", "tiS?'a as'aR"];
const tens = ['', '', "esR'im", "SloS'im", "aRba?'im", "XamiS'im", "SiS'im", "Siv?'im", "Smon'im", "tiS?'im"];
const hundreds = ['', "me?'a", "mat'ajim", "SloS me?'ot", "aRba me?'ot", "XameS me?'ot", "SeS me?'ot", "Sva me?'ot", "Smone me?'ot", "tSa me?'ot"];
const construct = ['', '', '', "SloSet", "aRba?at", "XameSet", "SeSet", "Siv?at", "Smonat", "tiS?at", "aseRet"];
function scalar(n) {
  if (!Number.isInteger(n) || n < 0 || n > 999) throw new Error('Hebrew scalar outside0..999');
  if (n < 10) return units[n];
  if (n < 20) return teens[n-10];
  if (n < 100) return tens[Math.floor(n/10)] + (n%10 ? ' ve'+units[n%10] : '');
  const remainder=n%100;
  // The remainder21..99 already has its final tens–units conjunction.
  const separator=remainder>=20&&remainder%10!==0?' ':' ve';
  return hundreds[Math.floor(n/100)] + (remainder ? separator+scalar(remainder) : '');
}
function number(n) {
  if (!Number.isInteger(n) || n < 0 || n > 999000000) throw new Error('Hebrew chunk outside supported range');
  if (n <= 999) return scalar(n);
  if (n%1000000===0) {
    const coefficient=n/1000000;
    return coefficient===1 ? "milj'on" : coefficient===2 ? "Snei milj'on" : scalar(coefficient)+" milj'on";
  }
  if (n%1000===0 && n<=999000) {
    const coefficient=n/1000;
    if (coefficient===1) return "'elef";
    if (coefficient===2) return "alp'ajim";
    return coefficient<=10 ? construct[coefficient]+" alaf'im" : scalar(coefficient)+" 'elef";
  }
  throw new Error('Hebrew chunk must be a scalar or exact thousand/million group');
}
const callbacks = [
  "hakiSu eX'ad lekabalat siXa XozeRet la mispaR Se mimenu atem mitkaSRim. hakiSu koXavit kedei lehiSa?eR batoR",
  "hakiSu eX'ad leSimuS ba mispaR Se mimenu atem mitkaSRim. hakiSu Sn'ajim lehazanat mispaR aXeR uvesijum sulamit. hakiSu koXavit kedei lehiSa?eR batoR",
  "mispaR ha telefon la siXa ha XozeRet Se hizantem hu",
  "hakiSu eX'ad leiSuR ha mispaR. hakiSu koXavit kedei lehiSa?eR batoR",
  "ha bakaSa niRSema. nitkaSeR aleiXem kSe jagia toRXem. lehitra?ot",
  "higia toRXem. hakiSu eX'ad kedei ledabeR im natsig"
];
const queue = [
  "mekomXem ha noXXi batoR hu", "mekomXem hu", "batoR",
  "jeS alija be mispaR ha siXot", "zman ha hamtana ha meSo'aR hu",
  "paXot mi daka aXat", "ka XameS dakot", "ke eseR dakot", "ka XameS esRe dakot",
  "ki SloSim dakot", "ke aRba?im ve XameS dakot", "ke Sa?a aXat", "lefaXot Sa?a aXat"
];
const callbackNames = ['menu-current','menu-alternate','number-readback','confirmation','success','returned-confirmation'];
const queueNames = ['your-current-position-is','you_are_at_position','in_the_queue','increase_in_call_volume','the_estimated_wait_time_is','less_than_1_minute','about_5_minutes','about_10_minutes','about_15_minutes','about_30_minutes','about_45_minutes','about_1_hour','at_least_1_hour'];
function prompt(id) {
  let match;
  if ((match=/^acdc-number-(\d+)$/.exec(id))) return number(Number(match[1]));
  if (id==='acdc-number-and') return 've';
  if ((match=/^acdc-callback-offer-(\d)$/.exec(id)))
    return 'lekabalat siXa XozeRet toX SmiRa al mekomXem batoR, hakiSu '+units[Number(match[1])];
  const callback=callbackNames.indexOf(id.replace(/^acdc-callback-/,''));
  if (callback!==-1) return callbacks[callback];
  const q=queueNames.indexOf(id.replace(/^acdc-queue-/,''));
  if (q!==-1) return queue[q];
  throw new Error('Unspecified Hebrew prompt pronunciation');
}
module.exports={prompt,number,scalar};
