'use strict';
// Offline comparison with the reviewed authoring catalog. Never runtime TTS.
const assert = require('node:assert/strict');
const catalog = require('../acdc-cardinal-catalog.cjs');
const {cases} = require('./acdc-cardinal-en-parity.cjs');
const values = cases().map(item => item.number);
for (const [locale, maximum] of [['es-es', 14], ['fr-fr', 8], ['he-il', 11], ['ar-sa', 9]]) {
    for (const number of values) {
        const roles = catalog.tokens(number, locale);
        assert(roles.length > 0 && roles.length <= maximum);
        process.stdout.write('{<<"' + locale + '">>,' + number + ',' + maximum + ',[' +
            roles.map(role => '<<"' + role + '">>').join(',') + ']}.\n');
    }
}
