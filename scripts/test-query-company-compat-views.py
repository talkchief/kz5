#!/usr/bin/env python3
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location('query_lab', pathlib.Path(__file__).with_name('query-company-compat-views.py'))
query_lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(query_lab)


class QueryTests(unittest.TestCase):
    def test_field_contract_comparison_does_not_output_values(self):
        result = query_lab.field_changes([{'id': 'private-id', 'value': {'old': 'private-value', 'name': 'old-name'}}], [{'id': 'private-id', 'value': {'new': 'new-value', 'name': 'new-name'}}])
        self.assertEqual(result['added_value_fields'], ['new'])
        self.assertEqual(result['removed_value_fields'], ['old'])
        self.assertEqual(result['changed_common_value_fields'], ['name'])
        self.assertTrue(result['same_row_ids'])
        self.assertNotIn('private', str(result))

    def test_duplicate_rows_are_not_silently_collapsed(self):
        rows = [{'id': 'one', 'value': {}}, {'id': 'one', 'value': {}}]
        self.assertIn('field_comparison', query_lab.field_changes(rows, rows))

    def test_missing_view_is_not_compatible(self):
        result = query_lab.summarize([{'view': 'legacy/test', 'baseline': {'http_status': 200, 'row_count': 0, 'rows_sha256': 'digest', 'rows': []}, 'working': {'http_status': 404}}])[0]
        self.assertFalse(result['same_rows'])
        self.assertEqual(result['working_status'], 404)


if __name__ == '__main__':
    unittest.main()
