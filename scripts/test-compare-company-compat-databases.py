#!/usr/bin/env python3
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location('compare_lab', pathlib.Path(__file__).with_name('compare-company-compat-databases.py'))
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


class CompareTests(unittest.TestCase):
    def test_exact_company_baselines_only(self):
        self.assertEqual(len(lab.DATABASES), 7)
        self.assertTrue(lab.baseline_name(lab.DATABASES[0]).startswith('baseline-account/'))
        self.assertTrue(lab.baseline_name(lab.DATABASES[1]).startswith('baseline-verified-account/'))
        for name in ['accounts', 'system_config', 'other', lab.DATABASES[0] + '-202603']:
            with self.assertRaises(ValueError):
                lab.baseline_name(name)

    def test_merge_compares_add_remove_content_and_revisions(self):
        old = [{'_id': 'a', '_rev': '1-a'}, {'_id': 'c', 'name': 'old'}, {'_id': 'd'}]
        new = [{'_id': 'a', '_rev': '2-a'}, {'_id': 'b'}, {'_id': 'c', 'name': 'new'}]
        changes = []
        summary = lab.compare_streams(old, new, changes.append)
        for field in ['added', 'removed', 'content_changed', 'revision_only', 'changed_non_designs']:
            self.assertEqual(summary[field], 1)
        self.assertEqual(summary['baseline_count'], 3)
        self.assertEqual(summary['working_count'], 3)
        self.assertEqual(len(changes), 4)

    def test_revision_independent_content_hash(self):
        result = lab.compare_streams([{'_id': 'a', '_rev': '1-a'}], [{'_id': 'a', '_rev': '2-a'}], lambda record: None)
        self.assertEqual(result['baseline_content_sha256'], result['working_content_sha256'])

    def test_design_change_count(self):
        result = lab.compare_streams([{'_id': '_design/a', 'views': {}}], [{'_id': '_design/a', 'views': {'v': {}}}], lambda record: None)
        self.assertEqual(result['changed_designs'], 1)
        self.assertEqual(result['changed_non_designs'], 0)

    def test_document_pages_are_bounded_get_only(self):
        class Client:
            def __init__(self):
                self.calls = []
            def request(self, method, path):
                self.calls.append((method, path))
                ids = range(100) if len(self.calls) == 1 else range(100, 101)
                return {'total_rows': 101, 'rows': [{'id': '%03d' % i, 'doc': {'_id': '%03d' % i}} for i in ids]}
        client = Client()
        self.assertEqual(len(list(lab.documents(client, 'fixture', 101))), 101)
        self.assertEqual(len(client.calls), 2)
        self.assertTrue(all(m == 'GET' and 'limit=100' in p for m, p in client.calls))
        self.assertIn('skip=1', client.calls[1][1])

    def test_incomplete_or_repeating_page_rejected(self):
        class Client:
            def request(self, method, path):
                return {'total_rows': 2, 'rows': [{'id': 'a', 'doc': {'_id': 'a'}}]}
        with self.assertRaises(ValueError):
            list(lab.documents(Client(), 'fixture', 2))
        with self.assertRaises(ValueError):
            list(lab.documents(Client(), 'fixture', 1))


if __name__ == '__main__':
    unittest.main()
