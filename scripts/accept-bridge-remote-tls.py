#!/usr/bin/env python3
"""Opt-in .26 -> isolated .44 broker TLS proof; never constructs providers."""
import hashlib
import importlib.util
import json
import logging
import os
from pathlib import Path
import re
import socket
import ssl
import sys
import uuid

HERE = Path(__file__).resolve()
spec = importlib.util.spec_from_file_location('consumer_proof', HERE.with_name('accept-push-bridge-consumer.py'))
consumer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(consumer)
from bridge import BridgeRuntime, amqp_tls_options
from amqp_management import verify_topology
from service_launcher import protected_read, unique_object

FIXTURE = Path('/root/kz5-bridge-remote-proof-client/client.json')
IDENTITY = 'kz5-bridge-proof'
HOST = '10.1.0.44'


def validate_fixture(value):
    if not isinstance(value, dict) or set(value) != {
            'owner', 'host', 'port', 'management_port', 'username', 'password', 'vhost', 'ca_pem'}:
        raise ValueError('invalid_fixture')
    for key, expected in {'owner': IDENTITY, 'host': HOST, 'port': 35671,
                          'management_port': 35672, 'username': IDENTITY, 'vhost': IDENTITY}.items():
        if type(value[key]) is not type(expected) or value[key] != expected:
            raise ValueError('foreign_broker_refused')
    if not isinstance(value['password'], str) or not re.fullmatch('[0-9a-f]{64}', value['password']):
        raise ValueError('invalid_fixture_password')
    ca = value['ca_pem']
    if not isinstance(ca, str) or len(ca) > 16384 or 'PRIVATE KEY' in ca:
        raise ValueError('invalid_fixture_ca')
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.load_verify_locations(cadata=ca)
    return value


def tls_probe(context, name=HOST, expected_failure=None):
    try:
        with socket.create_connection((HOST, 35671), timeout=5) as connection:
            with context.wrap_socket(connection, server_hostname=name) as protected:
                if expected_failure or protected.version() not in ('TLSv1.2', 'TLSv1.3'):
                    raise ValueError('tls_not_verified')
                return protected.version()
    except ssl.SSLCertVerificationError as error:
        codes = {'hostname': (62, 64), 'authority': (18, 19, 20, 21)}
        if expected_failure not in codes or error.verify_code not in codes[expected_failure]:
            raise ValueError('wrong_tls_failure') from None
        return 'certificate_rejected'


def write_new(path, value):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'w', closefd=False) as stream:
            stream.write(value); stream.flush(); os.fsync(fd)
    finally:
        os.close(fd)


def check_broker_identity(settings):
    import requests
    with requests.Session() as session:
        session.trust_env = False
        with session.get('https://10.1.0.44:35672/api/overview',
                         auth=(settings['AMQP_USER'], settings['AMQP_PASS']),
                         verify=settings['AMQP_MANAGEMENT_CA_FILE'], allow_redirects=False,
                         stream=True, timeout=(3.05, 5)) as response:
            if response.status_code != 200: raise ValueError('broker_identity_unverified')
            body = bytearray()
            for chunk in response.iter_content(8192):
                body.extend(chunk)
                if len(body) > 131072: raise ValueError('broker_identity_too_large')
            value = json.loads(body, object_pairs_hook=unique_object)
            # RabbitMQ's default display cluster name uses the OS hostname;
            # the Erlang node retains its explicitly configured localhost name.
            if (value.get('cluster_name') != 'rabbit_kz5_bridgeproof@dev-testing'
                    or value.get('node') != 'rabbit_kz5_bridgeproof@localhost'):
                raise ValueError('wrong_broker_cluster')


def cleanup_owned_resources(connection, settings):
    # RabbitMQ3.13 quorum queues reject if-unused/if-empty delete flags (the
    # whole AMQP connection closes). This is NOT a general queue cleanup tool:
    # only this fixed isolated instance and fresh UUID-local fixture are in
    # scope, after its sole producer/consumer have stopped. Read both queues
    # before any deletion and require the broker to report zero deleted bodies.
    queue, exchange = settings.get('QUEUE', ''), settings.get('EXCHANGE', '')
    match = re.fullmatch(r'(remote-[0-9a-f]{32})\.quorum-v1', queue)
    if (not match or exchange != match[1] + '.pushes' or settings.get('AMQP_HOST') != HOST
            or settings.get('AMQP_PORT') != 35671 or settings.get('AMQP_VHOST') != IDENTITY
            or settings.get('AMQP_USER') != IDENTITY or settings.get('AMQP_TLS') != 'true'):
        raise ValueError('cleanup_scope_refused')
    channel = connection.channel()
    for name in (queue, queue + '.dlq'):
        observed = channel.queue.declare(queue=name, passive=True)
        if any(type(observed.get(field)) is not int or observed[field] != 0
               for field in ('message_count', 'consumer_count')):
            raise ValueError('cleanup_not_drained')
    for name in (queue, queue + '.dlq'):
        deleted = channel.queue.delete(queue=name)
        if type(deleted.get('message_count')) is not int or deleted['message_count'] != 0:
            raise ValueError('cleanup_deleted_messages')
    for name in (queue + '.dlx', exchange):
        channel.exchange.delete(exchange=name, if_unused=True)
    channel.close()


def main():
    if (sys.argv[1:] != ['--run-development-remote-tls-proof'] or os.geteuid() != 0
            or socket.gethostname() != 'kz5-testing' or os.environ.get('NOTIFY_SOCKET')):
        raise ValueError('explicit_original_development_host_required')
    fixture = validate_fixture(json.loads(protected_read(FIXTURE, 32768), object_pairs_hook=unique_object))
    base = Path('/var/log/kazoo-acceptance')
    info = base.lstat()
    if not base.is_dir() or base.is_symlink() or info.st_uid or info.st_mode & 0o022:
        raise ValueError('unprotected_receipt_parent')
    directory = base / ('bridge-remote-tls-' + str(uuid.uuid4()))
    directory.mkdir(mode=0o700)
    ca = directory / 'ca.pem'
    write_new(ca, fixture['ca_pem'])
    receipt = {'owner': directory.name, 'complete': False, 'provider_calls': 0, 'production_touched': False,
               'broker': HOST, 'broker_instance': 'rabbit_kz5_bridgeproof@localhost',
               'client_host': 'kz5-testing', 'checks': [], 'counter_observations': [],
               'normal_service_reconfigured': False, 'broker_restart_tested': False}
    inputs = [HERE, HERE.with_name('accept-push-bridge-consumer.py'),
              HERE.with_name('accept-push-bridge-retry.py'),
              *sorted((HERE.parents[1] / 'services/push-bridge').glob('*.py')),
              HERE.parents[1] / 'services/push-bridge/requirements.lock']
    pins = {str(file): hashlib.sha256(file.read_bytes()).hexdigest() for file in inputs}
    connection = driver = None
    try:
        import amqpstorm
        from importlib.metadata import version
        if version('AMQPStorm') != '2.11.1': raise ValueError('unexpected_amqpstorm_version')
        prefix = 'remote-' + uuid.uuid4().hex
        settings = {'TOPOLOGY': 'quorum-v1', 'RETRY': 'quorum-counted-v1', 'FRESHNESS': 'unix-ms-v1',
                    'AMQP_HOST': HOST, 'AMQP_PORT': 35671, 'AMQP_USER': IDENTITY,
                    'AMQP_PASS': fixture['password'], 'AMQP_VHOST': IDENTITY,
                    'AMQP_TLS': 'true', 'AMQP_CA_FILE': str(ca),
                    'AMQP_MANAGEMENT_URL': 'https://10.1.0.44:35672',
                    'AMQP_MANAGEMENT_CA_FILE': str(ca),
                    'EXCHANGE': prefix + '.pushes', 'QUEUE': prefix + '.quorum-v1',
                    'BINDING_KEY': 'fixture.only'}
        tls = amqp_tls_options(settings)
        context = tls['ssl_options']['context']
        receipt['tls_version'] = tls_probe(context)
        tls_probe(context, name='wrong-broker.invalid', expected_failure='hostname')
        tls_probe(ssl.create_default_context(), expected_failure='authority')
        receipt['checks'].append('trusted_tls_and_exact_certificate_negative_cases')
        check_broker_identity(settings)
        receipt['checks'].append('authenticated_https_exact_isolated_broker_identity')
        # Actual production connector. No runtime/provider constructor is used.
        runtime = BridgeRuntime.__new__(BridgeRuntime)
        runtime._settings, runtime._amqp_tls_options, runtime.amqpstorm = settings, tls, amqpstorm
        connection = runtime._connect_amqp()
        channel = connection.channel()
        channel.exchange.declare(exchange=settings['EXCHANGE'], exchange_type='topic', durable=True)
        channel.close()
        receipt['queue'] = settings['QUEUE']; receipt['exchange'] = settings['EXCHANGE']
        driver = consumer.ConsumerProof(connection, settings, amqpstorm.AMQPChannelError,
                                        verify_topology, receipt)
        driver.run()
        receipt['checks'].append('native_consumer_retry_over_remote_amqps_and_https_topology')
        cleanup_owned_resources(connection, settings)
        receipt['isolated_queue_resources_removed'] = True
        receipt['complete'] = True
    except Exception as error:
        receipt['failure'] = (error.code if isinstance(error, consumer.proof.ProofFailure)
                              and error.code in consumer.proof.FAILURES else 'remote_tls_proof_failed')
    finally:
        if driver is not None: receipt['synthetic_dispatches'] = dict(driver.dispatches)
        if connection is not None:
            try: connection.close()
            except Exception: receipt['complete'] = False; receipt['connection_close_uncertain'] = True
        receipt['source_sha256'] = pins
        receipt['source_stable'] = all(hashlib.sha256(Path(file).read_bytes()).hexdigest() == digest
                                       for file, digest in pins.items())
        if not receipt['source_stable']: receipt['complete'] = False
        write_new(directory / 'receipt.json', json.dumps(receipt, indent=2) + '\n')
        print(json.dumps({'receipt': str(directory / 'receipt.json'), 'complete': receipt['complete'],
                          'checks': receipt['checks']}))
    if not receipt['complete']: raise ValueError('remote_tls_proof_incomplete')


if __name__ == '__main__':
    # Third-party error strings may contain credentials. Only receipt categories
    # and the fixed final error cross this acceptance tool's output boundary.
    logging.disable(logging.CRITICAL)
    try: main()
    except Exception:
        print('Remote bridge TLS proof failed; inspect protected receipt.', file=sys.stderr)
        sys.exit(1)
