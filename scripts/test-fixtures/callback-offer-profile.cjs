'use strict';
// Finite live acceptance profiles; not arbitrary timing supplied by a caller.
const assert = require('node:assert/strict');
function timingProfile(mode, profile = 'default') {
    assert(['legacy', 'gemini', 'prerecorded'].includes(mode), 'Unexpected offer audio mode');
    assert(['default', 'interval-30', 'dual-prerecorded'].includes(profile), 'Unexpected offer timing profile');
    if (mode === 'prerecorded' || profile === 'dual-prerecorded') {
        assert(mode === 'prerecorded' && profile === 'dual-prerecorded', 'Exact prerecorded profile required');
        return {name: profile, initial: 30, interval: 30, offers: [30, 60], positions: [45, 75],
            positionInitial: 45, duration: 86, earliest: 85, latest: 89, silenceUntil: 29};
    }
    if (profile === 'interval-30') {
        assert.equal(mode, 'gemini', 'Thirty-second profile requires immutable Gemini audio');
        return {name: profile, initial: 30, interval: 30, offers: [30, 60],
            duration: 76, earliest: 75, latest: 82, silenceUntil: 29};
    }
    return {name: profile, initial: 3, interval: 15, offers: [3, 18, 33],
        duration: 46, earliest: 45, latest: 52, silenceUntil: 2};
}
module.exports = {timingProfile};
