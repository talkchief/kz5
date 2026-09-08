#!/usr/bin/python3 -I
"""Bounded, pinned SSH transport for the existing create-only SUP catalog importer.

Only public metadata/images cross this protocol. The receiver is deliberately
not an arbitrary RPC, shell, file copier, catalog updater, or account creator.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit

APPS = frozenset('acdc accounts callflows csv-onboarding fax numbers pbxs voicemails webhooks voip'.split())
MAX_META, MAX_IMAGE, MAX_IMAGES, MAX_PACKET = 262144, 5242880, 16777216, 24 * 1024 * 1024
RECEIVER = Path('/usr/local/libexec/kazoo5-monster-catalog')
CONFIG = Path('/etc/kazoo-monster-catalog.json')
STATE = Path('/var/lib/kazoo-monster-catalog')
OWNERSHIP = STATE / 'installed.json'
ENV = {'PATH': '/usr/local/bin:/usr/bin:/bin', 'LANG': 'C', 'LC_ALL': 'C', 'HOME': '/root'}
REMOTE_COMMAND = '/usr/bin/sudo -n -- /usr/local/libexec/kazoo5-monster-catalog --receive'


class Refused(Exception):
    """Only fixed category codes, never provider, RPC, or SSH output."""


def require(value, category='invalid-input'):
    if not value:
        raise Refused(category)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate-json-key')
        result[key] = value
    return result


def decode_json(data):
    try:
        return json.loads(data, object_pairs_hook=object_pairs,
                          parse_constant=lambda _: require(False, 'invalid-json'))
    except (ValueError, UnicodeError, RecursionError):
        raise Refused('invalid-json') from None


def encode_json(value):
    return json.dumps(value, ensure_ascii=True, allow_nan=False,
                      separators=(',', ':'), sort_keys=True).encode('ascii')


def keys(value, expected):
    require(type(value) is dict and set(value) == set(expected), 'invalid-fields')


def safe_path(path, leaf_directory=False, private=False):
    path = Path(path)
    require(path.is_absolute() and str(path) == os.path.normpath(str(path)), 'unsafe-path')
    parts = path.parts
    for index in range(1, len(parts) + 1):
        item = Path(*parts[:index])
        info = item.lstat()
        last = index == len(parts)
        require(info.st_uid == 0 and not stat.S_ISLNK(info.st_mode), 'unsafe-owner')
        require(not info.st_mode & 0o022 or
                (not last and stat.S_ISDIR(info.st_mode) and info.st_mode & stat.S_ISVTX), 'unsafe-mode')
        require(stat.S_ISDIR(info.st_mode) if not last or leaf_directory
                else stat.S_ISREG(info.st_mode) and info.st_nlink == 1, 'unsafe-file-type')
        if last and private:
            require(stat.S_IMODE(info.st_mode) == 0o600, 'unsafe-private-mode')
    return path


def file_signature(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
            info.st_nlink, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def read_safe(path, maximum, private=False):
    path = safe_path(path, private=private)
    before = path.lstat()
    require(before.st_size <= maximum, 'file-too-large')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        require(file_signature(before) == file_signature(os.fstat(fd)), 'file-drift')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            data = stream.read(maximum + 1)
            stream.seek(0)
            again = stream.read(maximum + 1)
        require(len(data) == before.st_size and data == again, 'file-drift')
        require(file_signature(before) == file_signature(os.fstat(fd)) ==
                file_signature(path.lstat()), 'file-drift')
    finally:
        os.close(fd)
    safe_path(path, private=private)
    return data


def own_hash():
    return digest(read_safe(Path(__file__).absolute(), 2 * 1024 * 1024))


def api_url(value):
    require(type(value) is str and len(value) <= 2048 and
            not any(ord(char) <= 32 or ord(char) >= 127 for char in value), 'invalid-api-url')
    parsed = urlsplit(value)
    require(parsed.scheme in ('http', 'https') and parsed.username is None and parsed.password is None
            and not parsed.query and not parsed.fragment and parsed.path.endswith('/v2/')
            and re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?', parsed.hostname or ''), 'invalid-api-url')
    require(parsed.port is None or 1 <= parsed.port <= 65535, 'invalid-api-url')
    return value


def image_specs(meta, app):
    require(type(meta) is dict and meta.get('name') == app, 'invalid-app-metadata')
    shots = meta.get('screenshots', [])
    require(type(shots) is list and len(shots) <= 10, 'invalid-images')
    icon = meta.get('icon', '')
    specs = ([] if icon == '' else [('icon', icon)]) + [('screenshots', name) for name in shots]
    seen = set()
    for kind, name in specs:
        require(type(name) is str and 0 < len(name.encode('utf-8')) <= 192
                and name not in ('.', '..') and not any(char in name for char in '/\\\x00')
                and not any(ord(char) < 32 for char in name)
                and Path(name).suffix.lower() in ('.png', '.jpg', '.jpeg', '.gif', '.svg'), 'invalid-image-name')
        require(name not in seen, 'duplicate-image-name')
        seen.add(name)
    return specs


def blob(data):
    return {'sha256': digest(data), 'base64': base64.b64encode(data).decode('ascii')}


def unblob(value, maximum):
    keys(value, ('sha256', 'base64'))
    require(type(value['base64']) is str and len(value['base64']) <= 4 * ((maximum + 2) // 3), 'invalid-blob')
    try:
        data = base64.b64decode(value['base64'], validate=True)
    except (ValueError, UnicodeError):
        raise Refused('invalid-blob') from None
    require(len(data) <= maximum and base64.b64encode(data).decode('ascii') == value['base64']
            and digest(data) == value['sha256'], 'invalid-blob')
    return data


def request(action, master, app=None, api=None, web=None):
    packet = {'version': 1, 'receiver_sha256': own_hash(), 'action': action, 'master': master}
    if action != 'check':
        packet.update(app=app, api=api)
    if action == 'install-one':
        root = safe_path(Path(web) / 'apps' / app, leaf_directory=True)
        data = read_safe(root / 'metadata' / 'app.json', MAX_META)
        specs = image_specs(decode_json(data), app)
        packet['metadata'] = blob(data)
        packet['images'] = [dict(kind=kind, name=name,
                                 **blob(read_safe(root / 'metadata' / kind / name, MAX_IMAGE)))
                            for kind, name in specs]
    validate_request(packet)
    return packet


def validate_request(packet):
    require(type(packet) is dict, 'invalid-packet')
    action = packet.get('action')
    require(action in ('check', 'install-one', 'verify-one'), 'invalid-action')
    expected = ['version', 'receiver_sha256', 'action', 'master']
    if action != 'check':
        expected += ['app', 'api']
    if action == 'install-one':
        expected += ['metadata', 'images']
    keys(packet, expected)
    require(type(packet['version']) is int and packet['version'] == 1
            and packet['receiver_sha256'] == own_hash(), 'receiver-version-mismatch')
    require(type(packet['master']) is str and re.fullmatch('[0-9a-f]{32}', packet['master']), 'invalid-master')
    if action != 'check':
        require(packet['app'] in APPS, 'invalid-app')
        api_url(packet['api'])
    if action != 'install-one':
        return None
    metadata = unblob(packet['metadata'], MAX_META)
    specs = image_specs(decode_json(metadata), packet['app'])
    require(type(packet['images']) is list and len(packet['images']) == len(specs), 'invalid-images')
    images = []
    for image, (kind, name) in zip(packet['images'], specs):
        keys(image, ('kind', 'name', 'sha256', 'base64'))
        require((image['kind'], image['name']) == (kind, name), 'invalid-images')
        images.append((kind, name, unblob({key: image[key] for key in ('sha256', 'base64')}, MAX_IMAGE)))
    require(sum(len(data) for _, _, data in images) <= MAX_IMAGES, 'images-too-large')
    return metadata, images


def frame(packet):
    body = encode_json(packet)
    require(0 < len(body) <= MAX_PACKET, 'packet-too-large')
    return ('%08x\n' % len(body)).encode('ascii') + body


def read_frame(stream):
    header = stream.read(9)
    require(re.fullmatch(b'[0-9a-f]{8}\n', header), 'invalid-frame')
    length = int(header[:8], 16)
    require(0 < length <= MAX_PACKET, 'packet-too-large')
    body = stream.read(length)
    require(len(body) == length and stream.read(1) == b'', 'invalid-frame')
    return decode_json(body)


def bounded_run(argv, data=b'', timeout=15, env=None):
    """Bound output while draining, not after communicate has allocated it."""
    process = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, env=env or ENV, start_new_session=True)
    selector = selectors.DefaultSelector()
    output = bytearray()
    total, offset = 0, 0
    deadline = time.monotonic() + timeout
    try:
        for stream in (process.stdout, process.stderr):
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ)
        if data:
            os.set_blocking(process.stdin.fileno(), False)
            selector.register(process.stdin, selectors.EVENT_WRITE)
        else:
            process.stdin.close()
        while selector.get_map():
            remaining = deadline - time.monotonic()
            require(remaining > 0, 'command-timeout')
            for key, _ in selector.select(min(remaining, 0.5)):
                stream = key.fileobj
                if stream is process.stdin:
                    try:
                        offset += os.write(stream.fileno(), data[offset:offset + 65536])
                    except BrokenPipeError:
                        raise Refused('command-failed') from None
                    if offset == len(data):
                        selector.unregister(stream)
                        stream.close()
                else:
                    chunk = os.read(stream.fileno(), 8192)
                    if not chunk:
                        selector.unregister(stream)
                        stream.close()
                        continue
                    total += len(chunk)
                    require(total <= 16384, 'command-output-limit')
                    if stream is process.stdout:
                        output.extend(chunk)
        require(deadline > time.monotonic(), 'command-timeout')
        require(process.wait(timeout=max(0.01, deadline - time.monotonic())) == 0, 'command-failed')
        return bytes(output)
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        raise
    finally:
        selector.close()
        for stream in (process.stdin, process.stdout, process.stderr):
            stream.close()


def ssh_options(settings):
    host, user, port, identity, known_hosts = settings
    require(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?', host)
            and len(host) <= 253 and re.fullmatch('[a-z_][a-z0-9_-]{0,31}', user), 'invalid-ssh-target')
    require(re.fullmatch('[1-9][0-9]{0,4}', port) and int(port) <= 65535, 'invalid-ssh-port')
    require(all(re.fullmatch('/[A-Za-z0-9_./-]+', item) for item in (identity, known_hosts)), 'unsafe-ssh-path')
    read_safe(identity, 65536, private=True)
    read_safe(known_hosts, 1048576, private=True)
    target = host if port == '22' else '[%s]:%s' % (host, port)
    bounded_run(['/usr/bin/ssh-keygen', '-F', target, '-f', known_hosts])
    options = ['BatchMode=yes', 'IdentitiesOnly=yes', 'IdentityAgent=none', 'StrictHostKeyChecking=yes',
               'UserKnownHostsFile=' + known_hosts, 'GlobalKnownHostsFile=/dev/null',
               'ForwardAgent=no', 'ClearAllForwardings=yes', 'ProxyCommand=none', 'ProxyJump=none',
               'ControlMaster=no', 'ControlPath=none', 'ConnectTimeout=10', 'ConnectionAttempts=1',
               'ServerAliveInterval=5', 'ServerAliveCountMax=2', 'RequestTTY=no', 'PermitLocalCommand=no']
    return ['/usr/bin/ssh', '-F', '/dev/null', '-T'] + [item for option in options for item in ('-o', option)] + [
        '-i', identity, '-l', user, '-p', port, host, REMOTE_COMMAND]


def send(settings, packet):
    output = bounded_run(ssh_options(settings), frame(packet), timeout=125)
    response = decode_json(output)
    keys(response, ('version', 'receiver_sha256', 'status'))
    require(type(response['version']) is int and response['version'] == 1
            and response['receiver_sha256'] == own_hash(), 'receiver-version-mismatch')
    allowed = {'check': ('ready',), 'install-one': ('created', 'preserved'), 'verify-one': ('verified',)}
    require(response['status'] in allowed[packet['action']], 'remote-not-verified')
    return response['status']


def load_receiver_config():
    value = decode_json(read_safe(CONFIG, 4096, private=True))
    keys(value, ('root', 'config', 'hostname', 'node_type'))
    safe_path(value['root'], leaf_directory=True)
    safe_path(value['config'])
    safe_path('/usr/local/bin/sup')
    require(os.access('/usr/local/bin/sup', os.X_OK), 'sup-unavailable')
    bounded_run(['/usr/bin/systemctl', 'is-active', '--quiet', 'kazoo-apps.service'], timeout=5)
    require(re.fullmatch('[A-Za-z0-9][A-Za-z0-9._-]{0,252}', value['hostname'])
            and value['node_type'] in ('-name', '-sname'), 'invalid-receiver-config')
    return value


def erl_binary(value):
    return 'base64:decode(<<"' + base64.b64encode(value.encode('utf-8')).decode('ascii') + '">>)'


def readonly_rpc(config, master, app=None, api=None):
    candidates = sorted(Path('/usr/lib64/erlang').glob('erts-*/bin/erl_call')) + [
        Path('/usr/lib64/erlang/bin/erl_call'), Path('/usr/bin/erl_call')]
    executable = next((str(item) for item in candidates if item.is_file() and os.access(item, os.X_OK)), None)
    require(executable is not None, 'erl-call-unavailable')
    # No expression, module, function, file path, or database is caller-defined.
    # Values are strict identifiers or base64 binaries, never executable text.
    expression = ('try Expected = ' + erl_binary(master) + ', '
                  'Expected = kapps_config:get_ne_binary(<<"accounts">>,<<"master_account_id">>), '
                  '{ok,{kazoo_monster_catalog,[{exports,Exports}]}} = '
                  'beam_lib:chunks(code:which(kazoo_monster_catalog),[exports]), '
                  'true = lists:member({init_app,3},Exports), '
                  '{ok,_} = kz_json_schema:load(<<"app">>), '
                  'Db = kzs_util:format_account_db(Expected), ')
    if app is None:
        expression += '{ok,_} = kz_datamgr:get_results(Db,<<"apps_store/crossbar_listing">>,[{limit,1}]), ready'
        expected = b'{ok, ready}'
    else:
        expression += ('{ok,[Row]} = kz_datamgr:get_results(Db,<<"apps_store/crossbar_listing">>,'
                       '[{key,' + erl_binary(app) + '},{limit,2}]), '
                       '{ok,Doc} = kz_datamgr:open_doc(Db,kz_json:get_ne_binary_value(<<"id">>,Row)), '
                       'Api = ' + erl_binary(api) + ', Api = kz_json:get_ne_binary_value(<<"api_url">>,Doc), verified')
        expected = b'{ok, verified}'
    expression += ' catch _:_ -> refused end.\n'
    result = bounded_run(['/usr/sbin/runuser', '--user', 'kazoo', '--', executable,
                          config['node_type'], 'kazoo_apps@' + config['hostname'], '-e'],
                         expression.encode('ascii'), timeout=12)
    require(result.strip() == expected, 'catalog-read-not-verified')


def write_exclusive(path, data, mode):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(path, mode)


def process_request(packet, config):
    unpacked = validate_request(packet)
    readonly_rpc(config, packet['master'])
    if packet['action'] == 'check':
        return 'ready'
    if packet['action'] == 'verify-one':
        readonly_rpc(config, packet['master'], packet['app'], packet['api'])
        return 'verified'
    safe_path(STATE, leaf_directory=True)
    pending = STATE / ('pending-' + packet['master'] + '-' + packet['app'])
    # A previous uncertain outcome or a concurrent writer must be reviewed, not
    # silently retried by the next installer run. No lock is acquired by reads.
    try:
        pending.mkdir(mode=0o700)
    except FileExistsError:
        raise Refused('pending-target-requires-review') from None
    stage = Path(tempfile.mkdtemp(prefix='catalog-', dir=STATE))
    os.chmod(stage, 0o755)  # public input must be readable by the Kazoo VM
    metadata, images = unpacked
    (stage / 'metadata').mkdir(mode=0o755)
    (stage / 'metadata').chmod(0o755)
    write_exclusive(stage / 'metadata' / 'app.json', metadata, 0o644)
    for kind, name, data in images:
        directory = stage / 'metadata' / kind
        if not directory.exists():
            directory.mkdir(mode=0o755)
            directory.chmod(0o755)
        write_exclusive(directory / name, data, 0o644)
    # Retain only hashes and target identifiers, never credentials. Uncertain
    # stages are kept for explicit bounded operator review; no auto-retry.
    write_exclusive(stage / 'receipt.json', encode_json({
        'master': packet['master'], 'app': packet['app'], 'api': packet['api'],
        'packet_sha256': digest(encode_json(packet)), 'outcome': 'not-yet-verified'}), 0o600)
    write_exclusive(pending / 'stage.json', encode_json({'stage': str(stage)}), 0o600)
    readonly_rpc(config, packet['master'])
    env = dict(ENV, KAZOO_ROOT=config['root'], KAZOO_CONFIG=config['config'])
    result = bounded_run(['/usr/local/bin/sup', 'kazoo_monster_catalog', 'init_app',
                          packet['app'], str(stage), packet['api']], timeout=60, env=env)
    require(result.strip() in (b'created', b'preserved'), 'create-outcome-unverified')
    readonly_rpc(config, packet['master'], packet['app'], packet['api'])
    status = result.strip().decode('ascii')
    write_exclusive(stage / 'verified.json', encode_json({'status': status}), 0o600)
    # Exact known targets only; no recursive deletion or user-controlled glob.
    for kind, name, _ in images:
        (stage / 'metadata' / kind / name).unlink()
    for kind in sorted({kind for kind, _, _ in images}):
        (stage / 'metadata' / kind).rmdir()
    (stage / 'metadata' / 'app.json').unlink()
    (stage / 'metadata').rmdir()
    (stage / 'receipt.json').unlink()
    (stage / 'verified.json').unlink()
    stage.rmdir()
    (pending / 'stage.json').unlink()
    pending.rmdir()
    return status


def install_receiver(root, config, hostname, node_type):
    """Local apps-installer operation, never accepted by the SSH receiver."""
    safe_path(root, leaf_directory=True)
    safe_path(config)
    require(re.fullmatch('[A-Za-z0-9][A-Za-z0-9._-]{0,252}', hostname)
            and node_type in ('-name', '-sname'), 'invalid-receiver-config')
    source = read_safe(Path(__file__).absolute(), 2 * 1024 * 1024)
    content = encode_json(dict(root=root, config=config, hostname=hostname, node_type=node_type))
    for directory in (STATE, RECEIVER.parent):
        if not directory.exists():
            safe_path(directory.parent, leaf_directory=True)
            directory.mkdir(mode=0o755)
            directory.chmod(0o755)
        safe_path(directory, leaf_directory=True)
        if directory == STATE:
            require(stat.S_IMODE(directory.stat().st_mode) == 0o755, 'unsafe-stage-parent-mode')
    expected = {str(RECEIVER): digest(source), str(CONFIG): digest(content)}
    previous = decode_json(read_safe(OWNERSHIP, 4096, private=True)) if OWNERSHIP.exists() or OWNERSHIP.is_symlink() else {}
    require(type(previous) is dict and set(previous) in (set(), set(expected)), 'invalid-ownership')
    for destination in (RECEIVER, CONFIG):
        if destination.exists() or destination.is_symlink():
            data = read_safe(destination, 2 * 1024 * 1024, private=destination == CONFIG)
            require(previous.get(str(destination)) == digest(data), 'unowned-receiver-file')
        else:
            require(str(destination) not in previous, 'missing-owned-receiver-file')
    # Any interrupted update refuses a later rerun rather than adopting unknown
    # bytes. Retain the previous protected ownership receipt for operator review.
    for destination, data, mode in ((RECEIVER, source, 0o755), (CONFIG, content, 0o600),
                                    (OWNERSHIP, encode_json(expected), 0o600)):
        safe_path(destination.parent, leaf_directory=True)
        fd, name = tempfile.mkstemp(prefix='.catalog-install-', dir=destination.parent)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, mode)
        os.replace(name, destination)


def main(arguments):
    require(os.geteuid() == 0, 'root-required')
    if arguments == ['--receive']:
        signal.signal(signal.SIGALRM, lambda *_: require(False, 'receiver-timeout'))
        signal.alarm(120)
        packet = read_frame(sys.stdin.buffer)
        status = process_request(packet, load_receiver_config())
        sys.stdout.buffer.write(encode_json({'version': 1, 'receiver_sha256': own_hash(), 'status': status}))
        return
    if len(arguments) == 5 and arguments[0] == '--install-receiver':
        install_receiver(*arguments[1:])
        return
    require(len(arguments) in (8, 11), 'invalid-arguments')
    action, host, user, port, identity, known_hosts, master, expected_hash = arguments[:8]
    require(expected_hash == own_hash(), 'sender-source-drift')
    require(action in ('--check', '--install', '--verify'), 'invalid-action')
    settings = (host, user, port, identity, known_hosts)
    if action == '--check':
        require(len(arguments) == 8, 'invalid-arguments')
        send(settings, request('check', master))
        return
    require(len(arguments) == 11, 'invalid-arguments')
    web, api, selected = arguments[8:]
    apps = selected.split(',')
    require(apps and set(apps) <= APPS and len(apps) == len(set(apps)), 'invalid-apps')
    for app in apps:
        packet = request('install-one' if action == '--install' else 'verify-one', master, app, api, web)
        status = send(settings, packet)
        print('PASS remote catalog %s: %s' % (app, status))


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except Refused as error:
        print('Catalog operation refused: %s; no automatic retry or rollback' % error, file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError, RecursionError):
        print('Catalog operation refused: unavailable-or-invalid; no automatic retry or rollback', file=sys.stderr)
        sys.exit(1)
