#!/usr/bin/env python3
"""Offline transformation, destination-scope and fail-closed copy regressions."""
import copy
import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('devcopy', pathlib.Path(__file__).with_name('prepare-dev-company-copy.py'))
copytool = importlib.util.module_from_spec(spec); spec.loader.exec_module(copytool)


def original(kind, ident):
    return dict(_id=ident, _rev='1-original', pvt_type=kind, pvt_account_id=copytool.ACCOUNT,
                pvt_account_db=copytool.DB, pvt_auth_user_id='old-auth', name='Private fixture')


def plan():
    documents = [copytool.transform(original('account', copytool.ACCOUNT)),
                 copytool.transform(original('device', 'd' * 32)),
                 copytool.transform(original('user', 'u' * 32)),
                 copytool.transform(original('queue', 'q' * 32))]
    result = dict(version=1, owner=copytool.OWNER, account=copytool.ACCOUNT,
                  master=copytool.MASTER, database=copytool.DB, realm=copytool.REALM, documents=documents)
    result['sha256'] = copytool.digest(result)
    return result


class FakeCouch:
    username = 'fixture-admin'

    def __init__(self):
        self.databases = {copytool.MASTER_DB: {copytool.MASTER: {'_id': copytool.MASTER, 'pvt_tree': []}}, 'accounts': {}}
        self.calls = []
        self.fail_document = None

    def request(self, method, database, document=None, payload=None):
        self.calls.append((method, database, document))
        if document is None:
            if method == 'GET':
                return (200, {}) if database in self.databases else (404, None)
            if database in self.databases:
                raise ValueError('DB collision')
            self.databases[database] = {}; return 201, {'ok': True}
        if database not in self.databases:
            return 404, None
        data = self.databases[database]
        if method == 'GET' and document == '_all_docs':
            return 200, {'rows': [{'id': key} for key in sorted(data) if key != '_security']}
        if method == 'GET':
            return (200, copy.deepcopy(data[document])) if document in data else (404, None)
        if document in data:
            raise ValueError('No overwrites allowed in fixture')
        data[document] = copy.deepcopy(payload)
        if document == '_security':
            return 200, {'ok': True}
        data[document]['_rev'] = '1-destination'
        if self.fail_document == document:
            self.fail_document = None
            raise TimeoutError('Ambiguous committed write')
        return 201, {'ok': True}


class DevCopyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='devcopy-test-')
        self.base = pathlib.Path(self.temp.name)
        self.patches = [patch.object(copytool, 'RECEIPT', self.base / 'intent.json'),
                        patch.object(copytool, 'COMPLETED', self.base / 'complete.json'),
                        patch.object(copytool, 'safe_parent')]
        for p in self.patches: p.start()

    def tearDown(self):
        for p in reversed(self.patches): p.stop()
        self.temp.cleanup()

    def test_account_identity_isolated_and_input_unchanged(self):
        source = original('account', copytool.ACCOUNT)
        source.update(pvt_api_key='old-secret', pvt_cpaas_token='old-cloud', pvt_tree=['old-parent'], realm='prod.invalid')
        saved = copy.deepcopy(source); transformed = copytool.transform(source)
        self.assertEqual(source, saved)
        self.assertFalse(transformed['pvt_enabled'])
        self.assertEqual(transformed['pvt_tree'], [copytool.MASTER])
        self.assertEqual(transformed['realm'], copytool.REALM)
        self.assertNotIn('pvt_cpaas_token', transformed)
        self.assertNotEqual(transformed['pvt_api_key'], source['pvt_api_key'])

    def test_device_credentials_push_provision_and_forwarding_isolation(self):
        source = original('device', 'd' * 32)
        source.update(enabled=True, push={'token': 'private'}, provision={'url': 'https://prod.invalid'},
                      call_forward={'enabled': True, 'number': 'private'}, call_failover={'enabled': True},
                      sip={'realm': 'prod.invalid', 'password': 'private', 'ip': '10.1.0.28', 'method': 'ip'},
                      custom_sip_headers={'token': 'private'})
        result = copytool.transform(source)
        self.assertFalse(result['enabled'])
        for key in ('push', 'provision', 'custom_sip_headers'): self.assertNotIn(key, result)
        self.assertFalse(result['call_forward']['enabled']); self.assertFalse(result['call_failover']['enabled'])
        self.assertEqual(result['sip']['realm'], copytool.REALM)
        self.assertEqual(result['sip']['method'], 'password'); self.assertNotIn('ip', result['sip'])
        self.assertEqual(len(result['sip']['password']), 64)

    def test_user_login_and_notifications_replaced(self):
        source = original('user', 'u' * 32)
        source.update(email='private@prod.invalid', password='private', pvt_md5_auth='private', pvt_sha1_auth='private')
        result = copytool.transform(source)
        self.assertNotIn('password', result); self.assertNotEqual(result['pvt_md5_auth'], 'private')
        self.assertNotEqual(result['pvt_sha1_auth'], 'private')
        self.assertTrue(result['email'].endswith('@example.invalid'))
        self.assertFalse(result['send_email_on_creation']); self.assertFalse(result['vm_to_email_enabled'])

    def test_only_reviewed_types_and_company(self):
        for change in [{'pvt_type': 'webhook'}, {'pvt_account_id': 'other'}, {'pvt_account_db': 'other'},
                       {'_attachments': {'audio.wav': {'stub': True}}}, {'_deleted': True}]:
            with self.subTest(change=list(change)):
                with self.assertRaises(ValueError): copytool.transform({**original('device', 'd' * 32), **change})
        self.assertIsNone(copytool.transform({'_id': '_design/private'}))
        self.assertIsNone(copytool.transform(original('parked_call', 'p' * 32)))
        self.assertIsNone(copytool.transform({'_id': 'apps_store', 'apps': {}}))

    def test_plan_tampering_and_rehashed_unsafe_state_refused(self):
        valid = plan(); self.assertEqual(copytool.validate_plan(valid), valid)
        changed = copy.deepcopy(valid); changed['realm'] = 'prod.invalid'
        with self.assertRaises(ValueError): copytool.validate_plan(changed)
        changed = copy.deepcopy(valid); changed['documents'][0]['pvt_enabled'] = True
        changed['sha256'] = copytool.digest({k: v for k, v in changed.items() if k != 'sha256'})
        with self.assertRaises(ValueError): copytool.validate_plan(changed)

    def test_create_verify_and_repeat_without_overwrite(self):
        client, payload = FakeCouch(), plan()
        copytool.apply_plan(client, payload)
        writes = sum(c[0] == 'PUT' for c in client.calls)
        copytool.apply_plan(client, payload)
        self.assertEqual(writes, sum(c[0] == 'PUT' for c in client.calls))
        self.assertTrue(copytool.COMPLETED.exists())
        self.assertEqual(set(db for _, db, _ in client.calls), {copytool.DB, copytool.MASTER_DB, 'accounts'})

    def test_ambiguous_committed_document_resumes_by_readback(self):
        client, payload = FakeCouch(), plan(); client.fail_document = 'd' * 32
        with self.assertRaises(TimeoutError): copytool.apply_plan(client, payload)
        copytool.apply_plan(client, payload)
        self.assertEqual(sum(c == ('PUT', copytool.DB, 'd' * 32) for c in client.calls), 1)

    def test_unowned_db_and_aggregate_collisions_refused(self):
        for existing in ('db', 'aggregate'):
            with self.subTest(existing=existing):
                client = FakeCouch()
                if existing == 'db': client.databases[copytool.DB] = {}
                else: client.databases['accounts'][copytool.ACCOUNT] = {'_id': copytool.ACCOUNT}
                with self.assertRaises(ValueError): copytool.apply_plan(client, plan())
                self.assertFalse(any(c[0] == 'PUT' for c in client.calls))

    def test_modified_owned_document_never_overwritten(self):
        client, payload = FakeCouch(), plan(); copytool.apply_plan(client, payload)
        client.databases[copytool.DB]['d' * 32]['name'] = 'Operator edit'
        with self.assertRaises(ValueError): copytool.apply_plan(client, payload)
        self.assertEqual(client.databases[copytool.DB]['d' * 32]['name'], 'Operator edit')

    def test_security_drift_refused(self):
        client, payload = FakeCouch(), plan(); copytool.apply_plan(client, payload)
        client.databases[copytool.DB]['_security'] = {}
        with self.assertRaises(ValueError): copytool.apply_plan(client, payload)

    def test_transport_rejects_other_databases_before_network(self):
        client = object.__new__(copytool.MainClient)
        for method, db, ident in [('GET', 'system_config', 'x'), ('PUT', 'accounts', 'other'),
                                   ('DELETE', copytool.DB, 'x'), ('GET', copytool.MASTER_DB, 'other')]:
            with self.subTest(method=method, db=db):
                with self.assertRaises(ValueError): client.request(method, db, ident)


if __name__ == '__main__':
    unittest.main()
