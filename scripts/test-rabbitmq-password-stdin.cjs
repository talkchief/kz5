#!/usr/bin/env node
'use strict';
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process'), crypto = require('node:crypto'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..'), workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-rabbitmq-stdin.'));
const bin = path.join(workspace, 'bin'); fs.mkdirSync(bin);
fs.copyFileSync(path.join(__dirname, 'test-fixtures/rabbitmqctl-secret.cjs'), path.join(bin, 'rabbitmqctl'));
fs.chmodSync(path.join(bin, 'rabbitmqctl'), 0o700);
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
let count = 0;
function run({scenario = 'helper', operation = 'authenticate_user', password = 'Fixture-Only.AZaz09_@!%+=:-', cliStatus = 0, trace = false, hang = false}) {
  const work = path.join(workspace, String(++count)); fs.mkdirSync(work, {mode: 0o700});
  const traceFile = path.join(work, 'calls.jsonl'); fs.writeFileSync(traceFile, '', {mode: 0o600});
  const env = {...process.env, PATH: bin + path.delimiter + process.env.PATH,
    KAZOO_TEST_ROOT: root, KAZOO_TEST_WORK: work, KAZOO_TEST_TRACE: traceFile,
    KAZOO_TEST_SCENARIO: scenario, KAZOO_TEST_OPERATION: operation,
    KAZOO_TEST_CLI_STATUS: String(cliStatus), KAZOO_TEST_XTRACE: String(trace), KAZOO_TEST_HANG: String(hang)};
  // Password arrives only over the fixture's stdin, never test-runner argv/env.
  delete env.KAZOO_RABBITMQ_PASSWORD; delete env.KAZOO_AMQP_URI;
  const result = cp.spawnSync('bash', [path.join(__dirname, 'test-fixtures/rabbitmq-password.sh')],
    {env, input: password, encoding: 'utf8', timeout: 15000});
  assert(!result.error, 'Fixture execution failed');
  const records = fs.readFileSync(traceFile, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
  const logs = result.stdout + result.stderr + (fs.existsSync(path.join(work, 'xtrace')) ? fs.readFileSync(path.join(work, 'xtrace'), 'utf8') : '');
  if (password.length) assert(!logs.includes(password), 'Password exposed in output or shell trace');
  assert(!logs.includes(encodeURIComponent(password)) || password.length === 0, 'Encoded password exposed');
  assert(!logs.includes('client stdout') && !logs.includes('client stderr'), 'Untrusted CLI diagnostics leaked');
  for (const item of records.filter(p => p.stdin_sha256)) {
    assert.equal(item.stdin_sha256, digest(password + '\n'), 'CLI did not receive exact configured password');
    assert.equal(item.secret_environment_absent, true); assert.equal(item.argv_secret_absent, true);
    assert.deepEqual(item.arguments, [item.operation, 'fixture-user'], 'Exact RabbitMQ stdin dispatch arguments required');
  }
  return {status: result.status, records, logs};
}
try {
  for (const operation of ['add_user', 'change_password', 'authenticate_user']) {
    for (const trace of [false, true]) {
      const result = run({operation, trace}); assert.equal(result.status, 0);
      assert.equal(result.records.length, 2); assert.equal(result.records[0].operation, 'password-timeout');
      assert.equal(result.records[1].operation, operation);
    }
    for (const cliStatus of [1, 64, 70]) {
      const result = run({operation, cliStatus, trace: true}); assert.equal(result.status, cliStatus);
      assert.equal(result.records.length, 2);
    }
    const hung = run({operation, trace: true, hang: true}); assert.equal(hung.status, 124);
    assert.equal(hung.records[0].operation, 'password-timeout');
    assert.equal(hung.records[1].operation, operation);
  }
  console.log('PASS all3 operations, exact two-argument stdin dispatch, tracing/secret boundaries, failure status and bounded hung-client termination');
  for (const password of ['', ' leading', 'trailing ', 'line1\nline2', 'carriage\rreturn', 'quote"value']) {
    const result = run({password, trace: true}); assert.equal(result.status, 2); assert.equal(result.records.length, 0);
  }
  const unsupported = run({operation: 'delete_user', trace: true}); assert.equal(unsupported.status, 2);
  assert.equal(unsupported.records.length, 0);
  console.log('PASS malformed/whitespace/line-breaking input and nonallowlisted operation rejected before CLI');
  for (const scenario of ['create', 'update']) {
    const result = run({scenario}); assert.equal(result.status, 0);
    const passwordOps = result.records.filter(r => r.stdin_sha256).map(r => r.operation);
    assert.deepEqual(passwordOps, [scenario === 'create' ? 'add_user' : 'change_password', 'authenticate_user']);
    assert(result.records.some(r => r.operation === 'set_permissions'));
    assert.equal(result.records.filter(r => r.operation === 'restart').length, 1);
  }
  const verified = run({scenario: 'verify'}); assert.equal(verified.status, 0);
  assert.deepEqual(verified.records.filter(r => r.stdin_sha256).map(r => r.operation), ['authenticate_user']);
  assert(!verified.records.some(r => r.operation === 'restart'));
  for (const scenario of ['create', 'update', 'verify']) assert.notEqual(run({scenario, cliStatus: 70}).status, 0);
  const dry = run({scenario: 'dry-run'}); assert.equal(dry.status, 0); assert.equal(dry.records.length, 0);
  console.log('PASS installer create/update/verify semantics, vhost/permissions, failure propagation and nonmutating verify dry-run');
  const source = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
  const helper = source.slice(source.indexOf('rabbitmqctl_password() ('), source.indexOf('\ninstall_rabbitmq()'));
  assert(helper.indexOf('set +x') < helper.indexOf('${KAZOO_RABBITMQ_PASSWORD'));
  assert(!/rabbitmqctl (?:change_password|add_user|authenticate_user)[^\n]*KAZOO_RABBITMQ_PASSWORD/.test(source));
  assert.equal((source.match(/rabbitmqctl_password (?:change_password|add_user|authenticate_user)/g) || []).length, 3);
  assert(!/mktemp|write_file|eval|bash -c|--password/.test(helper));
  assert.match(helper, /timeout --signal=TERM --kill-after=5 30\s*\\\s*rabbitmqctl "\$operation" "\$KAZOO_RABBITMQ_USER"/);
  assert(!/rabbitmqctl -q/.test(helper), 'Quiet flag would disable RabbitMQ 3.13 password stdin');
  console.log(`PASS source call boundaries; ${count} offline scenarios, zero real broker operations. Private traces: ${workspace}`);
} catch (error) { console.error(error.stack); process.exitCode = 1; }
