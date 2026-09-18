#!/usr/bin/env bash
# Actual argument/timing functions only; no live SIP, files or account writes.
# Shared-library functions consume SOAK_SECONDS; do not execute the live main.
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
KAZOO_CALLS_LIBRARY=true source "$test_dir/test-kazoo-calls.sh"
for bad in 0 179 7201 9000 0180 -1 180.5 abc; do
    if (SOAK_SECONDS=$bad; validate_soak) >/dev/null 2>&1; then exit 1; fi
done
for seconds in 181 600 1800; do
    (
        parse_args --stress --stages 30 --queued-excess 0 --soak-seconds "$seconds"
        validate_soak
        [[ $(capacity_hold_ms) == $(((seconds + 120) * 1000)) ]]
    )
done
for args in '--all --stages 30 --queued-excess 0' '--stress --stages 1,30 --queued-excess 0' '--stress --stages 30 --queued-excess 5'; do
    # Intentional word splitting of fixed fixture args, never operator input.
    # shellcheck disable=SC2086
    if (parse_args $args --soak-seconds 1800; validate_soak) >/dev/null 2>&1; then exit 1; fi
done
# The owner's production target: 100 concurrent answered calls held two hours.
(
    parse_args --stress --capacity 100 --stages 100 --queued-excess 0 --soak-seconds 7200
    validate_soak
    [[ $(capacity_hold_ms) == 7320000 ]]
)
for capacity in 0 29 101 1000 030 abc; do
    if (parse_args --stress --capacity "$capacity"; validate_capacity) >/dev/null 2>&1; then exit 1; fi
done
# A raised capacity moves the extended-soak stage with it; the old stage is refused.
if (parse_args --stress --capacity 100 --stages 30 --queued-excess 0 --soak-seconds 7200; validate_soak) >/dev/null 2>&1; then exit 1; fi
if (parse_args --stress --stages 30 --queued-excess 0 --soak-seconds 7201; validate_soak) >/dev/null 2>&1; then exit 1; fi
validate_soak
[[ $MAX_ANSWERED_CALLS == 30 && $(capacity_hold_ms) == 360000 ]]
printf 'PASS actual extended-soak argument bounds and timing up to 100 calls for 7200s; default capacity/queue limits unchanged\n'
