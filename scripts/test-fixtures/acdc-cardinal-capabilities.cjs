'use strict';
// Synthetic evidence only: never publish this fixture as a runtime artifact.
const counts = {'en-us': 31, 'he-il': 131, 'fr-fr': 161, 'es-es': 53, 'ar-sa': 208};
function cardinalCapabilities(stage = 'source', pins = {}) {
    const installed = stage !== 'source', runtime = ['runtime', 'reviewed'].includes(stage), reviewed = stage === 'reviewed';
    return {schema_version: 2, backend_mode: 'prerecorded-cardinal-v1', generated_at: '2026-09-07T12:00:00Z',
        languages: Object.fromEntries(Object.entries(counts).map(([locale, count]) => [locale, {
            ready: runtime && reviewed, selection_ready: runtime, position: runtime, wait_time: runtime, callback: runtime,
            native_speaker_review: reviewed, numbers: 'prerecorded-cardinal', number_range: [0, 999999999],
            numeric_prompt_count: count, callback_prompt_count: 42,
            position_installed_verified: installed, callback_installed_verified: installed,
            position_runtime_verified: runtime, callback_runtime_verified: runtime, wait_time_runtime_verified: runtime,
            source_catalog_sha256: pins.catalog || 'a'.repeat(64), cardinal_map_sha256: pins[locale] || 'b'.repeat(64),
            fixed_map_sha256: pins.fixed || 'a316e74ff278ae53750781e57fe49fca0e61f50c626ef84278afc470fb02f974',
            installed_media_sha256: installed ? 'c'.repeat(64) : null,
            runtime_evidence_sha256: runtime ? 'd'.repeat(64) : null,
            native_review_sha256: reviewed ? 'e'.repeat(64) : null
        }]))};
}
module.exports = {cardinalCapabilities};
