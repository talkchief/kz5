#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo5-couchdb-security.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/etc/vm.args" "$test_dir/.erlang.cookie" "$test_dir/erlang/.erlang.cookie"
    rmdir -- "$test_dir/etc" "$test_dir/erlang" "$test_dir"
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
mkdir "$test_dir/etc" "$test_dir/erlang"
export KAZOO_DEPLOYMENT_CONFIG="$test_dir/no-deployment"
source "$SCRIPT_DIR/install-kazoo5.sh"
test_owner="$(id -un):$(id -gn)"
fixture_cookie=0123456789abcdef0123456789abcdef
printf '%s\n' '# Existing package configuration' '-name fixture@127.0.0.1' \
    "-setcookie '$fixture_cookie'" '+S 1:1' >"$test_dir/etc/vm.args"
before=$(sha256sum "$test_dir/etc/vm.args")
DRY_RUN=true
configure_couchdb_cookie "$test_dir" "$test_owner" >/dev/null
[[ $(sha256sum "$test_dir/etc/vm.args") == "$before" && ! -e $test_dir/.erlang.cookie ]] || fail 'dry run changed credentials'
DRY_RUN=false
output=$(configure_couchdb_cookie "$test_dir" "$test_owner")
[[ $output != *"$fixture_cookie"* ]] || fail 'cookie leaked in output'
[[ $(<"$test_dir/.erlang.cookie") == "$fixture_cookie" ]] || fail 'existing cookie changed'
[[ $(stat -c '%a' "$test_dir/.erlang.cookie") == 400 ]] || fail 'cookie file is not private'
[[ $(stat -c '%a' "$test_dir/etc/vm.args") == 640 ]] || fail 'vm.args permissions are unsafe'
grep -Fxq -- '-name fixture@127.0.0.1' "$test_dir/etc/vm.args" || fail 'node name changed'
grep -Fxq -- '+S 1:1' "$test_dir/etc/vm.args" || fail 'unrelated argument changed'
if grep -q -- '-setcookie' "$test_dir/etc/vm.args"; then fail 'cookie argument retained'; fi
before=$(sha256sum "$test_dir/etc/vm.args" "$test_dir/.erlang.cookie")
configure_couchdb_cookie "$test_dir" "$test_owner" >/dev/null
[[ $(sha256sum "$test_dir/etc/vm.args" "$test_dir/.erlang.cookie") == "$before" ]] || fail 'migration is not idempotent'

# Use the actual OTP cookie loader without passing the value to argv or env.
# erl already supplies -home; an extra fixture home causes OTP to use its XDG
# fallback. Both fixture locations resolve to the same protected test cookie,
# and the invoking user's real home and credentials remain untouched.
if command -v erl >/dev/null; then
    ln -s ../.erlang.cookie "$test_dir/erlang/.erlang.cookie"
    ERL_CRASH_DUMP=/dev/null XDG_CONFIG_HOME="$test_dir" KAZOO_COOKIE_TEST_PATH="$test_dir/.erlang.cookie" \
        erl +S 1:1 +A 1 -noshell -hidden -sname "couchdb_cookie_test_$$" -home "$test_dir" \
        -eval '{ok, B} = file:read_file(os:getenv("KAZOO_COOKIE_TEST_PATH")), true = atom_to_binary(erlang:get_cookie()) =:= string:trim(B), halt(0).'
fi

for invalid in '-setcookie unexpected' '-name fixture@127.0.0.1 -setcookie embedded' \
    $'-setcookie first\n-setcookie second' '-setcookie "bad syntax"'; do
    printf '%s\n' "$invalid" >"$test_dir/etc/vm.args"
    before=$(sha256sum "$test_dir/etc/vm.args" "$test_dir/.erlang.cookie")
    if output=$(configure_couchdb_cookie "$test_dir" "$test_owner" 2>&1); then fail 'ambiguous or conflicting cookie accepted'; fi
    [[ $output != *"$fixture_cookie"* ]] || fail 'failure exposed cookie'
    [[ $(sha256sum "$test_dir/etc/vm.args" "$test_dir/.erlang.cookie") == "$before" ]] || fail 'failed validation changed files'
done

# A fresh package without an explicit cookie receives a strong private value.
rm -f -- "$test_dir/.erlang.cookie"
printf '%s\n' '-name fixture@127.0.0.1' >"$test_dir/etc/vm.args"
configure_couchdb_cookie "$test_dir" "$test_owner" >/dev/null
generated_cookie=$(<"$test_dir/.erlang.cookie")
[[ $generated_cookie =~ ^[0-9a-f]{64}$ ]] || fail 'fresh cookie is not cryptographically generated'
rm -f -- "$test_dir/.erlang.cookie"
ln -s etc/vm.args "$test_dir/.erlang.cookie"
before=$(sha256sum "$test_dir/etc/vm.args")
if (configure_couchdb_cookie "$test_dir" "$test_owner") >/dev/null 2>&1; then fail 'symlinked cookie accepted'; fi
[[ $(sha256sum "$test_dir/etc/vm.args") == "$before" ]] || fail 'symlink target was changed'

# Confirm curl credentials are escaped in stdin, never appended to argv.
KAZOO_COUCHDB_USER=fixture
KAZOO_COUCHDB_PASSWORD='quote"slash\end'
curl() {
    [[ $* == '--config - --fail http://fixture.invalid/_up' ]] || fail 'curl argv differs or contains a credential'
    local config
    config=$(</dev/stdin)
    [[ $config == 'user = "fixture:quote\"slash\\end"' ]] || fail 'curl credential escaping failed'
}
couchdb_curl --fail http://fixture.invalid/_up
printf 'PASS: preserved private CouchDB cookie, actual OTP loading, idempotency, fail-closed migration and credential-free curl argv\n'
