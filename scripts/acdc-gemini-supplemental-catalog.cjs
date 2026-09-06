'use strict';

// Fixed text only: no caller/account data and no runtime synthesis. These
// three auxiliary contexts supplement, never replace, the historical packs.
const languages = Object.freeze({'en-us':'American English','he-il':'Israeli Hebrew',
  'ar-sa':'Modern Standard Arabic','fr-fr':'French from France','es-es':'Spanish from Spain'});
const auxiliaryIds = Object.freeze(['acdc-callback-unavailable','acdc-callback-invalid-entry','acdc-callback-enter-number']);
const auxiliary = {
  'en-us': [
    'A callback is not available right now. Please stay on the line to keep your place in the queue.',
    'That entry is not valid. Please try again.',
    'Please enter the phone number for your callback, followed by the pound key. Press star to stay in the queue.'
  ],
  'he-il': [
    'לא ניתן לקבל שיחה חוזרת כרגע. אנא הישארו על הקו כדי לשמור על מקומכם בתור.',
    'הבחירה אינה תקינה. אנא נסו שוב.',
    'אנא הקישו את מספר הטלפון לשיחה החוזרת, ובסיום הקישו סולמית. כדי להישאר בתור, הקישו כוכבית.'
  ],
  'ar-sa': [
    'خدمة معاودة الاتصال غير متاحة الآن. يرجى البقاء على الخط للحفاظ على مكانك في طابور الانتظار.',
    'الإدخال غير صحيح. يرجى المحاولة مرة أخرى.',
    'يرجى إدخال رقم الهاتف لمعاودة الاتصال، ثم الضغط على مفتاح المربع. للبقاء في طابور الانتظار، اضغط على مفتاح النجمة.'
  ],
  'fr-fr': [
    'Le rappel n’est pas disponible pour le moment. Veuillez rester en ligne pour conserver votre place dans la file d’attente.',
    'Cette saisie n’est pas valide. Veuillez réessayer.',
    'Veuillez saisir le numéro de téléphone auquel vous souhaitez être rappelé, puis appuyer sur dièse. Pour rester dans la file d’attente, appuyez sur étoile.'
  ],
  'es-es': [
    'La devolución de llamada no está disponible en este momento. Permanezca en línea para conservar su lugar en la cola.',
    'La opción introducida no es válida. Inténtelo de nuevo.',
    'Introduzca el número de teléfono para la devolución de llamada y pulse almohadilla al terminar. Pulse asterisco para permanecer en la cola.'
  ]
};
const telephoneDigits = {
  'en-us': ['zero','one','two','three','four','five','six','seven','eight','nine'],
  'fr-fr': ['zéro','un','deux','trois','quatre','cinq','six','sept','huit','neuf'],
  'es-es': ['cero','uno','dos','tres','cuatro','cinco','seis','siete','ocho','nueve']
};
const PROMPTS = Object.freeze([
  ...Object.keys(languages).flatMap(locale => auxiliaryIds.map((id,i) => Object.freeze({
    locale,id,language:languages[locale],transcript:auxiliary[locale][i],
    kind:'callback-auxiliary',maximum_duration_seconds:20
  }))),
  ...Object.keys(telephoneDigits).flatMap(locale => telephoneDigits[locale].map((transcript,digit) => Object.freeze({
    locale,id:`acdc-number-${digit}`,language:languages[locale],transcript,
    kind:'callback-digit',maximum_duration_seconds:5
  })))
]);
function plan() { return PROMPTS.map(entry => ({...entry})); }
module.exports = {PROMPTS,plan};
