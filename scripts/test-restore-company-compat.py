#!/usr/bin/env python3
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, pathlib.Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


restore = load('restore', 'restore-company-compat.py')
fixture = load('fixture', 'test-export-company-couchdb.py')


class FakeClient:
    def __init__(self, existing=None):
        self.calls = []
        self.existing = existing or []

    def request(self, method, path, payload=None):
        self.calls.append((method, path, payload))
        if path == '/_all_dbs':
            return self.existing
        if path.endswith('/_bulk_docs'):
            return []
        if method == 'GET':
            return {'doc_count': None, 'doc_del_count': None}
        return {}


class RestoreTests(unittest.TestCase):
    def test_distinct_retry_baseline_never_reuses_interrupted_names(self):
        self.assertEqual(restore.target_database(fixture.DB, 'baseline', 'retry1'), 'baseline-retry1-' + fixture.DB)
        for copy, tag in [('working', 'retry1'), ('baseline', '../other'), ('baseline', 'a/b')]:
            with self.assertRaises(ValueError):
                restore.target_database(fixture.DB, copy, tag)

    def snapshot(self, directory):
        out = io.StringIO()
        fixture.module.export(fixture.CONFIG, fixture.FakeReader(), fixture.module.Writer(out))
        path = pathlib.Path(directory) / 'fixture.ndjson'
        path.write_text(out.getvalue())
        return path

    def test_collision_prevents_all_writes(self):
        client = FakeClient([fixture.DB])
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                restore.restore(self.snapshot(directory), fixture.ACCOUNT, 'working', client)
        self.assertEqual([m for m, p, b in client.calls], ['GET'])

    def test_baseline_mapping_and_no_revision_rewrite(self):
        client = FakeClient()
        with tempfile.TemporaryDirectory() as directory:
            result = restore.restore(self.snapshot(directory), fixture.ACCOUNT, 'baseline', client)
        self.assertEqual(result[0]['database'], 'baseline-' + fixture.DB)
        batches = [b for m, p, b in client.calls if p.endswith('/_bulk_docs')]
        self.assertTrue(all(b['new_edits'] is False for b in batches))
        self.assertTrue(batches[0]['docs'][0]['_deleted'])
        self.assertTrue(batches[-1]['docs'][0]['_id'].startswith('_design/'))
        self.assertTrue(all(len(b['docs']) == 1 for b in batches if b['docs'][0]['_id'].startswith('_design/')))
        self.assertEqual(len([p for m, p, b in client.calls if p.endswith('/_revs_diff')]), len(batches))

    def test_row_error_fails(self):
        class Client:
            def request(self, *args):
                return [{'error': 'forbidden'}]
        with self.assertRaises(ValueError):
            restore.send_batch(Client(), fixture.DB, [fixture.document()])

    def test_missing_revision_fails(self):
        class Client:
            def request(self, method, path, payload):
                return [] if path.endswith('_bulk_docs') else {'one': {'missing': ['2-new']}}
        with self.assertRaises(ValueError):
            restore.send_batch(Client(), fixture.DB, [fixture.document()])

    def test_normal_host_namespace_refused(self):
        with patch.object(restore.os, 'geteuid', return_value=0), patch.object(restore.os, 'readlink', return_value='same'):
            with self.assertRaises(ValueError):
                restore.assert_namespace()

    def test_wrong_namespace_refused(self):
        with patch.object(restore.os, 'geteuid', return_value=0), patch.object(restore.os, 'readlink', side_effect=['self', 'host', 'self', 'other']), patch.object(restore.subprocess, 'check_output', return_value=b'42'):
            with self.assertRaises(ValueError):
                restore.assert_namespace()


if __name__ == '__main__':
    unittest.main()
