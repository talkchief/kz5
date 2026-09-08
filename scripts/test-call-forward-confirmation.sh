#!/usr/bin/env bash
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-cfwd-confirmation-test.XXXXXX)
trap 'rm -rf -- "$test_dir"' EXIT
mkdir "$test_dir/production" "$test_dir/test"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1' ERL_CRASH_DUMP=/dev/null
sources=(core/kazoo_media/src/kz_call_forward_confirmation.erl
 core/kazoo_documents/src/kzd_accounts.erl core/kazoo_endpoint/src/kz_endpoint_v4.erl
 core/kazoo_endpoint/src/kz_endpoint_v5.erl core/kazoo_directory/src/kz_directory_cfwd.erl
 core/kazoo_directory/src/kz_directory_failover.erl
 applications/crossbar/src/cb_account_call_forward_confirmation.erl applications/crossbar/src/modules/cb_accounts.erl)
args=(-I "$project_root/core/kazoo_media/src" -I "$project_root/core/kazoo_endpoint/src"
 -I "$project_root/core/kazoo_directory/src" -I "$project_root/core/kazoo_documents/src"
 -I "$project_root/applications/crossbar/src" -pa "$project_root/deps/lager/ebin" +'{parse_transform,lager_transform}')
cd "$project_root"
for file in "${sources[@]}"; do
 erlc -Werror +debug_info "${args[@]}" -o "$test_dir/production" "$file"
 erlc -DTEST +export_all +nowarn_export_all +debug_info "${args[@]}" -o "$test_dir/test" "$file"
done
erlc -Werror +debug_info -o "$test_dir/test" scripts/erlang-tests/call_forward_confirmation_tests.erl
erl -noshell -pa "$test_dir/test" -eval 'case eunit:test(call_forward_confirmation_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.'
printf '%s\n' 'PASS compiled production and direct v4/v5/directory/API confirmation tests; no live calls or account writes.'
