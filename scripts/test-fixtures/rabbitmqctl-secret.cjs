#!/usr/bin/env node
'use strict';
// Offline executable double: this file never delegates to a real CLI or broker.
const fs = require('node:fs'), crypto = require('node:crypto'), assert = require('node:assert/strict');
const args = process.argv.slice(2), env = process.env;
const append = item => fs.appendFileSync(env.KAZOO_TEST_TRACE, JSON.stringify(item) + '\n');
if (args[0] === '-q' && args[1] === 'list_users') {
  assert.equal(args.length, 2); append({operation: 'list_users'});
  if (env.KAZOO_TEST_SCENARIO === 'update') console.log(env.KAZOO_RABBITMQ_USER + '\t[]');
} else if (args[0] === '-q' && args[1] === 'list_vhosts') {
  assert.deepEqual(args, ['-q', 'list_vhosts', 'name']); append({operation: 'list_vhosts'});
  console.log(env.KAZOO_RABBITMQ_VHOST);
} else if (args[0] === 'set_permissions') {
  assert.deepEqual(args, ['set_permissions', '-p', env.KAZOO_RABBITMQ_VHOST,
    env.KAZOO_RABBITMQ_USER, '.*', '.*', '.*']); append({operation: 'set_permissions'});
} else {
  assert.equal(args.length, 2, 'RabbitMQ 3.13 disables stdin when any extra argument (including -q) is present');
  assert.equal(args[1], env.KAZOO_RABBITMQ_USER);
  assert(['add_user', 'change_password', 'authenticate_user'].includes(args[0]));
  assert(!Object.hasOwn(env, 'KAZOO_RABBITMQ_PASSWORD'), 'Password inherited by child');
  assert(!Object.hasOwn(env, 'KAZOO_AMQP_URI'), 'Encoded password inherited by child');
  assert(!(env.SHELLOPTS || '').split(':').includes('xtrace'), 'Tracing inherited by CLI wrapper');
  const bytes = fs.readFileSync(0);
  assert.equal(bytes.at(-1), 10); assert.equal(bytes.subarray(0, -1).includes(10), false);
  const secret = bytes.subarray(0, -1).toString('utf8');
  assert(Object.values(env).every(value => !value.includes(secret)), 'Secret present in another child environment value');
  assert(!fs.readFileSync('/proc/self/cmdline').includes(Buffer.from(secret)), 'Password exposed in process argv');
  append({operation: args[0], arguments: args, stdin_sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
    secret_environment_absent: true, argv_secret_absent: true});
  // Exercise worst-case client diagnostics; the wrapper must discard both.
  process.stdout.write('client stdout ' + secret + '\n');
  process.stderr.write('client stderr ' + secret + '\n');
  process.exitCode = Number(env.KAZOO_TEST_CLI_STATUS || 0);
  if (env.KAZOO_TEST_HANG === 'true') setInterval(() => {}, 1000);
}
