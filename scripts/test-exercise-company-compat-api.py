#!/usr/bin/env python3
import importlib.util
import io
import json
import pathlib
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location('api_lab', pathlib.Path(__file__).with_name('exercise-company-compat-api.py'))
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


class FakeApi:
    def __init__(self, fail_edit=False, fail_restore=False):
        self.value = 'Original'
        self.calls = []
        self.fail_edit = fail_edit
        self.fail_restore = fail_restore

    def request(self, method, path, data=None):
        self.calls.append((method, path, data))
        if data:
            self.value = data['name']
            if self.fail_edit and '[compat-lab]' in self.value:
                raise TimeoutError('Response lost after commit')
            if self.fail_restore and self.value == 'Original':
                self.value = 'Not restored'
                return {'http': 500, 'status': 'error', 'data': None}
        return {'http': 200, 'status': 'success', 'data': {'name': self.value}}


class ApiTests(unittest.TestCase):
    def test_authentication_token_kept_out_of_returned_evidence(self):
        class Response(io.BytesIO):
            status = 201
        class Opener:
            def open(self, request, timeout):
                self.request = request
                return Response(json.dumps({'status': 'success', 'auth_token': 'secret-token',
                                            'data': {'api_key': 'secret-key'}}).encode())
        api = lab.Api.__new__(lab.Api)
        api.token, api.opener = None, Opener()
        result = api.request('PUT', '/api_auth', {'api_key': 'secret-key'})
        self.assertEqual(api.token, 'secret-token')
        self.assertNotIn('secret', json.dumps(result))
        self.assertEqual(api.opener.request.full_url, 'http://127.0.0.1:8000/v2/api_auth')

    def test_authentication_error_body_is_discarded(self):
        class Opener:
            def open(self, request, timeout):
                raise HTTPError(request.full_url, 401, 'Unauthorized', {},
                                io.BytesIO(b'{"data":{"api_key":"secret-key"}}'))
        api = lab.Api.__new__(lab.Api)
        api.token, api.opener = None, Opener()
        self.assertEqual(api.request('PUT', '/api_auth', {'api_key': 'secret-key'}),
                         {'http': 401, 'status': 'error', 'data': None})

    def test_scope_rejects_other_accounts_globals_and_mutations(self):
        for path in ['/accounts/other', '/system_configs', '//evil', lab.PREFIX + '/../other',
                     lab.PREFIX + '/users/../devices', lab.PREFIX + '/users?account=other']:
            self.assertFalse(lab.allowed_path('GET', path))
        for method in ['PUT', 'POST', 'DELETE']:
            self.assertFalse(lab.allowed_path(method, lab.PREFIX))
            self.assertFalse(lab.allowed_path(method, lab.PREFIX + '/users/' + 'a' * 32))
        self.assertFalse(lab.allowed_path('GET', '/api_auth'))
        self.assertTrue(lab.allowed_path('PUT', '/api_auth'))

    def test_fixed_read_and_patch_scope(self):
        self.assertTrue(lab.allowed_path('GET', lab.PREFIX))
        for resource, _, _ in lab.RESOURCES[1:]:
            self.assertTrue(lab.allowed_path('GET', lab.PREFIX + '/' + resource))
            self.assertTrue(lab.allowed_path('GET', lab.PREFIX + '/' + resource + '?paginate=false'))
            self.assertFalse(lab.allowed_path('PATCH', lab.PREFIX + '/' + resource + '?paginate=false'))
            self.assertTrue(lab.allowed_path('PATCH', lab.PREFIX + '/' + resource + '/' + 'b' * 32))
            self.assertFalse(lab.allowed_path('PATCH', lab.PREFIX + '/' + resource))

    def test_namespace_required_before_network(self):
        with patch.object(lab.restore, 'assert_namespace', side_effect=ValueError), patch.object(lab, 'build_opener') as opener:
            with self.assertRaises(ValueError):
                lab.Api()
            opener.assert_not_called()

    def test_choose_skips_missing_empty_and_unsafe_fixture(self):
        docs = {'1': {'_id': '../other', 'pvt_type': 'user', 'first_name': 'Unsafe'},
                '2': {'_id': 'a' * 32, 'pvt_type': 'user', 'first_name': ''},
                '3': {'_id': 'b' * 32, 'pvt_type': 'user', 'first_name': 'Safe'}}
        self.assertEqual(lab.choose(docs, 'users', 'user', 'first_name')['_id'], 'b' * 32)
        self.assertIsNone(lab.choose(docs, 'devices', 'device', 'name'))

    def test_choose_excludes_kazoo_soft_deleted_documents(self):
        docs = {'1': {'_id': 'a' * 32, 'pvt_type': 'device', 'name': 'Deleted', 'pvt_deleted': True},
                '2': {'_id': 'b' * 32, 'pvt_type': 'device', 'name': 'Live'}}
        self.assertEqual(lab.choose(docs, 'devices', 'device', 'name')['_id'], 'b' * 32)

    def test_edit_and_restore_readbacks(self):
        api = FakeApi()
        journal = []
        result = lab.edit_and_restore(api, lab.PREFIX, 'name', 'Original', journal.append)
        self.assertTrue(result['edit_verified'])
        self.assertTrue(result['restored'])
        self.assertEqual(api.value, 'Original')
        self.assertEqual(journal[0]['event'], 'edit_intent')
        self.assertEqual([call[0] for call in api.calls], ['PATCH', 'GET', 'PATCH', 'GET'])

    def test_ambiguous_timeout_still_restores(self):
        api = FakeApi(fail_edit=True)
        with self.assertRaises(TimeoutError):
            lab.edit_and_restore(api, lab.PREFIX, 'name', 'Original', lambda record: None)
        self.assertEqual(api.value, 'Original')
        self.assertEqual(api.calls[-1][0], 'GET')

    def test_restore_failure_is_not_success(self):
        with self.assertRaises(RuntimeError):
            lab.edit_and_restore(FakeApi(fail_restore=True), lab.PREFIX, 'name', 'Original', lambda record: None)

    def test_rejected_edit_with_original_unchanged_can_continue(self):
        class Reject(FakeApi):
            def request(self, method, path, data=None):
                if method == 'PATCH':
                    return {'http': 400, 'status': 'error', 'data': {}}
                return super().request(method, path)
        result = lab.edit_and_restore(Reject(), lab.PREFIX, 'name', 'Original', lambda record: None)
        self.assertFalse(result['edit_verified'])
        self.assertTrue(result['restored'])
        self.assertEqual(result['restore_http'], 400)


if __name__ == '__main__':
    unittest.main()
