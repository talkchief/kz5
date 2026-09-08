#!/usr/bin/env python3
"""Offline remote service deployment/restore orchestration; no installer runs."""
from contextlib import ExitStack
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location('service_proof', Path(__file__).with_name('accept-bridge-remote-service.py'))
proof = importlib.util.module_from_spec(spec); spec.loader.exec_module(proof)


def original():
    return {'PUSH_BRIDGE_SA_FILE': '/etc/kazoo-push-bridge/fixture.json',
            'PUSH_BRIDGE_AMQP_HOST': '127.0.0.1', 'PUSH_BRIDGE_AMQP_USER': 'fixture',
            'PUSH_BRIDGE_AMQP_PASS': 'synthetic', 'PUSH_BRIDGE_AMQP_VHOST': '/',
            'PUSH_BRIDGE_EXCHANGE': 'kazoo5-mobile-acceptance', 'PUSH_BRIDGE_QUEUE': 'kazoo5-mobile-acceptance',
            'PUSH_BRIDGE_BINDING_KEY': 'acceptance.only', 'PUSH_BRIDGE_WORKERS': '8',
            'PUSH_BRIDGE_FCM_SCOPE': 'https://www.googleapis.com/auth/firebase.messaging',
            'PUSH_BRIDGE_FCM_URL_TEMPLATE': 'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send'}


class ServiceTests(unittest.TestCase):
    def test_installer_timeout_terminates_only_owned_process_group(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(proof, 'STATE', Path(directory)), \
                patch.object(proof.subprocess, 'Popen') as popen, \
                patch.object(proof.os, 'killpg') as killpg, \
                patch.object(proof.time, 'sleep'):
            process = popen.return_value
            process.pid = 12345
            process.wait.side_effect = [proof.subprocess.TimeoutExpired('installer', 180), -15]
            with self.assertRaises(proof.subprocess.TimeoutExpired): proof.normal_install('timeout')
            self.assertTrue(popen.call_args.kwargs['start_new_session'])
            self.assertEqual(killpg.call_args_list, [
                unittest.mock.call(12345, proof.signal.SIGTERM),
                unittest.mock.call(12345, proof.signal.SIGKILL)])
            self.assertEqual(process.wait.call_count, 2)

    def test_successful_installer_does_not_signal_processes(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(proof, 'STATE', Path(directory)), \
                patch.object(proof.subprocess, 'Popen') as popen, \
                patch.object(proof.os, 'killpg') as killpg:
            popen.return_value.wait.return_value = 0
            proof.normal_install('success')
            killpg.assert_not_called()

    def test_config_preserves_provider_and_worker_settings(self):
        value = original(); saved = dict(value)
        with patch.object(proof.remote, 'validate_fixture'):
            changed = proof.candidate_configuration(value, {'password': 'a'*64}, 'remote-'+'a'*32)
        self.assertEqual(value, saved)
        for key in ['SA_FILE', 'FCM_SCOPE', 'FCM_URL_TEMPLATE', 'WORKERS']:
            self.assertEqual(changed['PUSH_BRIDGE_'+key], value['PUSH_BRIDGE_'+key])
        self.assertEqual(changed['PUSH_BRIDGE_AMQP_TLS'], 'true')
        self.assertEqual(changed['PUSH_BRIDGE_TOPOLOGY'], 'quorum-v1')

    def test_original_scope_or_test_identity_refused(self):
        for field in ['AMQP_HOST', 'EXCHANGE', 'QUEUE', 'BINDING_KEY']:
            value = original(); value['PUSH_BRIDGE_'+field] = 'production'
            with self.assertRaises(ValueError): proof.candidate_configuration(value, {}, 'remote-'+'a'*32)
        with self.assertRaises(ValueError): proof.candidate_configuration(original(), {}, 'arbitrary')

    def connection(self):
        return {'name': 'fixture', 'peer_host': '10.1.0.26', 'peer_port': 40123,
                'user': 'kz5-bridge-proof', 'vhost': 'kz5-bridge-proof',
                'ssl': True, 'ssl_protocol': 'tlsv1.3', 'state': 'running'}

    def sockets(self):
        return 'ESTAB 0 0 10.1.0.26:40123 10.1.0.44:35671 users:(("python",pid=1234,fd=3))'

    def test_exact_service_pid_socket_and_tls_evidence(self):
        value = self.connection()
        self.assertEqual(proof.matching_connection([value], 1234, self.sockets()), value)

    def test_foreign_pid_peer_plaintext_or_duplicate_refused(self):
        with self.assertRaises(ValueError): proof.matching_connection([self.connection()], 123, self.sockets())
        for key, value in [('peer_host', '10.1.0.28'), ('peer_port', 40124), ('user', 'other'),
                           ('vhost', '/'), ('ssl', False), ('ssl', 1), ('ssl_protocol', 'tlsv1.1'),
                           ('state', 'closing')]:
            with self.assertRaises(ValueError):
                proof.matching_connection([dict(self.connection(), **{key: value})], 1234, self.sockets())
        with self.assertRaises(ValueError):
            proof.matching_connection([self.connection(), self.connection()], 1234, self.sockets())

    def test_idle_broker_outage_and_stable_same_process_recovery(self):
        result, states, verify = self.outage_fixture()
        self.assertTrue(result['same_process'])
        self.assertEqual(result['stable_consumer_samples'], 6)
        self.assertEqual(verify.call_count, 6)
        self.assertEqual(states, ['awaiting_broker_outage', 'broker_outage_observed'])
        self.assertFalse(result['provider_dispatch_recovery_tested'])

    def outage_fixture(self, fault=None):
        clock = [0]
        receipt = {'service_evidence': {'pid': 1234}}
        states = []
        props = {'MainPID': '1234', 'ActiveState': 'active', 'SubState': 'running',
                 'StatusText': 'AMQP consumer disconnected'}
        if fault == 'no-outage': props['StatusText'] = 'AMQP consumer registered; mobile delivery not verified'
        if fault == 'process-exit': props['ActiveState'] = 'failed'
        with patch.object(proof.time, 'monotonic', side_effect=lambda: clock[0]), \
                patch.object(proof.time, 'sleep', side_effect=lambda n: clock.__setitem__(0, clock[0]+n)), \
                patch.object(proof, 'service_properties', return_value=props), \
                patch.object(proof, 'save', side_effect=lambda r: states.append(r['phase'])), \
                patch.object(proof, 'verify_remote', return_value={'pid': 1234}) as verify:
            if fault == 'no-recovery': verify.side_effect = ValueError('not ready')
            if fault == 'restarted': verify.return_value = {'pid': 5678}
            if fault == 'unstable': verify.side_effect = [{'pid': 1234}, ValueError('duplicate consumer')]
            result = proof.verify_outage_recovery({}, receipt)
        return result, states, verify

    def test_outage_is_required_not_inferred_from_a_healthy_service(self):
        with self.assertRaisesRegex(ValueError, 'broker_outage_not_observed'): self.outage_fixture('no-outage')

    def test_process_exit_does_not_pass_idle_reconnect(self):
        with self.assertRaisesRegex(ValueError, 'service_did_not_survive'): self.outage_fixture('process-exit')

    def test_missing_recovery_and_restarted_process_do_not_pass(self):
        for fault in ['no-recovery', 'restarted']:
            with self.assertRaisesRegex(ValueError, 'broker_recovery_not_verified'): self.outage_fixture(fault)

    def test_transient_recovery_or_duplicate_consumer_does_not_pass(self):
        with self.assertRaises(ValueError): self.outage_fixture('unstable')

    def run_fixture(self, fault=None, outage=False):
        with tempfile.TemporaryDirectory(prefix='bridge-service-test.', dir='/root') as directory, ExitStack() as stack:
            base = Path(directory); state = base/'state'; config = base/'config.json'
            fixture_file = base/'fixture.json'; provider = base/'provider.json'
            value = original(); value['PUSH_BRIDGE_SA_FILE'] = str(provider)
            raw = (json.dumps(value)+'\n').encode(); config.write_bytes(raw); config.chmod(0o600)
            provider.write_text('synthetic provider bytes'); provider.chmod(0o600)
            fixture = {'password': 'a'*64, 'ca_pem': 'synthetic CA'}
            fixture_file.write_text(json.dumps(fixture)); fixture_file.chmod(0o600)
            for name, item in [('STATE', state), ('CONFIG', config), ('CA', base/'ca.pem')]:
                stack.enter_context(patch.object(proof, name, item))
            stack.enter_context(patch.object(proof.remote, 'FIXTURE', fixture_file))
            stack.enter_context(patch.object(proof.remote, 'validate_fixture', side_effect=lambda item: item))
            stack.enter_context(patch.object(proof, 'load_configuration', return_value=value))
            stack.enter_context(patch.object(proof.remote, 'check_broker_identity'))
            stack.enter_context(patch.object(proof, 'amqp_tls_options', return_value={}))
            connection = MagicMock()
            stack.enter_context(patch.object(proof.BridgeRuntime, '_connect_amqp', return_value=connection))
            installer = stack.enter_context(patch.object(proof, 'normal_install'))
            stack.enter_context(patch.object(proof, 'service_state', return_value=4321))
            verify = stack.enter_context(patch.object(proof, 'verify_remote', return_value={'pid': 1234}))
            recovery = stack.enter_context(patch.object(proof, 'verify_outage_recovery', return_value={'same_process': True}))
            stack.enter_context(patch.object(proof.socket, 'gethostname', return_value='kz5-testing'))
            stack.enter_context(patch.object(proof.sys, 'argv', ['proof', '--run-development-service-proof']
                                            + (['--broker-outage'] if outage else [])))
            stack.enter_context(patch('builtins.print'))
            if fault == 'close': connection.close.side_effect = RuntimeError('synthetic close failure')
            if fault == 'verify': verify.side_effect = RuntimeError('synthetic verification failure')
            if fault == 'install': installer.side_effect = [RuntimeError('synthetic install failure'), None]
            if fault == 'outage': recovery.side_effect = ValueError('synthetic recovery failure')
            if fault:
                with self.assertRaises(ValueError): proof.main()
            else: proof.main()
            receipt = json.loads((state/'receipt.json').read_text())
            self.assertEqual(config.read_bytes(), raw)
            self.assertEqual(provider.read_text(), 'synthetic provider bytes')
            self.assertEqual(installer.call_count, 2)
            self.assertTrue(receipt['restored'])
            self.assertEqual(receipt['complete'], fault is None)
            self.assertEqual(receipt['pushes_published'], 0)
            self.assertEqual(receipt['provider_calls_requested'], 0)
            self.assertEqual(bool(receipt.get('broker_recovery_verified')), outage and fault is None)

    def test_full_orchestration_restores_after_success(self): self.run_fixture()
    def test_failed_install_restores(self): self.run_fixture('install')
    def test_failed_verification_restores(self): self.run_fixture('verify')
    def test_failed_probe_close_still_restores_but_not_passes(self): self.run_fixture('close')
    def test_outage_success_restores_original_service(self): self.run_fixture(outage=True)
    def test_outage_failure_restores_but_does_not_pass(self): self.run_fixture('outage', outage=True)

    def test_changed_config_refuses_overwrite(self):
        with tempfile.TemporaryDirectory(prefix='bridge-service-test.', dir='/root') as directory:
            config = Path(directory)/'config.json'; config.write_text('operator change')
            with patch.object(proof, 'CONFIG', config):
                with self.assertRaises(ValueError): proof.replace_config(b'expected', b'replacement', 0o600, 0)
            self.assertEqual(config.read_text(), 'operator change')


if __name__ == '__main__': unittest.main()
