#!/usr/bin/env bash
# Test an explicitly reconstructed installer baseline, never staged language code.
# Usage: bash scripts/test-acdc-callback-announcements-baseline.sh /absolute/acdc/source-root
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
if [[ $# != 1 || $1 != /* || ! -d "$1/src" || ! -d "$1/include" ]]; then
    printf '%s\n' 'Supply one absolute reconstructed ACDC source root containing src/ and include/.' >&2
    exit 2
fi
baseline_source=$(cd -- "$1" && pwd -P)
if [[ -e "$baseline_source/src/acdc_language.erl" ]]; then
    printf '%s\n' 'Refusing a staged-language source tree as the installer baseline.' >&2
    exit 2
fi
test_dir=$(mktemp -d /tmp/kazoo-callback-announcements-baseline.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/acdc_announcements.beam" "$test_dir/acdc_announcements_sup.beam" \
        "$test_dir/acdc_queue_manager.beam" "$test_dir/acdc_callback_announcement_tests.beam" \
        "$test_dir/acdc_callback_announcement_baseline_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
source_files=("$baseline_source/src/acdc_announcements.erl"
    "$baseline_source/src/acdc_announcements_sup.erl" "$baseline_source/src/acdc_queue_manager.erl")
before_fingerprint=$(sha256sum -- "${source_files[@]}" | sha256sum | awk '{print $1}')
# First catch production-only warnings. Then enable test exports in the same
# private directory. No source or BEAM under the application is changed.
erlc -Werror -I "$baseline_source/src" -I "$baseline_source/include" \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" "${source_files[@]}"
erlc -DTEST +debug_info -Werror -I "$baseline_source/src" -I "$baseline_source/include" \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" "${source_files[@]}"
erlc -Werror -o "$test_dir" scripts/erlang-tests/acdc_callback_announcement_tests.erl \
    scripts/erlang-tests/acdc_callback_announcement_baseline_tests.erl
erl -pa "$test_dir" -noshell -eval '
    %% ERL_LIBS provides common dependencies, but never allow an already built
    %% staged acdc_language BEAM to hide a baseline dependency failure.
    Paths = [P || P <- code:get_path(), filelib:is_regular(filename:join(P, "acdc_language.beam"))],
    [code:del_path(P) || P <- Paths],
    code:purge(acdc_language), code:delete(acdc_language),
    non_existing = code:which(acdc_language),
    case eunit:test(acdc_callback_announcement_baseline_tests, [verbose]) of
        ok -> halt(0); _ -> halt(1)
    end.'
after_fingerprint=$(sha256sum -- "${source_files[@]}" | sha256sum | awk '{print $1}')
if [[ "$before_fingerprint" != "$after_fingerprint" ]]; then
    printf '%s\n' 'Baseline source changed while testing; result is not an immutable-source receipt.' >&2
    exit 1
fi
printf 'Baseline source fingerprint %s; staged acdc_language unavailable; no live writes.\n' "$after_fingerprint"
