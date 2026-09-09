#!/usr/bin/env bash
# Library-backed fixture provisioning, never an all-in-one readiness claim.
set -Eeuo pipefail
umask 077
[[ $EUID == 0 && $# == 0 && $(hostname) == kz5-stage-kazoo-apps ]] || exit 78
ip -o -4 addr show | grep -F '172.30.253.14/' >/dev/null || exit 78
export KAZOO_ACCEPTANCE_STATE_FILE=/etc/kazoo/distributed-acceptance-secrets.env
export KAZOO_ACCEPTANCE_AGENT_COUNT=3
[[ ! -e $KAZOO_ACCEPTANCE_STATE_FILE && ! -L $KAZOO_ACCEPTANCE_STATE_FILE ]] || exit 78
source /opt/kz5/scripts/test-kazoo-call-provision.sh
[[ $KAZOO_AMQP_HOST == 172.30.253.12 && $KAZOO_COUCHDB_HOST == 172.30.253.13 &&
   $KAZOO_PUBLIC_IP == 172.30.253.14 && $KAZOO_MASTER_ACCOUNT_REALM == installer-stage.invalid ]] || exit 78
for unit in kazoo-apps kazoo-stage-isolation; do
    systemctl is-active --quiet "$unit" || exit 78
done
# The owning host admitted all seven private roles and zero media channels.
# The normal provisioner's local-FS/local-Kamailio admission is intentionally
# not used on this apps-only server. No deployment configuration is rewritten.
KAZOO_PUBLIC_IP=172.30.253.17
load_acceptance_state
resolve_requested_agent_count
initialize_acceptance_state
expand_acceptance_agents
validate_acceptance_state
resolve_agent_range
authenticate_master
ensure_acceptance_account
provision_acceptance_resources
verify_acceptance_queue_wait
verify_acceptance_resources
AGENT_RANGE_START=1
AGENT_RANGE_END=$ACCEPTANCE_AGENT_COUNT
set_all_agent_statuses logout
set_all_agent_statuses login
# API readiness is cluster-facing; don't require every worker to be local to
# this node or call a local SUP listing a distributed ownership proof.
log 'PASS isolated distributed three-agent fixture provisioned; SIP/RTP and node ownership still require live acceptance'
