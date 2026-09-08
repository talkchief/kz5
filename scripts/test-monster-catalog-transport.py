#!/usr/bin/python3
"""Offline fixtures only: never start ssh, SUP, erl_call, a service, or broker.

Tests use private filesystem fixtures and process/RPC doubles only.
"""
import base64
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('catalog_transport', Path(__file__).with_name('monster-catalog-transport.py'))
catalog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(catalog)
MASTER = 'a' * 32
API = 'https://ui.example.test/v2/'


class OfflineCatalogTests(unittest.TestCase):
    def setUp(self):
        if os.geteuid() != 0:
            self.skipTest('ownership regression cases require an isolated root-owned temporary directory')
        self.temporary = tempfile.TemporaryDirectory(prefix='catalog-offline-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        # The importer runs in the Kazoo VM and must be able to traverse input.
        self.root.chmod(0o755)
        self.web = self.root / 'web'
        self.metadata = self.web / 'apps' / 'acdc' / 'metadata'
        self.metadata.mkdir(parents=True)
        (self.metadata / 'icon').mkdir()
        (self.metadata / 'screenshots').mkdir()
        self.meta = {'name': 'acdc', 'icon': 'logo.png', 'screenshots': ['queue.png']}
        (self.metadata / 'app.json').write_bytes(catalog.encode_json(self.meta))
        (self.metadata / 'icon' / 'logo.png').write_bytes(b'public-icon')
        (self.metadata / 'screenshots' / 'queue.png').write_bytes(b'public-screenshot')
        self.state = self.root / 'state'
        self.state.mkdir()
        self.state.chmod(0o755)
        self.addCleanup(patch.stopall)
        patch.object(catalog, 'STATE', self.state).start()
        # This test suite has no process authority. Every attempted subprocess
        # must be explicitly modelled at the leaf bounded_run interface.
        patch.object(catalog.subprocess, 'Popen', side_effect=AssertionError('offline fixture attempted subprocess')).start()
        self.config = {'root': str(self.root), 'config': str(self.root / 'config.ini'),
                       'hostname': 'apps.example.test', 'node_type': '-name'}

    def packet(self, action='install-one'):
        return catalog.request(action, MASTER, 'acdc', API, self.web)

    def test_real_pack_frame_unpack_roundtrip(self):
        packet = self.packet()
        readback = catalog.read_frame(io.BytesIO(catalog.frame(packet)))
        metadata, images = catalog.validate_request(readback)
        self.assertEqual(json.loads(metadata), self.meta)
        self.assertEqual(images, [('icon', 'logo.png', b'public-icon'),
                                  ('screenshots', 'queue.png', b'public-screenshot')])
        self.assertNotIn('web', readback)

    def test_checks_and_verify_have_no_asset_body(self):
        (self.metadata / 'app.json').unlink()
        self.assertIsNone(catalog.validate_request(self.packet('verify-one')))
        self.assertIsNone(catalog.validate_request(catalog.request('check', MASTER)))
        self.assertNotIn('metadata', self.packet('verify-one'))

    def test_duplicate_keys_and_invalid_framing(self):
        for body in (b'{"version":1,"version":1}', b'{"a":NaN}'):
            with self.subTest(body=body), self.assertRaises(catalog.Refused):
                catalog.decode_json(body)
        for frame in (b'FFFFFFFF\n', b'02000000\n', b'00000000\n', b'00000002\n{', b'00000002\n{}x'):
            with self.subTest(frame=frame), self.assertRaises(catalog.Refused):
                catalog.read_frame(io.BytesIO(frame))

    def test_actual_hash_rejects_changed_source(self):
        source = self.root / 'helper.py'
        source.write_bytes(b'first-release')
        with patch.object(catalog, '__file__', str(source)):
            packet = self.packet('verify-one')
            source.write_bytes(b'other-release')
            with self.assertRaisesRegex(catalog.Refused, 'receiver-version-mismatch'):
                catalog.validate_request(packet)
            with self.assertRaisesRegex(catalog.Refused, 'sender-source-drift'):
                catalog.main(['--check', 'apps.example.test', 'root', '22', '/key', '/pins', MASTER,
                              packet['receiver_sha256']])

    def test_payload_integrity_and_closed_fields(self):
        packet = self.packet()
        variants = []
        for key, value in (('action', 'shell'), ('master', 'A' * 32), ('app', '../../root'),
                           ('api', 'https://user:pass@host/v2/'), ('version', True)):
            item = copy.deepcopy(packet)
            item[key] = value
            variants.append(item)
        item = copy.deepcopy(packet)
        item['command'] = 'arbitrary'
        variants.append(item)
        item = copy.deepcopy(packet)
        item['images'][0]['base64'] = base64.b64encode(b'changed-icon').decode()
        variants.append(item)
        item = copy.deepcopy(packet)
        item['images'].reverse()
        variants.append(item)
        for item in variants:
            with self.subTest(item=item.get('action')), self.assertRaises(catalog.Refused):
                catalog.validate_request(item)

    def test_limits_and_noncanonical_base64(self):
        with patch.object(catalog, 'MAX_IMAGES', 1), self.assertRaises(catalog.Refused):
            self.packet()
        with patch.object(catalog, 'MAX_IMAGE', 1), self.assertRaises(catalog.Refused):
            self.packet()
        value = catalog.blob(b'f')
        value['base64'] = 'Zh=='  # same decoded byte, noncanonical unused bits
        with self.assertRaises(catalog.Refused):
            catalog.unblob(value, 10)
        with patch.object(catalog, 'MAX_PACKET', 2), self.assertRaises(catalog.Refused):
            catalog.frame({'too': 'large'})

    def test_no_traversal_duplicates_or_unexpected_image_kind(self):
        for icon in ('../secret.png', '..', 'x\\y.png', 'x\x00.png', 'script.js', 'queue.png'):
            self.meta['icon'] = icon
            with self.subTest(icon=icon), self.assertRaises(catalog.Refused):
                catalog.image_specs(self.meta, 'acdc')
        packet = self.packet()
        packet['images'][0]['kind'] = '../escape'
        with self.assertRaises(catalog.Refused):
            catalog.validate_request(packet)

    def test_no_symlinks_hardlinks_or_writable_ancestors(self):
        logo = self.metadata / 'icon' / 'logo.png'
        original = logo.read_bytes()
        logo.unlink()
        target = self.root / 'other.png'
        target.write_bytes(original)
        logo.symlink_to(target)
        with self.assertRaises(catalog.Refused):
            self.packet()
        logo.unlink()
        os.link(target, logo)
        with self.assertRaises(catalog.Refused):
            self.packet()
        logo.unlink()
        logo.write_bytes(original)
        self.web.chmod(0o777)
        with self.assertRaises(catalog.Refused):
            self.packet()

    def test_wrong_master_or_unavailable_check_has_no_stage_or_sup(self):
        packet = self.packet()
        with patch.object(catalog, 'readonly_rpc', side_effect=catalog.Refused('catalog-read-not-verified')):
            with self.assertRaises(catalog.Refused):
                catalog.process_request(packet, self.config)
        self.assertEqual(list(self.state.iterdir()), [])

    def test_create_and_preserve_use_exact_existing_sup_contract(self):
        for outcome in (b'created\n', b'preserved\n'):
            with self.subTest(outcome=outcome):
                checks = []
                calls = []

                def run(argv, data=b'', timeout=15, env=None):
                    calls.append(argv)
                    self.assertEqual(argv[:4], ['/usr/local/bin/sup', 'kazoo_monster_catalog', 'init_app', 'acdc'])
                    self.assertEqual(argv[5], API)
                    stage = Path(argv[4])
                    self.assertEqual(catalog.read_safe(stage / 'metadata' / 'icon' / 'logo.png', 100), b'public-icon')
                    self.assertEqual(stage.stat().st_mode & 0o777, 0o755)
                    self.assertEqual(env['KAZOO_CONFIG'], self.config['config'])
                    self.assertNotIn('KAZOO_COOKIE', env)
                    self.assertEqual(data, b'')
                    return outcome

                with patch.object(catalog, 'readonly_rpc', side_effect=lambda *args: checks.append(args)), \
                     patch.object(catalog, 'bounded_run', side_effect=run):
                    self.assertEqual(catalog.process_request(self.packet(), self.config), outcome.decode().strip())
                self.assertEqual(len(calls), 1)
                self.assertEqual(len(checks), 3)
                self.assertEqual(checks[-1][1:], (MASTER, 'acdc', API))
                self.assertEqual(list(self.state.iterdir()), [])

    def test_unknown_outcome_retains_stage_and_blocks_retry(self):
        for failure in (catalog.Refused('command-timeout'), b'{error,create_outcome_unknown}\n'):
            with self.subTest(failure=failure), patch.object(catalog, 'readonly_rpc'), \
                 patch.object(catalog, 'bounded_run', side_effect=[failure] if isinstance(failure, Exception) else None,
                              return_value=failure) as run:
                with self.assertRaises(catalog.Refused):
                    catalog.process_request(self.packet(), self.config)
                self.assertEqual(run.call_count, 1)
                stages = list(self.state.glob('catalog-*'))
                self.assertEqual(len(stages), 1)
                self.assertTrue((stages[0] / 'receipt.json').is_file())
                with self.assertRaisesRegex(catalog.Refused, 'pending-target-requires-review'):
                    catalog.process_request(self.packet(), self.config)
                self.assertEqual(run.call_count, 1)
            # Fixture-owned directory only; not helper or live cleanup logic.
            for item in self.state.iterdir():
                shutil.rmtree(item)

    def test_public_stage_is_vm_readable_even_with_private_umask(self):
        self.addCleanup(os.umask, os.umask(0o077))

        def run(argv, **kwargs):
            stage = Path(argv[4])
            for item in (stage, stage / 'metadata', stage / 'metadata' / 'icon', stage / 'metadata' / 'screenshots'):
                self.assertEqual(item.stat().st_mode & 0o777, 0o755)
            self.assertEqual((stage / 'metadata' / 'app.json').stat().st_mode & 0o777, 0o644)
            return b'created'

        with patch.object(catalog, 'readonly_rpc'), patch.object(catalog, 'bounded_run', side_effect=run):
            self.assertEqual(catalog.process_request(self.packet(), self.config), 'created')

    def test_post_create_wrong_api_retains_evidence_and_never_rolls_back(self):
        with patch.object(catalog, 'readonly_rpc', side_effect=[None, None, catalog.Refused('catalog-read-not-verified')]), \
             patch.object(catalog, 'bounded_run', return_value=b'preserved') as run:
            with self.assertRaises(catalog.Refused):
                catalog.process_request(self.packet(), self.config)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(len(list(self.state.glob('catalog-*'))), 1)

    def test_verify_calls_reads_only_no_stage_write_or_sup(self):
        with patch.object(catalog, 'readonly_rpc') as check, patch.object(catalog, 'bounded_run') as run:
            self.assertEqual(catalog.process_request(self.packet('verify-one'), self.config), 'verified')
        self.assertEqual(check.call_count, 2)
        run.assert_not_called()
        self.assertEqual(list(self.state.iterdir()), [])

    def test_rpc_expression_terminates_the_erl_call_input_form(self):
        with patch.object(catalog.Path, 'glob', return_value=[]), \
             patch.object(catalog.Path, 'is_file', return_value=True), \
             patch.object(catalog.os, 'access', return_value=True), \
             patch.object(catalog, 'bounded_run', return_value=b'{ok, ready}') as run:
            catalog.readonly_rpc(self.config, MASTER)
        self.assertTrue(run.call_args.args[1].endswith(b'end.\n'))
        self.assertNotIn(b'code:ensure_loaded', run.call_args.args[1])
        self.assertIn(b'beam_lib:chunks', run.call_args.args[1])

    def test_ssh_has_fixed_receiver_pins_and_no_inherited_authority(self):
        identity, pins = self.root / 'identity', self.root / 'known_hosts'
        identity.write_bytes(b'not-a-real-key')
        pins.write_bytes(b'not-a-real-host-key')
        identity.chmod(0o600)
        pins.chmod(0o600)
        with patch.object(catalog, 'bounded_run', return_value=b'') as run:
            argv = catalog.ssh_options(('apps.example.test', 'catalog', '2222', str(identity), str(pins)))
        run.assert_called_once_with(['/usr/bin/ssh-keygen', '-F', '[apps.example.test]:2222', '-f', str(pins)])
        self.assertEqual(argv[:4], ['/usr/bin/ssh', '-F', '/dev/null', '-T'])
        self.assertEqual(argv[-2:], ['apps.example.test', catalog.REMOTE_COMMAND])
        self.assertIn('StrictHostKeyChecking=yes', argv)
        self.assertIn('IdentityAgent=none', argv)
        self.assertIn('GlobalKnownHostsFile=/dev/null', argv)
        identity.chmod(0o644)
        with self.assertRaises(catalog.Refused):
            catalog.ssh_options(('apps.example.test', 'catalog', '2222', str(identity), str(pins)))

    def test_remote_output_is_exact_closed_status_and_version(self):
        packet = self.packet('verify-one')
        response = {'version': 1, 'receiver_sha256': catalog.own_hash(), 'status': 'verified'}
        with patch.object(catalog, 'ssh_options', return_value=['fixed-ssh']), \
             patch.object(catalog, 'bounded_run', return_value=catalog.encode_json(response)) as run:
            self.assertEqual(catalog.send(('unused',) * 5, packet), 'verified')
            self.assertEqual(catalog.read_frame(io.BytesIO(run.call_args.args[1])), packet)
        for replacement in ({'status': 'created'}, {'receiver_sha256': '0' * 64}, {'extra': True}, {'version': True}):
            with patch.object(catalog, 'ssh_options', return_value=['fixed-ssh']), \
                 patch.object(catalog, 'bounded_run', return_value=catalog.encode_json(dict(response, **replacement))), \
                 self.assertRaises(catalog.Refused):
                catalog.send(('unused',) * 5, packet)

    def test_bounded_child_runner_drains_then_kills_on_overflow_or_timeout(self):
        class Stream:
            def __init__(self, fd):
                self.fd, self.closed = fd, False

            def fileno(self):
                return self.fd

            def close(self):
                self.closed = True

        class Child:
            pid = 98765

            def __init__(self):
                self.stdin, self.stdout, self.stderr = Stream(1), Stream(2), Stream(3)
                self.waits = 0

            def wait(self, timeout=None):
                self.waits += 1
                return 0

        class Selector:
            def __init__(self):
                self.map = {}

            def register(self, stream, event):
                self.map[stream.fd] = (stream, event)

            def unregister(self, stream):
                del self.map[stream.fd]

            def get_map(self):
                return self.map

            def select(self, timeout):
                from types import SimpleNamespace
                return [(SimpleNamespace(fileobj=stream), event) for stream, event in list(self.map.values())]

            def close(self):
                self.map.clear()

        for scenario in ('success', 'output-limit', 'timeout'):
            child = Child()
            reads = {2: [b'ok', b''], 3: [b'', b'']}
            if scenario == 'output-limit':
                reads[2] = [b'x' * 8192, b'y' * 8192, b'z', b'']
            clock = [0, 0, 0, 0, 0, 0] if scenario != 'timeout' else [0, 99]
            with self.subTest(scenario=scenario), \
                 patch.object(catalog.subprocess, 'Popen', return_value=child), \
                 patch.object(catalog.selectors, 'DefaultSelector', Selector), \
                 patch.object(catalog.os, 'set_blocking'), \
                 patch.object(catalog.os, 'read', side_effect=lambda fd, size: reads[fd].pop(0)), \
                 patch.object(catalog.os, 'write', side_effect=lambda fd, data: len(data)), \
                 patch.object(catalog.os, 'killpg') as kill, \
                 patch.object(catalog.time, 'monotonic', side_effect=clock):
                if scenario == 'success':
                    self.assertEqual(catalog.bounded_run(['fixed'], b'packet'), b'ok')
                    kill.assert_not_called()
                else:
                    with self.assertRaisesRegex(catalog.Refused, 'command-' + scenario):
                        catalog.bounded_run(['fixed'], b'packet')
                    kill.assert_called_once_with(child.pid, catalog.signal.SIGKILL)
                self.assertTrue(all(stream.closed for stream in (child.stdin, child.stdout, child.stderr)))
                self.assertEqual(child.waits, 1)

    def test_receiver_install_replay_refuses_unknown_existing_content(self):
        destination = self.root / 'libexec' / 'receiver'
        config_path = self.root / 'receiver.json'
        receipt = self.state / 'installed.json'
        local_config = self.root / 'config.ini'
        local_config.write_bytes(b'private-config-fixture')
        local_config.chmod(0o640)
        with patch.object(catalog, 'RECEIVER', destination), patch.object(catalog, 'CONFIG', config_path), \
             patch.object(catalog, 'OWNERSHIP', receipt):
            catalog.install_receiver(str(self.root), str(local_config), 'apps.example.test', '-name')
            before = destination.read_bytes()
            catalog.install_receiver(str(self.root), str(local_config), 'apps.example.test', '-name')
            self.assertEqual(before, destination.read_bytes())
            destination.write_bytes(b'operator-owned-change')
            with self.assertRaisesRegex(catalog.Refused, 'unowned-receiver-file'):
                catalog.install_receiver(str(self.root), str(local_config), 'apps.example.test', '-name')
            self.assertEqual(destination.read_bytes(), b'operator-owned-change')


if __name__ == '__main__':
    unittest.main()
