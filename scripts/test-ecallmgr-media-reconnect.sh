#!/usr/bin/env bash
# Offline regression for ecallmgr-media-reconnect-delay.patch. After a media server
# restart eCallMgr reconnected through fixed waits of 3 s before the first attempt,
# 3 s before the pinger's first check and 3 s again on node-up. FreeSWITCH accepts
# SIP a few seconds after its Erlang listener, so for about ten seconds Kamailio
# routed to a media server with no controller and calls got "486 Unable to Comply"
# (private lab, September 18, 2026). Works on private copies of the fetched source.
set -Eeuo pipefail
umask 077
mr_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
mr_patch="$mr_root/scripts/patches/ecallmgr-media-reconnect-delay.patch"
mr_integration="$mr_root/scripts/patches/ecallmgr-kazoo5-integration.patch"
mr_work=$(mktemp -d /tmp/kazoo-media-reconnect.XXXXXX)
trap 'rm -rf -- "$mr_work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
files=(src/node/ecallmgr_fs_nodes.erl src/node/ecallmgr_fs_pinger.erl)
# Rebuild the post-integration state of the two files from the pinned revision.
mkdir -p "$mr_work/tree/src/node"; git -C "$mr_work/tree" init -q .
for file in "${files[@]}"; do git -C "$mr_root/applications/ecallmgr" show "HEAD:$file" > "$mr_work/tree/$file"; done
git -C "$mr_work/tree" apply --include='src/node/ecallmgr_fs_nodes.erl' --include='src/node/ecallmgr_fs_pinger.erl' "$mr_integration" || \
    fail 'the integration patch no longer applies to the pinned node modules'
git -C "$mr_work/tree" apply --check "$mr_patch" || fail 'patch does not apply on top of the integration patch'
git -C "$mr_work/tree" apply "$mr_patch"
git -C "$mr_work/tree" apply --check --reverse "$mr_patch" || fail 'patch does not reverse: a repeat install would not recognise it'
# The property the stacking relies on: the integration patch is still recognised.
git -C "$mr_work/tree" apply --check --reverse --include='src/node/ecallmgr_fs_nodes.erl' --include='src/node/ecallmgr_fs_pinger.erl' "$mr_integration" || \
    fail 'with this patch applied the integration patch is no longer recognised as applied: repeat installs would fail'
printf 'PASS: stacks on the integration patch, reverses, and leaves the integration patch recognisable\n'
nodes="$mr_work/tree/src/node/ecallmgr_fs_nodes.erl"; pinger="$mr_work/tree/src/node/ecallmgr_fs_pinger.erl"
! grep -Fq 'timer:sleep(3 * ?MILLISECONDS_IN_SECOND)' "$nodes" || fail 'the fixed three-second connect wait is still there'
grep -Fq '<<"fs_node_connect_delay_ms">>, ?MILLISECONDS_IN_SECOND' "$nodes" || fail 'connect delay is not configurable with a one-second default'
grep -Fq "erlang:send_after(?MILLISECONDS_IN_SECOND, self(), 'check_node_status')" "$pinger" || fail 'the pinger still waits three seconds for its first check'
grep -Fq ',timeout = ?MILLISECONDS_IN_SECOND' "$pinger" || fail 'the pinger retry does not start at one second'
grep -Fq 'State#state{timeout=Timeout+?MILLISECONDS_IN_SECOND}' "$pinger" || fail 'the pinger must still back off for a node that stays away'
order=$(grep -n 'apply_kazoo_integration_patch ecallmgr\|ecallmgr-media-reconnect-delay.patch' "$mr_root/scripts/install-kazoo5.sh" | cut -d: -f1 | tr '\n' ' ')
read -r first second _ <<<"$order"; [[ -n ${second:-} && $first -lt $second ]] || fail 'installer must apply this patch after the integration patch'
printf 'PASS: one-second defaults, back-off kept, applied after the integration patch\nAll 2 media reconnect groups passed\n'
