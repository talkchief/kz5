#!/usr/bin/env bash
# Source-only integration fixtures. Extract one helper; never source the installer or modify shared trees.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || { printf 'Usage: %s\n' "$0" >&2; exit 2; }
transition_fixture_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
transition_fixture_installer="$transition_fixture_dir/install-kazoo5.sh"
transition_fixture_formatter="$transition_fixture_dir/format-json.py"
transition_fixture_patches="$transition_fixture_dir/patches"
transition_fixture_output=$(mktemp -d /tmp/kazoo-source-transition-tests.XXXXXX)
transition_fixture_helper="$transition_fixture_output/apply-source-transition.sh"
readonly transition_fixture_shared=$(cd -- "$transition_fixture_dir/.." && pwd -P)
readonly transition_fixture_blackhole_ref=4e3f02a5ab01c09a44c287f4f93b15d2782f5614
readonly transition_fixture_crossbar_ref=2ac862830f9b626d2170d08daf1991b0ca33dba7
readonly transition_fixture_ecallmgr_ref=fb8eba201b41762ce8fae928c61bd5d22379a1bc
transition_fixture_count=0
transition_fixture_inputs=(
    "$transition_fixture_dir/test-kazoo-source-transition.sh"
    "$transition_fixture_installer"
    "$transition_fixture_patches/blackhole-kazoo5-integration.patch"
    "$transition_fixture_patches/blackhole-token-redaction.patch"
    "$transition_fixture_patches/blackhole-redaction-to-integration.patch"
    "$transition_fixture_patches/crossbar-kazoo5-integration.patch"
    "$transition_fixture_patches/crossbar-kazoo5-before-frame.patch"
    "$transition_fixture_patches/crossbar-blackhole-frame-schema.patch"
    "$transition_fixture_patches/crossbar-kazoo5-before-empty-icon.patch"
    "$transition_fixture_patches/crossbar-empty-icon.patch"
    "$transition_fixture_patches/crossbar-build-json-format.patch"
    "$transition_fixture_patches/blackhole-binding-cleanup.patch"
    "$transition_fixture_patches/blackhole-pre-queue-live-integration.patch"
    "$transition_fixture_patches/blackhole-queue-live.patch"
    "$transition_fixture_patches/blackhole-before-stream-guard.patch"
    "$transition_fixture_patches/blackhole-stream-guard-transition.patch"
    "$transition_fixture_patches/ecallmgr-kazoo5-integration.patch"
    "$transition_fixture_patches/ecallmgr-kazoo5-before-atomic.patch"
    "$transition_fixture_patches/ecallmgr-atomic-answer-runtime.patch"
)
finish() {
    local status=$?
    trap - EXIT
    if [[ -f $transition_fixture_output/input-pins.sha256 ]] &&
       ! sha256sum --check --status "$transition_fixture_output/input-pins.sha256"; then
        printf 'FAIL private source-transition input changed during validation\n' >&2
        status=99
    fi
    printf 'Source-transition exit=%s; cases=%s; retained evidence: %s\n' \
        "$status" "$transition_fixture_count" "$transition_fixture_output"
    exit "$status"
}
trap finish EXIT
for transition_fixture_input in "${transition_fixture_inputs[@]}"; do
    [[ -f $transition_fixture_input && ! -L $transition_fixture_input ]] || {
        printf 'Missing or symlinked fixture input: %s\n' "$transition_fixture_input" >&2
        exit 2
    }
done
[[ -f $transition_fixture_formatter && ! -L $transition_fixture_formatter ]] || {
    printf 'Missing or symlinked real build JSON formatter\n' >&2
    exit 2
}
sha256sum "${transition_fixture_inputs[@]}" "$transition_fixture_formatter" >"$transition_fixture_output/input-pins.sha256"

# Generate only the reviewed function into the protected evidence directory.
# Pin the full installer, assert both integration call sites, and pin extraction.
node - "$transition_fixture_installer" "$transition_fixture_helper" <<'NODE'
const fs = require('node:fs'), assert = require('node:assert/strict');
const [installer, output] = process.argv.slice(2);
const source = fs.readFileSync(installer, 'utf8');
const definitions = source.match(/^apply_kazoo_integration_patch\(\) \(\n[\s\S]*?^\)\n/gm);
assert.equal(definitions?.length, 1, 'Expected exactly one integration helper');
for (const family of ['blackhole', 'crossbar', 'ecallmgr']) {
  assert(source.includes('    apply_kazoo_integration_patch ' + family + '\n'), 'Missing integration call site');
}
fs.writeFileSync(output, definitions[0], {flag: 'wx', mode: 0o600});
NODE
sha256sum "$transition_fixture_helper" >>"$transition_fixture_output/input-pins.sha256"

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
pass() {
    transition_fixture_count=$((transition_fixture_count + 1))
    printf 'PASS %s\n' "$*" | tee -a "$transition_fixture_output/results.log"
}

# Include names, object types, permissions, regular bytes and link destinations.
# No dereference: an escaping fixture symlink must not hide a target mutation.
snapshot_tree() (
    cd -- "$1"
    while IFS= read -r -d '' path; do
        printf '%s\0%s\0' "$path" "$(stat -c '%F:%a' -- "$path")"
        if [[ -L $path ]]; then
            readlink -- "$path"
        elif [[ -f $path ]]; then
            sha256sum -- "$path"
        elif [[ ! -d $path ]]; then
            fail "unexpected fixture object: $path"
        fi
        printf '\0'
    done < <(find . -print0 | LC_ALL=C sort -z)
)

# Intentional test-data edit, limited to the exact file passed by this harness.
# Refuse silent no-ops and ambiguous replacements.
replace_once() {
    node - "$1" "$2" "$3" <<'NODE'
const fs = require('node:fs');
const [file, before, after] = process.argv.slice(2);
const value = fs.readFileSync(file, 'utf8');
if (!before || value.split(before).length !== 2) {
  throw new Error(`fixture replacement must match exactly once: ${file}`);
}
fs.writeFileSync(file, value.replace(before, after));
NODE
}

select_app() {
    app=$1
    new_patch="$app-kazoo5-integration.patch"
    case $app in
        blackhole)
            old_patch=blackhole-token-redaction.patch
            step_patch=blackhole-redaction-to-integration.patch
            sentinel_source=src/modules/bh_token_auth.erl
            partial_source=src/modules/bh_token_auth.erl
            missing_hunk_source=src/blackhole_socket_handler.erl
            missing_source=src/modules/bh_token_auth.erl
            ;;
        crossbar)
            old_patch=crossbar-kazoo5-before-frame.patch
            step_patch=crossbar-blackhole-frame-schema.patch
            sentinel_source=src/api_util.erl
            partial_source=priv/couchdb/schemas/queues.json
            missing_hunk_source=src/crossbar_auth.erl
            missing_source=src/modules/cb_members.erl
            ;;
        ecallmgr)
            old_patch=ecallmgr-kazoo5-before-atomic.patch
            step_patch=ecallmgr-atomic-answer-runtime.patch
            sentinel_source=src/ecallmgr_util.erl
            partial_source=src/ecallmgr_originate.erl
            missing_hunk_source=src/ecallmgr_fs_xml.erl
            missing_source=src/ecallmgr_call_monitor.erl
            ;;
        *) fail "unsupported fixture app: $app" ;;
    esac
}

prepare_baseline() {
    local ref=$1
    shift
    [[ $(git -C "$transition_fixture_shared/applications/$app" rev-parse HEAD) == "$ref" ]] ||
        fail "$app shared checkout is not the pinned baseline"
    mkdir -m 0700 "$transition_fixture_output/baseline-$app"
    git -C "$transition_fixture_shared/applications/$app" archive "$ref" "$@" |
        tar -xf - -C "$transition_fixture_output/baseline-$app"
    printf '%s %s\n' "$app" "$ref" >>"$transition_fixture_output/baseline-refs.txt"
    snapshot_tree "$transition_fixture_output/baseline-$app" >"$transition_fixture_output/baseline-$app.snapshot"
}

select_app blackhole
prepare_baseline "$transition_fixture_blackhole_ref" \
    src/blackhole_bindings.erl src/blackhole_socket_handler.erl src/modules/bh_token_auth.erl \
    src/bh_context.erl src/bh_events.erl src/blackhole.hrl
select_app crossbar
# The other four permitted Crossbar paths are genuinely absent in this commit;
# the integration adds them. Do not manufacture placeholder files in baseline.
prepare_baseline "$transition_fixture_crossbar_ref" \
    priv/couchdb/schemas/queue_update.json priv/couchdb/schemas/queues.json \
    src/api_util.erl src/crossbar_auth.erl src/modules/cb_channels.erl \
    src/modules/cb_devices.erl priv/couchdb/schemas/system_config.blackhole.json
select_app ecallmgr
# The monitoring module is created by both reviewed aggregates, not upstream.
prepare_baseline "$transition_fixture_ecallmgr_ref" \
    src/call_cmd/ecallmgr_call_command.erl src/call_cmd/ecallmgr_fs_bridge.erl \
    src/ecallmgr_fs_channels.erl src/ecallmgr_fs_resource.erl src/ecallmgr_fs_xml.erl \
    src/ecallmgr_originate.erl src/ecallmgr_util.erl src/event_stream/ecallmgr_fs_event_stream.erl \
    src/mod_kazoo.erl src/node/ecallmgr_fs_nodes.erl src/node/ecallmgr_fs_pinger.erl

seed_sentinels() {
    local source_module=${sentinel_source##*/}
    source_module=${source_module%.erl}
    printf 'unrelated source-transition sentinel\n' >"$1/UNRELATED.fixture"
    chmod 0640 "$1/UNRELATED.fixture"
    # Keep the sentinel away from EOF: the legacy token patch has an
    # intentionally EOF-anchored hunk and must still be applicable as authored.
    replace_once "$1/$sentinel_source" "-module($source_module)." \
        $'%% KAZOO_SOURCE_TRANSITION_SENTINEL\n'"-module($source_module)."
}

new_case() {
    local label=$1 state=$2
    case_dir="$transition_fixture_output/$app-$label"
    work="$case_dir/work"
    root="$work/root"
    source_dir="$root/applications/$app"
    script_dir="$root/scripts"
    mkdir -p -m 0700 "$root/applications" "$script_dir/patches"
    cp -a -- "$transition_fixture_output/baseline-$app" "$source_dir"
    cp -- "${transition_fixture_inputs[@]:2}" "$script_dir/patches/"
    seed_sentinels "$source_dir"
    case $state in
        clean) ;;
        legacy) git -C "$source_dir" apply "$script_dir/patches/$old_patch" ;;
        current) git -C "$source_dir" apply "$script_dir/patches/$new_patch" ;;
        pre-queue)
            [[ $app == blackhole ]] || fail 'pre-queue state is Blackhole only'
            git -C "$source_dir" apply "$script_dir/patches/blackhole-pre-queue-live-integration.patch"
            ;;
        pre-stream)
            [[ $app == blackhole ]] || fail 'pre-stream state is Blackhole only'
            git -C "$source_dir" apply "$script_dir/patches/blackhole-before-stream-guard.patch"
            ;;
        pre-icon)
            [[ $app == crossbar ]] || fail 'pre-icon state is Crossbar only'
            git -C "$source_dir" apply "$script_dir/patches/crossbar-kazoo5-before-empty-icon.patch"
            ;;
        *) fail "unknown fixture state: $state" ;;
    esac
    configured_root="$root"
    fixture_dry_run=false
    fixture_git_redirect=false
    fixture_failure_mode=none
}

invoke_helper() (
    # Actual private helper, with only the documented caller environment.
    # A distinguishable die status prevents command-not-found from counting as
    # an expected safety rejection.
    set -Eeuo pipefail
    KAZOO_ROOT="$configured_root"
    SCRIPT_DIR="$script_dir"
    DRY_RUN=$fixture_dry_run
    log() { printf 'FIXTURE-LOG %s\n' "$*"; }
    die() { printf 'FIXTURE-DIE %s\n' "$*" >&2; exit 65; }
    source "$transition_fixture_helper"
    case $fixture_failure_mode in
        mktemp)
            mktemp() {
                if [[ $# == 2 && $1 == -d && $2 == /tmp/kazoo-integration-preflight.XXXXXX ]]; then
                    printf 'FIXTURE-INJECT mktemp\n' >&2
                    return 73
                fi
                command mktemp "$@"
            }
            ;;
        private-copy)
            cp() {
                if [[ $# == 4 && $1 == --preserve=mode,timestamps && $2 == -- &&
                      $4 == /tmp/kazoo-integration-preflight.*/desired/* ]]; then
                    printf 'FIXTURE-INJECT private-copy\n' >&2
                    return 74
                fi
                command cp "$@"
            }
            ;;
        none) ;;
        *) die 'Unknown fixture failure injection' ;;
    esac
    if [[ $fixture_git_redirect == true ]]; then
        # Injection occurs only after all fixture-setup Git commands have run,
        # and only in the caller of the helper's own isolation subshell.
        export GIT_DIR="$fixture_git_tree/repo/.git"
        export GIT_WORK_TREE="$fixture_git_tree/repo"
        export GIT_COMMON_DIR="$fixture_git_tree/repo/.git"
        export GIT_INDEX_FILE="$fixture_git_tree/index.sentinel"
        export GIT_OBJECT_DIRECTORY="$fixture_git_tree/repo/.git/objects"
        export GIT_ALTERNATE_OBJECT_DIRECTORIES="$fixture_git_tree/repo/.git/objects"
        export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree
        export GIT_CONFIG_VALUE_0="$fixture_git_tree/repo"
        export GIT_CONFIG_PARAMETERS="'core.worktree=$fixture_git_tree/repo'"
        export GIT_TRACE="$fixture_git_tree/trace.sentinel"
        export GIT_EXEC_PATH="$fixture_git_tree/empty-exec"
        for fixture_git_name in "${!GIT_@}"; do
            declare -p "$fixture_git_name"
        done >"$case_dir/git-caller.before"
    fi
    apply_kazoo_integration_patch "$app" || return "$?"
    if [[ $fixture_git_redirect == true ]]; then
        for fixture_git_name in "${!GIT_@}"; do
            declare -p "$fixture_git_name"
        done >"$case_dir/git-caller.after"
        cmp -- "$case_dir/git-caller.before" "$case_dir/git-caller.after" ||
            die 'Integration helper changed its caller Git environment'
    fi
)

expect_success() {
    local label=$1
    invoke_helper >"$case_dir/invoke.log" 2>&1 || fail "$app/$label helper rejected valid state; see $case_dir/invoke.log"
    git -C "$source_dir" apply --reverse --check "$script_dir/patches/$new_patch" \
        >"$case_dir/reverse.log" 2>&1 || fail "$app/$label new postcondition absent"
    if git -C "$source_dir" apply --check "$script_dir/patches/$new_patch" >"$case_dir/reapply.log" 2>&1; then
        fail "$app/$label complete integration unexpectedly applies twice"
    fi
    # Independently build the exact target from the pinned clean archive.
    cp -a -- "$transition_fixture_output/baseline-$app" "$case_dir/expected"
    seed_sentinels "$case_dir/expected"
    git -C "$case_dir/expected" apply "$transition_fixture_patches/$new_patch"
    snapshot_tree "$case_dir/expected" >"$case_dir/expected.snapshot"
    snapshot_tree "$source_dir" >"$case_dir/actual.snapshot"
    cmp -- "$case_dir/expected.snapshot" "$case_dir/actual.snapshot" ||
        fail "$app/$label target bytes, modes or sentinel differ"
    snapshot_tree "$work" >"$case_dir/before-repeat.snapshot"
    invoke_helper >"$case_dir/repeat.log" 2>&1 || fail "$app/$label repeat failed"
    snapshot_tree "$work" >"$case_dir/after-repeat.snapshot"
    cmp -- "$case_dir/before-repeat.snapshot" "$case_dir/after-repeat.snapshot" ||
        fail "$app/$label repeat changed the private tree"
    pass "$app/$label exact target + unrelated bytes/modes + idempotence"
}

expect_rejection() {
    local label=$1 status=0
    snapshot_tree "$work" >"$case_dir/before.snapshot"
    invoke_helper >"$case_dir/invoke.log" 2>&1 || status=$?
    [[ $status == 65 ]] || fail "$app/$label expected explicit die=65, got $status; see $case_dir/invoke.log"
    snapshot_tree "$work" >"$case_dir/after.snapshot"
    cmp -- "$case_dir/before.snapshot" "$case_dir/after.snapshot" ||
        fail "$app/$label rejected state mutated bytes, modes, links or paths"
    if [[ $fixture_failure_mode != none ]]; then
        /usr/bin/grep -Fq "FIXTURE-INJECT $fixture_failure_mode" "$case_dir/invoke.log" ||
            fail "$app/$label did not reach the requested private-operation failure"
    fi
    pass "$app/$label explicit rejection with no private-tree mutation"
}

expect_unverified_dry_run() {
    snapshot_tree "$work" >"$case_dir/before.snapshot"
    invoke_helper >"$case_dir/invoke.log" 2>&1 || fail "$app/dry-run absent source was rejected"
    /usr/bin/grep -Fq 'source state and preflight are unverified' "$case_dir/invoke.log" ||
        fail "$app/dry-run must not imply source-state validation"
    [[ ! -e $configured_root && ! -L $configured_root ]] || fail "$app/dry-run created source root"
    snapshot_tree "$work" >"$case_dir/after.snapshot"
    cmp -- "$case_dir/before.snapshot" "$case_dir/after.snapshot" ||
        fail "$app/dry-run mutated the private tree"
    pass "$app/dry-run absent source, explicit unverified warning, no mutation"
}

format_crossbar_case() (
    [[ $app == crossbar ]] || fail 'JSON formatter fixture is Crossbar only'
    # The completed installer exposes public schemas as0644. The formatter
    # replaces files, so use that public-file mode inside this isolated fixture.
    umask 022
    /usr/bin/python3 -I "$transition_fixture_formatter" \
        "$source_dir/priv/couchdb/schemas/channel_monitoring.json" \
        "$source_dir/priv/couchdb/schemas/queues.json" \
        "$source_dir/priv/couchdb/schemas/queue_update.json"
    git -C "$source_dir" apply --reverse --check "$script_dir/patches/crossbar-build-json-format.patch" ||
        fail 'Real build formatter no longer matches the exact reviewed delta'
)

for app in blackhole crossbar ecallmgr; do
    select_app "$app"
    for state in clean current legacy; do
        new_case "$state" "$state"
        expect_success "$state"
    done

    if [[ $app == crossbar ]]; then
        new_case pre-icon pre-icon
        expect_success pre-icon

        for state in current pre-icon legacy; do
            new_case "build-formatted-$state" "$state"
            format_crossbar_case
            expect_success "build-formatted-$state"
        done

        new_case completed-install-build-repeat clean
        invoke_helper >"$case_dir/first-install.log" 2>&1 || fail 'Initial clean Crossbar installation failed'
        format_crossbar_case
        expect_success completed-install-build-repeat

        # Known formatting is byte-exact, not permissive JSON equality. Include
        # edits outside aggregate hunks and even duplicate keys with equal values.
        for representation in raw formatted; do
            for mutation in duplicate-key conflicting-key semantic schema-property whitespace; do
                new_case "$representation-json-$mutation" current
                [[ $representation != formatted ]] || format_crossbar_case
                case $mutation in
                    duplicate-key)
                        replace_once "$source_dir/priv/couchdb/schemas/queues.json" \
                            '    "_id": "queues",' $'    "_id": "queues",\n    "_id": "queues",' ;;
                    conflicting-key)
                        replace_once "$source_dir/priv/couchdb/schemas/queues.json" \
                            '    "_id": "queues",' $'    "_id": "wrong",\n    "_id": "queues",' ;;
                    semantic)
                        replace_once "$source_dir/priv/couchdb/schemas/queues.json" \
                            'Call Queues - FIFO call queues' 'Operator-edited call queues' ;;
                    schema-property)
                        replace_once "$source_dir/priv/couchdb/schemas/queues.json" \
                            '    "_id": "queues",' $'    "_id": "queues",\n    "operator_schema_extension": true,' ;;
                    whitespace)
                        printf '\n' >>"$source_dir/priv/couchdb/schemas/queue_update.json" ;;
                esac
                expect_rejection "$representation-json-$mutation"
            done
        done

        for mutation in duplicate-key semantic; do
            new_case "clean-json-$mutation" clean
            if [[ $mutation == duplicate-key ]]; then
                replace_once "$source_dir/priv/couchdb/schemas/queues.json" \
                    '    "_id": "queues",' $'    "_id": "queues",\n    "_id": "queues",'
            else
                replace_once "$source_dir/priv/couchdb/schemas/queues.json" \
                    'Call Queues - FIFO call queues' 'Operator-edited call queues'
            fi
            expect_rejection "clean-json-$mutation"
        done

        new_case partially-build-formatted current
        /usr/bin/python3 -I "$transition_fixture_formatter" "$source_dir/priv/couchdb/schemas/queues.json"
        expect_rejection partially-build-formatted

        for dry in false true; do
            new_case "missing-formatter-$dry" current
            fixture_dry_run=$dry
            mv -- "$script_dir/patches/crossbar-build-json-format.patch" "$work/withheld-formatter.patch"
            expect_rejection "missing-formatter-$dry"
        done

        new_case wrong-formatter-content current
        format_crossbar_case
        replace_once "$script_dir/patches/crossbar-build-json-format.patch" \
            '+    "id": "channel_monitoring",' '+    "id": "wrong_monitoring",'
        expect_rejection wrong-formatter-content

        new_case non-whole-file-formatter current
        replace_once "$script_dir/patches/crossbar-build-json-format.patch" \
            '@@ -1,27 +1,60 @@' '@@ -2,27 +2,60 @@'
        expect_rejection non-whole-file-formatter

        new_case symlink-formatter current
        mv -- "$script_dir/patches/crossbar-build-json-format.patch" "$work/formatter-target.patch"
        ln -s -- "$work/formatter-target.patch" "$script_dir/patches/crossbar-build-json-format.patch"
        expect_rejection symlink-formatter

        new_case out-of-scope-formatter current
        printf '\ndiff --git a/src/fixture-out-of-scope b/src/fixture-out-of-scope\nnew file mode 100644\n--- /dev/null\n+++ b/src/fixture-out-of-scope\n@@ -0,0 +1 @@\n+unexpected mutation\n' \
            >>"$script_dir/patches/crossbar-build-json-format.patch"
        expect_rejection out-of-scope-formatter

        new_case edited-catalog pre-icon
        replace_once "$source_dir/src/kazoo_monster_catalog.erl" \
            'Specs=case Icon of undefined -> [];' 'Specs=case Icon of undefined -> [operator_edit];'
        expect_rejection edited-catalog

        new_case partial-icon-delta pre-icon
        replace_once "$source_dir/src/kazoo_monster_catalog.erl" \
            '-export([create_only/4, read_regular/2, read_regular/3, master_db/1]).' \
            '-export([create_only/4, read_regular/2, read_regular/3, master_db/1, images/2]).'
        expect_rejection partial-icon-delta

        new_case missing-icon-delta pre-icon
        mv -- "$script_dir/patches/crossbar-empty-icon.patch" "$work/withheld-icon.patch"
        expect_rejection missing-icon-delta

        new_case wrong-icon-delta pre-icon
        replace_once "$script_dir/patches/crossbar-empty-icon.patch" '<<>> -> [];' '<<>> -> [wrong];'
        expect_rejection wrong-icon-delta

        new_case out-of-scope-icon-delta pre-icon
        printf '\ndiff --git a/src/fixture-out-of-scope b/src/fixture-out-of-scope\nnew file mode 100644\n--- /dev/null\n+++ b/src/fixture-out-of-scope\n@@ -0,0 +1 @@\n+unexpected mutation\n' \
            >>"$script_dir/patches/crossbar-empty-icon.patch"
        expect_rejection out-of-scope-icon-delta
    fi

    # expect_rejection calls invoke_helper conditionally; invoke_helper also
    # calls the actual helper conditionally. Safety must not depend on errexit.
    for failure in mktemp private-copy; do
        new_case "$failure-failure" legacy
        fixture_failure_mode=$failure
        expect_rejection "$failure-failure"
    done

    new_case legacy-git-environment-isolation legacy
    fixture_git_tree="$work/redirect-sentinel"
    mkdir -m 0700 "$fixture_git_tree" "$fixture_git_tree/empty-exec"
    cp -a -- "$transition_fixture_output/baseline-$app" "$fixture_git_tree/repo"
    seed_sentinels "$fixture_git_tree/repo"
    git -C "$fixture_git_tree/repo" apply "$transition_fixture_patches/$old_patch"
    git -C "$fixture_git_tree/repo" init --quiet
    printf 'unrelated index sentinel\n' >"$fixture_git_tree/index.sentinel"
    printf 'unrelated trace sentinel\n' >"$fixture_git_tree/trace.sentinel"
    snapshot_tree "$fixture_git_tree" >"$case_dir/git-redirect.before"
    fixture_git_redirect=true
    expect_success legacy-git-environment-isolation
    snapshot_tree "$fixture_git_tree" >"$case_dir/git-redirect.after"
    cmp -- "$case_dir/git-redirect.before" "$case_dir/git-redirect.after" ||
        fail "$app/Git environment redirected a write into unrelated sentinel tree"

    new_case dry-run-absent-source clean
    fixture_dry_run=true
    configured_root="$work/not-created"
    expect_unverified_dry_run

    new_case dry-run-missing-patch clean
    fixture_dry_run=true
    configured_root="$work/not-created"
    mv -- "$script_dir/patches/$new_patch" "$work/withheld-current.patch"
    expect_rejection dry-run-missing-patch

    new_case partial-legacy clean
    git -C "$source_dir" apply --include="$partial_source" "$script_dir/patches/$old_patch"
    expect_rejection partial-legacy

    new_case missing-legacy-hunk legacy
    git -C "$source_dir" apply --reverse --include="$missing_hunk_source" "$script_dir/patches/$old_patch"
    expect_rejection missing-legacy-hunk

    new_case half-new-transition legacy
    if [[ $app == blackhole ]]; then
        git -C "$source_dir" apply --include=src/blackhole_bindings.erl "$script_dir/patches/$step_patch"
    elif [[ $app == ecallmgr ]]; then
        replace_once "$source_dir/src/ecallmgr_originate.erl" \
            '-export([originate_api_command/4, build_originate/3]).' \
            '-export([originate_api_command/4, build_originate/3, intercept_unbridged_only/2]).'
    else
        replace_once "$source_dir/priv/couchdb/schemas/system_config.blackhole.json" \
            '        "max_queued_messages": {' \
            $'        "max_frame_size_bytes": {"type": "integer"},\n        "max_queued_messages": {'
    fi
    expect_rejection half-new-transition

    new_case edited-feature-line legacy
    if [[ $app == blackhole ]]; then
        replace_once "$source_dir/src/modules/bh_token_auth.erl" \
            'lager:debug("trying to authenticate with token")' \
            'lager:debug("fixture-edited-token-message")'
    elif [[ $app == ecallmgr ]]; then
        replace_once "$source_dir/src/ecallmgr_originate.erl" \
            '-export([originate_api_command/4, build_originate/3]).' \
            '-export([originate_api_command/4]).'
    else
        replace_once "$source_dir/src/api_util.erl" \
            'is_custom_route_module(<<"members">>) -> '\''true'\'';' \
            'is_custom_route_module(<<"members">>) -> '\''false'\'';'
    fi
    expect_rejection edited-feature-line

    new_case missing-file legacy
    mv -- "$source_dir/$missing_source" "$work/removed-source.fixture"
    expect_rejection missing-file

    new_case symlink-file legacy
    mv -- "$source_dir/$missing_source" "$work/link-target.fixture"
    ln -s -- "$work/link-target.fixture" "$source_dir/$missing_source"
    expect_rejection symlink-file

    new_case symlink-ancestor legacy
    mv -- "$source_dir/src" "$work/external-src"
    ln -s -- "$work/external-src" "$source_dir/src"
    expect_rejection symlink-ancestor

    new_case traversal-root legacy
    configured_root="$root/../root"
    expect_rejection traversal-root

    for patch_kind in current transition; do
        new_case "out-of-scope-$patch_kind-patch" legacy
        if [[ $patch_kind == current ]]; then target_patch=$new_patch; else target_patch=$step_patch; fi
        printf '\ndiff --git a/src/fixture-out-of-scope b/src/fixture-out-of-scope\nnew file mode 100644\n--- /dev/null\n+++ b/src/fixture-out-of-scope\n@@ -0,0 +1 @@\n+unexpected mutation\n' \
            >>"$script_dir/patches/$target_patch"
        expect_rejection "out-of-scope-$patch_kind-patch"
    done

    new_case missing-transition legacy
    mv -- "$script_dir/patches/$step_patch" "$work/withheld-transition.patch"
    expect_rejection missing-transition

    new_case invalid-new-postcondition legacy
    # Transition itself is valid, but the proposed current patch describes a
    # different result. This must fail during private staging, before real apply.
    if [[ $app == blackhole ]]; then
        replace_once "$script_dir/patches/$new_patch" \
            '+    lager:debug("trying to authenticate with token"),' \
            '+    lager:debug("fixture-inconsistent-current-patch"),'
    elif [[ $app == ecallmgr ]]; then
        replace_once "$script_dir/patches/$new_patch" \
            "erlang:error('invalid_acdc_intercept_target')" "erlang:error('fixture_invalid_intercept_target')"
    else
        replace_once "$script_dir/patches/$new_patch" \
            '+            "default": 65536,' '+            "default": 65535,'
    fi
    expect_rejection invalid-new-postcondition

    new_case wrong-transition-content legacy
    # Unlike the previous case, current is the authentic reviewed patch. The
    # transition is valid/applicable but its result has the wrong frame default.
    # Full-current reverse verification must catch this before real-tree writes.
    if [[ $app == blackhole ]]; then
        replace_once "$script_dir/patches/$step_patch" \
            '+-define(DEFAULT_MAX_FRAME_SIZE, 65536).' '+-define(DEFAULT_MAX_FRAME_SIZE, 65535).'
    elif [[ $app == ecallmgr ]]; then
        replace_once "$script_dir/patches/$step_patch" \
            "erlang:error('invalid_acdc_intercept_target')" "erlang:error('fixture_invalid_intercept_target')"
    else
        replace_once "$script_dir/patches/$step_patch" \
            '+            "default": 65536,' '+            "default": 65535,'
    fi
    git -C "$source_dir" apply --check "$script_dir/patches/$step_patch"
    expect_rejection wrong-transition-content
done

select_app blackhole
new_case previous-complete-pre-stream pre-stream
expect_success previous-complete-pre-stream

new_case previous-frame-integration legacy
git -C "$source_dir" apply "$script_dir/patches/$step_patch"
expect_success previous-frame-integration

new_case cleanup-before-frame legacy
git -C "$source_dir" apply "$script_dir/patches/blackhole-binding-cleanup.patch"
expect_success cleanup-before-frame

new_case partial-binding-cleanup legacy
git -C "$source_dir" apply "$script_dir/patches/$step_patch"
git -C "$source_dir" apply --include=src/bh_context.erl "$script_dir/patches/blackhole-binding-cleanup.patch"
expect_rejection partial-binding-cleanup

new_case missing-binding-cleanup legacy
mv -- "$script_dir/patches/blackhole-binding-cleanup.patch" "$work/withheld-cleanup.patch"
expect_rejection missing-binding-cleanup

new_case previous-complete-pre-queue pre-queue
[[ ! -e $source_dir/src/modules/bh_queue_live.erl ]] || fail 'pre-queue baseline must not contain the new module'
expect_success previous-complete-pre-queue

# Queue-live overlaps the older socket/context deltas. Every partial queue-live
# state must be rejected, not mistaken for another independently installed step.
for queue_path in src/bh_context.erl src/blackhole_socket_handler.erl src/blackhole.hrl src/modules/bh_queue_live.erl; do
    queue_label="partial-queue-${queue_path##*/}"
    new_case "$queue_label" pre-queue
    git -C "$source_dir" apply --include="$queue_path" "$script_dir/patches/blackhole-queue-live.patch"
    expect_rejection "$queue_label"
done

new_case missing-blackhole-header pre-queue
mv -- "$source_dir/src/blackhole.hrl" "$work/withheld-header.fixture"
expect_rejection missing-blackhole-header

new_case unrelated-new-module pre-queue
printf 'unrelated module sentinel\n' >"$source_dir/src/modules/bh_queue_live.erl"
expect_rejection unrelated-new-module

new_case missing-current-queue-module current
mv -- "$source_dir/src/modules/bh_queue_live.erl" "$work/withheld-queue-module.fixture"
expect_rejection missing-current-queue-module

for queue_patch in blackhole-pre-queue-live-integration.patch blackhole-queue-live.patch; do
    new_case "missing-$queue_patch" pre-queue
    mv -- "$script_dir/patches/$queue_patch" "$work/withheld-queue-patch.fixture"
    expect_rejection "missing-$queue_patch"
done

new_case dry-run-missing-queue-transition clean
fixture_dry_run=true
configured_root="$work/not-created"
mv -- "$script_dir/patches/blackhole-queue-live.patch" "$work/withheld-queue-patch.fixture"
expect_rejection dry-run-missing-queue-transition

new_case out-of-scope-queue-transition pre-queue
printf '\ndiff --git a/src/fixture-out-of-scope b/src/fixture-out-of-scope\nnew file mode 100644\n--- /dev/null\n+++ b/src/fixture-out-of-scope\n@@ -0,0 +1 @@\n+unexpected mutation\n' \
    >>"$script_dir/patches/blackhole-queue-live.patch"
expect_rejection out-of-scope-queue-transition

new_case wrong-queue-transition-content pre-queue
replace_once "$script_dir/patches/blackhole-queue-live.patch" \
    'queue_live requires fresh asynchronous authorization' 'fixture-inconsistent-queue-authorization'
git -C "$source_dir" apply --check "$script_dir/patches/blackhole-queue-live.patch"
expect_rejection wrong-queue-transition-content

new_case wrong-pre-queue-baseline legacy
replace_once "$script_dir/patches/blackhole-pre-queue-live-integration.patch" \
    '+    lager:debug("trying to authenticate with token"),' \
    '+    lager:debug("fixture-inconsistent-pre-queue-baseline"),'
expect_rejection wrong-pre-queue-baseline

[[ $transition_fixture_count == 111 ]] || fail "unexpected case count: $transition_fixture_count"
printf 'PASS all %s bounded source-transition cases (no builds, services or network)\n' "$transition_fixture_count" \
    | tee -a "$transition_fixture_output/results.log"
