#!/usr/bin/env python3
"""Add a private broker and real Kazoo5 apps to the existing compatibility lab.

All units join the lab's loopback-only network namespace and use separate
credentials/data. No production or main-development configuration is loaded.
Run once explicitly on .44 after creating/restoring the lab working copy.
"""
import importlib.util
import json
import os
import pathlib
import pwd
import secrets
import subprocess
import sys

spec = importlib.util.spec_from_file_location('lab', pathlib.Path(__file__).with_name('prepare-company-compat-lab.py'))
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)
BASE = lab.BASE


def unit(role, environment, command, memory):
    return '''# Managed by kz5 isolated compatibility assessment.
[Unit]
Description=Isolated Kazoo compatibility %s
BindsTo=kazoo-compat-couchdb.service
After=kazoo-compat-couchdb.service
JoinsNamespaceOf=kazoo-compat-couchdb.service

[Service]
Type=simple
User=kazoo-compat
Group=kazoo-compat
WorkingDirectory=%s/%s
%s
ExecStart=%s
PrivateNetwork=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=%s/%s
InaccessiblePaths=-/etc/kazoo -/etc/rabbitmq -/var/lib/rabbitmq -/var/lib/kazoo -/opt/couchdb/etc/local.ini -/opt/couchdb/etc/local.d -/opt/couchdb/data
NoNewPrivileges=yes
CapabilityBoundingSet=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
UMask=0077
MemoryMax=%s
MemorySwapMax=0
CPUQuota=200%%
TasksMax=256
LimitCORE=0
LimitNOFILE=65536
TimeoutStopSec=60
Restart=no
StandardOutput=append:%s/%s/stdout.log
StandardError=inherit
''' % (role, BASE, role, '\n'.join('Environment="%s=%s"' % (k, v) for k, v in environment.items()),
       command, BASE, role, memory, BASE, role)


def app_start_script():
    return '''#!/bin/sh
set -eu
export ERL_LIBS=/opt/kz5/deps:/opt/kz5/core:/opt/kz5/applications
for dependency in /opt/kz5/deps/rabbitmq_erlang_client-*/deps; do
    [ ! -d "$dependency" ] || ERL_LIBS="$ERL_LIBS:$dependency"
done
export ERL_CRASH_DUMP=/var/lib/kazoo-compat-runtime/apps/erl_crash.dump
export ERL_CRASH_DUMP_BYTES=10485760
export ERL_CRASH_DUMP_SECONDS=5
exec /usr/bin/erl -name kazoo_compat@127.0.0.1 \\
    -kernel inet_dist_use_interface '{127,0,0,1}' \\
    -args_file /opt/kz5/rel/dev.vm.args -config /opt/kz5/rel/sys.config \\
    -ra data_dir '"/var/lib/kazoo-compat-runtime/apps/ra"' \\
    -lager log_root '"/var/lib/kazoo-compat-runtime/apps"' \\
    +S 2:2 +SDcpu 1 +SDio 2 +A 4 -noshell -noinput
'''


def prepare():
    if os.geteuid() != 0:
        raise ValueError('Root required')
    addresses = json.loads(subprocess.check_output(['ip', '-j', 'address', 'show']))
    if lab.HOST not in {a.get('local') for interface in addresses for a in interface.get('addr_info', [])}:
        raise ValueError('Wrong development host')
    if subprocess.check_output(['systemctl', 'is-active', 'kazoo-compat-couchdb.service'], text=True).strip() != 'active':
        raise ValueError('Existing lab required')
    roles = ['broker', 'apps']
    for role in roles:
        path = pathlib.Path('/etc/systemd/system/kazoo-compat-%s.service' % role)
        if (BASE / role).exists() or (BASE / role).is_symlink() or path.exists() or path.is_symlink():
            raise ValueError('Existing lab role; inspect rather than overwrite')
    owner = pwd.getpwnam(lab.USER)
    def directory(relative):
        path = BASE / relative
        path.mkdir(mode=0o700)
        os.chown(str(path), owner.pw_uid, owner.pw_gid)
    def write(relative, content, mode=0o600):
        lab.write_exclusive(BASE / relative, content, mode, owner)
    for relative in ['broker', 'broker/home', 'broker/mnesia', 'broker/log', 'broker/plugins', 'apps', 'apps/home', 'apps/log', 'apps/ra']:
        directory(relative)
    credentials = json.loads((BASE / 'credentials.json').read_text())
    broker_password, app_cookie = secrets.token_hex(32), secrets.token_hex(32)
    write('broker/home/.erlang.cookie', secrets.token_hex(32) + '\n', 0o400)
    write('apps/home/.erlang.cookie', app_cookie + '\n', 0o400)
    write('broker/rabbitmq-env.conf', '# No inherited main-host RabbitMQ settings.\n')
    write('broker/enabled_plugins', '[rabbitmq_consistent_hash_exchange].\n')
    write('broker/rabbitmq.conf', '''listeners.tcp.1 = 127.0.0.1:5672
default_user = compat
default_pass = %s
default_vhost = /
loopback_users.guest = true
log.console = false
log.file.level = warning
vm_memory_high_watermark.absolute = 512MiB
''' % broker_password)
    write('apps/config.ini', '''[amqp]
uri = amqp://compat:%s@127.0.0.1:5672
[data]
config = couchdb3
[couchdb3]
ip = 127.0.0.1
port = 25984
admin_port = 25984
username = compat_admin
password = %s
[zone]
name = compatibility_lab
amqp_uri = amqp://compat:%s@127.0.0.1:5672
[kazoo_apps]
cookie = %s
[log]
syslog = none
console = warning
file = error
''' % (broker_password, credentials['password'], broker_password, app_cookie))
    write('apps/start.sh', app_start_script(), 0o700)
    broker_env = {
        'HOME': str(BASE / 'broker/home'),
        'RABBITMQ_CONF_ENV_FILE': str(BASE / 'broker/rabbitmq-env.conf'),
        'RABBITMQ_CONFIG_FILE': str(BASE / 'broker/rabbitmq.conf'),
        'RABBITMQ_NODENAME': 'rabbit_compat@localhost',
        'RABBITMQ_NODE_IP_ADDRESS': '127.0.0.1',
        'RABBITMQ_NODE_PORT': '5672',
        'RABBITMQ_DIST_PORT': '35672',
        'RABBITMQ_MNESIA_BASE': str(BASE / 'broker/mnesia'),
        'RABBITMQ_LOG_BASE': str(BASE / 'broker/log'),
        'RABBITMQ_PID_FILE': str(BASE / 'broker/rabbitmq.pid'),
        'RABBITMQ_ENABLED_PLUGINS_FILE': str(BASE / 'broker/enabled_plugins'),
        'RABBITMQ_PLUGINS_EXPAND_DIR': str(BASE / 'broker/plugins'),
        'RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS': '+S 2:2 +SDcpu 1 +SDio 2 +A 4 -kernel inet_dist_use_interface {127,0,0,1}'
    }
    apps_env = {'HOME': str(BASE / 'apps/home'), 'KAZOO_CONFIG': str(BASE / 'apps/config.ini'),
                'KAZOO_APPS': 'crossbar acdc callflow blackhole'}
    lab.write_exclusive(pathlib.Path('/etc/systemd/system/kazoo-compat-broker.service'), unit('broker', broker_env, '/usr/lib/rabbitmq/bin/rabbitmq-server', '1G'), 0o644)
    lab.write_exclusive(pathlib.Path('/etc/systemd/system/kazoo-compat-apps.service'), unit('apps', apps_env, str(BASE / 'apps/start.sh'), '2G'), 0o644)
    subprocess.run(['systemctl', 'daemon-reload'], check=True)
    subprocess.run(['systemctl', 'start', 'kazoo-compat-broker.service'], check=True)
    # Apps are deliberately started separately after broker/network validation.
    print(json.dumps({'broker_start_requested': True, 'apps_prepared_not_started': True,
                      'runtime': str(BASE), 'boot_enable_requested': False}))


if __name__ == '__main__':
    try:
        if sys.argv[1:] != ['--create-on-development-44']:
            raise ValueError('Explicit creation flag required')
        prepare()
    except Exception:
        print('Isolated app preparation failed; inspect private lab state before retrying.', file=sys.stderr)
        sys.exit(1)
