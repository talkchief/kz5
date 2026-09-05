'use strict';

// Fixed, reviewable text only. No caller text is submitted to a speech service.
// Synthetic voices are not a claim of native-speaker pronunciation approval.
const definitions = {
  'en-us': {
    voice: 'en-us', conjunction: 'and',
    offer: 'To request a callback while keeping your place in the queue, press {key}.',
    callback: [
      'Press 1 to receive a callback at the phone number you are calling from. Press star to stay in the queue.',
      'Press 1 to use the phone number you are calling from. Press 2 to enter a different number followed by the pound key. Press star to stay in the queue.',
      'The callback number you entered is.',
      'Press 1 to confirm this callback number. Press star to stay in the queue.',
      'Your callback is registered. We will call you when you reach the front of the queue. Goodbye.',
      'Your callback is ready. Press 1 to connect to an agent.'
    ],
    queue: [
      'Your current position is.', 'You are at position.', 'in the queue.',
      'We are experiencing an increase in call volume.', 'The estimated wait time is.',
      'less than one minute.', 'about five minutes.', 'about ten minutes.',
      'about fifteen minutes.', 'about thirty minutes.', 'about forty five minutes.',
      'about one hour.', 'at least one hour.'
    ]
  },
  'es-es': {
    voice: 'es', conjunction: 'y',
    offer: 'Para solicitar que le devolvamos la llamada sin perder su lugar en la cola, pulse {key}.',
    callback: [
      'Pulse 1 para recibir la llamada en el número desde el que está llamando. Pulse asterisco para permanecer en la cola.',
      'Pulse 1 para utilizar el número desde el que está llamando. Pulse 2 para introducir otro número seguido de la tecla almohadilla. Pulse asterisco para permanecer en la cola.',
      'El número que ha introducido para la devolución de llamada es.',
      'Pulse 1 para confirmar este número. Pulse asterisco para permanecer en la cola.',
      'Su solicitud ha quedado registrada. Le llamaremos cuando llegue su turno. Hasta luego.',
      'Ha llegado su turno. Pulse 1 para hablar con un agente.'
    ],
    queue: [
      'Su posición actual es.', 'Su posición es.', 'en la cola.',
      'Estamos recibiendo un mayor número de llamadas.', 'El tiempo de espera estimado es.',
      'menos de un minuto.', 'unos cinco minutos.', 'unos diez minutos.',
      'unos quince minutos.', 'unos treinta minutos.', 'unos cuarenta y cinco minutos.',
      'aproximadamente una hora.', 'al menos una hora.'
    ]
  },
  'fr-fr': {
    voice: 'fr-fr', conjunction: 'et',
    offer: 'Pour être rappelé sans perdre votre place dans la file d’attente, appuyez sur {key}.',
    callback: [
      'Appuyez sur 1 pour être rappelé au numéro depuis lequel vous appelez. Appuyez sur étoile pour rester dans la file d’attente.',
      'Appuyez sur 1 pour utiliser le numéro depuis lequel vous appelez. Appuyez sur 2 pour saisir un autre numéro, suivi de la touche dièse. Appuyez sur étoile pour rester dans la file d’attente.',
      'Le numéro de rappel que vous avez saisi est.',
      'Appuyez sur 1 pour confirmer ce numéro. Appuyez sur étoile pour rester dans la file d’attente.',
      'Votre demande de rappel est enregistrée. Nous vous rappellerons quand ce sera votre tour. Au revoir.',
      'Votre tour est arrivé. Appuyez sur 1 pour parler à un agent.'
    ],
    queue: [
      'Votre position actuelle est.', 'Vous êtes en position.', 'dans la file d’attente.',
      'Nous recevons un plus grand nombre d’appels.', 'Le temps d’attente estimé est de.',
      'moins d’une minute.', 'environ cinq minutes.', 'environ dix minutes.',
      'environ quinze minutes.', 'environ trente minutes.', 'environ quarante-cinq minutes.',
      'environ une heure.', 'au moins une heure.'
    ]
  },
  'ar-sa': {
    voice: 'ar', conjunction: 'وَ',
    offer: 'لِطَلَبِ مُعاوَدَةِ الاِتِّصالِ مَعَ الاِحْتِفاظِ بِمَكانِكَ في الطّابورِ، اِضْغَطْ {key}.',
    callback: [
      'اِضْغَطْ 1 لِمُعاوَدَةِ الاِتِّصالِ بِالرَّقْمِ الَّذي تَتَّصِلُ مِنْهُ. اِضْغَطْ نَجْمَةً لِلْبَقاءِ في الطّابورِ.',
      'اِضْغَطْ 1 لاِسْتِخْدامِ الرَّقْمِ الَّذي تَتَّصِلُ مِنْهُ. اِضْغَطْ 2 لِإِدْخالِ رَقْمٍ آخَرَ ثُمَّ مِفْتاحَ المُرَبَّعِ. اِضْغَطْ نَجْمَةً لِلْبَقاءِ في الطّابورِ.',
      'رَقْمُ مُعاوَدَةِ الاِتِّصالِ الَّذي أَدْخَلْتَهُ هُوَ.',
      'اِضْغَطْ 1 لِتَأْكيدِ هَذا الرَّقْمِ. اِضْغَطْ نَجْمَةً لِلْبَقاءِ في الطّابورِ.',
      'تَمَّ تَسْجيلُ طَلَبِكَ. سَنَتَّصِلُ بِكَ عِنْدَ وُصولِ دَوْرِكَ. مَعَ السَّلامَةِ.',
      'حانَ دَوْرُكَ. اِضْغَطْ 1 لِلتَّحَدُّثِ مَعَ مُوَظَّفِ خِدْمَةِ العُمَلاءِ.'
    ],
    queue: [
      'مَوْقِعُكَ الحالي هُوَ.', 'أَنْتَ في المَوْقِعِ.', 'في طابورِ الاِنْتِظارِ.',
      'نَشْهَدُ زِيادَةً في عَدَدِ المُكالَماتِ.', 'وَقْتُ الاِنْتِظارِ المُتَوَقَّعُ هُوَ.',
      'أَقَلُّ مِنْ دَقيقَةٍ واحِدَةٍ.', 'حَوالَيْ خَمْسِ دَقائِقَ.', 'حَوالَيْ عَشْرِ دَقائِقَ.',
      'حَوالَيْ خَمْسَ عَشْرَةَ دَقيقَةً.', 'حَوالَيْ ثَلاثينَ دَقيقَةً.', 'حَوالَيْ خَمْسٍ وَأَرْبَعينَ دَقيقَةً.',
      'حَوالَيْ ساعَةٍ واحِدَةٍ.', 'ساعَةٌ واحِدَةٌ عَلى الأَقَلِّ.'
    ]
  },
  'he-il': {
    voice: 'he', conjunction: 'וְ',
    offer: 'לְקַבָּלַת שִׂיחָה חוֹזֶרֶת תּוֹךְ שְׁמִירָה עַל מְקוֹמְכֶם בַּתּוֹר, הַקִּישׁוּ {key}.',
    callback: [
      'הַקִּישׁוּ 1 לְקַבָּלַת שִׂיחָה חוֹזֶרֶת לַמִּסְפָּר שֶׁמִּמֶּנּוּ אַתֶּם מִתְקַשְּׁרִים. הַקִּישׁוּ כּוֹכָבִית כְּדֵי לְהִשָּׁאֵר בַּתּוֹר.',
      'הַקִּישׁוּ 1 לְשִׁמּוּשׁ בַּמִּסְפָּר שֶׁמִּמֶּנּוּ אַתֶּם מִתְקַשְּׁרִים. הַקִּישׁוּ 2 לַהֲזָנַת מִסְפָּר אַחֵר וּבְסִיּוּם סוּלָמִית. הַקִּישׁוּ כּוֹכָבִית כְּדֵי לְהִשָּׁאֵר בַּתּוֹר.',
      'מִסְפַּר הַטֶּלֶפוֹן לַשִּׂיחָה הַחוֹזֶרֶת שֶׁהִזַּנְתֶּם הוּא.',
      'הַקִּישׁוּ 1 לְאִשּׁוּר הַמִּסְפָּר. הַקִּישׁוּ כּוֹכָבִית כְּדֵי לְהִשָּׁאֵר בַּתּוֹר.',
      'הַבַּקָּשָׁה נִרְשְׁמָה. נִתְקַשֵּׁר אֲלֵיכֶם כְּשֶׁיַּגִּיעַ תּוֹרְכֶם. לְהִתְרָאוֹת.',
      'הִגִּיעַ תּוֹרְכֶם. הַקִּישׁוּ 1 כְּדֵי לְדַבֵּר עִם נָצִיג.'
    ],
    queue: [
      'מְקוֹמְכֶם הַנּוֹכְחִי בַּתּוֹר הוּא.', 'מְקוֹמְכֶם הוּא.', 'בַּתּוֹר.',
      'יֵשׁ עֲלִיָּה בְּמִסְפַּר הַשִּׂיחוֹת.', 'זְמַן הַהַמְתָּנָה הַמְּשֹׁעָר הוּא.',
      'פָּחוֹת מִדַּקָּה אַחַת.', 'כַּחֲמֵשׁ דַּקּוֹת.', 'כְּעֶשֶׂר דַּקּוֹת.',
      'כַּחֲמֵשׁ עֶשְׂרֵה דַּקּוֹת.', 'כִּשְׁלוֹשִׁים דַּקּוֹת.', 'כְּאַרְבָּעִים וְחָמֵשׁ דַּקּוֹת.',
      'כְּשָׁעָה אַחַת.', 'לְפָחוֹת שָׁעָה אַחַת.'
    ]
  }
};

const callbackNames = ['menu-current', 'menu-alternate', 'number-readback', 'confirmation', 'success', 'returned-confirmation'];
const queueNames = ['your-current-position-is', 'you_are_at_position', 'in_the_queue', 'increase_in_call_volume', 'the_estimated_wait_time_is', 'less_than_1_minute', 'about_5_minutes', 'about_10_minutes', 'about_15_minutes', 'about_30_minutes', 'about_45_minutes', 'about_1_hour', 'at_least_1_hour'];

function catalog(locale) {
  const definition = definitions[locale];
  if (!definition) throw new Error('unsupported canonical locale');
  const prompts = [];
  const add = (id, text, kind = 'fixed') => prompts.push({id, text, kind});
  for (let key = 0; key <= 9; key++) add(`acdc-callback-offer-${key}`, definition.offer.replace('{key}', key));
  callbackNames.forEach((name, index) => add(`acdc-callback-${name}`, definition.callback[index]));
  queueNames.forEach((name, index) => add(`acdc-queue-${name}`, definition.queue[index]));
  if (locale === 'ar-sa' || locale === 'he-il') {
    add('acdc-number-and', definition.conjunction, 'conjunction');
    add('acdc-number-0', '0', 'number');
    // Three base-1000 groups cover the same nine-digit range as FS say modules.
    // Render each scaled group as a whole so dual/plural forms are synthesized
    // together; do not concatenate a coefficient with an invariant scale word.
    for (const scale of [1, 1000, 1000000]) {
      for (let coefficient = 1; coefficient <= 999; coefficient++) {
        const value = coefficient * scale;
        add(`acdc-number-${value}`, String(value), 'number');
      }
    }
  }
  if (locale === 'he-il') {
    const hebrew = require('./acdc-hebrew-phonemes.cjs');
    for (const entry of prompts) entry.synthesis_text = '[['+hebrew.prompt(entry.id)+']]';
  }
  return {locale, voice: definition.voice, prompts};
}

module.exports = {catalog, locales: Object.keys(definitions), definitions};
