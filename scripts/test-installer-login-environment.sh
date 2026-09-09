#!/usr/bin/env bash
# Installer helper reads these globals after sourcing.
# shellcheck disable=SC2034
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=/dev/null
KAZOO_DEPLOYMENT_CONFIG=/nonexistent source "$root/scripts/install-kazoo5.sh"
SELECTED=([kazoo-apps]=1)
DRY_RUN=false
VERIFY_ONLY=false
validate_build_login_environment
if (unset HOME; validate_build_login_environment) >/dev/null 2>&1; then
    echo 'FAIL missing login home accepted for source build' >&2; exit 1
fi
(unset HOME; VERIFY_ONLY=true; validate_build_login_environment)
(unset HOME; DRY_RUN=true; validate_build_login_environment)
(unset HOME; SELECTED=([couchdb]=1); validate_build_login_environment)
echo 'PASS login-home build preflight and verify/dry-run/data-role exemptions'
