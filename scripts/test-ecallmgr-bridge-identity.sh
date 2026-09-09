#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
bridge_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bridge_mode=${1:-current}
[[ $# -le 1 && ( $bridge_mode == current || $bridge_mode == --baseline ) ]] || exit 64
bridge_output=$(mktemp -d /tmp/kazoo-bridge-identity.XXXXXXXX)
cd "$bridge_root"
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$bridge_root/deps:$bridge_root/core:$bridge_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP="$bridge_output/erl_crash.dump"
[[ $(git -C applications/ecallmgr rev-parse HEAD) == fb8eba201b41762ce8fae928c61bd5d22379a1bc ]] || exit 65
mkdir "$bridge_output/source"
git -C applications/ecallmgr archive HEAD src/ecallmgr_fs_channel.erl | tar -xf - -C "$bridge_output/source"
bridge_source="$bridge_output/source/src/ecallmgr_fs_channel.erl"
if [[ $bridge_mode == current ]]; then
    source <(sed -n '/^apply_required_source_patch() {$/,/^}$/p' scripts/install-kazoo5.sh)
    DRY_RUN=false
    log() { printf '%s\n' "$*"; }
    die() { printf '%s\n' "$*" >&2; exit 65; }
    apply_required_source_patch "$bridge_output/source" "$bridge_root/scripts/patches/ecallmgr-bridge-peer-identity.patch"
    apply_required_source_patch "$bridge_output/source" "$bridge_root/scripts/patches/ecallmgr-bridge-peer-identity.patch"
fi
printf 'Bridge identity evidence: %s\n' "$bridge_output"
erlc -Werror +debug_info -I applications/ecallmgr/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$bridge_output" "$bridge_source" \
    applications/ecallmgr/src/call_cmd/ecallmgr_call_command.erl
erlc -Werror +debug_info -I applications/ecallmgr/src -o "$bridge_output" \
    scripts/erlang-tests/ecallmgr_bridge_identity_tests.erl
erl -noshell -pa "$bridge_output" -eval '
    case eunit:test(ecallmgr_bridge_identity_tests,[verbose]) of ok->halt(0);_->halt(1) end.' | tee "$bridge_output/eunit.log"
