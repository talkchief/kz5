#!/usr/bin/env bash
# Offline source/schema proof only. Run inside the external resource guard and
# an isolated network namespace; this runner does not install or deploy anything.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || { printf '%s\n' 'This regression takes no arguments.' >&2; exit 64; }
unset NODE_OPTIONS NODE_PATH
catalog_root=$(cd -- "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
catalog_proof_dir=$(/usr/bin/mktemp -d /tmp/kazoo-api-live-catalog.XXXXXX) || exit 73
[[ $catalog_proof_dir == /tmp/kazoo-api-live-catalog.* && -d $catalog_proof_dir && ! -L $catalog_proof_dir ]] || exit 73
[[ $(/usr/bin/stat -c '%u:%a' -- "$catalog_proof_dir") == "$(/usr/bin/id -u):700" ]] || exit 73
readonly catalog_root catalog_proof_dir
cd -- "$catalog_root"
catalog_stage=pinning
catalog_pins_ready=false
catalog_inputs=(
    scripts/test-api-docs-queue-live-catalog.sh
    scripts/test-api-docs-queue-live.cjs
    scripts/build-api-docs.cjs scripts/verify-api-docs.cjs
    scripts/api-docs-queue-live.cjs scripts/api-docs-overlays.cjs
    scripts/api-docs-queue-editor.cjs scripts/api-docs-agent-queue-login.cjs
    scripts/api-docs-members-devices.cjs scripts/api-docs-blackhole.cjs
    scripts/api-docs-tooling/package.json scripts/api-docs-tooling/package-lock.json
    applications/acdc/src/cb_acdc_live.erl applications/acdc/src/cb_queues.erl
    applications/acdc/src/acdc_dashboard_collector.erl
    applications/acdc/src/acdc_dashboard_projection.erl
    applications/acdc/src/acdc_dashboard_snapshot.erl
    applications/acdc/src/kapi_acdc_dashboard.erl applications/acdc/src/acdc_stats.erl
    applications/acdc/src/acdc_stats.hrl
    core/kazoo_amqp/src/gen_listener.erl core/kazoo_apps/src/kz_amqp_worker.erl
    /usr/bin/node
)

catalog_finish() {
    local catalog_status=$? catalog_stable=false
    trap - EXIT
    set +e
    if [[ $catalog_pins_ready == true ]]; then
        if /usr/bin/sha256sum -- "${catalog_inputs[@]}" > "$catalog_proof_dir/inputs.after.sha256" 2> "$catalog_proof_dir/pins.after.log" \
            && /usr/bin/cmp -s -- "$catalog_proof_dir/inputs.before.sha256" "$catalog_proof_dir/inputs.after.sha256"; then
            catalog_stable=true
        else
            catalog_status=1
            printf '%s\n' 'Input stability failed; retained before/after hashes.' >&2
        fi
    else
        catalog_status=1
    fi
    [[ $catalog_stage == complete ]] || { ((catalog_status != 0)) || catalog_status=1; }
    /usr/bin/node - "$catalog_proof_dir" "$catalog_status" "$catalog_stage" "$catalog_stable" <<'JS'
const fs = require('node:fs'), path = require('node:path');
const [directory, code, stage, stable] = process.argv.slice(2);
const receipt = {format_version: 1, result: Number(code) === 0 ? 'PASS' : 'FAIL',
    exit_code: Number(code), stage, pinned_inputs_stable: stable === 'true',
    scope: 'offline focused queue-live schemas and complete private API catalog',
    network_isolation: 'external guard responsibility', runtime_verified: false,
    deployment_verified: false, repository_generated_assets_written: false,
    evidence_directory: directory};
fs.writeFileSync(path.join(directory, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify(receipt));
JS
    if (($? != 0)); then catalog_status=1; fi
    printf 'Queue-live catalog exit %s; retained evidence: %s\n' "$catalog_status" "$catalog_proof_dir"
    exit "$catalog_status"
}
trap catalog_finish EXIT
printf 'Retaining private API catalog proof in %s\n' "$catalog_proof_dir"
/usr/bin/sha256sum -- "${catalog_inputs[@]}" > "$catalog_proof_dir/inputs.before.sha256"
catalog_pins_ready=true

catalog_stage=focused
/usr/bin/node "$catalog_root/scripts/test-api-docs-queue-live.cjs" > "$catalog_proof_dir/focused.log" 2>&1
catalog_stage=build
# The builder makes its nested public-documentation artifact 0755/0644. The
# outer mktemp parent stays 0700; no existing or repository artifact is targeted.
/usr/bin/node "$catalog_root/scripts/build-api-docs.cjs" --output "$catalog_proof_dir/catalog" > "$catalog_proof_dir/build.log" 2>&1
catalog_stage=verify
/usr/bin/node "$catalog_root/scripts/verify-api-docs.cjs" "$catalog_proof_dir/catalog" > "$catalog_proof_dir/verify.log" 2>&1
catalog_stage=coverage
/usr/bin/node - "$catalog_root" "$catalog_proof_dir" <<'JS' > "$catalog_proof_dir/coverage.log" 2>&1
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const [root, directory] = process.argv.slice(2);
const coverage = JSON.parse(fs.readFileSync(path.join(directory, 'catalog/coverage.json')));
const spec = JSON.parse(fs.readFileSync(path.join(directory, 'catalog/openapi.json')));
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const checked = new Map();
function check(input) {
    assert(input && typeof input.file === 'string' && /^[a-f0-9]{64}$/.test(input.sha256), 'Invalid recorded input');
    assert(!path.isAbsolute(input.file) && input.file.split('/').every(part => part && part !== '.' && part !== '..'), 'Unsafe recorded input path');
    const file = path.join(root, input.file), real = fs.realpathSync(file);
    assert(real.startsWith(root + path.sep) && fs.statSync(real).isFile(), 'Recorded input escaped source tree');
    assert.equal(sha(fs.readFileSync(file)), input.sha256, 'Stale catalog input: ' + input.file);
    if (checked.has(input.file)) assert.equal(checked.get(input.file), input.sha256, 'Conflicting duplicate input');
    checked.set(input.file, input.sha256);
}
assert(Array.isArray(coverage.inputs) && coverage.inputs.length > 0, 'Missing catalog input inventory');
assert(Array.isArray(coverage.source_inventory) && coverage.source_inventory.length > 0, 'Missing handler inventory');
coverage.inputs.forEach(check);
coverage.source_inventory.forEach(check);
for (const required of ['scripts/build-api-docs.cjs', 'scripts/api-docs-overlays.cjs', 'scripts/api-docs-queue-live.cjs',
    'applications/acdc/src/cb_acdc_live.erl', 'applications/acdc/src/cb_queues.erl',
    'applications/acdc/src/acdc_dashboard_collector.erl', 'applications/acdc/src/acdc_dashboard_projection.erl',
    'applications/acdc/src/acdc_dashboard_snapshot.erl', 'applications/acdc/src/kapi_acdc_dashboard.erl',
    'applications/acdc/src/acdc_stats.erl']) {
    assert(coverage.inputs.some(input => input.file === required), 'Required coverage pin missing: ' + required);
}
for (const route of ['/accounts/{ACCOUNT_ID}/queues/live', '/accounts/{ACCOUNT_ID}/queues/{QUEUE_ID}/live']) {
    const operation = spec.paths[route]?.get;
    assert(operation, 'Queue-live route missing from full catalog');
    assert.equal(operation['x-implementation-status'], 'implemented-in-source; not-live-deployed');
    assert.equal(operation['x-runtime-source-sha256'], checked.get('applications/acdc/src/cb_acdc_live.erl'));
    assert(coverage.source_reviewed_operations.includes('GET ' + route), 'Reviewed route missing from coverage');
}
assert.equal(coverage.unresolved_reference_count, 0);
assert.equal(Object.keys(spec.paths).length, coverage.path_count);
console.log(JSON.stringify({result: 'PASS', recorded_inputs: coverage.inputs.length,
    handler_inputs: coverage.source_inventory.length, unique_current_inputs: checked.size,
    paths: coverage.path_count, operations: coverage.operation_count,
    internal_references: coverage.internal_reference_count, runtime_verified: false}));
JS
catalog_stage=complete
