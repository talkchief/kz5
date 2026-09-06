#!/usr/bin/env bash
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$project_root"
node --check scripts/test-channel-monitor-live.cjs
node scripts/test-channel-monitor-fixture.cjs
node scripts/test-fixtures/monitor-audio.test.cjs
work=$(mktemp -d /tmp/kazoo-monitor-sipp-parse.XXXXXX)
cleanup() {
    rm -f -- "$work/input.csv" "$work/parse.log"
    rmdir -- "$work"
}
trap cleanup EXIT
umask 077
printf 'SEQUENTIAL\ndummy;[authentication username=dummy password=dummy];example.invalid;1002;120000;0;/dev/null\n' >"$work/input.csv"
for scenario in monitor-customer.xml monitor-agent.xml monitor-supervisor.xml; do
    if ! timeout 5 sipp -ci 127.0.0.1 127.0.0.1:9 -sf "scripts/sip-tests/$scenario" -inf "$work/input.csv" \
        -i 127.0.0.51 -p 18999 -mi 127.0.0.51 -mp 49990 -m 0 -nostdin >"$work/parse.log" 2>&1; then
        printf 'FAIL: SIPp parse did not exit successfully for %s\n' "$scenario" >&2
        exit 1
    fi
    if /usr/bin/grep -Eq 'parse error|Unable to load|Unknown element|Variable .* referenced.*(not declared|[01] times)' "$work/parse.log"; then
        printf 'FAIL: SIPp scenario parse %s\n' "$scenario" >&2
        exit 1
    fi
done
printf 'PASS: three SIPp monitor scenarios parse with zero calls; no live traffic or API writes\n'
