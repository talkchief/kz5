#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2034,SC2154
# Deployment persistence and HTTPS validation regressions; no service changes.
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo5-deployment-test.XXXXXX)
export KAZOO_DEPLOYMENT_CONFIG="$test_dir/deployment.env"
unset KAZOO_AMQP_HOST KAZOO_RABBITMQ_PASSWORD KAZOO_MASTER_ACCOUNT_REALM \
    KAZOO_MASTER_ADMIN_USER KAZOO_MASTER_ADMIN_PASSWORD
cleanup() {
    rm -f -- "$test_dir/deployment.env" "$test_dir/installer-secrets.env" \
        "$test_dir/explicit-secrets.env" \
        "$test_dir/server.key" "$test_dir/server.crt" "$test_dir/other.key"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
# shellcheck source=install-kazoo5.sh
source "$SCRIPT_DIR/install-kazoo5.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

if ((EUID == 0)); then
    # Ten bytes intentionally produces padded base64, exercising preservation
    # of trailing '=' characters while the state line is parsed.
    KAZOO_AMQP_HOST=mq.example
    KAZOO_RABBITMQ_PASSWORD='a-password-with-$(literal)-text'
    save_deployment_config >/dev/null
    [[ $(stat -c '%a' "$KAZOO_DEPLOYMENT_CONFIG") == 600 ]] || fail 'saved configuration permissions'
    unset KAZOO_AMQP_HOST KAZOO_RABBITMQ_PASSWORD
    load_deployment_config
    [[ $KAZOO_AMQP_HOST == mq.example ]] || fail 'remote host was not restored'
    [[ $KAZOO_RABBITMQ_PASSWORD == 'a-password-with-$(literal)-text' ]] || fail 'saved values did not round trip literally'
    KAZOO_AMQP_HOST=mq2.example.net
    load_deployment_config
    [[ $KAZOO_AMQP_HOST == mq2.example.net ]] || fail 'explicit setting did not override saved value'
    chmod 0644 "$KAZOO_DEPLOYMENT_CONFIG"
    if (load_deployment_config) >/dev/null 2>&1; then fail 'world-readable settings were accepted'; fi
    chmod 0400 "$KAZOO_DEPLOYMENT_CONFIG"
    if (load_deployment_config) >/dev/null 2>&1; then fail 'non-0600 settings were accepted'; fi
    chmod 0600 "$KAZOO_DEPLOYMENT_CONFIG"

    KAZOO_INSTALLER_SECRETS="$test_dir/installer-secrets.env"
    printf '%s\n' \
        'KAZOO_MASTER_ACCOUNT_REALM=master.saved.example.net' \
        'KAZOO_MASTER_ADMIN_USER=saved-admin' \
        'KAZOO_MASTER_ADMIN_PASSWORD=saved-password' >"$KAZOO_INSTALLER_SECRETS"
    chmod 0600 "$KAZOO_INSTALLER_SECRETS"
    KAZOO_HOSTNAME=kz5.example.net
    KAZOO_MASTER_ACCOUNT_REALM=master.default.example.net
    KAZOO_MASTER_ADMIN_USER='admin'
    KAZOO_MASTER_ADMIN_PASSWORD=
    VERIFY_ONLY=true
    load_or_create_master_credentials
    [[ $KAZOO_MASTER_ACCOUNT_REALM == master.saved.example.net ]] || fail 'stored master realm was not restored'
    [[ $KAZOO_MASTER_ADMIN_USER == saved-admin ]] || fail 'stored administrator username was not restored'
    [[ $KAZOO_MASTER_ADMIN_PASSWORD == saved-password ]] || fail 'stored administrator password was not restored'
    chmod 0644 "$KAZOO_INSTALLER_SECRETS"
    if (KAZOO_MASTER_ADMIN_PASSWORD=; load_or_create_master_credentials) >/dev/null 2>&1; then
        fail 'world-readable installer credentials were accepted'
    fi
    chmod 0600 "$KAZOO_INSTALLER_SECRETS"

    KAZOO_INSTALLER_SECRETS="$test_dir/explicit-secrets.env"
    KAZOO_MASTER_ADMIN_PASSWORD=operator-supplied-initial-password
    VERIFY_ONLY=true
    load_or_create_master_credentials
    [[ ! -e $KAZOO_INSTALLER_SECRETS ]] || fail 'verification persisted supplied credentials'
    VERIFY_ONLY=false
    DRY_RUN=true
    load_or_create_master_credentials
    [[ ! -e $KAZOO_INSTALLER_SECRETS ]] || fail 'dry run persisted supplied credentials'
    DRY_RUN=false
    load_or_create_master_credentials >/dev/null
    [[ $(stat -c '%a' "$KAZOO_INSTALLER_SECRETS") == 600 ]] || fail 'supplied initial credentials were not protected'
    KAZOO_MASTER_ADMIN_PASSWORD=
    load_or_create_master_credentials
    [[ $KAZOO_MASTER_ADMIN_PASSWORD == operator-supplied-initial-password ]] || fail 'supplied initial password was not preserved across reruns'
    saved_hash=$(sha256sum "$KAZOO_INSTALLER_SECRETS")
    KAZOO_MASTER_ADMIN_PASSWORD=unverified-override
    load_or_create_master_credentials
    [[ $(sha256sum "$KAZOO_INSTALLER_SECRETS") == "$saved_hash" ]] || fail 'unverified override replaced known credentials'
fi

SELECTED[monster-ui]=1
DRY_RUN=true
KAZOO_PUBLIC_HOSTNAME=kz5.example.net
KAZOO_TLS_CERT_FILE="$test_dir/server.crt"
KAZOO_TLS_KEY_FILE="$test_dir/server.key"
KAZOO_API_URL=https://kz5.example.net/v2/
validate_tls_configuration
if (KAZOO_API_URL=http://example.net/v2/; validate_tls_configuration) >/dev/null 2>&1; then
    fail 'HTTPS UI accepted a mixed-content API'
fi
if (KAZOO_PUBLIC_HOSTNAME='bad;hostname.example'; validate_tls_configuration) >/dev/null 2>&1; then
    fail 'unsafe nginx hostname was accepted'
fi
if (KAZOO_PUBLIC_HOSTNAME='good.-bad.example'; validate_tls_configuration) >/dev/null 2>&1; then
    fail 'invalid DNS label was accepted'
fi
if (KAZOO_PUBLIC_HOSTNAME="$(printf 'a%.0s' {1..64}).example"; validate_tls_configuration) >/dev/null 2>&1; then
    fail 'overlong DNS label was accepted'
fi
if (KAZOO_PUBLIC_HOSTNAME=192.0.2.1; validate_tls_configuration) >/dev/null 2>&1; then
    fail 'IP address was accepted as a public DNS hostname'
fi
if (KAZOO_TLS_KEY_FILE=; validate_tls_configuration) >/dev/null 2>&1; then fail 'missing TLS key was accepted'; fi

openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=kz5.example.net \
    -addext subjectAltName=DNS:kz5.example.net -keyout "$test_dir/server.key" \
    -out "$test_dir/server.crt" >/dev/null 2>&1
DRY_RUN=false
# Trust this temporary fixture only inside this test process.
export SSL_CERT_FILE="$test_dir/server.crt"
validate_tls_configuration
if (KAZOO_PUBLIC_HOSTNAME=other.example.net; validate_tls_configuration) >/dev/null 2>&1; then
    fail 'certificate hostname mismatch was accepted'
fi
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$test_dir/other.key" >/dev/null 2>&1
if (KAZOO_TLS_KEY_FILE="$test_dir/other.key"; validate_tls_configuration) >/dev/null 2>&1; then
    fail 'mismatched certificate/key pair was accepted'
fi
printf 'PASS: deployment persistence, protected credentials, and HTTPS validation\n'
