#!/usr/bin/env bash
# Trusted foreground validation only; this is a resource guard, not a sandbox.
# No caller environment, alternate manager, or arbitrary unit property is forwarded.
set +x

validation_error() {
    printf 'Validation refused: %s\n' "$2" >&2
    return "$1"
}

validation_usage() {
    printf '%s\n' 'Usage: run-kazoo-validation.sh [--memory-mib 128..384] [--reserve-mib 512..4096] [--runtime-sec 10..1800] -- /absolute/command [arguments...]'
}

validation_number() {
    [[ $1 =~ ^[1-9][0-9]{0,3}$ ]] && ((10#$1 >= $2 && 10#$1 <= $3))
}

validation_stat() {
    LC_ALL=C /usr/bin/stat -c '%u:%g:%a:%F:%h:%s' -- "$1"
}

validation_secure_directory() {
    local path=$1 exact_mode=${2:-} metadata owner group mode kind links bytes
    [[ -d $path && ! -L $path ]] || return 1
    metadata=$(validation_stat "$path") || return 1
    IFS=: read -r owner group mode kind links bytes <<<"$metadata"
    [[ $owner == 0 && $group == 0 && $kind == directory && $mode =~ ^[0-7]{3,4}$ ]] || return 1
    (( (8#$mode & 0022) == 0 )) || return 1
    [[ -z $exact_mode || $mode == "$exact_mode" ]]
}

validation_secure_lockfile() {
    local path=$1 metadata owner group mode kind links bytes
    [[ -f $path && ! -L $path ]] || return 1
    metadata=$(validation_stat "$path") || return 1
    IFS=: read -r owner group mode kind links bytes <<<"$metadata"
    [[ $owner == 0 && $group == 0 && $mode == 600 && $kind == 'regular empty file' && $links == 1 && $bytes == 0 ]]
}

validation_prepare_lock() {
    local parent=$1 directory=$2 lockfile=$2/validation.lock
    validation_secure_directory "$parent" || return 1
    [[ $directory == "$parent/kazoo-validation" ]] || return 1
    if [[ ! -e $directory && ! -L $directory ]]; then
        /usr/bin/mkdir -m 0700 -- "$directory" || return 1
    fi
    validation_secure_directory "$directory" 700 || return 1
    if [[ ! -e $lockfile && ! -L $lockfile ]]; then
        # Never truncate a preexisting file or replace another process's lock.
        (umask 077; set -o noclobber; : >"$lockfile") || return 1
    fi
    validation_secure_lockfile "$lockfile" || return 1
    printf '%s\n' "$lockfile"
}

validation_mem_available() {
    local source=$1 key value unit extra found=0 available=
    [[ -r $source ]] || return 1
    while read -r key value unit extra; do
        if [[ $key == MemAvailable: ]]; then
            ((found+=1))
            [[ $value =~ ^[0-9]{1,12}$ && $unit == kB && -z $extra ]] || return 1
            available=$((10#$value))
        fi
    done <"$source"
    [[ $found == 1 ]] || return 1
    printf '%s\n' "$available"
}

validation_require_memory() {
    local required=$1 source=$2 available
    available=$(validation_mem_available "$source") || {
        validation_error 69 'MemAvailable cannot be verified'; return;
    }
    ((available >= required)) || validation_error 69 'insufficient MemAvailable for cap plus reserve'
}

validation_limits() {
    local unit=$1 memory_bytes=$2 membership=$3 cgroup_root=$4
    local line count=0 expected="0::/system.slice/$unit" directory
    local memory swap oom_group tasks quota period extra
    [[ $unit =~ ^kazoo-validation-[0-9a-f-]{36}\.service$ && $memory_bytes =~ ^[1-9][0-9]{1,9}$ ]] || return 1
    while IFS= read -r line; do
        [[ $line == "$expected" ]] || return 1
        ((count+=1))
    done <"$membership"
    [[ $count == 1 ]] || return 1
    directory=$cgroup_root/system.slice/$unit
    IFS= read -r memory <"$directory/memory.max" || return 1
    IFS= read -r swap <"$directory/memory.swap.max" || return 1
    IFS= read -r oom_group <"$directory/memory.oom.group" || return 1
    IFS= read -r tasks <"$directory/pids.max" || return 1
    read -r quota period extra <"$directory/cpu.max" || return 1
    [[ $memory == "$memory_bytes" && $swap == 0 && $oom_group == 1 && $tasks == 128 && $quota == 50000 && $period == 100000 && -z $extra ]]
}

validation_worker_source() {
    declare -f validation_error validation_mem_available validation_require_memory validation_limits
    printf '%s\n' 'set +x' 'set -euo pipefail' \
        '[[ $# -ge 4 ]] || exit 64' \
        'unit=$1; memory_bytes=$2; required_kib=$3; shift 3' \
        '[[ $required_kib =~ ^[1-9][0-9]{1,9}$ ]] || exit 64' \
        'validation_limits "$unit" "$memory_bytes" /proc/self/cgroup /sys/fs/cgroup || { validation_error 78 "effective cgroup limits are not the required hard limits"; exit $?; }' \
        'validation_require_memory "$required_kib" /proc/meminfo || exit $?' \
        'exec -- "$@"'
}

validation_host() {
    local controllers controller executable
    [[ $(/usr/bin/id -u) == 0 ]] || { validation_error 77 'root is required'; return; }
    for executable in /usr/bin/bash /usr/bin/env /usr/bin/flock /usr/bin/mkdir /usr/bin/stat /usr/bin/systemd-run /usr/bin/timeout; do
        [[ -x $executable ]] || { validation_error 69 'a required fixed-path system tool is unavailable'; return; }
    done
    [[ -d /run/systemd/system && -r /sys/fs/cgroup/cgroup.controllers ]] || {
        validation_error 69 'local systemd and unified cgroup v2 are required'; return;
    }
    IFS= read -r controllers </sys/fs/cgroup/cgroup.controllers || return 69
    for controller in cpu memory pids; do
        [[ " $controllers " == *" $controller "* ]] || {
            validation_error 69 'a required cgroup controller is unavailable'; return;
        }
    done
}

validation_flock() { /usr/bin/flock "$@"; }

validation_nonce() {
    local nonce
    IFS= read -r nonce </proc/sys/kernel/random/uuid || return 1
    [[ $nonce =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || return 1
    printf '%s\n' "$nonce"
}

validation_transport() {
    local runtime=$1; shift
    # Bound the client too, including an unavailable/hung manager. The unit's
    # independent runtime limit and service-held lock survive client loss.
    /usr/bin/timeout --signal=TERM --kill-after=10s "$((runtime+45))s" \
        /usr/bin/env -i PATH=/usr/bin:/bin LANG=C \
        SYSTEMD_LOG_LEVEL=err SYSTEMD_LOG_TARGET=console SYSTEMD_BUS_TIMEOUT=15s \
        /usr/bin/systemd-run "$@"
}

validation_main() (
    set +x
    set -euo pipefail
    umask 077
    local memory=384 reserve=768 runtime=900 value option seen=' ' separated=false
    while (($#)); do
        case $1 in
            --) separated=true; shift; break ;;
            --help) (($# == 1)) || { validation_error 64 'help does not accept a command'; return; }; validation_usage; return 0 ;;
            --memory-mib|--reserve-mib|--runtime-sec)
                option=$1
                [[ $seen != *" $option "* && $# -ge 2 ]] || { validation_error 64 'missing or duplicate bounded option'; return; }
                seen+="$option "
                value=$2
                case $option in
                    --memory-mib) validation_number "$value" 128 384 || { validation_error 64 'memory must be 128 through 384 MiB'; return; }; memory=$value ;;
                    --reserve-mib) validation_number "$value" 512 4096 || { validation_error 64 'reserve must be 512 through 4096 MiB'; return; }; reserve=$value ;;
                    --runtime-sec) validation_number "$value" 10 1800 || { validation_error 64 'runtime must be 10 through 1800 seconds'; return; }; runtime=$value ;;
                esac
                shift 2 ;;
            *) validation_error 64 'unsupported option; use bounded options then --'; return ;;
        esac
    done
    [[ $separated == true && $# -gt 0 && $1 == /* && -f $1 && -x $1 ]] || {
        validation_error 64 'an absolute executable after -- is required'; return;
    }
    validation_host || return $?
    local lockfile lock_fd required_kib memory_bytes nonce unit working_directory worker result
    lockfile=$(validation_prepare_lock /run /run/kazoo-validation) || {
        validation_error 73 'lock directory/file is not protected and root-owned'; return;
    }
    exec {lock_fd}<>"$lockfile"
    validation_flock --exclusive --nonblock --conflict-exit-code 75 "$lock_fd" || {
        validation_error 75 'another validation owns the global lock'; return;
    }
    required_kib=$(((memory+reserve)*1024))
    memory_bytes=$((memory*1024*1024))
    validation_require_memory "$required_kib" /proc/meminfo || return $?
    nonce=$(validation_nonce) || { validation_error 69 'cannot generate a safe transient unit identity'; return; }
    unit=kazoo-validation-$nonce.service
    working_directory=$(pwd -P)
    worker=$(validation_worker_source)
    # The service takes the same nonblocking lock and repeats memory admission.
    # Racing launchers may start a tiny guarded service, but only one payload
    # can run. Keeping the lock solely in this shell would be unsafe on SIGKILL.
    validation_flock --unlock "$lock_fd"
    exec {lock_fd}>&-
    if validation_transport "$runtime" \
        --system --no-ask-password --quiet --wait --pipe --collect \
        --service-type=exec --slice=system.slice --unit="$unit" \
        '--description=Kazoo bounded validation' --working-directory="$working_directory" \
        --property=MemoryAccounting=yes --property=MemoryMax="${memory}M" \
        --property=MemorySwapMax=0 --property=OOMPolicy=kill \
        --property=CPUAccounting=yes --property=CPUQuota=50% --property=CPUQuotaPeriodSec=100ms \
        --property=TasksAccounting=yes --property=TasksMax=128 \
        --property=RuntimeMaxSec="${runtime}s" --property=TimeoutStartSec=15s \
        --property=TimeoutStopSec=10s --property=KillMode=control-group \
        --property=SendSIGKILL=yes --property=Delegate=no --property=ProtectControlGroups=yes \
        -- /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C \
        /usr/bin/flock --exclusive --nonblock --conflict-exit-code 75 \
        "$lockfile" /usr/bin/bash -c "$worker" kazoo-validation-worker \
        "$unit" "$memory_bytes" "$required_kib" "$@"; then
        result=0
    else
        result=$?
    fi
    return "$result"
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    validation_main "$@"
fi
