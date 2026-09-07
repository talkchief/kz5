'use strict';
// Offline fixture authoring only. Runtime Erlang does not invoke JavaScript.
const assert = require('node:assert/strict');
const catalog = require('../acdc-cardinal-catalog.cjs');
const boundaries = [0, 1, 2, 10, 11, 19, 20, 21, 29, 30, 31, 99, 100, 101, 110, 121, 199, 200, 500, 700, 900, 999];
function cases() {
    const values = [];
    for (let number = 0; number <= 999; number++) {
        for (const scale of [1, 1000, 1000000]) values.push(number * scale);
    }
    for (const million of boundaries) for (const thousand of boundaries) for (const unit of boundaries) {
        values.push(million * 1000000 + thousand * 1000 + unit);
    }
    for (let number = 0; number <= 999; number++) {
        values.push(number * 1000000 + ((number * 37) % 1000) * 1000 + ((number * 91) % 1000));
    }
    return values.map(number => {
        const roles = catalog.tokens(number, 'en-us');
        assert(roles.length > 0 && roles.length <= 14);
        for (const role of roles) assert(/^acdc-cardinal-v1-(?:number-(?:[0-9]|1[0-9]|[2-9]0)|hundred|thousand|million)$/.test(role));
        return {number, roles};
    });
}
module.exports = {cases};
if (require.main === module) {
    assert.equal(process.argv.length, 2, 'Usage: acdc-cardinal-en-parity.cjs (Erlang terms on stdout)');
    for (const {number, roles} of cases()) {
        process.stdout.write('{' + number + ',[' + roles.map(role => '<<"' + role + '">>').join(',') + ']}.\n');
    }
}
