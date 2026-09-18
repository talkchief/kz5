#!/usr/bin/env bash
# Text regression for the post-boot verifier. On September 18, 2026 its one-shot
# unit started the lab guests with a bare "podman start": conmon stayed in the
# unit's cgroup and was killed when the unit ended, leaving nine guests running
# without a monitor. Reproduced and fixed natively with a throwaway container
# (bare start: monitor gone; own scope: monitor alive). Reads text only.
set -Eeuo pipefail
vb_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
vb="$vb_root/scripts/verify-dev-stack-after-boot.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
bash -n "$vb"
[[ $(grep -c 'podman start' "$vb") == 1 ]] || fail 'guests must be started in one place only'
grep -Fq 'systemd-run --quiet --scope --slice=machine.slice podman start "$1"' "$vb" || fail 'a guest must start in its own scope, outside the unit'
[[ $(grep -c 'start_guest "\$guest"' "$vb") == 3 ]] || fail 'all three start groups must use start_guest'
grep -Fq 'lab guests have no monitor that outlives this unit' "$vb" || fail 'the receipt must fail when a guest has no surviving monitor'
grep -Fq "port mapper is not the socket-activated epmd.service" "$vb" && grep -Fq '/usr/local/libexec/kazoo5-stack-health' "$vb" && \
    grep -Fq 'broker node name pin is missing or wrong' "$vb" || fail 'the receipt must judge the port mapper, functional health and the broker pin'
grep -Fq 'ExecStartPost=/usr/bin/systemctl disable' "$vb" || fail 'the verifier must disarm itself after one boot'
! grep -Eq 'systemctl (restart|stop) (kazoo|rabbitmq|couchdb)|set-hostname|setenforce' "$vb" || fail 'the verifier must never reconfigure the main stack'
printf 'PASS: guests start in their own scope, a missing monitor fails the receipt, one boot only, main stack untouched\nAll 1 post-boot verifier groups passed\n'
