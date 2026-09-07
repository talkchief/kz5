#!/usr/bin/env python3
"""Offline settlement/owner-loop fixtures; no broker, provider or real executor."""

from concurrent.futures import Future
import json
from pathlib import Path
import sys
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


SOURCE = Path(__file__).resolve().parents[1] / "services/push-bridge"
sys.path.insert(0, str(SOURCE))
import bridge
from delivery_settlement import OwnerSettlements, SettlementFailure


ACCEPTED = (True, 200, "provider_response")
BODY = json.dumps({"Token-ID": "fixture-token", "Call-ID": "fixture-call"})


class Message:
    def __init__(self, ack_error=False):
        self.owner = threading.get_ident()
        self.acks = 0
        self.ack_error = ack_error

    @property
    def body(self):
        if threading.get_ident() != self.owner:
            raise AssertionError("worker touched AMQP message")
        return BODY

    def ack(self):
        if threading.get_ident() != self.owner:
            raise AssertionError("ACK outside owner thread")
        self.acks += 1
        if self.ack_error:
            raise RuntimeError("fixture-private-ack-error")


class Executor:
    def __init__(self, immediate=False):
        self.jobs = []
        self.immediate = immediate
        self.shutdown = Mock()

    def submit(self, worker, body):
        future = Future()
        self.jobs.append((worker, body, future))
        if self.immediate:
            try:
                future.set_result(worker(body))
            except BaseException as error:
                future.set_exception(error)
        return future


class Stop:
    def __init__(self):
        self.stopped = False
    def is_set(self):
        return self.stopped
    def set(self):
        self.stopped = True
    def wait(self, _seconds):
        return self.stopped


class SettlementTests(unittest.TestCase):
    def test_worker_receives_body_only_and_ack_waits_for_owner_drain(self):
        owner, executor, message = OwnerSettlements(2), Executor(), Message()
        worker = Mock()
        owner.submit(executor, worker, message, BODY)
        self.assertEqual(executor.jobs[0][:2], (worker, BODY))
        self.assertEqual(owner.pending_count, 1)
        owner.drain()
        self.assertEqual(message.acks, 0)
        future = executor.jobs[0][2]
        thread = threading.Thread(target=lambda: future.set_result(ACCEPTED))
        thread.start()
        thread.join(timeout=2)
        self.assertFalse(thread.is_alive())
        self.assertEqual(message.acks, 0)
        owner.drain()
        self.assertEqual(message.acks, 1)
        self.assertEqual(owner.pending_count, 0)
        owner.drain()
        self.assertEqual(message.acks, 1)

    def test_failed_malformed_and_ambiguous_provider_results_never_ack(self):
        results = [(False, 400, "provider_response"), (False, 503, "provider_response"),
                   (False, 0, "invalid_push_payload"), (False, 0, "apns_initialization_failed"),
                   None, True, [True, 200, "provider_response"], (1, 200, "provider_response"),
                   (True, "200", "provider_response"), (True, 201, "provider_response"),
                   (True, 200, "unknown_status")]
        for result in results:
            with self.subTest(result=result):
                owner, executor, message = OwnerSettlements(1), Executor(), Message()
                owner.submit(executor, Mock(), message, BODY)
                executor.jobs[0][2].set_result(result)
                with self.assertRaisesRegex(SettlementFailure, "^push_delivery_unsettled$"):
                    owner.drain()
                self.assertEqual(message.acks, 0)
                self.assertEqual(owner.pending_count, 1)
                owner.invalidate()

    def test_worker_exception_cancellation_and_systemexit_are_unsettled(self):
        for error in (RuntimeError("fixture-secret"), SystemExit("fixture-secret"), None):
            owner, executor, message = OwnerSettlements(1), Executor(), Message()
            owner.submit(executor, Mock(), message, BODY)
            if error is None:
                executor.jobs[0][2].cancel()
            else:
                executor.jobs[0][2].set_exception(error)
            with self.assertRaisesRegex(SettlementFailure, "^push_delivery_unsettled$"):
                owner.drain()
            self.assertEqual(message.acks, 0)

    def test_uncertain_ack_is_not_blindly_retried(self):
        owner, executor, message = OwnerSettlements(1), Executor(), Message(ack_error=True)
        owner.submit(executor, Mock(), message, BODY)
        executor.jobs[0][2].set_result(ACCEPTED)
        for _ in range(2):
            with self.assertRaises(SettlementFailure):
                owner.drain()
        self.assertEqual(message.acks, 1)
        self.assertEqual(owner.pending_count, 1)

    def test_other_accepted_deliveries_are_settled_before_failure_is_reported(self):
        owner, executor = OwnerSettlements(2), Executor()
        failed, accepted = Message(), Message()
        owner.submit(executor, Mock(), failed, BODY)
        owner.submit(executor, Mock(), accepted, BODY)
        executor.jobs[0][2].set_result((False, 503, "provider_response"))
        executor.jobs[1][2].set_result(ACCEPTED)
        with self.assertRaises(SettlementFailure):
            owner.drain()
        self.assertEqual(failed.acks, 0)
        self.assertEqual(accepted.acks, 1)
        self.assertEqual(owner.pending_count, 1)

    def test_admission_is_bounded_and_invalidated_generation_cannot_submit_or_ack(self):
        owner, executor, message = OwnerSettlements(1), Executor(), Message()
        owner.submit(executor, Mock(), message, BODY)
        with self.assertRaises(SettlementFailure):
            owner.submit(executor, Mock(), Message(), BODY)
        self.assertEqual(len(executor.jobs), 1)
        owner.invalidate()
        executor.jobs[0][2].set_result(ACCEPTED)
        with self.assertRaises(SettlementFailure):
            owner.drain()
        with self.assertRaises(SettlementFailure):
            owner.submit(executor, Mock(), Message(), BODY)
        self.assertEqual(message.acks, 0)
        self.assertEqual(len(executor.jobs), 1)

    def test_nonowner_cannot_drain_and_rejection_does_not_ack(self):
        owner, executor, message = OwnerSettlements(1), Executor(), Message()
        owner.submit(executor, Mock(), message, BODY)
        executor.jobs[0][2].set_result(ACCEPTED)
        failures = []
        def wrong_thread():
            try:
                owner.drain()
            except SettlementFailure:
                failures.append(True)
        thread = threading.Thread(target=wrong_thread)
        thread.start()
        thread.join(timeout=2)
        self.assertFalse(thread.is_alive())
        self.assertEqual(failures, [True])
        self.assertEqual(message.acks, 0)
        owner.drain()
        self.assertEqual(message.acks, 1)

    def test_invalid_capacity_body_and_executor_failure_fail_before_ack(self):
        for limit in (0, -1, 129, True, "2"):
            with self.assertRaises(ValueError):
                OwnerSettlements(limit)
        for body in (None, {}, "x" * 32769):
            owner, executor, message = OwnerSettlements(1), Executor(), Message()
            with self.assertRaises(SettlementFailure):
                owner.submit(executor, Mock(), message, body)
            self.assertEqual(len(executor.jobs), 0)
            self.assertEqual(message.acks, 0)
        owner, message = OwnerSettlements(1), Message()
        executor = SimpleNamespace(submit=Mock(side_effect=RuntimeError("fixture-private-error")))
        with self.assertRaisesRegex(SettlementFailure, "^push_delivery_unsettled$"):
            owner.submit(executor, Mock(), message, BODY)
        self.assertEqual(message.acks, 0)


class OwnerLoopTests(unittest.TestCase):
    def runtime(self, result=ACCEPTED, disconnect=False, pending=False, ack_error=False):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._settings = {"WORKERS": 1, "APNS_WORKERS": 1, "AMQP_HOST": "fixture",
                             "AMQP_USER": "fixture", "AMQP_PASS": "fixture-not-secret",
                             "AMQP_PORT": 5672, "AMQP_VHOST": "/fixture",
                             "EXCHANGE": "pushes", "QUEUE": "fixture", "BINDING_KEY": "fixture.*"}
        runtime._amqp_tls_options = {}
        runtime._stop = Stop()
        runtime.mark_progress = Mock()
        runtime.start_self_watchdog = Mock()
        runtime.deliver = Mock(return_value=result)
        runtime._conn = None
        message = Message(ack_error=ack_error)
        executor = Executor(immediate=not pending)
        channel = SimpleNamespace(is_open=True, exchange=SimpleNamespace(declare=Mock()),
                                  queue=SimpleNamespace(declare=Mock(), bind=Mock()))
        callbacks = []
        channel.basic = SimpleNamespace(qos=Mock(), consume=lambda callback, **_kwargs: callbacks.append(callback))
        events = [0]
        def dispatch(**_kwargs):
            events[0] += 1
            if events[0] == 1:
                callbacks[0](message)
                self.assertEqual(message.acks, 0, "ACK must not happen inside worker submission")
                if disconnect:
                    channel.is_open = False
            else:
                runtime._stop.set()
        channel.process_data_events = dispatch
        connection = SimpleNamespace(is_open=True, channel=lambda: channel, close=Mock())
        factory = Mock(return_value=connection)
        runtime.amqpstorm = SimpleNamespace(Connection=factory, AMQPChannelError=RuntimeError)
        return runtime, message, executor, connection, factory, callbacks

    def test_actual_owner_loop_acks_accepted_result_after_worker_completion(self):
        runtime, message, executor, connection, factory, _callbacks = self.runtime()
        with patch.object(bridge, "ThreadPoolExecutor", return_value=executor):
            runtime.run()
        self.assertEqual(message.acks, 1)
        runtime.deliver.assert_called_once_with(BODY)
        self.assertEqual(factory.call_count, 1)
        connection.close.assert_called_once_with()
        self.assertEqual(executor.shutdown.call_count, 2)

    def test_actual_owner_loop_preserves_failed_delivery_and_does_not_reconnect(self):
        runtime, message, executor, connection, factory, _callbacks = self.runtime(result=(False, 503, "provider_response"))
        with patch.object(bridge, "ThreadPoolExecutor", return_value=executor):
            with self.assertRaises(SettlementFailure):
                runtime.run()
        self.assertEqual(message.acks, 0)
        self.assertEqual(factory.call_count, 1)
        connection.close.assert_called_once_with()
        self.assertTrue(runtime._stop.is_set())

    def test_disconnect_with_inflight_work_and_late_callback_cannot_ack_or_resubmit(self):
        runtime, message, executor, connection, factory, callbacks = self.runtime(disconnect=True, pending=True)
        with patch.object(bridge, "ThreadPoolExecutor", return_value=executor):
            with self.assertRaises(SettlementFailure):
                runtime.run()
        self.assertEqual(factory.call_count, 1)
        self.assertEqual(len(executor.jobs), 1)
        executor.jobs[0][2].set_result(ACCEPTED)
        callbacks[0](Message())
        self.assertEqual(len(executor.jobs), 1)
        self.assertEqual(message.acks, 0)
        connection.close.assert_called_once_with()

    def test_ack_exception_is_fatal_uncertainty_not_retried_or_reconnected(self):
        runtime, message, executor, connection, factory, _callbacks = self.runtime(ack_error=True)
        with patch.object(bridge, "ThreadPoolExecutor", return_value=executor):
            with self.assertRaises(SettlementFailure):
                runtime.run()
        self.assertEqual(message.acks, 1)
        self.assertEqual(factory.call_count, 1)
        connection.close.assert_called_once_with()

    def test_late_closed_generation_callback_cannot_enter_successor(self):
        runtime, message, executor, second_connection, factory, _callbacks = self.runtime()
        old_callbacks = []
        old_message = Message()
        first_channel = SimpleNamespace(is_open=True, exchange=SimpleNamespace(declare=Mock()),
                                        queue=SimpleNamespace(declare=Mock(), bind=Mock()),
                                        basic=SimpleNamespace(qos=Mock(), consume=lambda callback, **_kwargs: old_callbacks.append(callback)))
        def close_idle_generation(**_kwargs):
            first_channel.is_open = False
        first_channel.process_data_events = close_idle_generation
        first_connection = SimpleNamespace(is_open=True, channel=lambda: first_channel, close=Mock())
        factory.side_effect = [first_connection, second_connection]
        second_channel = second_connection.channel()
        original_dispatch = second_channel.process_data_events
        invoked = [False]
        def dispatch_with_late_callback(**kwargs):
            if not invoked[0]:
                old_callbacks[0](old_message)
                invoked[0] = True
            original_dispatch(**kwargs)
        second_channel.process_data_events = dispatch_with_late_callback
        with patch.object(bridge, "ThreadPoolExecutor", return_value=executor):
            runtime.run()
        self.assertEqual(factory.call_count, 2)
        self.assertEqual(len(executor.jobs), 1)
        self.assertEqual(old_message.acks, 0)
        self.assertEqual(message.acks, 1)
        first_connection.close.assert_called_once_with()
        second_connection.close.assert_called_once_with()

    def test_main_emits_fixed_manual_recovery_status_without_restart_or_provider_work(self):
        runtime = SimpleNamespace(handle_term=Mock(), run=Mock(side_effect=SettlementFailure()), close=Mock())
        with patch.object(bridge, "BridgeRuntime", return_value=runtime), \
                patch.object(bridge.signal, "signal"), self.assertLogs("push_bridge", level="ERROR") as logs:
            self.assertEqual(bridge.main([], {}), 78)
        self.assertEqual(logs.output, ["ERROR:push_bridge:push_delivery_unsettled_manual_recovery_required"])
        runtime.close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
