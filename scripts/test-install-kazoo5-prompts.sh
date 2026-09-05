#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
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
printf 'PASS: complete prompt attachment gates, non-mutating dry run, preserved existing sounds\n'
