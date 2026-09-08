#!/usr/bin/env python3
"""Create an isolated, temporary TLS broker on the authorized development .44.

Creation only: no main broker config, service restart, production connection,
provider key, or notification. Refuse existing state instead of overwriting it.
"""
import json
import os
from pathlib import Path
import pwd
import secrets
import socket
import subprocess
import sys

BASE = Path('/var/lib/kz5-bridge-remote-proof')
UNIT = Path('/etc/systemd/system/kz5-bridge-remote-proof.service')
USER = 'kz5-bridge-proof'
HOST = '10.1.0.44'
PORTS = ((HOST, 35671), (HOST, 35672), ('127.0.0.1', 35369), ('127.0.0.1', 35370))


def run(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=60, check=False)
    if result.returncode:
        raise RuntimeError('proof_setup_command_failed')


def broker_configuration(password):
    if len(password) != 64 or any(ch not in '0123456789abcdef' for ch in password):
        raise ValueError('invalid_fixture_password')
    return f'''listeners.tcp = none
listeners.ssl.1 = {HOST}:35671
ssl_options.cacertfile = {BASE}/tls/ca.pem
ssl_options.certfile = {BASE}/tls/server.pem
ssl_options.keyfile = {BASE}/tls/server.key
ssl_options.verify = verify_peer
ssl_options.fail_if_no_peer_cert = false
ssl_options.versions.1 = tlsv1.2
ssl_options.versions.2 = tlsv1.3
management.ssl.ip = {HOST}
management.ssl.port = 35672
management.ssl.cacertfile = {BASE}/tls/ca.pem
management.ssl.certfile = {BASE}/tls/server.pem
management.ssl.keyfile = {BASE}/tls/server.key
management.ssl.versions.1 = tlsv1.2
management.ssl.versions.2 = tlsv1.3
default_user = {USER}
default_pass = {password}
default_vhost = {USER}
default_user_tags.monitoring = true
log.console = false
log.file.level = warning
vm_memory_high_watermark.absolute = 512MiB
disk_free_limit.absolute = 1GB
'''


def service_unit():
    environment = {
        'ERL_EPMD_PORT': '35369', 'ERL_EPMD_ADDRESS': '127.0.0.1',
        'RABBITMQ_CONF_ENV_FILE': str(BASE / 'rabbitmq-env.conf'),
        'RABBITMQ_CONFIG_FILE': str(BASE / 'rabbitmq.conf'),
        'RABBITMQ_ADVANCED_CONFIG_FILE': str(BASE / 'advanced.config'),
        'RABBITMQ_NODENAME': 'rabbit_kz5_bridgeproof@localhost',
        'RABBITMQ_DIST_PORT': '35370',
        'RABBITMQ_MNESIA_BASE': str(BASE / 'mnesia'),
        'RABBITMQ_LOG_BASE': str(BASE / 'log'),
        'RABBITMQ_PID_FILE': str(BASE / 'state/rabbitmq.pid'),
        'RABBITMQ_ENABLED_PLUGINS_FILE': str(BASE / 'enabled_plugins'),
        'RABBITMQ_PLUGINS_EXPAND_DIR': str(BASE / 'state/plugins'),
        'RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS': '+S 2:2 +SDcpu 1 +SDio 2 +A 4 -kernel inet_dist_use_interface {127,0,0,1}',
    }
    return ('[Unit]\nDescription=Isolated Kazoo bridge remote TLS acceptance broker\n'
            '[Service]\nType=simple\nUser=' + USER + '\nGroup=' + USER + '\n'
            'WorkingDirectory=' + str(BASE) + '\n' +
            ''.join('Environment="' + key + '=' + value + '"\n' for key, value in environment.items()) +
            'ExecStart=/usr/lib/rabbitmq/bin/rabbitmq-server\n'
            'Restart=no\nRuntimeMaxSec=3600\nTimeoutStopSec=60\nKillMode=control-group\n'
            'MemoryMax=1G\nMemorySwapMax=0\nCPUQuota=200%\nTasksMax=256\n'
            'UMask=0077\nLimitCORE=0\nNoNewPrivileges=true\n'
            'ProtectSystem=strict\nProtectHome=read-only\nPrivateTmp=true\n'
            'ReadWritePaths=' + str(BASE) + '\n')


def write(path, content, mode=0o600, uid=0, gid=0):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    try:
        os.fchown(fd, uid, gid)
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'w', closefd=False) as output:
            output.write(content); output.flush(); os.fsync(fd)
    finally:
        os.close(fd)


def create():
    if os.geteuid() != 0 or socket.gethostname() != 'dev-testing':
        raise ValueError('wrong_development_host')
    if BASE.exists() or BASE.is_symlink() or UNIT.exists() or UNIT.is_symlink():
        raise ValueError('existing_fixture_refused')
    try:
        pwd.getpwnam(USER)
    except KeyError:
        pass
    else:
        raise ValueError('existing_user_refused')
    # This only tests exact port availability; it does not change firewall or
    # host resolution. Services must still prove actual TLS readiness afterward.
    for address, port in PORTS:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.bind((address, port))
    run(['/usr/sbin/useradd', '--system', '--user-group', '--no-create-home',
         '--home-dir', str(BASE / 'home'), '--shell', '/sbin/nologin', USER])
    identity = pwd.getpwnam(USER)
    BASE.mkdir(mode=0o750)
    os.chown(BASE, 0, identity.pw_gid)
    os.chmod(BASE, 0o750)
    for name in ['home', 'mnesia', 'log', 'state']:
        directory = BASE / name
        directory.mkdir(mode=0o700)
        os.chown(directory, identity.pw_uid, identity.pw_gid)
    (BASE / 'tls').mkdir(mode=0o750)
    os.chown(BASE / 'tls', 0, identity.pw_gid)
    os.chmod(BASE / 'tls', 0o750)
    write(BASE / 'home/.erlang.cookie', secrets.token_hex(32) + '\n', 0o400,
          identity.pw_uid, identity.pw_gid)
    password = secrets.token_hex(32)
    write(BASE / 'rabbitmq.conf', broker_configuration(password), 0o640, gid=identity.pw_gid)
    write(BASE / 'rabbitmq-env.conf', '', 0o640, gid=identity.pw_gid)
    write(BASE / 'advanced.config', '[].\n', 0o640, gid=identity.pw_gid)
    write(BASE / 'enabled_plugins', '[rabbitmq_management].\n', 0o640, gid=identity.pw_gid)
    tls = BASE / 'tls'
    # Synthetic, short-lived test CA only. No deployed wildcard/private key.
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
         '-subj', '/CN=Kazoo isolated bridge proof CA', '-addext', 'basicConstraints=critical,CA:TRUE',
         '-keyout', str(tls / 'ca.key'), '-out', str(tls / 'ca.pem')])
    run(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes',
         '-subj', '/CN=kz5-bridge-proof.invalid', '-keyout', str(tls / 'server.key'),
         '-out', str(tls / 'server.csr')])
    write(tls / 'server.ext', 'subjectAltName=IP:10.1.0.44,DNS:kz5-bridge-proof.invalid\n'
          'basicConstraints=critical,CA:FALSE\nextendedKeyUsage=serverAuth\n')
    run(['openssl', 'x509', '-req', '-in', str(tls / 'server.csr'), '-CA', str(tls / 'ca.pem'),
         '-CAkey', str(tls / 'ca.key'), '-CAcreateserial', '-days', '2', '-sha256',
         '-extfile', str(tls / 'server.ext'), '-out', str(tls / 'server.pem')])
    for name in ['ca.pem', 'server.pem', 'server.key']:
        os.chown(tls / name, 0, identity.pw_gid); os.chmod(tls / name, 0o640)
    # CA signing key is never available to the broker service user.
    os.chmod(tls / 'ca.key', 0o600)
    write(BASE / 'client.json', json.dumps({
        'owner': USER, 'host': HOST, 'port': 35671, 'management_port': 35672,
        'username': USER, 'password': password, 'vhost': USER,
        'ca_pem': (tls / 'ca.pem').read_text(),
    }, indent=2) + '\n')
    write(UNIT, service_unit(), 0o644)
    write(BASE / 'setup-receipt.json', json.dumps({
        'owner': USER, 'unit': UNIT.name, 'broker_prepared': True,
        'started': False, 'enabled_at_boot': False, 'main_broker_modified': False,
        'provider_calls': 0, 'amqp_port': 35671, 'management_port': 35672,
    }, indent=2) + '\n')
    run(['systemctl', 'daemon-reload'])
    print('PASS isolated TLS broker prepared, not started or enabled; main broker unchanged')


def refresh_owned_unit():
    """Repair only the exact first-version proof unit; never arbitrary services."""
    if os.geteuid() != 0 or socket.gethostname() != 'dev-testing':
        raise ValueError('wrong_development_host')
    marker = BASE / 'setup-receipt.json'
    for file in [marker, UNIT]:
        info = file.lstat()
        if file.is_symlink() or not file.is_file() or info.st_uid or info.st_nlink != 1 or info.st_mode & 0o022:
            raise ValueError('unowned_fixture')
    if json.loads(marker.read_text()).get('owner') != USER:
        raise ValueError('unowned_fixture')
    wanted = service_unit()
    previous = wanted.replace('RABBITMQ_PLUGINS_EXPAND_DIR=' + str(BASE / 'state/plugins'),
                              'RABBITMQ_PLUGINS_EXPAND_DIR=' + str(BASE / 'plugins'))
    current = UNIT.read_text()
    if current == wanted: return
    if current != previous: raise ValueError('changed_fixture_unit_refused')
    temporary = UNIT.with_suffix('.service.next')
    write(temporary, wanted, 0o644)
    os.replace(temporary, UNIT)
    run(['systemctl', 'daemon-reload'])
    print('PASS exact owned proof unit updated; no service started')


if __name__ == '__main__':
    try:
        if sys.argv[1:] == ['--create-on-development-44']: create()
        elif sys.argv[1:] == ['--refresh-owned-unit-on-development-44']: refresh_owned_unit()
        else: raise ValueError('explicit_action_required')
    except Exception:
        print('Remote bridge proof preparation refused; inspect private state before retrying.', file=sys.stderr)
        sys.exit(1)
