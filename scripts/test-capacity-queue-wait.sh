#!/usr/bin/bash
set -euo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_path=$test_dir/test-kazoo-call-provision.sh
eval "$(sed -n '/^verify_acceptance_queue_wait() {/,/^}/p' "$source_path")"
eval "$(sed -n '/^readonly ACCEPTANCE_QUEUE_WAIT_SECONDS=/p' "$source_path")"
eval "$(sed -n '/^readonly CAPACITY_HOLD_MS=/p' "$test_dir/test-kazoo-calls.sh")"
((ACCEPTANCE_QUEUE_WAIT_SECONDS >= CAPACITY_HOLD_MS / 1000 + 60))
ACCEPTANCE_ACCOUNT_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
ACCEPTANCE_QUEUE_ID=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
die() { printf '%s\n' "$*" >&2; exit 1; }
acceptance_api() {
    [[ "$*" == "GET accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID" ]] || exit 91
    printf '%s\n' "$response_fixture"
}
for timeout in 600 900; do
    response_fixture=$(jq -cn --arg id "$ACCEPTANCE_QUEUE_ID" --argjson timeout "$timeout" \
        '{data:{id:$id,name:"Acceptance Queue 2000",connection_timeout:$timeout}}')
    verify_acceptance_queue_wait
done
for timeout in 120 599 null '"600"'; do
    response_fixture=$(jq -cn --arg id "$ACCEPTANCE_QUEUE_ID" --argjson timeout "$timeout" \
        '{data:{id:$id,name:"Acceptance Queue 2000",connection_timeout:$timeout}}')
    if (verify_acceptance_queue_wait) 2>/dev/null; then die "Accepted unsafe timeout $timeout"; fi
done
for wrong in id name; do
    response_fixture=$(jq -cn --arg id "$ACCEPTANCE_QUEUE_ID" --arg wrong "$wrong" \
        '{data:{id:$id,name:"Acceptance Queue 2000",connection_timeout:600}} | .data[$wrong]="other"')
    if (verify_acceptance_queue_wait) 2>/dev/null; then die "Accepted wrong $wrong"; fi
done
printf 'PASS capacity queue wait budget, typed policy, identity and read-only preflight; no API calls\n'
