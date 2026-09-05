#!/usr/bin/env bash
# All installer effects are mocked; the fake CLI cannot contact a broker.
# shellcheck disable=SC2034
set -Eeuo pipefail
export KAZOO_DEPLOYMENT_CONFIG="$KAZOO_TEST_WORK/absent-deployment.env"
# shellcheck source=/dev/null
source "$KAZOO_TEST_ROOT/scripts/install-kazoo5.sh"
IFS= read -r -d '' KAZOO_RABBITMQ_PASSWORD || :
export KAZOO_RABBITMQ_PASSWORD
export KAZOO_AMQP_URI="amqp://fixture:${KAZOO_RABBITMQ_PASSWORD}@remote.invalid/fixture"
export KAZOO_RABBITMQ_USER=fixture-user KAZOO_RABBITMQ_VHOST=fixture-vhost
export KAZOO_RABBITMQ_BIND=10.20.0.12 KAZOO_AMQP_PORT=5679
record() { printf '{"operation":"%s"}\n' "$1" >>"$KAZOO_TEST_TRACE"; }
dnf_install() { record package; }
download() { record download; }
run() { record run; }
write_file() { [[ $2 == /etc/rabbitmq/rabbitmq.conf ]]; local ignored; ignored=$(</dev/stdin); record config; }
service_enable_restart() { [[ $1 == rabbitmq-server.service ]]; record restart; }
timeout() {
    if [[ $1 == 120 ]]; then record health; return 0; fi
    [[ $# == 6 && $1 == --signal=TERM && $2 == --kill-after=5 && $3 == 30 && $4 == rabbitmqctl ]]
    record password-timeout
    shift 3
    if [[ ${KAZOO_TEST_HANG:-false} == true ]]; then
        # Exercise actual timeout/child termination without a 30-second test.
        command timeout --signal=TERM --kill-after=1 1 "$@"
    else
        command "$@"
    fi
}
assert_service() { [[ $1 == rabbitmq-server.service ]]; record service-check; }
ss() { printf 'LISTEN 0 128 10.20.0.12:25672 0.0.0.0:*\n'; }
rpm() {
    case ${*: -1} in rabbitmq-server) printf '%s\n' "$RABBITMQ_VERSION" ;;
        erlang) printf '%s\n' "$ERLANG_VERSION" ;; *) return 1 ;; esac
}
rabbitmq-diagnostics() {
    case ${*: -1} in ping) record diagnostics ;;
        listeners) printf 'Interface: 10.20.0.12, port: 5679, protocol: amqp\n' ;; *) return 1 ;; esac
}
rabbitmq-plugins() { [[ $* == 'list -e -m' ]]; printf 'rabbitmq_consistent_hash_exchange\n'; }
runuser() {
    [[ $* == '--user rabbitmq -- /usr/lib/rabbitmq/bin/rabbitmq-plugins list -e -m' ]]
    rabbitmq-plugins list -e -m
}
DRY_RUN=false
case $KAZOO_TEST_SCENARIO in
    create|update) install_rabbitmq ;;
    verify) verify_rabbitmq ;;
    dry-run) DRY_RUN=true; verify_rabbitmq ;;
    *)
        # Secret assignment/export occurs before tracing. Only the helper and
        # its caller boundary are under audit; no password is a function arg.
        if [[ ${KAZOO_TEST_XTRACE:-false} == true ]]; then
            exec 9>"$KAZOO_TEST_WORK/xtrace"
            export BASH_XTRACEFD=9
            set -x
            export SHELLOPTS
        fi
        set +e
        rabbitmqctl_password "$KAZOO_TEST_OPERATION"
        status=$?
        if [[ ${KAZOO_TEST_XTRACE:-false} == true && $- != *x* ]]; then exit 90; fi
        set +x
        # Subshell unexport/trace settings must not alter the caller's inputs.
        [[ -v KAZOO_RABBITMQ_PASSWORD && -v KAZOO_AMQP_URI ]] || exit 91
        [[ ${KAZOO_RABBITMQ_PASSWORD@a} == *x* && ${KAZOO_AMQP_URI@a} == *x* ]] || exit 92
        exit "$status"
        ;;
esac
