#!/usr/bin/env bash
# Offline private compilation only. No shared ebin, live API or daemon changes.
set -Eeuo pipefail
umask 077
members_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
members_output=$(mktemp -d /tmp/kazoo-members-devices-test.XXXXXX)
trap 'members_status=$?; printf "Members/devices offline result: exit=%s evidence=%s\n" "$members_status" "$members_output"' EXIT
cd "$members_root"
export ERL_LIBS="$members_root/deps:$members_root/core:$members_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
members_source=scripts/erlang-candidates/members_devices
members_runtime=applications/crossbar/src/modules/cb_members.erl
members_auth_sources=(
    applications/crossbar/src/cb_context.erl
    applications/crossbar/src/crossbar_bindings.erl
    applications/crossbar/src/crossbar_util.erl
    applications/crossbar/src/crossbar_auth.erl
    applications/crossbar/src/modules/cb_token_auth.erl
    applications/crossbar/src/modules/cb_simple_authz.erl
    applications/crossbar/src/modules/cb_token_restrictions.erl
    applications/crossbar/src/modules/cb_users.erl
    applications/crossbar/src/modules/cb_devices.erl
    core/kazoo_auth/src/kz_auth.erl
    core/kazoo_auth/src/kz_auth_jwt.erl
    core/kazoo_auth/src/kz_auth_scope.erl
)
members_tests=("$members_source/cb_members_tests.erl" "$members_source/cb_members_auth_review_tests.erl"
    "$members_source/cb_members_real_auth_tests.erl")
sha256sum scripts/test-members-devices-candidate.sh applications/crossbar/src/api_util.erl \
    "$members_runtime" "${members_auth_sources[@]}" "${members_tests[@]}" > "$members_output/source-pins.sha256"
erlc +debug_info +warn_missing_spec -Werror -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$members_output" applications/crossbar/src/api_util.erl
# Deliberately NOT -DTEST: cb_token_restrictions has test-only lookup/hierarchy
# branches. JWT signature/expiry, claims, scope matching and authz run real code.
for members_auth_source in "${members_auth_sources[@]}"; do
    erlc +debug_info -Werror -I applications/crossbar/src -pa deps/lager/ebin \
        +'{parse_transform,lager_transform}' -o "$members_output" "$members_auth_source"
done
erlc +debug_info +warn_export_all +warn_unused_import +warn_unused_vars +warn_missing_spec -Werror \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$members_output" "$members_runtime"
erlc -DTEST +debug_info -Werror -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$members_output" "$members_runtime" "${members_tests[@]}"
erl -pa "$members_output" -noshell -eval 'case eunit:test([cb_members_tests,cb_members_auth_review_tests,cb_members_real_auth_tests],[verbose]) of ok -> halt(0); _ -> halt(1) end.' \
    2>&1 | tee "$members_output/eunit.log"
sha256sum --check "$members_output/source-pins.sha256"
