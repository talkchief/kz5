#!/usr/bin/env python3
"""Exercise the normal bridge installer with a temporary remote TLS config.

Fixed development scope. No push publishes. Original config and provider files
are preserved; a finally block restores through the same normal installer.
Protected receipts permit explicit --restore-only after an outer interruption.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import socket
import stat
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve()
spec = importlib.util.spec_from_file_location('remote_tls', HERE.with_name('accept-bridge-remote-tls.py'))
remote = importlib.util.module_from_spec(spec); spec.loader.exec_module(remote)
from service_launcher import CONFIG, CREDENTIAL_KEYS, protected_read, unique_object, load_configuration
from validate_config import PREFIX, validate
from bridge import BridgeRuntime, amqp_tls_options

STATE = Path('/var/log/kazoo-acceptance/bridge-service-remote')
CA = CONFIG.parent / 'remote-proof-ca.pem'
INSTALLER = HERE.with_name('install-kazoo5.sh')


def require(value, code):
    if not value: raise ValueError(code)


def digest(raw): return hashlib.sha256(raw).hexdigest()


def candidate_configuration(original, fixture, prefix):
    require(re.fullmatch('remote-[0-9a-f]{32}', prefix), 'invalid_test_identity')
    require(original.get(PREFIX+'AMQP_HOST') == '127.0.0.1'
            and original.get(PREFIX+'EXCHANGE') == 'kazoo5-mobile-acceptance'
            and original.get(PREFIX+'QUEUE') == 'kazoo5-mobile-acceptance'
            and original.get(PREFIX+'BINDING_KEY') == 'acceptance.only', 'original_scope_refused')
    remote.validate_fixture(fixture)
    changed = dict(original)
    overrides = {'AMQP_HOST': remote.HOST, 'AMQP_PORT': '35671', 'AMQP_TLS': 'true',
                 'AMQP_USER': remote.IDENTITY, 'AMQP_PASS': fixture['password'],
                 'AMQP_VHOST': remote.IDENTITY, 'AMQP_CA_FILE': str(CA),
                 'AMQP_MANAGEMENT_CA_FILE': str(CA), 'AMQP_MANAGEMENT_URL': 'https://10.1.0.44:35672',
                 'TOPOLOGY': 'quorum-v1', 'RETRY': 'quorum-counted-v1', 'FRESHNESS': 'unix-ms-v1',
                 'EXCHANGE': prefix + '.pushes', 'QUEUE': prefix + '.quorum-v1', 'BINDING_KEY': 'fixture.only'}
    changed.update({PREFIX+key: value for key, value in overrides.items()})
    require(not validate(changed), 'candidate_invalid')
    return changed


def save(receipt):
    temporary = STATE / ('receipt-' + uuid.uuid4().hex + '.tmp')
    remote.write_new(temporary, json.dumps(receipt, indent=2) + '\n')
    os.replace(temporary, STATE / 'receipt.json')
    for directory in (STATE, STATE.parent):
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try: os.fsync(descriptor)
        finally: os.close(descriptor)


def replace_config(expected, desired, mode, gid):
    info = CONFIG.lstat()
    require(stat.S_ISREG(info.st_mode) and not CONFIG.is_symlink() and info.st_uid == 0
            and info.st_nlink == 1 and CONFIG.read_bytes() == expected, 'changed_live_config_refused')
    temporary = CONFIG.parent / ('remote-proof-' + uuid.uuid4().hex + '.tmp')
    remote.write_new(temporary, desired.decode('utf8'))
    os.chown(temporary, 0, gid); os.chmod(temporary, mode)
    os.replace(temporary, CONFIG)
    descriptor = os.open(CONFIG.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try: os.fsync(descriptor)
    finally: os.close(descriptor)


def normal_install(label):
    log = STATE / (label + '.log')
    descriptor = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        process = subprocess.Popen(['/usr/bin/bash', str(INSTALLER), 'push-bridge'],
                                   stdout=descriptor, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            returncode = process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            # Killing Bash alone strands package-manager children and blocks
            # the restoration installer on their lock. Scope termination to
            # this invocation's new process group, never all package managers.
            for sig in (signal.SIGTERM, signal.SIGKILL):
                try: os.killpg(process.pid, sig)
                except ProcessLookupError: pass
                if sig == signal.SIGTERM:
                    time.sleep(2)
            process.wait(timeout=10)
            raise
    finally: os.close(descriptor)
    require(returncode == 0, 'normal_installer_failed')


def service_state():
    result = subprocess.run(['systemctl', 'show', 'kazoo-push-bridge.service', '-p', 'MainPID',
                             '-p', 'ActiveState', '-p', 'SubState', '-p', 'StatusText'],
                            capture_output=True, text=True, timeout=10, check=True)
    value = dict(line.split('=', 1) for line in result.stdout.splitlines())
    require(value.get('ActiveState') == 'active' and value.get('SubState') == 'running'
            and value.get('StatusText') == 'AMQP consumer registered; mobile delivery not verified'
            and value.get('MainPID', '').isdigit() and int(value['MainPID']) > 1, 'service_not_ready')
    return int(value['MainPID'])


def matching_connection(connections, pid, sockets):
    ports = set()
    for line in sockets.splitlines():
        columns = line.split()
        if len(columns) >= 6 and columns[0] == 'ESTAB' and columns[4] == '10.1.0.44:35671' \
                and re.search(r'pid=' + str(pid) + r',', line):
            match = re.fullmatch(r'10\.1\.0\.26:([0-9]+)', columns[3])
            if match: ports.add(int(match[1]))
    found = [value for value in connections if value.get('peer_host') == '10.1.0.26'
             and type(value.get('peer_port')) is int and value['peer_port'] in ports
             and value.get('user') == remote.IDENTITY and value.get('vhost') == remote.IDENTITY
             and value.get('ssl') is True and value.get('ssl_protocol') in ('tlsv1.2', 'tlsv1.3')
             and value.get('state') == 'running']
    require(len(ports) == 1 and len(found) == 1, 'service_tls_socket_not_verified')
    return found[0]


def verify_remote(settings):
    import requests
    pid = service_state()
    result = subprocess.run(['ss', '-Hntp', 'dst', '10.1.0.44:35671'], capture_output=True,
                            text=True, timeout=10, check=True)
    with requests.Session() as session:
        session.trust_env = False
        def get(path):
            with session.get(settings['AMQP_MANAGEMENT_URL'] + '/api/' + path,
                             auth=(settings['AMQP_USER'], settings['AMQP_PASS']), verify=str(CA),
                             timeout=(3.05, 5), allow_redirects=False, stream=True) as response:
                require(response.status_code == 200, 'management_read_failed')
                raw = bytearray()
                for chunk in response.iter_content(8192):
                    raw.extend(chunk); require(len(raw) <= 131072, 'management_response_too_large')
                return json.loads(raw, object_pairs_hook=unique_object)
        connection = matching_connection(get('connections'), pid, result.stdout)
        queue = get('queues/' + remote.IDENTITY + '/' + settings['QUEUE'])
        require(queue.get('consumers') == 1 and len(queue.get('consumer_details', [])) == 1,
                'service_consumer_not_verified')
        require(all(type(queue.get(key)) is int and queue[key] == 0
                    for key in ('messages', 'messages_ready', 'messages_unacknowledged')), 'test_queue_not_empty')
        require(queue['consumer_details'][0].get('channel_details', {}).get('connection_name')
                == connection['name'], 'consumer_connection_mismatch')
    return {'pid': pid, 'tls_protocol': connection['ssl_protocol'], 'consumer_count': 1}


def restore(receipt):
    original = protected_read(STATE/'original.json', 32768)
    candidate = protected_read(STATE/'candidate.json', 32768)
    require(digest(original) == receipt['original_sha256'] and digest(candidate) == receipt['candidate_sha256'],
            'backup_changed')
    live = CONFIG.read_bytes()
    if live != original:
        replace_config(candidate, original, receipt['original_mode'], receipt['original_gid'])
    receipt['phase'] = 'restoring_service'; save(receipt)
    normal_install('restore-' + uuid.uuid4().hex)
    service_state()
    require(CONFIG.read_bytes() == original, 'original_not_restored')
    for file, expected in receipt['provider_sha256'].items():
        require(digest(Path(file).read_bytes()) == expected, 'provider_file_changed')
    receipt['restored'] = True; receipt['phase'] = 'restored'; save(receipt)


def main():
    require(os.geteuid() == 0 and socket.gethostname() == 'kz5-testing', 'development_client_required')
    if sys.argv[1:] == ['--restore-only']:
        receipt = json.loads(protected_read(STATE/'receipt.json', 32768), object_pairs_hook=unique_object)
        require(receipt.get('owner') == 'kz5-bridge-remote-service-v1', 'wrong_receipt')
        restore(receipt); print('PASS original bridge configuration and service restored'); return
    require(sys.argv[1:] == ['--run-development-service-proof'], 'explicit_action_required')
    require(not STATE.exists() and not STATE.is_symlink() and not CA.exists() and not CA.is_symlink(),
            'existing_proof_state_refused')
    original_config = load_configuration()
    original = CONFIG.read_bytes(); info = CONFIG.stat()
    fixture = remote.validate_fixture(json.loads(protected_read(remote.FIXTURE, 32768), object_pairs_hook=unique_object))
    prefix = 'remote-' + uuid.uuid4().hex
    changed = candidate_configuration(original_config, fixture, prefix)
    candidate = (json.dumps(changed, indent=2) + '\n').encode()
    STATE.mkdir(mode=0o700)
    remote.write_new(STATE/'original.json', original.decode())
    remote.write_new(STATE/'candidate.json', candidate.decode())
    remote.write_new(CA, fixture['ca_pem'])
    receipt = {'owner': 'kz5-bridge-remote-service-v1', 'phase': 'prepared', 'complete': False, 'restored': False,
               'original_sha256': digest(original), 'candidate_sha256': digest(candidate),
               'original_mode': stat.S_IMODE(info.st_mode), 'original_gid': info.st_gid,
               'provider_sha256': {original_config[key]: digest(Path(original_config[key]).read_bytes())
                                  for key in CREDENTIAL_KEYS if original_config.get(key)},
               'provider_calls_requested': 0, 'pushes_published': 0,
               'queue': changed[PREFIX+'QUEUE'], 'exchange': changed[PREFIX+'EXCHANGE']}
    save(receipt)
    settings = {key[len(PREFIX):]: value for key, value in changed.items()}
    settings['AMQP_PORT'] = 35671
    connection = None; activated = False
    try:
        import amqpstorm
        remote.check_broker_identity(settings)
        runtime = BridgeRuntime.__new__(BridgeRuntime)
        runtime._settings, runtime.amqpstorm = settings, amqpstorm
        runtime._amqp_tls_options = amqp_tls_options(settings)
        connection = runtime._connect_amqp()
        channel = connection.channel()
        channel.exchange.declare(exchange=settings['EXCHANGE'], exchange_type='topic', durable=True)
        channel.close()
        replace_config(original, candidate, 0o600, 0)
        activated = True; receipt['phase'] = 'activated'; save(receipt)
        normal_install('remote-install')
        receipt['phase'] = 'verifying_remote_service'; save(receipt)
        deadline = time.monotonic() + 20
        while True:
            try:
                receipt['service_evidence'] = verify_remote(settings)
                break
            except ValueError:
                if time.monotonic() >= deadline: raise
                time.sleep(1)
        receipt['remote_service_verified'] = True; save(receipt)
    except Exception:
        receipt['failed_phase'] = receipt['phase']; save(receipt)
    finally:
        try:
            if connection is not None: connection.close(); connection = None
        except Exception:
            receipt['probe_connection_close_uncertain'] = True
        finally:
            if activated: restore(receipt)
        receipt['complete'] = bool(receipt.get('remote_service_verified') and receipt['restored']
                                   and not receipt.get('probe_connection_close_uncertain'))
        save(receipt)
        print(json.dumps({'receipt': str(STATE/'receipt.json'), 'complete': receipt['complete'],
                          'restored': receipt['restored'], 'remote_service_verified': receipt.get('remote_service_verified', False)}))
    require(receipt['complete'], 'remote_service_proof_incomplete')


if __name__ == '__main__':
    import logging
    logging.disable(logging.CRITICAL)
    try: main()
    except Exception:
        print('Remote service proof failed; inspect protected receipt; --restore-only is available.', file=sys.stderr)
        sys.exit(1)
