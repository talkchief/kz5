#!/usr/bin/env bash
# Isolated safety/parse checks: no API, registrations, phone starts or services.
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=run-live-test-agents.sh
source "$script_dir/run-live-test-agents.sh"
test_dir=$(mktemp -d /tmp/kazoo-live-agent-tests.XXXXXX)
trap 'rm -f -- "$test_dir/input.csv" "$test_dir/parse.log"; rmdir -- "$test_dir"' EXIT

STATE=$(jq -n --arg owner "$OWNER" --arg account "$ACCOUNT_ID" '{
  schema_version:1, owner:$owner, account_id:$account,
  deployment_id:"11111111111111111111111111111111", realm:"example.invalid",
  queue_id:"22222222222222222222222222222222", queue_extension:"2000",
  api_base:"http://127.0.0.1:8000/v2", credentials_file:"/etc/kazoo/installer-secrets.env",
  sip_proxy_host:"127.0.0.1", sip_proxy_port:5060, sip_transport:"udp",
  protected_microsip_device_id:"33333333333333333333333333333333",
  agents:[range(1;31) as $i | {index:$i, extension:(1001+$i|tostring),
    user_id:(("00000000000000000000000000000000" + ($i|tostring))[-32:]),
    device_id:(("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" + ($i|tostring))[-32:]),
    sip_username:("livetest" + (1001+$i|tostring)), sip_password:"abcdef0123456789abcdef0123456789"}]
}')
validate_state
valid_state=$STATE
for change in '.account_id="ffffffffffffffffffffffffffffffff"' \
    '.owner="foreign"' '.queue_extension="+12025550100"' \
    '.agents[0].device_id=.protected_microsip_device_id' \
    '.agents[1].device_id=.agents[0].device_id' \
    '.agents[0].sip_password="bad;[exec]"' '.agents[0].extension="1001"' \
    '.api_base="https://foreign.invalid/v2"'; do
    STATE=$(jq "$change" <<<"$valid_state")
    if validate_state; then die 'Unsafe fixture manifest accepted'; fi
done
STATE=$valid_state
device_id=$(jq -r '.agents[0].device_id' <<<"$STATE")
owned_channel "$ACCOUNT_ID" "$device_id" "$PHONE_IP"
if owned_channel "$ACCOUNT_ID" "$device_id" 127.0.0.20 ||
   owned_channel ffffffffffffffffffffffffffffffff "$device_id" "$PHONE_IP" ||
   owned_channel "$ACCOUNT_ID" 33333333333333333333333333333333 "$PHONE_IP"; then
    die 'Unowned channel passed cleanup guard'
fi

timeout() { printf 'Address: %s\n' "$MOCK_CONTACT"; }
MOCK_CONTACT=sip:livetest1002@127.0.0.40:17100
contact_present 1
for MOCK_CONTACT in sip:livetest1002@127.0.0.40:171000 sip:livetest1002@127.0.0.20:17100 sip:livetest1001@127.0.0.40:17100; do
    if contact_present 1; then die 'Wrong contact accepted'; fi
done
unset -f timeout

# One dead phone must not tear down or log out the healthy 29. In-call repair
# is deferred, then only that child restarts after a complete zero-call proof.
for index in {1..30}; do PHONE_PIDS[index-1]=$((10000+index)); done
kill() { [[ $2 != 10002 ]]; }
contact_present() { [[ $1 != 2 ]]; }
no_active_calls() { return 1; }
start_phone() { repaired_index=$1; }
owned_helper() { die 'Runtime repair must not change agent login/pause status'; }
repaired_index=none
monitor_phones >/dev/null 2>&1
[[ $repaired_index == none ]]
no_active_calls() { return 0; }
monitor_phones >/dev/null 2>&1
[[ $repaired_index == 2 ]]
unset -f kill contact_present no_active_calls start_phone owned_helper

write_input 1 600 "$test_dir/input.csv"
[[ $(stat -c '%a' "$test_dir/input.csv") == 600 ]]
timeout 5 sipp 127.0.0.1:9 -sf "$script_dir/sip-tests/live-agent-register.xml" \
    -rxsf "$script_dir/sip-tests/agent-answer.xml" -inf "$test_dir/input.csv" \
    -i 127.0.0.41 -p 19999 -mi 127.0.0.41 -ci 127.0.0.41 -mp 48000 -m 0 -nostdin \
    >"$test_dir/parse.log" 2>&1
if rg -i 'parse error|Unable to load|Unknown element' "$test_dir/parse.log" >/dev/null; then
    die 'Mixed-mode SIPp scenario rejected'
fi
[[ $(rg -c 'REGISTER sip:' "$script_dir/sip-tests/live-agent-register.xml") == 2 ]]
if rg -n 'INVITE sip:|<send.*INVITE' "$script_dir/sip-tests/live-agent-register.xml" "$script_dir/sip-tests/agent-answer.xml" >/dev/null; then
    die 'Phone scenarios must not originate an INVITE'
fi
bash -n "$script_dir/run-live-test-agents.sh" "$script_dir/install-live-test-agents.sh"
shellcheck "$script_dir/run-live-test-agents.sh" "$script_dir/install-live-test-agents.sh"
bash "$script_dir/run-live-test-agents.sh" --dry-run >/dev/null
bash "$script_dir/install-live-test-agents.sh" --dry-run >/dev/null
unit=$(bash "$script_dir/install-live-test-agents.sh" --dry-run)
[[ $unit == *'Wants=kazoo-apps.service'* && $unit != *'Requires=kazoo-'* &&
   $unit != *'BindsTo=kazoo-'* && $unit != *'PartOf=kazoo-'* ]]
printf '%s\n' 'PASS live test phones: manifest scope, protected MicroSIP exclusion, exact contact/channel guards, individual dead-phone repair with active-call deferral/status preservation, private injection, mixed SIPp parse, receive-only scenarios, shell checks and dry runs'
