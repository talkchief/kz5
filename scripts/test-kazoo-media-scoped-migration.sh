#!/usr/bin/env bash
# Run through run-kazoo-validation.sh. No live services or databases are used.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
media_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
media_output=$(mktemp -d /tmp/kazoo-media-scoped-migration.XXXXXX)
media_ref=5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72
media_patch="$media_root/scripts/patches/kazoo-media-scoped-migration.patch"
media_source=kazoo_media/src/kazoo_media_maintenance.erl
cd "$media_root"
[[ $(git -C core rev-parse HEAD) == "$media_ref" ]]
export ERL_LIBS="$media_root/deps:$media_root/core:$media_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 2'
export ERL_CRASH_DUMP="$media_output/erl_crash.dump"
mkdir "$media_output/replay" "$media_output/before" "$media_output/after" "$media_output/rejected"
git -C core archive "$media_ref" "$media_source" | tar -xf - -C "$media_output/replay"
erlc -Werror +debug_info +'{parse_transform,lager_transform}' -I core/kazoo_media/src \
    -o "$media_output/before" "$media_output/replay/$media_source"
erlc -Werror +debug_info -o "$media_output/before" scripts/erlang-tests/kazoo_media_maintenance_tests.erl
erl -pa "$media_output/before" -noshell -eval '
    {module,kazoo_media_maintenance}=code:ensure_loaded(kazoo_media_maintenance),
    false=erlang:function_exported(kazoo_media_maintenance,migrate,1),
    case eunit:test(kazoo_media_maintenance_tests,[verbose]) of
        error -> io:format("before_fix_expected_failures=true~n"), halt(0);
        _ -> halt(1)
    end.'
# Execute the real installer helper on a clean pinned fixture, then repeat it.
[[ $(grep -Fc '    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-media-scoped-migration.patch"' scripts/install-kazoo5.sh) == 1 ]]
source <(sed -n '/^apply_required_source_patch() {$/,/^}$/p' scripts/install-kazoo5.sh)
DRY_RUN=false
log() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }
apply_required_source_patch "$media_output/replay" "$media_patch"
cp "$media_output/replay/$media_source" "$media_output/first-apply.erl"
apply_required_source_patch "$media_output/replay" "$media_patch"
cmp "$media_output/first-apply.erl" "$media_output/replay/$media_source"
if (apply_required_source_patch "$media_output/rejected" "$media_patch"); then
    printf 'Installer accepted missing source\n' >&2; exit 1
fi
git -C "$media_output/replay" apply --reverse --check "$media_patch"
cmp "core/$media_source" "$media_output/replay/$media_source"
erlc -Werror +debug_info +'{parse_transform,lager_transform}' -I core/kazoo_media/src \
    -o "$media_output/after" "$media_output/replay/$media_source"
erlc -Werror +debug_info -o "$media_output/after" scripts/erlang-tests/kazoo_media_maintenance_tests.erl
erl -pa "$media_output/after" -noshell -eval '
    {module,kazoo_media_maintenance}=code:ensure_loaded(kazoo_media_maintenance),
    true=erlang:function_exported(kazoo_media_maintenance,migrate,0),
    true=erlang:function_exported(kazoo_media_maintenance,migrate,1),
    Options=proplists:get_value(options,kazoo_media_maintenance:module_info(compile),[]),
    true=lists:member({parse_transform,lager_transform},Options),
    false=lists:member(export_all,Options),
    case eunit:test(kazoo_media_maintenance_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.'
sha256sum "$media_output/after/kazoo_media_maintenance.beam"
printf 'PASS native production compile, regression, installer apply/reapply/rejection; evidence=%s\n' "$media_output"
