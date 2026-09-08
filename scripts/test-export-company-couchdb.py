#!/usr/bin/env python3
"""Offline source-safety and snapshot completeness regression tests."""
import hashlib
import importlib.util
import io
import json
import pathlib
import unittest
from unittest.mock import patch

PATH = pathlib.Path(__file__).with_name('export-company-couchdb.py')
spec = importlib.util.spec_from_file_location('exporter', PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ACCOUNT = 'a' * 32
DB = 'account/aa/aa/' + 'a' * 28
CONFIG = {'account_id': ACCOUNT, 'databases': [DB]}


def document(doc_id='one', rev='2-new', **extra):
    result = {'_id': doc_id, '_rev': rev, '_revisions': {'start': 2, 'ids': [rev.split('-')[1], 'old']}}
    result.update(extra)
    return result


class FakeReader:
    def __init__(self, moving=False):
        self.calls = []
        self.metadata_calls = 0
        self.moving = moving

    def get(self, path, query=None):
        self.calls.append((path, query))
        base = '/' + module.encoded(DB)
        if path == '/':
            return {'version': '3.fixture'}
        if path == base:
            self.metadata_calls += 1
            return {'db_name': DB, 'update_seq': '2-end' if self.moving and self.metadata_calls > 1 else '1-start', 'purge_seq': 0}
        if path == base + '/_security':
            return {'members': {'names': ['fixture']}}
        if path == base + '/_changes':
            if query['since'] == '0':
                return {'results': [{'id': '_design/test', 'changes': [{'rev': '2-new'}, {'rev': '2-conflict'}]}], 'last_seq': '1-next', 'pending': 1}
            return {'results': [{'id': 'gone', 'deleted': True, 'changes': [{'rev': '2-deleted'}]}], 'last_seq': '2-end', 'pending': 0}
        if path == base + '/_design/test':
            return document('_design/test', query['rev'], _attachments={'x.wav': {'data': 'd2F2', 'content_type': 'audio/wav'}})
        if path == base + '/gone':
            return document('gone', '2-deleted', _deleted=True)
        raise AssertionError('Unexpected endpoint')


class ExportTests(unittest.TestCase):
    def test_design_route_without_redirect_and_normal_ids_stay_encoded(self):
        self.assertEqual(module.document_path('_design/test'), '_design/test')
        self.assertEqual(module.document_path('_design/odd/name'), '_design/odd%2Fname')
        self.assertEqual(module.document_path('normal/id?secret'), 'normal%2Fid%3Fsecret')

    def test_exact_account_allowlist(self):
        for name in [DB, DB + '-202601', DB + '-202612']:
            self.assertEqual(module.scope({'account_id': ACCOUNT, 'databases': [name]})[1], [name])

    def test_foreign_global_path_and_bad_month_rejected(self):
        for name in ['accounts', 'system_config', DB + 'x', DB + '-202613', DB + '/../../accounts', DB.replace('aa/aa', 'bb/bb'), DB + '-202609-extra', 4]:
            with self.assertRaises(module.ExportError):
                module.scope({'account_id': ACCOUNT, 'databases': [DB, name]})

    def test_missing_duplicate_or_invalid_account_rejected(self):
        for config in [{}, {'account_id': ACCOUNT, 'databases': []}, {'account_id': ACCOUNT, 'databases': [DB, DB]}, {'account_id': '../bad', 'databases': [DB]}]:
            with self.assertRaises(module.ExportError):
                module.scope(config)

    def test_no_network_before_entire_scope_validation(self):
        reader = FakeReader()
        with self.assertRaises(module.ExportError):
            module.export({'account_id': ACCOUNT, 'databases': [DB, 'system_config']}, reader, module.Writer(io.StringIO()))
        self.assertEqual(reader.calls, [])

    def snapshot(self, moving=False):
        reader, out = FakeReader(moving), io.StringIO()
        module.export(CONFIG, reader, module.Writer(out))
        return reader, out.getvalue(), [json.loads(line) for line in out.getvalue().splitlines()]

    def test_conflicts_tombstones_designs_and_attachment_bytes(self):
        reader, raw, records = self.snapshot()
        docs = [r['doc'] for r in records if r['type'] == 'document']
        self.assertEqual(len(docs), 3)
        self.assertEqual([d['_rev'] for d in docs], ['2-new', '2-conflict', '2-deleted'])
        self.assertTrue(docs[-1]['_deleted'])
        self.assertEqual(docs[0]['_attachments']['x.wav']['data'], 'd2F2')
        for path, query in reader.calls:
            if query and 'rev' in query:
                self.assertEqual(query['revs'], 'true')
                self.assertEqual(query['attachments'], 'true')
        changes = [q for p, q in reader.calls if p.endswith('/_changes')]
        self.assertEqual([q['since'] for q in changes], ['0', '1-next'])
        self.assertTrue(all(q['style'] == 'all_docs' for q in changes))

    def test_stream_digest_and_completion_marker(self):
        reader, raw, records = self.snapshot()
        end = records[-1]
        self.assertEqual(end['type'], 'snapshot_end')
        self.assertEqual(end['records_before_end'], len(records) - 1)
        self.assertEqual(end['sha256'], hashlib.sha256(''.join(raw.splitlines(True)[:-1]).encode()).hexdigest())
        self.assertTrue(end['all_databases_unchanged'])

    def test_live_changes_not_claimed_consistent(self):
        self.assertFalse(self.snapshot(True)[2][-1]['all_databases_unchanged'])

    def test_missing_ancestry_attachment_or_wrong_identity_fail(self):
        for doc in [{'_id': 'one', '_rev': '2-new'}, document('wrong'), document(_attachments={'x': {'stub': True}}), document(_attachments={'x': {'data': '!!!'}})]:
            with self.assertRaises(module.ExportError):
                module.validate_doc(doc, 'one', '2-new')

    def test_stuck_feed_fails_without_end_record(self):
        reader, out = FakeReader(), io.StringIO()
        original = reader.get
        def get(path, query=None):
            result = original(path, query)
            if path.endswith('/_changes'):
                result['last_seq'] = query['since']
            return result
        reader.get = get
        with self.assertRaises(module.ExportError):
            module.export(CONFIG, reader, module.Writer(out))
        self.assertNotIn('snapshot_end', out.getvalue())

    def test_http_client_get_only_fixed_loopback_and_no_proxy(self):
        captured = []
        class Opener:
            def open(self, req, timeout):
                captured.append(req)
                return io.BytesIO(b'{}')
        with patch.object(module, 'build_opener', return_value=Opener()) as build, patch.object(module.time, 'sleep'):
            reader = module.Reader('fixture-user', 'fixture-secret')
            reader.get('/' + module.encoded(DB), {'rev': '1-x'})
            self.assertEqual(build.call_args.args[0].proxies, {})
        req = captured[0]
        self.assertEqual(req.get_method(), 'GET')
        self.assertIsNone(req.data)
        self.assertTrue(req.full_url.startswith('http://127.0.0.1:5984/account%2F'))
        self.assertNotIn('fixture-secret', req.full_url)

    def test_redirect_refused(self):
        with self.assertRaises(module.ExportError):
            module.NoRedirect().redirect_request(None, None, 302, '', {}, 'http://foreign/')

    def test_response_size_bounded(self):
        class Opener:
            def open(self, *args, **kwargs):
                return io.BytesIO(b'12345')
        with patch.object(module, 'build_opener', return_value=Opener()), patch.object(module.time, 'sleep'), patch.object(module, 'MAX_RESPONSE', 4):
            with self.assertRaises(module.ExportError):
                module.Reader('u', 'p').get('/')


if __name__ == '__main__':
    unittest.main()
