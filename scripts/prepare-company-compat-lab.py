#!/usr/bin/env python3
"""Create the dedicated, outbound-isolated CouchDB compatibility lab on .44.

This assessment helper is deliberately not a normal stack installer option.
It never modifies an existing lab, enables it at boot, imports data, or changes
the running Kazoo/CouchDB services. Must be run explicitly on development .44.
"""
import ipaddress
import json
import os
import pathlib
import pwd
import secrets
import subprocess
import sys

BASE = pathlib.Path('/var/lib/kazoo-compat-runtime')
UNIT_PATH = pathlib.Path('/etc/systemd/system/kazoo-compat-couchdb.service')
UNIT_NAME = UNIT_PATH.name
USER = 'kazoo-compat'
HOST = '10.1.0.44'


def unit_text():
    return '''# Managed by kz5 prepare-company-compat-lab.py; isolated assessment only.
[Unit]
Description=Isolated company CouchDB compatibility lab (no external network)

[Service]
Type=simple
User=kazoo-compat
Group=kazoo-compat
WorkingDirectory=/opt/couchdb
Environment=HOME=/var/lib/kazoo-compat-runtime/home
Environment=COUCHDB_ARGS_FILE=/var/lib/kazoo-compat-runtime/vm.args
Environment="COUCHDB_INI_FILES=/opt/couchdb/etc/default.ini /var/lib/kazoo-compat-runtime/local.ini"
ExecStart=/opt/couchdb/bin/couchdb
PrivateNetwork=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/kazoo-compat-runtime
InaccessiblePaths=-/etc/kazoo -/var/lib/kazoo-compat/snapshots -/opt/couchdb/etc/local.ini -/opt/couchdb/etc/local.d -/opt/couchdb/data
NoNewPrivileges=yes
CapabilityBoundingSet=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
UMask=0077
MemoryMax=4G
MemorySwapMax=0
CPUQuota=200%
TasksMax=256
LimitCORE=0
TimeoutStartSec=120
TimeoutStopSec=60
Restart=no
'''


def local_ini(password):
    return '''; Dedicated development compatibility lab. Never production endpoints.
[couchdb]
database_dir = /var/lib/kazoo-compat-runtime/data
view_index_dir = /var/lib/kazoo-compat-runtime/views
single_node = true
[query_server_config]
os_process_limit = 8
os_process_soft_limit = 4
[ken]
batch_channels = 1
incremental_channels = 0
[cluster]
n = 1
q = 1
[chttpd]
bind_address = 127.0.0.1
port = 25984
require_valid_user = true
[httpd]
bind_address = 127.0.0.1
port = 25986
[admins]
compat_admin = %s
[log]
writer = file
file = /var/lib/kazoo-compat-runtime/couchdb.log
level = warning
''' % password


def vm_args(cookie):
    return '''-name compat_couchdb@127.0.0.1
-setcookie %s
-kernel inet_dist_use_interface {127,0,0,1}
-kernel error_logger silent
-sasl sasl_error_logger false
-kernel prevent_overlapping_partitions false
+S 2:2
+SDcpu 1
+SDio 2
+A 4
+P 262144
+Bd -noinput
''' % cookie


def write_exclusive(path, content, mode, owner=None):
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, 'w') as output:
        output.write(content)
        output.flush()
        os.fsync(output.fileno())
    if owner is not None:
        os.chown(str(path), owner.pw_uid, owner.pw_gid)


def preflight():
    if os.geteuid() != 0:
        raise RuntimeError('Root required on the development host')
    addresses = json.loads(subprocess.check_output(['ip', '-j', 'address', 'show']))
    found = {entry.get('local') for interface in addresses for entry in interface.get('addr_info', [])}
    if HOST not in found:
        raise RuntimeError('This helper is restricted to the designated development host')
    if BASE.exists() or BASE.is_symlink() or UNIT_PATH.exists() or UNIT_PATH.is_symlink():
        raise RuntimeError('Lab already exists; inspect it, never overwrite it')
    for filename in ['/opt/couchdb/bin/couchdb', '/opt/couchdb/etc/default.ini']:
        if not pathlib.Path(filename).is_file():
            raise RuntimeError('Installed CouchDB binaries/defaults required')
    existing = subprocess.run(['systemctl', 'show', UNIT_NAME, '-p', 'LoadState', '--value'], capture_output=True, text=True, check=True).stdout.strip()
    if existing != 'not-found':
        raise RuntimeError('Service name already exists')


def prepare():
    preflight()
    try:
        pwd.getpwnam(USER)
    except KeyError:
        subprocess.run(['useradd', '--system', '--user-group', '--home-dir', str(BASE / 'home'), '--no-create-home', '--shell', '/sbin/nologin', USER], check=True)
    else:
        raise RuntimeError('Dedicated user already exists; inspect prior lab state')
    owner = pwd.getpwnam(USER)
    BASE.mkdir(mode=0o700)
    os.chown(str(BASE), owner.pw_uid, owner.pw_gid)
    for name in ['home', 'data', 'views']:
        path = BASE / name
        path.mkdir(mode=0o700)
        os.chown(str(path), owner.pw_uid, owner.pw_gid)
    password, cookie = secrets.token_hex(32), secrets.token_hex(32)
    write_exclusive(BASE / 'credentials.json', json.dumps({'username': 'compat_admin', 'password': password}), 0o600)
    write_exclusive(BASE / 'local.ini', local_ini(password), 0o600, owner)
    write_exclusive(BASE / 'vm.args', vm_args(cookie), 0o600, owner)
    write_exclusive(UNIT_PATH, unit_text(), 0o644)
    subprocess.run(['systemctl', 'daemon-reload'], check=True)
    subprocess.run(['systemctl', 'start', UNIT_NAME], check=True)
    print(json.dumps({'service': UNIT_NAME, 'runtime': str(BASE), 'started': True,
                      'boot_enable_requested': False, 'imported_databases': 0}))


if __name__ == '__main__':
    try:
        if sys.argv[1:] != ['--create-on-development-44']:
            raise RuntimeError('Explicit development creation flag required')
        prepare()
    except Exception:
        sys.stderr.write('Lab preparation failed; inspect private development state before retrying.\n')
        sys.exit(1)
