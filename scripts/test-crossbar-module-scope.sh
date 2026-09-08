#!/usr/bin/env bash
# Isolated production-module tests for split-role installer configuration scope.
set -Eeuo pipefail
umask 077
scope_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
scope_mode=${1:-current}
[[ $# -le 1 && ( $scope_mode == current || $scope_mode == --baseline ) ]] || exit 64
scope_output=$(mktemp -d /tmp/kazoo-module-scope.XXXXXXXX)
cd "$scope_root"
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$scope_root/deps:$scope_root/core:$scope_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP="$scope_output/erl_crash.dump"
scope_source=applications/crossbar/src/crossbar_maintenance.erl
scope_patch="$scope_root/scripts/patches/crossbar-module-autoload-scope.patch"
[[ $(git -C applications/crossbar rev-parse HEAD) == 2ac862830f9b626d2170d08daf1991b0ca33dba7 ]] || exit 65
if [[ $scope_mode == --baseline ]]; then
    mkdir "$scope_output/baseline"
    git -C applications/crossbar archive HEAD src/crossbar_maintenance.erl | tar -xf - -C "$scope_output/baseline"
    scope_source="$scope_output/baseline/src/crossbar_maintenance.erl"
else
    mkdir "$scope_output/replay"
    git -C applications/crossbar archive HEAD src/crossbar_maintenance.erl | tar -xf - -C "$scope_output/replay"
    source <(sed -n '/^apply_required_source_patch() {$/,/^}$/p' scripts/install-kazoo5.sh)
    DRY_RUN=false
    log() { printf '%s\n' "$*"; }
    die() { printf '%s\n' "$*" >&2; exit 65; }
    apply_required_source_patch "$scope_output/replay" "$scope_patch"
    cmp "$scope_source" "$scope_output/replay/src/crossbar_maintenance.erl"
    apply_required_source_patch "$scope_output/replay" "$scope_patch"
    cmp "$scope_source" "$scope_output/replay/src/crossbar_maintenance.erl"
fi
sha256sum "$scope_source" "$scope_patch" scripts/install-kazoo5.sh scripts/erlang-tests/crossbar_module_scope_tests.erl > "$scope_output/inputs.sha256"
printf 'Configuration-scope evidence: %s\n' "$scope_output"
erlc -Werror +debug_info -I applications/crossbar/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$scope_output" "$scope_source"
erlc -Werror +debug_info -o "$scope_output" scripts/erlang-tests/crossbar_module_scope_tests.erl
erl -noshell -pa "$scope_output" -eval '
    {module,crossbar_maintenance}=code:ensure_loaded(crossbar_maintenance),
    case eunit:test(crossbar_module_scope_tests,[verbose]) of ok->halt(0);_->halt(1) end.' | tee "$scope_output/eunit.log"
sha256sum --status --check "$scope_output/inputs.sha256"
printf '%s\n' 'PASS public production start/stop calls with controlled configuration persistence. No live database/node/HTTP or concurrent-writer acceptance.'
