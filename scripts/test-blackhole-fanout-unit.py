#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import threading
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('fanout', Path(__file__).with_name('test-blackhole-fanout.py'))
fanout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fanout)


class FanoutChecks(unittest.TestCase):
    def message(self, **data):
        return {'action': 'event', 'name': 'CHANNEL_HOLD',
                'data': {'call_id': 'fanout-' + 'a' * 32,
                         'custom_channel_vars': {'account_id': fanout.ACCOUNT, 'kz5_fixture_sequence': 1,
                                                 'kz5_fixture_sent_ms': 100}, **data}}

    def receive(self, messages, control=False):
        c = object.__new__(fanout.Client)
        c.call, c.control, c.delayed = 'fanout-' + 'a' * 32, control, False
        c.events, c.latencies, c.replies, c.error = [], [], {}, None
        c.socket, c.stopping, c.cv = object(), False, threading.Condition()
        frames = iter(messages)

        def next_frame(_):
            try:
                return next(frames)
            except StopIteration:
                c.stopping = True
                raise OSError('test finished')

        with patch.object(fanout.transport, 'receive_json', next_frame):
            c.receive()
        return c

    def test_correlated_event(self):
        c = self.receive([self.message()])
        self.assertEqual(c.events, [1])
        self.assertIsNone(c.error)

    def test_wrong_identity_or_call(self):
        for message in [self.message(call_id='other'), {**self.message(), 'name': 'OTHER'},
                        self.message(custom_channel_vars={'account_id': 'other'})]:
            self.assertIsNotNone(self.receive([message]).error)

    def test_duplicates_and_control_leaks(self):
        self.assertIsNotNone(self.receive([self.message(), self.message()]).error)
        self.assertIsNotNone(self.receive([self.message()], control=True).error)

    def test_closed_or_invalid_frame_is_failure(self):
        self.assertIsNotNone(self.receive([{}]).error)


if __name__ == '__main__':
    unittest.main()
