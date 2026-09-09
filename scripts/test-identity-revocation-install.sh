#!/usr/bin/env bash
# Pinned pristine source, real patch helper and actual module regressions.
set -Eeuo pipefail
umask 077
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$project_root"
test_dir=$(mktemp -d /tmp/kazoo-identity-install.XXXXXX)
test_ref=5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72
test_source=kazoo_auth/src/kz_auth_identity.erl
test_patch="$project_root/scripts/patches/kazoo-identity-authoritative-read.patch"
[[ $(git -C core rev-parse HEAD) == "$test_ref" ]]
mkdir "$test_dir/replay" "$test_dir/before" "$test_dir/after" "$test_dir/rejected"
git -C core archive "$test_ref" "$test_source" | tar -xf - -C "$test_dir/replay"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 2:2 +A 2'
export ERL_CRASH_DUMP="$test_dir/erl_crash.dump"
compile() {
    erlc -Werror -I core/kazoo_auth/src -I core/kazoo_auth/include -pa deps/lager/ebin \
        +'{parse_transform,lager_transform}' -o "$1" \
        "$test_dir/replay/$test_source" scripts/erlang-tests/kz_auth_identity_revocation_tests.erl
}
compile "$test_dir/before"
KAZOO_CONFIG="$project_root/rel/config-test.ini" erl -pa "$test_dir/before" -noshell \
    -eval 'application:ensure_all_started(lager), case eunit:test(kz_auth_identity_revocation_tests, [verbose]) of error -> halt(0); _ -> halt(1) end.' >"$test_dir/before.log" 2>&1
grep -Fq 'Failed: 6.' "$test_dir/before.log"
# Used by the actual installer helper extracted below.
# shellcheck disable=SC2034
DRY_RUN=false
log() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }
# shellcheck disable=SC1090
source <(sed -n '/^apply_required_source_patch() {$/,/^}$/p' scripts/install-kazoo5.sh)
apply_required_source_patch "$test_dir/replay" "$test_patch"
cp "$test_dir/replay/$test_source" "$test_dir/first.erl"
apply_required_source_patch "$test_dir/replay" "$test_patch"
cmp "$test_dir/first.erl" "$test_dir/replay/$test_source"
if (apply_required_source_patch "$test_dir/rejected" "$test_patch"); then exit 1; fi
git -C "$test_dir/replay" apply --reverse --check "$test_patch"
cmp "core/$test_source" "$test_dir/replay/$test_source"
compile "$test_dir/after"
KAZOO_CONFIG="$project_root/rel/config-test.ini" erl -pa "$test_dir/after" -noshell \
    -eval 'application:ensure_all_started(lager), case eunit:test(kz_auth_identity_revocation_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.' >"$test_dir/after.log" 2>&1
printf 'PASS six before-fail/after-pass cases, pristine installer apply/reapply/missing-source rejection; receipt=%s\n' "$test_dir"
