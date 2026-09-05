#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output_dir=${1:-"$project_root/scripts/assets/acdc-callback-prompts/en-us"}

for command_name in espeak-ng sox soxi install cmp mktemp; do
    command -v "$command_name" >/dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$command_name" >&2
        exit 1
    }
done

case "$output_dir" in
    /*) ;;
    *) output_dir="$PWD/$output_dir" ;;
esac

umask 022
install -d -m 0755 -- "$output_dir"
work_dir=$(mktemp -d /tmp/kazoo-acdc-callback-prompts.XXXXXX)
cleanup() {
    find "$work_dir" -type f -delete
    rmdir -- "$work_dir"
}
trap cleanup EXIT

media_ids=()
prompt_texts=()
for entry_key in {0..9}; do
    media_ids+=("acdc-callback-offer-$entry_key")
    prompt_texts+=("To request a callback while keeping your place in the queue, press $entry_key.")
done

media_ids+=(
    acdc-callback-menu-current
    acdc-callback-menu-alternate
    acdc-callback-number-readback
    acdc-callback-confirmation
    acdc-callback-success
    acdc-callback-returned-confirmation
    acdc-queue-your-current-position-is
)

prompt_texts+=(
    'Press 1 to receive a callback at the phone number you are calling from. Press star to stay in the queue.'
    'Press 1 to use the phone number you are calling from. Press 2 to enter a different number followed by the pound key. Press star to stay in the queue.'
    'The callback number you entered is.'
    'Press 1 to confirm this callback number. Press star to stay in the queue.'
    'Your callback is registered. We will call you when you reach the front of the queue. Goodbye.'
    'Your callback is ready. Press 1 to connect to an agent.'
    'Your current position is.'
)

for index in "${!media_ids[@]}"; do
    media_id=${media_ids[$index]}
    source_wav="$work_dir/$media_id.source.wav"
    rendered_wav="$work_dir/$media_id.wav"
    destination="$output_dir/$media_id.wav"

    espeak-ng -v en-us -s 150 -a 120 -w "$source_wav" -- "${prompt_texts[$index]}"
    sox "$source_wav" -r 8000 -c 1 -b 16 -e signed-integer "$rendered_wav" \
        gain -3 highpass 80 lowpass 3600 gain -n -3

    sample_rate=$(soxi -r "$rendered_wav")
    channels=$(soxi -c "$rendered_wav")
    bits=$(soxi -b "$rendered_wav")
    duration=$(soxi -D "$rendered_wav")
    [[ $sample_rate == 8000 && $channels == 1 && $bits == 16 ]] || {
        printf 'invalid telephony WAV format for %s\n' "$media_id" >&2
        exit 1
    }
    awk -v duration="$duration" 'BEGIN { exit !(duration >= 0.25 && duration <= 20.0) }' || {
        printf 'prompt duration outside 0.25..20 seconds for %s\n' "$media_id" >&2
        exit 1
    }

    if [[ ! -f $destination ]] || ! cmp -s -- "$rendered_wav" "$destination"; then
        install -m 0644 -- "$rendered_wav" "$destination"
    fi
    printf '%s\t%s\n' "$media_id" "$destination"
done
