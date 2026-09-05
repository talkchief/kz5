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
grep -Fq 'Would render English-US callback prompts, import missing system prompts' <<<"$output" || fail 'prompt dry run omitted installation'
grep -Fq 'dnf_install espeak-ng sox' "$SCRIPT_DIR/install-kazoo5.sh" || fail 'callback speech dependencies omitted'
grep -Fq 'generate-acdc-callback-prompts.sh" "$callback_dir"' "$SCRIPT_DIR/install-kazoo5.sh" || fail 'callback audio generation omitted'
output=$(install_freeswitch_sounds)
grep -Fq 'rsync -a --ignore-existing' <<<"$output" || fail 'FreeSWITCH sound installation would overwrite existing files'
output=$(KAZOO_COUCHDB_HOST=database.example.invalid KAZOO_COUCHDB_PORT=15984 install_acdc_language_packs)
grep -Fq 'EN/AR/HE/ES/FR packs into configured CouchDB database.example.invalid:15984' <<<"$output" || \
    fail 'language pack installation lost its standalone CouchDB endpoint'
grep -Fq 'does not require local FreeSWITCH or publish runtime readiness' <<<"$output" || \
    fail 'media installation incorrectly implies local FS or runtime readiness'
declare -f install_kazoo_apps | grep -Fq install_acdc_language_packs || fail 'Kazoo apps installer omits language media'
if declare -f install_nodejs_toolchain | grep -Eq 'nginx|freeswitch'; then
    fail 'standalone media tooling unexpectedly installs a web/media server'
fi
if validate_acdc_language_receipt <<<'{"schema_version":1,"owner":"kazoo5-acdc-media-importer","runtime_ready":false,"languages":{}}'; then
    fail 'empty language import receipt accepted'
fi
printf 'PASS: complete prompt attachment gates, non-mutating dry run, preserved existing sounds\n'
