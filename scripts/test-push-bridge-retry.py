#!/usr/bin/env python3
"""Offline counted-retry policy/owner fixtures. No brokers, keys or sends."""
import importlib.util
import json
from pathlib import Path
import sys
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "services/push-bridge"))
import bridge
import freshness_runtime
from delivery_retry import MODE, delivery_count, completed_transient, RetryMetadataFailure
from delivery_settlement import OwnerSettlements, SettlementFailure
from freshness import capture


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / file)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


fixture = load("retry_settlement_fixture", "test-push-bridge-settlement.py")
BODY = json.dumps({"Token-ID": "fixture-token", "Call-ID": "fixture-call",
                   "Push-Freshness": {"version": 1, "created_at_ms": 1000000,
                                      "deadline_ms": 1060000}})
TRANSIENT = (False, 503, "provider_response")


class Clock:
    def __init__(self):
        self.wall, self.mono = 1000000, 100

    def __call__(self):
        return {"now_ms": self.wall, "monotonic_ms": self.mono}

    def advance(self, ms):
        self.wall += ms
        self.mono += ms


class Message(fixture.Message):
    def __init__(self, count=0, nack_error=False):
        super().__init__(body=BODY)
        self.properties = {"headers": {"x-delivery-count": count}} if count else {}
        self.redelivered = count > 0
        self.nacks = []
        self.nack_error = nack_error

    def nack(self, requeue=True):
        if threading.get_ident() != self.owner:
            raise AssertionError("NACK outside owner")
        self.nacks.append(requeue)
        if self.nack_error:
            raise RuntimeError("fixture-private-nack-error")


class RetryTests(unittest.TestCase):
    def owner(self, count=0, lifetime=60000, nack_error=False, limit=2, provider="fcm"):
        clock = Clock()
        lease = capture({"Push-Freshness": {"version": 1, "created_at_ms": clock.wall,
                                           "deadline_ms": clock.wall + lifetime}},
                        "unix-ms-v1", **clock())
        owner = OwnerSettlements(limit, quarantine=True, retry=True, clock=clock)
        executor, message = fixture.Executor(), Message(count, nack_error)
        owner.submit(executor, Mock(), message, BODY, provider=provider, freshness=lease)
        return owner, executor, message, clock, lease

    def test_exact_broker_metadata_only_never_reset_redelivery_count(self):
        for props in ({}, {"headers": None}, {"headers": {}}, {"headers": {"x-delivery-count": 0}}):
            self.assertEqual(delivery_count(props, False), 0)
        for count in (1, 2, 3, 2**63 - 1):
            self.assertEqual(delivery_count({"headers": {"x-delivery-count": count}}, True), count)
        for props, redelivered in (({}, True), ({"headers": None}, True), ({}, None), ({}, 0),
                                  ({"headers": []}, False), ({"headers": {b"x-delivery-count": 1}}, True),
                                  ({"headers": {"x-death": []}}, True), ([], False)):
            with self.assertRaises(RetryMetadataFailure): delivery_count(props, redelivered)
        for count in (None, True, 1.0, "1", -1, 2**63, 0):
            with self.assertRaises(RetryMetadataFailure): delivery_count({"headers": {"x-delivery-count": count}}, True)
        with self.assertRaises(RetryMetadataFailure): delivery_count({"headers": {"x-delivery-count": 1}}, False)
        class IntegerSubclass(int):
            pass
        with self.assertRaises(RetryMetadataFailure): delivery_count({"headers": {"x-delivery-count": IntegerSubclass(1)}}, True)
        for kwargs in ({"retry": True}, {"retry": 1, "quarantine": True}, {"clock": 1}):
            with self.assertRaises(ValueError): OwnerSettlements(1, **kwargs)

    def test_only_exact_completed_500_503_are_retryable(self):
        for status in (500, 503): self.assertTrue(completed_transient((False, status, "provider_response"), "fcm"))
        for result in ((False, 429, "provider_response"), (False, 502, "provider_response"),
                       (False, 504, "provider_response"), (False, 401, "provider_response"),
                       (False, 403, "provider_response"), (False, -1, "provider_transport_error"),
                       (False, -1, "apns_transport_error"), (False, 503, "apns_incomplete_response"),
                       (False, 503, "oauth_transport_error"), (True, 503, "provider_response"),
                       (False, 503, "provider_retry_after_required"),
                       (0, 503, "provider_response"), (False, 503.0, "provider_response"),
                       [False, 503, "provider_response"], None):
            self.assertFalse(completed_transient(result, "fcm"))
        for provider in (None, "apns", "unknown", ["fcm"]): self.assertFalse(completed_transient(TRANSIENT, provider))

    def test_owner_delays_single_nack_without_sleep_or_same_process_resubmit(self):
        for count, delay in ((0, 2000), (1, 5000)):
            owner, executor, message, clock, _ = self.owner(count)
            executor.jobs[0][2].set_result(TRANSIENT)
            with patch("time.sleep", side_effect=AssertionError("no sleeps")):
                owner.drain(); owner.drain()
                self.assertEqual(owner.pending_count, 1); self.assertEqual(message.nacks, [])
                clock.advance(delay - 1); owner.drain(); self.assertEqual(message.nacks, [])
                clock.advance(1); owner.drain(); owner.drain()
            self.assertEqual(message.nacks, [True]); self.assertEqual(message.acks, 0)
            self.assertEqual(message.rejections, []); self.assertEqual(owner.pending_count, 0)
            self.assertEqual(len(executor.jobs), 1)

    def test_deferred_message_holds_prefetch_but_does_not_block_completed_success(self):
        owner, executor, message, clock, lease = self.owner()
        accepted = Message()
        owner.submit(executor, Mock(), accepted, BODY, provider="fcm", freshness=lease)
        executor.jobs[0][2].set_result(TRANSIENT); executor.jobs[1][2].set_result(fixture.ACCEPTED)
        owner.drain(); self.assertEqual(accepted.acks, 1); self.assertEqual(owner.pending_count, 1)
        clock.advance(2000); owner.drain(); self.assertEqual(message.nacks, [True])
        owner, executor, _message, _clock, lease = self.owner(limit=1)
        executor.jobs[0][2].set_result(TRANSIENT); owner.drain()
        with self.assertRaises(SettlementFailure): owner.submit(executor, Mock(), Message(), BODY, provider="fcm", freshness=lease)
        self.assertEqual(len(executor.jobs), 1)

    def test_third_failure_or_fourth_delivery_is_quarantined_without_another_send(self):
        owner, executor, message, _clock, _lease = self.owner(2)
        executor.jobs[0][2].set_result(TRANSIENT); owner.drain()
        self.assertEqual(message.rejections, [False]); self.assertEqual(message.nacks, [])
        for count in (3, 4, 100):
            owner, executor, message, _clock, _lease = self.owner(count)
            self.assertEqual(executor.jobs, []); owner.drain()
            self.assertEqual(message.rejections, [False]); self.assertEqual(message.nacks, [])

    def test_counted_redelivery_sequence_cannot_submit_a_fourth_provider_worker(self):
        submitted, nacks, quarantines = 0, 0, 0
        for count in (0, 1, 2, 3):
            owner, executor, message, clock, _lease = self.owner(count)
            submitted += len(executor.jobs)
            if executor.jobs: executor.jobs[0][2].set_result(TRANSIENT)
            owner.drain(); clock.advance(5000); owner.drain()
            nacks += len(message.nacks); quarantines += len(message.rejections)
        self.assertEqual(submitted, 3); self.assertEqual(nacks, 2); self.assertEqual(quarantines, 2)

    def test_expiry_before_or_during_delay_never_requeues(self):
        owner, executor, message, _clock, _lease = self.owner(lifetime=2000)
        executor.jobs[0][2].set_result(TRANSIENT); owner.drain()
        self.assertEqual(message.rejections, [False]); self.assertEqual(message.nacks, [])
        owner, executor, message, clock, _lease = self.owner(lifetime=3000)
        executor.jobs[0][2].set_result(TRANSIENT); owner.drain(); clock.advance(3000); owner.drain()
        self.assertEqual(message.rejections, [False]); self.assertEqual(message.nacks, [])
        owner, executor, message, clock, _lease = self.owner()
        executor.jobs[0][2].set_result(TRANSIENT); owner.drain(); clock.wall += 60000; owner.drain()
        self.assertEqual(message.rejections, [False])

    def test_bad_metadata_missing_freshness_and_expired_admission_make_no_worker(self):
        clock, executor = Clock(), fixture.Executor()
        lease = capture(json.loads(BODY), "unix-ms-v1", **clock())
        message = Message(); message.redelivered = True
        owner = OwnerSettlements(2, quarantine=True, retry=True, clock=clock)
        with self.assertRaises(SettlementFailure): owner.submit(executor, Mock(), message, BODY, provider="fcm", freshness=lease)
        self.assertEqual(executor.jobs, []); self.assertEqual(message.nacks, []); self.assertEqual(message.rejections, [])
        for admitted in (None, lease):
            owner, message = OwnerSettlements(2, quarantine=True, retry=True, clock=clock), Message()
            clock.advance(60000)
            owner.submit(executor, Mock(), message, BODY, provider="fcm", freshness=admitted); owner.drain()
            self.assertEqual(executor.jobs, []); self.assertEqual(message.rejections, [False])

    def test_uncertain_outcomes_and_nack_exception_fail_stop_without_replay(self):
        for result in ((False, -1, "provider_transport_error"), (False, 429, "provider_response"),
                       (False, 403, "provider_response"), (False, 503, "apns_incomplete_response"),
                       (False, 503, "provider_retry_after_required")):
            owner, executor, message, _clock, _lease = self.owner()
            executor.jobs[0][2].set_result(result)
            with self.assertRaises(SettlementFailure): owner.drain()
            self.assertEqual(message.nacks, []); self.assertEqual(message.rejections, [])
        owner, executor, message, clock, _lease = self.owner(nack_error=True)
        executor.jobs[0][2].set_result(TRANSIENT); owner.drain(); clock.advance(2000)
        with self.assertRaises(SettlementFailure): owner.drain()
        with self.assertRaises(SettlementFailure): owner.drain()
        self.assertEqual(message.nacks, [True]); self.assertEqual(owner.pending_count, 1)
        owner, executor, message, _clock, _lease = self.owner(provider="apns")
        executor.jobs[0][2].set_result(TRANSIENT)
        with self.assertRaises(SettlementFailure): owner.drain()
        self.assertEqual(message.nacks, []); self.assertEqual(message.rejections, [])

    def test_count_is_captured_once_and_private_clock_failure_cannot_requeue(self):
        owner, executor, message, clock, _lease = self.owner()
        message.properties = {"headers": {"x-delivery-count": 2}}; message.redelivered = True
        executor.jobs[0][2].set_result(TRANSIENT); owner.drain(); clock.advance(2000); owner.drain()
        self.assertEqual(message.nacks, [True]); self.assertEqual(message.rejections, [])
        for broken in (Mock(side_effect=RuntimeError("fixture-private-clock")),
                       Mock(return_value={"now_ms": -1, "monotonic_ms": 100})):
            owner, executor, message, _clock, _lease = self.owner()
            executor.jobs[0][2].set_result(TRANSIENT); owner._clock = broken
            with self.assertRaises(SettlementFailure): owner.drain()
            with self.assertRaises(SettlementFailure): owner.drain()
            self.assertEqual(message.nacks, []); self.assertEqual(message.rejections, [])
        clock = Clock(); lease = capture(json.loads(BODY), "unix-ms-v1", **clock())
        for broken in (Mock(side_effect=RuntimeError("fixture-private-clock")),
                       Mock(return_value={"now_ms": -1, "monotonic_ms": 100})):
            owner, executor, message = OwnerSettlements(1, quarantine=True, retry=True, clock=broken), fixture.Executor(), Message()
            with self.assertRaises(SettlementFailure): owner.submit(executor, Mock(), message, BODY, provider="fcm", freshness=lease)
            with self.assertRaises(SettlementFailure): owner.drain()
            self.assertEqual(executor.jobs, []); self.assertEqual(message.nacks, []); self.assertEqual(message.rejections, [])

    def test_cancelled_workers_invalidated_generations_and_nonowner_cannot_retry(self):
        owner, executor, message, clock, _lease = self.owner()
        executor.jobs[0][2].cancel()
        with self.assertRaises(SettlementFailure): owner.drain()
        self.assertEqual(message.nacks, [])
        owner, executor, message, clock, _lease = self.owner()
        executor.jobs[0][2].set_result(TRANSIENT); owner.drain(); owner.invalidate(); clock.advance(5000)
        with self.assertRaises(SettlementFailure): owner.drain()
        self.assertEqual(message.nacks, [])
        owner, executor, message, clock, _lease = self.owner()
        executor.jobs[0][2].set_result(TRANSIENT); errors = []
        def other():
            try: owner.drain()
            except SettlementFailure: errors.append(True)
        thread = threading.Thread(target=other); thread.start(); thread.join(timeout=2)
        self.assertFalse(thread.is_alive()); self.assertEqual(errors, [True]); self.assertEqual(message.nacks, [])

    def test_native_pinned_message_nack_is_one_tag_multiple_false(self):
        from amqpstorm.basic import Basic
        from amqpstorm.message import Message as NativeMessage
        from pamqp import specification
        clock, frames = Clock(), []
        channel = SimpleNamespace(write_frame=frames.append); channel.basic = Basic(channel)
        message = NativeMessage(channel, body=BODY, method={"delivery_tag": 42, "redelivered": True},
                                properties={"headers": {"x-delivery-count": 1}})
        lease = capture(json.loads(BODY), "unix-ms-v1", **clock())
        owner, executor = OwnerSettlements(1, quarantine=True, retry=True, clock=clock), fixture.Executor()
        owner.submit(executor, Mock(), message, BODY, provider="fcm", freshness=lease)
        executor.jobs[0][2].set_result(TRANSIENT); owner.drain(); clock.advance(5000); owner.drain(); owner.drain()
        self.assertEqual(len(frames), 1); self.assertIs(type(frames[0]), specification.Basic.Nack)
        self.assertEqual(frames[0].delivery_tag, 42); self.assertIs(frames[0].multiple, False)
        self.assertIs(frames[0].requeue, True)

    def test_actual_owner_loop_waits_then_nacks_and_handles_broker_redelivery(self):
        runtime, message, executor, connection, factory, callbacks = fixture.OwnerLoopTests().runtime(quorum=True, body=BODY)
        runtime._settings.update(RETRY=MODE, FRESHNESS="unix-ms-v1")
        message.properties = {}; message.redelivered = False; message.nack = Mock()
        redelivery, clock, steps = Message(1), Clock(), [0]
        runtime.deliver = Mock(side_effect=[TRANSIENT, fixture.ACCEPTED])
        def events(**_kwargs):
            steps[0] += 1
            if steps[0] == 1: callbacks[0](message)
            elif steps[0] == 2:
                message.nack.assert_not_called(); clock.advance(2000)
            elif steps[0] == 3:
                message.nack.assert_called_once_with(requeue=True); callbacks[0](redelivery)
            else: runtime._stop.set()
        connection.channel().process_data_events = events
        with patch.object(bridge, "ThreadPoolExecutor", return_value=executor), \
                patch("amqp_management.verify_topology", return_value=True), \
                patch("delivery_settlement.clocks", clock), patch.object(freshness_runtime, "clocks", clock):
            runtime.run()
        self.assertEqual(runtime.deliver.call_count, 2); self.assertEqual(redelivery.acks, 1)
        self.assertEqual(factory.call_count, 1); self.assertEqual(message.acks, 0)
        self.assertEqual(message.rejections, []); self.assertEqual(len(executor.jobs), 2)

    def test_runtime_never_admits_retry_before_live_quorum_verification(self):
        runtime, message, executor, _connection, _factory, callbacks = fixture.OwnerLoopTests().runtime(quorum=True, body=BODY)
        runtime._settings.update(RETRY=MODE, FRESHNESS="unix-ms-v1")
        with patch.object(bridge, "ThreadPoolExecutor", return_value=executor), \
                patch("amqp_management.verify_topology", return_value=False), \
                patch.object(bridge, "OwnerSettlements") as settlements:
            with self.assertRaises(bridge.TopologyFailure): runtime.run()
        settlements.assert_not_called(); self.assertEqual(callbacks, []); self.assertEqual(executor.jobs, [])

    def test_runtime_bad_redelivery_metadata_stops_before_provider_and_reconnect(self):
        runtime, message, executor, _connection, factory, _callbacks = fixture.OwnerLoopTests().runtime(quorum=True, body=BODY)
        runtime._settings.update(RETRY=MODE, FRESHNESS="unix-ms-v1")
        message.properties = {}; message.redelivered = True
        with patch.object(bridge, "ThreadPoolExecutor", return_value=executor), \
                patch("amqp_management.verify_topology", return_value=True), \
                patch("delivery_settlement.clocks", Clock()), patch.object(freshness_runtime, "clocks", Clock()):
            with self.assertRaises(SettlementFailure): runtime.run()
        self.assertEqual(executor.jobs, []); runtime.deliver.assert_not_called()
        self.assertEqual(factory.call_count, 1); self.assertEqual(message.acks, 0); self.assertEqual(message.rejections, [])


if __name__ == "__main__":
    unittest.main()
