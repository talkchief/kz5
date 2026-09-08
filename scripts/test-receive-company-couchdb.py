#!/usr/bin/env python3
import hashlib
import importlib.util
import io
import json
import os
import pathlib
import tempfile
import unittest


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, pathlib.Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


receiver = load('receiver', 'receive-company-couchdb.py')
fixture = load('fixture', 'test-export-company-couchdb.py')


class ReceiverTests(unittest.TestCase):
    def stream(self):
        output = io.StringIO()
        fixture.module.export(fixture.CONFIG, fixture.FakeReader(), fixture.module.Writer(output))
        return output.getvalue().encode()

    def test_private_verified_snapshot(self):
        raw = self.stream()
        with tempfile.TemporaryDirectory() as directory:
            result = receiver.receive(io.BytesIO(raw), directory, fixture.ACCOUNT)
            path = pathlib.Path(result['path'])
            self.assertEqual(path.read_bytes(), raw)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(result['leaf_revisions'], 3)
            self.assertEqual(result['sha256_file'], hashlib.sha256(raw).hexdigest())
            self.assertEqual(len(list(path.parent.iterdir())), 1)

    def test_truncation_tamper_and_trailing_data_not_published(self):
        raw = self.stream()
        for changed in [raw[:-10], b''.join(raw.splitlines(True)[:-1]), raw.replace(b'd2F2', b'd2F3'), raw + b'{}\n']:
            with tempfile.TemporaryDirectory() as directory:
                with self.assertRaises((ValueError, KeyError)):
                    receiver.receive(io.BytesIO(changed), directory, fixture.ACCOUNT)
                paths = list(pathlib.Path(directory).iterdir())
                self.assertTrue(all(p.suffix == '.partial' and p.stat().st_mode & 0o777 == 0o600 for p in paths))

    def test_wrong_company_not_published(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                receiver.receive(io.BytesIO(self.stream()), directory, 'b' * 32)
            self.assertFalse(list(pathlib.Path(directory).glob('*.ndjson')))

    def test_public_directory_rejected_before_write(self):
        with tempfile.TemporaryDirectory() as directory:
            os.chmod(directory, 0o755)
            with self.assertRaises(ValueError):
                receiver.receive(io.BytesIO(self.stream()), directory, fixture.ACCOUNT)
            self.assertEqual(os.listdir(directory), [])

    def test_repeat_never_overwrites(self):
        with tempfile.TemporaryDirectory() as directory:
            first = receiver.receive(io.BytesIO(self.stream()), directory, fixture.ACCOUNT)
            second = receiver.receive(io.BytesIO(self.stream()), directory, fixture.ACCOUNT)
            self.assertNotEqual(first['path'], second['path'])
            self.assertEqual(len(os.listdir(directory)), 2)

    def test_symlink_directory_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            link = pathlib.Path(directory) / 'link'
            link.symlink_to(directory, target_is_directory=True)
            with self.assertRaises(ValueError):
                receiver.receive(io.BytesIO(self.stream()), str(link), fixture.ACCOUNT)


if __name__ == '__main__':
    unittest.main()
