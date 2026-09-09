#!/usr/bin/env bash
# Isolated production compile + public-entry regression; never touches live BEAMs.
set -Eeuo pipefail
umask 077
[[ $# == 0 || ( $# == 1 && $1 == --baseline ) ]] || exit 2
location_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
location_output=$(mktemp -d /tmp/kazoo-location-recovery.XXXXXX)
cd "$location_root"
location_source=applications/ecallmgr/src/fetch/ecallmgr_fs_fetch_location.erl
location_patch=scripts/patches/ecallmgr-location-cache-recovery.patch
sha256sum "$location_source" "$location_patch" scripts/test-ecallmgr-location-recovery.sh \
    scripts/erlang-tests/ecallmgr_location_recovery_tests.erl > "$location_output/input-pins.sha256"
finish() {
    local location_status=$?
    trap - EXIT
    sha256sum --check --status "$location_output/input-pins.sha256" || location_status=99
    printf 'Location regression exit=%s; evidence %s\n' "$location_status" "$location_output"
    exit "$location_status"
}
trap finish EXIT
git -C applications/ecallmgr apply --reverse --check "$location_root/$location_patch"
mkdir -p "$location_output/src/fetch"
cp "$location_source" "$location_output/src/fetch/"
git -C "$location_output" apply --reverse "$location_root/$location_patch"
git -C "$location_output" apply --check "$location_root/$location_patch"
git -C "$location_output" apply "$location_root/$location_patch"
cmp "$location_source" "$location_output/src/fetch/ecallmgr_fs_fetch_location.erl"
if [[ ${1:-} == --baseline ]]; then
    git -C "$location_output" apply --reverse "$location_root/$location_patch"
fi
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$location_root/deps:$location_root/core:$location_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1' ERL_CRASH_DUMP=/dev/null
erlc -Werror +debug_info -I applications/ecallmgr/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$location_output" \
    "$location_output/src/fetch/ecallmgr_fs_fetch_location.erl"
erlc -Werror -o "$location_output" scripts/erlang-tests/ecallmgr_location_recovery_tests.erl
export KAZOO_LOCATION_OUTPUT="$location_output"
erl -pa "$location_output" -noshell -eval '
{module, ecallmgr_fs_fetch_location} = code:ensure_loaded(ecallmgr_fs_fetch_location),
Expected = filename:join(os:getenv("KAZOO_LOCATION_OUTPUT"), "ecallmgr_fs_fetch_location.beam"),
Expected = code:which(ecallmgr_fs_fetch_location),
case eunit:test(ecallmgr_location_recovery_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.' \
    2>&1 | tee "$location_output/eunit.log"
