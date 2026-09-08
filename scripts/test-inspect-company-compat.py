#!/usr/bin/env python3
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location('inspect_lab', pathlib.Path(__file__).with_name('inspect-company-compat.py'))
inspect_lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspect_lab)


class CompareTests(unittest.TestCase):
    def test_equal_documents(self):
        summary, details = inspect_lab.compare({'one': {'_rev': '1-x'}}, {'one': {'_rev': '1-x'}})
        self.assertTrue(all(value == 0 for value in summary.values()))

    def test_revision_only_not_content_change(self):
        summary, _ = inspect_lab.compare({'one': {'_rev': '1-x', 'enabled': True}}, {'one': {'_rev': '2-x', 'enabled': True}})
        self.assertEqual(summary['revision_only_changes'], 1)
        self.assertEqual(summary['content_changed_documents'], 0)

    def test_design_added_removed_and_changed_views(self):
        summary, details = inspect_lab.compare(
            {'_design/users': {'views': {'removed': {}, 'changed': {'map': 'old'}}}},
            {'_design/users': {'views': {'added': {}, 'changed': {'map': 'new'}}}})
        self.assertEqual(summary['changed_design_documents'], 1)
        self.assertEqual(details['design_changes'][0]['added_views'], ['added'])
        self.assertEqual(details['design_changes'][0]['removed_views'], ['removed'])
        self.assertEqual(details['design_changes'][0]['changed_views'], ['changed'])

    def test_counts_do_not_expose_customer_data(self):
        summary, details = inspect_lab.compare({'private-id': {'name': 'private-person'}, 'gone': {}}, {'private-id': {'name': 'updated-person'}, 'new': {}})
        self.assertEqual(summary['added_documents'], 1)
        self.assertEqual(summary['removed_documents'], 1)
        self.assertEqual(summary['changed_non_design_documents'], 1)
        self.assertTrue(all(isinstance(value, int) for value in summary.values()))


if __name__ == '__main__':
    unittest.main()
