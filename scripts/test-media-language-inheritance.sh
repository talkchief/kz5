#!/usr/bin/env bash
# Compile the native public resolver in isolation. Never load it into Kazoo.
set -Eeuo pipefail
umask 077
language_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
language_mode=${1:-current}
[[ $# -le 1 && ( $language_mode == current || $language_mode == --baseline ) ]] || exit 64
language_output=$(mktemp -d /tmp/kazoo-media-language.XXXXXXXX)
cd "$language_root"
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$language_root/deps:$language_root/core:$language_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP="$language_output/erl_crash.dump"
language_source=core/kazoo_media/src/kz_media_util.erl
language_patch="$language_root/scripts/patches/kazoo-media-reseller-language.patch"
[[ $(git -C core rev-parse HEAD) == 5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72 ]] || exit 65
mkdir "$language_output/source"
git -C core archive HEAD kazoo_media/src/kz_media_util.erl | tar -xf - -C "$language_output/source"
if [[ $language_mode == --baseline ]]; then
    language_source="$language_output/source/kazoo_media/src/kz_media_util.erl"
else
    source <(sed -n '/^apply_required_source_patch() {$/,/^}$/p' scripts/install-kazoo5.sh)
    DRY_RUN=false
    log() { printf '%s\n' "$*"; }
    die() { printf '%s\n' "$*" >&2; exit 65; }
    apply_required_source_patch "$language_output/source" "$language_patch"
    cmp "$language_source" "$language_output/source/kazoo_media/src/kz_media_util.erl"
    apply_required_source_patch "$language_output/source" "$language_patch"
    cmp "$language_source" "$language_output/source/kazoo_media/src/kz_media_util.erl"
fi
sha256sum "$language_source" scripts/install-kazoo5.sh scripts/erlang-tests/media_language_inheritance_tests.erl > "$language_output/inputs.sha256"
printf 'Language inheritance evidence: %s\n' "$language_output"
erlc -Werror +debug_info -I core/kazoo_media/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$language_output" "$language_source"
erlc -Werror +debug_info -o "$language_output" scripts/erlang-tests/media_language_inheritance_tests.erl
erl -noshell -pa "$language_output" -eval '
    {module,kz_media_util}=code:ensure_loaded(kz_media_util),
    case eunit:test(media_language_inheritance_tests,[verbose]) of ok->halt(0);_->halt(1) end.' | tee "$language_output/eunit.log"
sha256sum --status --check "$language_output/inputs.sha256"
printf '%s\n' 'PASS production resolver with controlled account/reseller reads. No native tenant/media/call acceptance.'
