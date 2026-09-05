#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2016
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
export KAZOO_DEPLOYMENT_CONFIG=/tmp/kazoo5-prompt-test-no-deployment
source "$SCRIPT_DIR/install-kazoo5.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
valid='{"rows":[{"key":"en-us/test","doc":{"_attachments":{"test.wav":{"length":42}}}}]}'
validate_prompt_documents 1 <<<"$valid" || fail 'valid prompt attachments rejected'
if validate_prompt_documents 2 <<<"$valid"; then fail 'incomplete prompt result accepted'; fi
for invalid in \
    '{"rows":[{"key":"en-us/test","error":"not_found"}]}' \
    '{"rows":[{"key":"en-us/test","value":{"deleted":true},"doc":{"_attachments":{"test.wav":{"length":42}}}}]}' \
    '{"rows":[{"key":"en-us/test","doc":{}}]}' \
    '{"rows":[{"key":"en-us/test","doc":{"_attachments":{}}}]}' \
    '{"rows":[{"key":"en-us/test","doc":{"_attachments":{"test.wav":{"length":0}}}}]}'; do
    if validate_prompt_documents 1 <<<"$invalid"; then fail 'missing, deleted or empty prompt accepted'; fi
done
DRY_RUN=true
output=$(install_kazoo_prompts)
grep -Fq 'Would import missing pinned English-US system prompts and verify every audio attachment; no synthetic ACDC generation' <<<"$output" || fail 'prompt dry run omitted pinned official prompts'
official_source=$(declare -f install_kazoo_prompts)
for expected in 'prepare_kazoo_sounds' 'kazoo_media_maintenance import_prompts' 'prompt_documents' 'verify_kazoo_prompts'; do
    grep -Fq "$expected" <<<"$official_source" || fail "official prompt protection omitted: $expected"
done
if grep -Eq 'espeak|generate-acdc-|callback_dir' <<<"$official_source"; then
    fail 'ordinary prompt installer still generates synthetic ACDC defaults'
fi
source_preparation=$(declare -f prepare_kazoo_sounds)
grep -Fq 'https://github.com/2600hz/kazoo-sounds.git' <<<"$source_preparation" || fail 'official prompt source changed'
grep -Fq '"$KAZOO_SOUNDS_REF"' <<<"$source_preparation" || fail 'official prompt revision is not pinned'
[[ $KAZOO_SOUNDS_REF =~ ^[0-9a-f]{40}$ ]] || fail 'official prompt revision is not an exact commit'
output=$(install_freeswitch_sounds)
grep -Fq 'rsync -a --ignore-existing' <<<"$output" || fail 'FreeSWITCH sound installation would overwrite existing files'
output=$(KAZOO_COUCHDB_HOST=database.example.invalid KAZOO_COUCHDB_PORT=15984 install_acdc_language_packs)
grep -Fq '165 checked-in Gemini EN/AR/HE/ES/FR fixed/callback-digit assets into configured CouchDB database.example.invalid:15984' <<<"$output" || \
    fail 'language pack installation lost its standalone CouchDB endpoint'
grep -Fq 'requires no provider key, generation call, eSpeak, or local FreeSWITCH; it does not publish runtime or full-position readiness' <<<"$output" || \
    fail 'media installation incorrectly implies local FS or runtime readiness'
apps_source=$(declare -f install_kazoo_apps)
[[ $apps_source == *install_acdc_language_packs*build_kazoo* ]] || fail 'voice verification does not precede mapped application build/activation'
language_source=$(declare -f install_acdc_language_packs)
for expected in 'import-acdc-gemini-voices.cjs' '--plan --all-locales' '--import --all-locales' '--verify-only --all-locales' 'validate_acdc_language_receipt'; do
    grep -Fq -- "$expected" <<<"$language_source" || fail "immutable media gate omitted: $expected"
done
if grep -Eq 'generate-acdc-|dnf_install espeak|language-capabilities' <<<"$language_source"; then
    fail 'immutable media installation still generates speech or publishes language readiness'
fi
if declare -f install_nodejs_toolchain | grep -Eq 'nginx|freeswitch'; then
    fail 'standalone media tooling unexpectedly installs a web/media server'
fi
if validate_acdc_language_receipt <<<'{"schema_version":1,"owner":"kazoo5-acdc-media-importer","runtime_ready":false,"languages":{}}'; then
    fail 'empty language import receipt accepted'
fi
printf 'PASS: pinned official attachment gates, immutable Gemini import ordering, non-mutating dry run, preserved existing sounds\n'
