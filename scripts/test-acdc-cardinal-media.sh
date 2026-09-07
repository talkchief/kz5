#!/usr/bin/env bash
# Private production and test BEAMs only. Root runs under the validation guard.
set -Eeuo pipefail
cardinal_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cardinal_build=$(mktemp -d /tmp/kazoo-cardinal-media.XXXXXX)
mkdir "$cardinal_build/production" "$cardinal_build/test"
trap 'printf "Private cardinal media artifacts: %s\n" "$cardinal_build"' EXIT
cd "$cardinal_root"
export ERL_LIBS="$cardinal_root/deps:$cardinal_root/core:$cardinal_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
inputs=(applications/acdc/src/acdc_cardinal_media.erl
        applications/acdc/src/acdc_cardinal_prompts.erl
        applications/acdc/src/acdc_gemini_prompts.erl
        applications/acdc/src/acdc_announcements.erl
        applications/acdc/src/acdc_cardinal_map.hrl
        applications/acdc/src/acdc_gemini_map.hrl
        scripts/erlang-tests/acdc_cardinal_media_tests.erl
        scripts/test-acdc-cardinal-media.sh
        scripts/acdc-cardinal-catalog.cjs
        scripts/import-acdc-gemini-cardinals.cjs
        applications/acdc/src/cardinal_maps/acdc_cardinal_he-il.hrl
        applications/acdc/src/cardinal_maps/acdc_cardinal_fr-fr.hrl
        applications/acdc/src/cardinal_maps/acdc_cardinal_es-es.hrl
        applications/acdc/src/cardinal_maps/acdc_cardinal_ar-sa.hrl
        applications/acdc/src/acdc_wait_time_media.erl)
before=$(sha256sum -- "${inputs[@]}" | sha256sum | cut -d ' ' -f 1)
# Pure authoring-source expectations only; no WAV, provider, approval or database
# operation. Synthetic EUnit metadata must never be mistaken for a release map.
export ACDC_CARDINAL_MEDIA_INVENTORY="$cardinal_build/inventory.term"
node > "$ACDC_CARDINAL_MEDIA_INVENTORY" <<'NODE'
const catalog = require('./scripts/acdc-cardinal-catalog.cjs');
const {INTROS} = require('./scripts/import-acdc-gemini-cardinals.cjs');
const binary = value => '<<' + JSON.stringify(value) + '>>';
const rows = catalog.REQUIRED_LOCALES.map(locale => {
  const intro = INTROS[locale];
  return '{' + binary(locale) + ',[' + catalog.plan(locale).map(p => binary(p.id)).join(',') + '],{'
    + [intro.canonical_id, intro.transcript_sha256, intro.wav_sha256].map(binary).join(',') + '}}';
});
process.stdout.write('[' + rows.join(',\n') + '].\n');
NODE
erlc -Werror -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$cardinal_build/production" \
    "${inputs[@]:0:4}" applications/acdc/src/acdc_wait_time_media.erl
erlc -DTEST +debug_info -Werror -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$cardinal_build/test" \
    "${inputs[@]:0:4}" applications/acdc/src/acdc_wait_time_media.erl
erlc -Werror -I applications/acdc/src -o "$cardinal_build/test" "${inputs[6]}"
erl -noshell -pa "$cardinal_build/test" \
    -eval 'case eunit:test(acdc_cardinal_media_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
after=$(sha256sum -- "${inputs[@]}" | sha256sum | cut -d ' ' -f 1)
[[ $before == "$after" ]] || { printf '%s\n' 'Cardinal media source changed during validation' >&2; exit 1; }
printf 'PASS cardinal media fixture; input SHA-256 %s\n' "$after"
