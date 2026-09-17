#!/usr/bin/env bash
# Offline regression: kazoo_web should_validate_dns defaults to false in source,
# schema, API documentation and the installed database. No service, database or
# network access; the real installer functions run against stubs.
set -Eeuo pipefail
umask 077
dns_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
dns_installer="$dns_root/scripts/install-kazoo5.sh"
dns_work=$(mktemp -d /tmp/kazoo-dns-default.XXXXXX)
trap 'rm -rf -- "$dns_work"' EXIT
dns_pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { dns_pass=$((dns_pass + 1)); printf 'PASS: %s\n' "$*"; }
function_body() { sed -n "/^$1() {\$/,/^}\$/p" "$dns_installer"; }

# Clean pinned files from each checkout's HEAD, never the patched worktree.
replay() {
    local name=$1 checkout=$2 patch=$3; shift 3
    local repo="$dns_work/$name" path
    mkdir -p "$repo"; git -C "$repo" init -q
    for path in "$@"; do
        mkdir -p "$repo/$(dirname "$path")"
        git -C "$checkout" show "HEAD:$path" > "$repo/$path"
    done
    git -C "$repo" add -A
    git -C "$repo" -c user.name=t -c user.email=t@invalid commit -qm pinned
    (
        DRY_RUN=false
        log() { printf '%s\n' "$*"; }
        die() { printf '%s\n' "$*" >&2; exit 1; }
        eval "$(function_body apply_required_source_patch)"
        [[ $(apply_required_source_patch "$repo" "$patch") == Applied* ]] || exit 11
        [[ $(apply_required_source_patch "$repo" "$patch") == *'already applied'* ]] || exit 12
        printf 'drift\n' >> "$repo/$1"; sed -i 's/should_validate_dns/should_validate_dnx/' "$repo/$1"
        # die exits its shell: isolate the expected refusal.
        if ( apply_required_source_patch "$repo" "$patch" ) >/dev/null 2>&1; then exit 13; fi
    ) || fail "$name patch replay (code $?)"
}
replay core "$dns_root/core" "$dns_root/scripts/patches/kazoo-dns-validation-default.patch" \
    kazoo_schemas/src/kz_json_schema_extensions.erl
pass 'core patch applies to pinned source, reapplies idempotently and refuses drifted source'
replay crossbar "$dns_root/applications/crossbar" "$dns_root/scripts/patches/crossbar-dns-validation-default.patch" \
    priv/couchdb/schemas/system_config.kazoo_web.json priv/api/swagger.json priv/oas3/oas3-schemas.yml
pass 'crossbar patch applies to pinned source, reapplies idempotently and refuses drifted source'

# Re-create the patched result and inspect exact values.
rm -rf "$dns_work/core" "$dns_work/crossbar"
for spec in "core:$dns_root/core:kazoo-dns-validation-default.patch:kazoo_schemas/src/kz_json_schema_extensions.erl" \
            "crossbar:$dns_root/applications/crossbar:crossbar-dns-validation-default.patch:priv/couchdb/schemas/system_config.kazoo_web.json priv/api/swagger.json priv/oas3/oas3-schemas.yml"; do
    IFS=: read -r name checkout patch paths <<<"$spec"
    mkdir -p "$dns_work/$name"; git -C "$dns_work/$name" init -q
    for path in $paths; do
        mkdir -p "$dns_work/$name/$(dirname "$path")"; git -C "$checkout" show "HEAD:$path" > "$dns_work/$name/$path"
    done
    git -C "$dns_work/$name" apply "$dns_root/scripts/patches/$patch"
done
grep -Fq "kapps_config:is_true(<<\"kazoo_web\">>, <<\"should_validate_dns\">>, 'false')" \
    "$dns_work/core/kazoo_schemas/src/kz_json_schema_extensions.erl" || fail 'compiled default is not false'
! grep -Fq "<<\"should_validate_dns\">>, 'true')" "$dns_work/core/kazoo_schemas/src/kz_json_schema_extensions.erl" || \
    fail 'a true default remains in source'
[[ $(jq '.properties.should_validate_dns.default' "$dns_work/crossbar/priv/couchdb/schemas/system_config.kazoo_web.json") == false ]] || \
    fail 'schema default is not false'
[[ $(jq '[.. | objects | select(has("should_validate_dns")) | .should_validate_dns.default] | unique | tostring' \
    "$dns_work/crossbar/priv/api/swagger.json") == '"[false]"' ]] || fail 'API documentation default is not false'
jq -e . "$dns_work/crossbar/priv/api/swagger.json" >/dev/null || fail 'patched swagger is not valid JSON'
grep -A1 "^    'should_validate_dns':\$" "$dns_work/crossbar/priv/oas3/oas3-schemas.yml" | grep -Fxq "      'default': false" || \
    fail 'OAS3 catalog source default is not false'
# The tracked, published catalog is generated from that source.
[[ $(jq '[.. | objects | select(has("should_validate_dns")) | .should_validate_dns.default] | unique | tostring' \
    "$dns_root/scripts/assets/api-docs/openapi.json") == '"[false]"' ]] || fail 'published API catalog default is not false'
pass 'patched source, schema and API documentation all default to false'

# Installer wiring.
bash -n "$dns_installer"
sources=$(function_body ensure_kazoo_sources)
grep -Fq 'patches/kazoo-dns-validation-default.patch' <<<"$sources" || fail 'core patch is not a required installer patch'
grep -Fq 'patches/crossbar-dns-validation-default.patch' <<<"$sources" || fail 'crossbar patch is not a required installer patch'
grep -Fq 'ensure_dns_validation_disabled' <<<"$(function_body install_kazoo_apps)" || fail 'installation does not store false'
verify=$(function_body verify_kazoo_apps)
grep -Fq 'verify_dns_validation_disabled' <<<"$verify" || fail 'verification omits the DNS default gate'
! grep -Eq 'ensure_dns_validation_disabled|set_default' <<<"$verify" || fail '--verify-only path must never write configuration'
pass 'both patches are required; install stores false; verification only reads'

# Real functions against a stubbed sup. SUP_MODE selects the simulated node.
run_case() {
    local mode=$1 fn=$2
    (
        log() { printf '%s\n' "$*"; }
        die() { printf '%s\n' "$*" >&2; exit 1; }
        timeout() { while [[ $1 != sup ]]; do shift; done; shift; SUP_ARGS="$*" sup_stub; }
        sup_stub() {
            printf '%s\n' "$SUP_ARGS" >> "$dns_work/calls.$mode"
            case "$mode:$SUP_ARGS" in
                *:*set_default*) [[ $mode == set-fails ]] && return 1
                                 [[ $mode == set-unconfirmed ]] && { echo '{error,conflict}'; return 0; }
                                 echo '{ok,{[{<<"should_validate_dns">>,false}]}}' ;;
                *:*flush*) [[ $mode == flush-fails ]] && return 1; echo ok ;;
                stays-true:*get_is_true*) echo true ;;
                read-fails:*get_is_true*) return 1 ;;
                *:*get_is_true*) echo false ;;
            esac
        }
        eval "$(function_body dns_validation_setting)"
        eval "$(function_body verify_dns_validation_disabled)"
        eval "$(function_body ensure_dns_validation_disabled)"
        "$fn"
    )
}
: > "$dns_work/calls.ok"
run_case ok ensure_dns_validation_disabled | grep -Fq 'PASS kazoo_web hostname DNS validation is disabled' || fail 'successful install path'
grep -q 'set_default.*should_validate_dns.*false' "$dns_work/calls.ok" || fail 'false was not stored'
grep -q 'flush kazoo_web' "$dns_work/calls.ok" || fail 'configuration cache was not flushed'
: > "$dns_work/calls.verify"
( cp /dev/null "$dns_work/calls.ok2"; run_case ok2 verify_dns_validation_disabled >/dev/null )
! grep -q 'set_default\|flush' "$dns_work/calls.ok2" || fail 'verification wrote configuration'
pass 'install stores false, flushes and rereads; verification performs reads only'
for mode in set-fails set-unconfirmed flush-fails stays-true read-fails; do
    : > "$dns_work/calls.$mode"
    if run_case "$mode" ensure_dns_validation_disabled >/dev/null 2>&1; then fail "install accepted $mode"; fi
done
: > "$dns_work/calls.stays-true"
if run_case stays-true verify_dns_validation_disabled >/dev/null 2>&1; then fail 'verification accepted true'; fi
pass 'failed, unconfirmed, unflushed, unreadable and still-true results all refuse'
printf 'All %d DNS validation default groups passed\n' "$dns_pass"
