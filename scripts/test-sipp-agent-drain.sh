#!/usr/bin/bash
# Run the actual shutdown helper with virtual time and synthetic child/stat data.
set -euo pipefail
source_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test-kazoo-calls.sh
eval "$(sed -n '/^stop_waiting_agents_checked() {/,/^}/p' "$source_path")"
AGENT_PIDS=(1001 1002) RUN_DIR=/fixture
die() { printf '%s\n' "$*" >&2; exit 1; }
sleep() { SECONDS=$((SECONDS + $1)); }
agent_stats_totals() {
    case $fixture in
        failed) printf '2 1\n' ;;
        excess) printf '4 0\n' ;;
        missing) return 1 ;;
        *) if ((SECONDS < 2)); then printf '2 0\n'; else printf '3 0\n'; fi ;;
    esac
}
stat_value() { if ((SECONDS < 2)); then printf 1; else printf 0; fi; }
kill() {
    [[ $1 == -0 || $1 == -USR1 ]] || exit 91
    ((SECONDS >= 2)) || exit 92
    signals+=1
}
wait_checked() { [[ $fixture != child_failed ]] || die 'child failure retained'; waits+=1; }
fixture=delayed SECONDS=0 signals= waits=
stop_waiting_agents_checked test 3
[[ $signals == 1111 && $waits == 11 ]]
for fixture in failed excess missing child_failed; do
    SECONDS=0
    if (stop_waiting_agents_checked test 3) 2>/dev/null; then die "Accepted $fixture"; fi
done
printf 'PASS final-pause wait, no early signal, failed/excess/missing counters and child failure preservation\n'
