#!/usr/bin/env bash
# Optional development tooling, deliberately separate from stack runtime roles.
set -Eeuo pipefail
umask 077
[[ $# == 0 && $EUID == 0 ]] || { echo 'Usage: sudo bash scripts/setup-kazoo-browser-tests.sh' >&2; exit 64; }
[[ $(uname -m) == x86_64 ]] || { echo 'Only Linux x64 is supported' >&2; exit 69; }
# shellcheck disable=SC1091
source /etc/os-release
[[ $ID == rocky && $VERSION_ID == 9* ]] || { echo 'Validated target is Rocky Linux 9 only' >&2; exit 69; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
base=/usr/local/lib/kazoo5-browser-tests
for parent in /usr /usr/local /usr/local/lib; do
    [[ -d $parent && ! -L $parent && $(stat -c %u "$parent") == 0 ]] || exit 78
    mode=$(stat -c %a "$parent"); (( (8#$mode & 0022) == 0 )) || exit 78
done
if [[ ! -e $base && ! -L $base ]]; then mkdir -m 0700 "$base"; fi
[[ -d $base && ! -L $base && $(stat -c '%u:%a' "$base") == 0:700 ]] || exit 78
if [[ ! -e $base/setup.lock && ! -L $base/setup.lock ]]; then
    (set -o noclobber; : > "$base/setup.lock")
fi
[[ ! -L $base/setup.lock && -f $base/setup.lock && $(stat -c '%u:%a:%h:%s' "$base/setup.lock") == 0:600:1:0 ]] || exit 78
exec 9<> "$base/setup.lock"
flock -n 9 || { echo 'Browser setup already running' >&2; exit 75; }
if [[ -e $base/current || -L $base/current ]]; then
    [[ -L $base/current && $(readlink "$base/current") =~ ^release\.[[:alnum:]]+$ ]] || exit 78
fi
fingerprint=$(sha256sum "$script_dir/browser-tests/package-lock.json")
fingerprint=${fingerprint%% *}
smoke() {
    KZ5_BROWSER_TOOLS=$1 PLAYWRIGHT_BROWSERS_PATH=$1/browsers \
        timeout 60 "$1/node_modules/node-linux-x64/bin/node" "$script_dir/browser-tests/smoke.cjs"
}
if [[ -d $base/current && -f $base/current/lock.sha256 ]] &&
    [[ $(< "$base/current/lock.sha256") == "$fingerprint" ]]; then
    cmp "$script_dir/browser-tests/package-lock.json" "$base/current/package-lock.json"
    smoke "$(readlink -f "$base/current")"
    echo 'Existing private browser tools verified; no installation changes'
    exit 0
fi
packages=(nodejs npm nss atk at-spi2-atk libX11 libXcomposite libXdamage libXrandr
    mesa-libgbm libxcb cups-libs alsa-lib dejavu-sans-fonts fontconfig libxkbcommon
    libdrm nspr pango cairo at-spi2-core)
missing=()
for package in "${packages[@]}"; do
    rpm -q "$package" >/dev/null 2>&1 || missing+=("$package")
done
if ((${#missing[@]})); then dnf -y install "${missing[@]}"; fi
stage=$(mktemp -d "$base/release.XXXXXXXX")
trap 'echo "Browser setup failed; previous current unchanged, staging evidence retained: ${stage:-none}" >&2' ERR
install -m 0600 "$script_dir/browser-tests/package.json" "$script_dir/browser-tests/package-lock.json" "$stage/"
install -m 0600 /dev/null "$stage/npm-user.conf"
install -m 0600 /dev/null "$stage/npm-global.conf"
# Never run package lifecycle scripts or the node wrapper's secondary download.
# Empty npm user/global config prevents accidental reuse of root credentials.
env -i PATH=/usr/bin:/bin NPM_CONFIG_USERCONFIG="$stage/npm-user.conf" NPM_CONFIG_GLOBALCONFIG="$stage/npm-global.conf" \
    npm ci --prefix "$stage" --cache "$base/npm-cache" --ignore-scripts --omit=optional \
    --no-audit --no-fund --strict-ssl=true --registry=https://registry.npmjs.org
env -i PATH=/usr/bin:/bin PLAYWRIGHT_BROWSERS_PATH="$stage/browsers" \
    "$stage/node_modules/node-linux-x64/bin/node" "$stage/node_modules/playwright/cli.js" \
    install chromium --only-shell
smoke "$stage"
printf '%s\n' "$fingerprint" > "$stage/lock.sha256"
link_dir=$(mktemp -d "$base/activate.XXXXXXXX")
ln -s "${stage##*/}" "$link_dir/current"
mv -Tf "$link_dir/current" "$base/current"
rmdir "$link_dir"
echo 'Private browser tools installed; system Node and Kazoo services unchanged'
