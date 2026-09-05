#!/usr/bin/env bash
# Generated artifacts and all scanner fault injections stay in a private tree.
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$script_dir/install-kazoo5.sh"
fixture_dir=$(mktemp -d /tmp/kazoo-production-beam-test.XXXXXX)
fixture_root="$fixture_dir/tree"
KAZOO_ROOT=$fixture_root
DRY_RUN=false
export ERL_FLAGS='+S 1:1 +A 1'
export ERL_CRASH_DUMP=/dev/null

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
cleanup() {
    # Explicit files only; never recursively remove a directory reached by a link.
    rm -f -- "$fixture_root/core/normal/ebin/beam_build_marker.beam" \
        "$fixture_root/applications/testing/ebin/beam_build_marker.beam" \
        "$fixture_root/deps/valued/ebin/beam_build_marker.beam" \
        "$fixture_root/core/normal/ebin/corrupt.beam" \
        "$fixture_root/core/normal/ebin/normal.app" \
        "$fixture_root/core/normal/priv/couchdb/views/public.json" \
        "$fixture_root/core/normal/priv/couchdb/views/linked.json" \
        "$fixture_root/core/normal/priv/couchdb/schemas/public.json" \
        "$fixture_root/core/normal/priv/private-config.json" \
        "$fixture_dir/outside/private.json" \
        "$fixture_root/core/linked" "$fixture_dir/outside/ebin/beam_build_marker.beam"
    rmdir -- "$fixture_root/core/normal/priv/couchdb/views" \
        "$fixture_root/core/normal/priv/couchdb/schemas" \
        "$fixture_root/core/normal/priv/couchdb" "$fixture_root/core/normal/priv"
    rmdir -- "$fixture_root/core/normal/ebin" "$fixture_root/core/normal" \
        "$fixture_root/applications/testing/ebin" "$fixture_root/applications/testing" \
        "$fixture_root/deps/valued/ebin" "$fixture_root/deps/valued" \
        "$fixture_root/core" "$fixture_root/applications" "$fixture_root/deps" \
        "$fixture_root" "$fixture_dir/outside/ebin" "$fixture_dir/outside" "$fixture_dir"
}
trap cleanup EXIT
mkdir -p "$fixture_root/core/normal/ebin" "$fixture_root/applications/testing/ebin" \
    "$fixture_root/deps/valued/ebin" "$fixture_dir/outside/ebin" \
    "$fixture_root/core/normal/priv/couchdb/views" "$fixture_root/core/normal/priv/couchdb/schemas"
erlc -o "$fixture_root/core/normal/ebin" "$script_dir/test-fixtures/beam_build_marker.erl"
normal_hash=$(sha256sum "$fixture_root/core/normal/ebin/beam_build_marker.beam")
[[ -z $(kazoo_test_compiled_beams) ]] || fail 'ordinary production module marked as TEST'
verify_kazoo_production_beams

# A root build with umask 077 must leave code/public definitions readable to
# the unprivileged runtime, without relaxing private config or symlink targets.
for artifact in core/normal/ebin/normal.app \
    core/normal/priv/couchdb/views/public.json core/normal/priv/couchdb/schemas/public.json \
    core/normal/priv/private-config.json; do
    install -m 0600 "$script_dir/test-fixtures/beam_build_marker.erl" "$fixture_root/$artifact"
done
install -m 0600 "$script_dir/test-fixtures/beam_build_marker.erl" "$fixture_dir/outside/private.json"
ln -s "$fixture_dir/outside/private.json" "$fixture_root/core/normal/priv/couchdb/views/linked.json"
chmod 0600 "$fixture_root/core/normal/ebin/beam_build_marker.beam"
prepare_kazoo_runtime_artifact_permissions
for artifact in core/normal/ebin/normal.app core/normal/ebin/beam_build_marker.beam \
    core/normal/priv/couchdb/views/public.json core/normal/priv/couchdb/schemas/public.json; do
    [[ $(stat -c '%a' "$fixture_root/$artifact") == 644 ]] || fail 'public runtime artifact is unreadable'
done
[[ $(stat -c '%a' "$fixture_root/core/normal/priv/private-config.json") == 600 ]] || fail 'private config permissions changed'
[[ $(stat -c '%a' "$fixture_dir/outside/private.json") == 600 ]] || fail 'permission repair followed a symlink'
if (KAZOO_ROOT=/; prepare_kazoo_runtime_artifact_permissions) >/dev/null 2>&1; then
    fail 'permission repair accepted a broad filesystem root'
fi

erlc -DTEST -o "$fixture_root/applications/testing/ebin" "$script_dir/test-fixtures/beam_build_marker.erl"
erlc -DTEST=0 -o "$fixture_root/deps/valued/ebin" "$script_dir/test-fixtures/beam_build_marker.erl"
scan=$(kazoo_test_compiled_beams) || fail 'valid module scan failed'
[[ $scan == *"$fixture_root/applications/testing/ebin/beam_build_marker.beam"* ]] || fail 'DTEST module omitted'
[[ $scan == *"$fixture_root/deps/valued/ebin/beam_build_marker.beam"* ]] || fail 'valued DTEST macro omitted'
if (verify_kazoo_production_beams) >/dev/null 2>&1; then fail 'production verification accepted TEST modules'; fi
remove_test_compiled_kazoo_beams
[[ ! -e $fixture_root/applications/testing/ebin/beam_build_marker.beam && \
   ! -e $fixture_root/deps/valued/ebin/beam_build_marker.beam ]] || fail 'TEST artifacts not removed'
[[ $(sha256sum "$fixture_root/core/normal/ebin/beam_build_marker.beam") == "$normal_hash" ]] || fail 'ordinary production module changed'
verify_kazoo_production_beams

cp "$script_dir/test-fixtures/beam_build_marker.erl" "$fixture_root/core/normal/ebin/corrupt.beam"
if kazoo_test_compiled_beams >/dev/null 2>&1; then fail 'corrupt BEAM accepted by scanner'; fi
if (verify_kazoo_production_beams) >/dev/null 2>&1; then fail 'corrupt BEAM accepted by verifier'; fi
rm -- "$fixture_root/core/normal/ebin/corrupt.beam"

# The verifier invokes this fault-injection function indirectly.
# shellcheck disable=SC2317
if (kazoo_test_compiled_beams() { return 42; }; verify_kazoo_production_beams) >/dev/null 2>&1; then
    fail 'scanner process failure was swallowed by verifier'
fi
# shellcheck disable=SC2317
if (kazoo_test_compiled_beams() { return 42; }; remove_test_compiled_kazoo_beams) >/dev/null 2>&1; then
    fail 'scanner process failure was swallowed before removal'
fi

erlc -DTEST -o "$fixture_dir/outside/ebin" "$script_dir/test-fixtures/beam_build_marker.erl"
ln -s "$fixture_dir/outside" "$fixture_root/core/linked"
if (remove_test_compiled_kazoo_beams) >/dev/null 2>&1; then fail 'symlink escape was not rejected'; fi
[[ -f $fixture_dir/outside/ebin/beam_build_marker.beam ]] || fail 'scanner deleted a BEAM outside configured source root'
rm -- "$fixture_root/core/linked"

log 'PASS production BEAM detection, macro values, bounded cleanup, scanner errors and symlink safety'
