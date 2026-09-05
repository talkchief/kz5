#!/usr/bin/env bash
# Isolated compile/tests only: never contacts or loads code into a running node.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
keep_artifacts=false
[[ $# == 0 || ($# == 1 && $1 == --keep-artifacts) ]] || { printf 'Use --keep-artifacts or no options\n' >&2; exit 2; }
[[ $# == 0 ]] || keep_artifacts=true
test_dir=$(mktemp -d /tmp/kazoo-sup-audit-test.XXXXXX)
cleanup() {
    if [[ $keep_artifacts == true ]]; then
        printf 'SUP private production artifact: %s/production/sup.beam\n' "$test_dir"
    else
        rm -f -- "$test_dir/production/sup.beam" "$test_dir/sup.beam" "$test_dir/sup_audit_redaction_tests.beam" \
            "$test_dir/replay/sup/src/sup.erl"
        rmdir -- "$test_dir/replay/sup/src" "$test_dir/replay/sup" "$test_dir/replay" "$test_dir/production" "$test_dir"
    fi
}
trap cleanup EXIT
mkdir -m 0700 "$test_dir/production" "$test_dir/replay"
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
# Replay the dedicated patch against the pinned core source without fetching,
# changing the checkout, or including unrelated pending core changes.
git -C core archive HEAD sup/src/sup.erl | tar -xf - -C "$test_dir/replay"
patch_file="$project_root/scripts/patches/kazoo-sup-audit-redaction.patch"
git -C "$test_dir/replay" apply --check "$patch_file"
git -C "$test_dir/replay" apply "$patch_file"
git -C "$test_dir/replay" apply --reverse --check "$patch_file"
if git -C "$test_dir/replay" apply --check "$patch_file" 2>/dev/null; then
    printf 'Patch unexpectedly applies twice\n' >&2; exit 1
fi
git -C core apply --reverse --check "$patch_file"
# Production build includes the same logging parse transform as make/kz.mk.
erlc -Werror +debug_info -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$test_dir/production" core/sup/src/sup.erl
# Direct logger calls make exact log arguments observable without live handlers.
erlc -Werror +debug_info -o "$test_dir" core/sup/src/sup.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/sup_audit_redaction_tests.erl
erl -pa "$test_dir" -noshell -eval 'case eunit:test(sup_audit_redaction_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.'
sha256sum core/sup/src/sup.erl "$test_dir/production/sup.beam"
