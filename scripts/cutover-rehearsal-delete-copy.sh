#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Delete the production copy held by the cutover rehearsal lab (owner's retention:
# one week). Removes only containers that carry the rehearsal lab's owner label,
# with their storage, plus the copy's credentials and the production sizing file.
# Count-only receipts and install logs are kept. Development host only.
set -Eeuo pipefail
((EUID == 0)) || { echo 'Root required' >&2; exit 1; }
ip -o -4 address show | grep -Eq 'inet 10\.1\.0\.44/' || { echo 'Only development44 allowed' >&2; exit 1; }
readonly owner=distributed-install-v1-cutover
receipt=/root/kz5-cutover-copy-deleted-$(date -u +%Y%m%dT%H%M%SZ).txt
readonly receipt
umask 077
{
    printf 'deletion started %s\n' "$(date -u +%FT%TZ)"
    mapfile -t guests < <(podman ps -a --filter "label=io.talkchief.kazoo.acceptance=${owner}" --format '{{.Names}}')
    for guest in "${guests[@]}"; do
        [[ $guest == kz5-cutover-* ]] || { printf 'REFUSED unexpected guest name %s\n' "$guest"; exit 1; }
        podman rm --force --volumes "$guest" >/dev/null
        printf 'removed guest %s with its storage\n' "$guest"
    done
    rm -f -- /root/kz5-cutover-couchdb.key /root/kz5-cutover-sizing-*.json /root/kz5-cutover-sizing-*.err
    printf 'removed the copy credentials and the production sizing file\n'
    remaining=$(podman ps -a --filter "label=io.talkchief.kazoo.acceptance=${owner}" --format '{{.Names}}' | wc -l)
    printf 'remaining rehearsal guests: %s\n' "$remaining"
    if [[ $remaining == 0 ]]; then printf 'RESULT deleted\n'; else printf 'RESULT incomplete\n'; exit 1; fi
} | tee "$receipt"
