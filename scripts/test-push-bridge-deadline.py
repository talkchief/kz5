#!/usr/bin/env python3
"""Offline deadline/fail-stop fixtures. Child owns no broker/provider resources."""

from concurrent.futures import Future
from functools import partial
from pathlib import Path
import subprocess
import sys
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

SOURCE = Path(__file__).resolve().parents[1] / "services/push-bridge"
sys.path.insert(0, str(SOURCE))
import bridge
from delivery_settlement import OwnerSettlements, SettlementFailure
import validate_config

ACCEPTED = (True, 200, "provider_response")
BODY = '{"Token-ID":"fixture-token","Call-ID":"fixture-call"}'


class Clock:
    def __init__(self):
        self.now = 1000
    def __call__(self):
        return self.now


class Executor:
    def __init__(self):
        self.jobs = []
        self.shutdown = Mock()
    def submit(self, worker, body):
        future = Future()
        self.jobs.append((worker, body, future))
        return future


def message():
    return SimpleNamespace(body=BODY, ack=Mock(), nack=Mock(), reject=Mock())


def environment():
    values = {
        "SA_FILE": "/fixture/nonexistent.json", "AMQP_HOST": "broker.example.invalid",
        "AMQP_USER": "fixture", "AMQP_PASS": "fixture-secret", "AMQP_VHOST": "/fixture",
        "EXCHANGE": "pushes", "QUEUE": "fixture", "BINDING_KEY": "notification.push.*",
        "FCM_SCOPE": validate_config.FCM_SCOPE, "FCM_URL_TEMPLATE": validate_config.FCM_URL,
    }
    return {validate_config.PREFIX + key: value for key, value in values.items()}


def owner_runtime(clock, *, block_worker=False, block_cleanup=False):
    """Actual run loop, synthetic channel/provider only; never constructs clients."""
    runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
    runtime._settings = {"WORKERS": 1, "APNS_WORKERS": 1, "QUEUE": "fixture", "DELIVERY_TIMEOUT": 10}
    runtime._stop = threading.Event()
    runtime.mark_progress = Mock()
    runtime.start_self_watchdog = Mock()
    runtime.close = Mock()
    runtime.amqpstorm = SimpleNamespace(AMQPChannelError=RuntimeError)
    entered = threading.Event()
    def worker(_body):
        entered.set()
        threading.Event().wait()
    runtime.deliver = worker if block_worker else Mock()
    callbacks = []
    item = message()
    channel = SimpleNamespace(is_open=True)
    channel.basic = SimpleNamespace(qos=Mock(), consume=lambda callback, **_kwargs: callbacks.append(callback))
    def events(**_kwargs):
        if callbacks:
            callbacks.pop(0)(item)
            if block_worker and not entered.wait(1):
                raise RuntimeError("fixture_worker_not_started")
            clock.now += 10000
    channel.process_data_events = events
    def cleanup():
        if block_cleanup:
            threading.Event().wait()
    connection = SimpleNamespace(is_open=True, close=Mock(side_effect=cleanup))
    runtime._connect_amqp = Mock(return_value=connection)
    return runtime, channel, connection, item


class DeadlineTests(unittest.TestCase):
    def setup_owner(self, **options):
        clock, executor, item = Clock(), Executor(), message()
        owner = OwnerSettlements(2, deadline_clock=clock, **options)
        owner.submit(executor, Mock(), item, BODY, provider="fcm")
        return owner, clock, executor, item

    def unacked(self, item):
        item.ack.assert_not_called(); item.nack.assert_not_called(); item.reject.assert_not_called()

    def test_default_and_exact_boundary_for_queued_and_running_work(self):
        for running in (False, True):
            owner, clock, executor, item = self.setup_owner()
            future = executor.jobs[0][2]
            if running:
                self.assertTrue(future.set_running_or_notify_cancel())
            clock.now = 60999
            owner.drain()
            self.assertEqual(owner.pending_count, 1)
            clock.now = 61000
            with self.assertRaisesRegex(SettlementFailure, "^push_delivery_unsettled$"):
                owner.drain()
            self.unacked(item)
            self.assertEqual(len(executor.jobs), 1)

    def test_completed_acceptance_before_at_and_after_deadline_is_not_uncertain(self):
        for now in (60999, 61000, 90000):
            owner, clock, executor, item = self.setup_owner()
            clock.now = now
            executor.jobs[0][2].set_result(ACCEPTED)
            owner.drain()
            item.ack.assert_called_once_with()
            self.assertEqual(owner.pending_count, 0)
            self.assertEqual(owner._worker_deadlines, {})

    def test_completed_permanent_quarantine_after_deadline_unchanged(self):
        owner, clock, executor, item = self.setup_owner(quarantine=True)
        clock.now += 90000
        executor.jobs[0][2].set_result((False, 404, "provider_response"))
        owner.drain()
        item.reject.assert_called_once_with(requeue=False)
        item.ack.assert_not_called()

    def test_each_submission_uses_its_own_immutable_monotonic_admission(self):
        owner, clock, executor, first = self.setup_owner(delivery_timeout=10)
        clock.now += 5000
        second = message()
        owner.submit(executor, Mock(), second, BODY)
        self.assertEqual(list(owner._worker_deadlines.values()), [11000, 16000])
        executor.jobs[0][2].set_result(ACCEPTED)
        clock.now = 15999
        owner.drain()
        first.ack.assert_called_once_with()
        self.unacked(second)
        clock.now = 16000
        with self.assertRaises(SettlementFailure): owner.drain()
        self.unacked(second)

    def test_wall_clock_is_not_read_for_worker_admission_or_deadline(self):
        with patch("time.time", side_effect=AssertionError("wall_clock_forbidden")), \
                patch("time.time_ns", side_effect=AssertionError("wall_clock_forbidden")):
            owner, clock, executor, item = self.setup_owner()
            owner.drain()
            clock.now += 60000
            with self.assertRaises(SettlementFailure): owner.drain()
        self.unacked(item)

    def test_unknown_completion_still_fail_stops_without_retry(self):
        owner, clock, executor, item = self.setup_owner()
        executor.jobs[0][2].set_result((False, 503, "provider_response"))
        with self.assertRaises(SettlementFailure): owner.drain()
        self.unacked(item)

    def test_timeout_is_sticky_and_generation_invalidation_fences_late_completion(self):
        owner, clock, executor, item = self.setup_owner()
        clock.now += 60000
        with self.assertRaises(SettlementFailure): owner.drain()
        executor.jobs[0][2].set_result(ACCEPTED)
        with self.assertRaises(SettlementFailure): owner.drain()
        with self.assertRaises(SettlementFailure): owner.submit(executor, Mock(), message(), BODY)
        owner.invalidate()
        self.assertEqual(owner._worker_deadlines, {})
        with self.assertRaises(SettlementFailure): owner.drain()
        self.unacked(item)

    def test_companion_acceptance_settles_before_timeout_failure(self):
        owner, clock, executor, item = self.setup_owner()
        companion = message()
        owner.submit(executor, Mock(), companion, BODY)
        executor.jobs[1][2].set_result(ACCEPTED)
        clock.now += 60000
        with self.assertRaises(SettlementFailure): owner.drain()
        companion.ack.assert_called_once_with()
        self.unacked(item)
        self.assertEqual(owner.pending_count, 1)

    def test_non_owner_cannot_check_deadline_or_settle(self):
        owner, clock, executor, item = self.setup_owner()
        errors = []
        def other_owner():
            try: owner.drain()
            except SettlementFailure: errors.append("fixed")
        thread = threading.Thread(target=other_owner)
        thread.start(); thread.join(1)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, ["fixed"])
        self.unacked(item)

    def test_invalid_rollback_and_exception_clocks_fail_without_raw_text(self):
        for value in (None, True, 1.5, -1, "fixture-secret", 999):
            owner, clock, executor, item = self.setup_owner()
            clock.now = value
            with self.assertRaisesRegex(SettlementFailure, "^push_delivery_unsettled$"): owner.drain()
            self.unacked(item)
        owner = OwnerSettlements(1, deadline_clock=Mock(side_effect=RuntimeError("fixture-secret")))
        executor = Executor()
        with self.assertRaisesRegex(SettlementFailure, "^push_delivery_unsettled$"):
            owner.submit(executor, Mock(), message(), BODY)
        self.assertEqual(executor.jobs, [])

    def test_timeout_and_clock_validation(self):
        for value in (True, None, 9, 301, "60", 60.0):
            with self.assertRaises(ValueError): OwnerSettlements(1, delivery_timeout=value)
        for value in (10, 60, 300):
            self.assertEqual(OwnerSettlements(1, delivery_timeout=value)._delivery_timeout_ms, value * 1000)
        with self.assertRaises(ValueError): OwnerSettlements(1, deadline_clock=1)
        self.assertEqual(validate_config.NUMBERS["DELIVERY_TIMEOUT"], ("60", 10, 300))
        self.assertEqual(validate_config.validate(environment()), ())
        for value in ("10", "60", "300"):
            self.assertEqual(validate_config.validate({**environment(), "PUSH_BRIDGE_DELIVERY_TIMEOUT": value}), ())
        for value in ("9", "301", "-1", "1.5", "true", "fixture-secret", True):
            errors = validate_config.validate({**environment(), "PUSH_BRIDGE_DELIVERY_TIMEOUT": value})
            self.assertTrue(errors)
            self.assertNotIn("fixture-secret", repr(errors))


class FailStopTests(unittest.TestCase):
    def test_once_only_daemon_fixed_exit_and_signal_cannot_override(self):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._stop = threading.Event()
        timer = Mock()
        with patch.object(bridge.threading, "Timer", return_value=timer) as factory, patch.object(bridge.os, "_exit") as leave:
            runtime._fail_unsettled(True)
            runtime._fail_unsettled(True)
            runtime.handle_term()
            factory.assert_called_once()
            delay, callback = factory.call_args.args
            self.assertEqual(delay, 3)
            self.assertIs(timer.daemon, True)
            timer.start.assert_called_once_with()
            self.assertTrue(runtime._stop.is_set())
            leave.assert_not_called()
            callback(); leave.assert_called_once_with(78)

    def test_timer_start_failure_exits_fixed_immediately(self):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._stop = threading.Event()
        with patch.object(bridge.threading, "Timer", side_effect=RuntimeError("fixture-secret")), patch.object(bridge.os, "_exit") as leave:
            runtime._fail_unsettled(True)
            leave.assert_called_once_with(78)

    def test_owner_arms_before_connection_cleanup_and_cancels_queued_work(self):
        clock, executor = Clock(), Executor()
        runtime, channel, connection, item = owner_runtime(clock)
        timer = Mock()
        connection.close.side_effect = lambda: timer.start.assert_called_once_with()
        with patch.object(bridge, "ThreadPoolExecutor", return_value=executor), \
                patch.object(bridge, "configure_topology", return_value=channel), \
                patch.object(bridge, "OwnerSettlements", partial(OwnerSettlements, deadline_clock=clock)), \
                patch.object(bridge.threading, "Timer", return_value=timer), \
                patch("service_notify.notify_consumer_ready"), patch("service_notify.notify_status"):
            with self.assertRaises(SettlementFailure): runtime.run(fail_stop_exit=True)
        connection.close.assert_called_once_with()
        self.assertEqual(executor.shutdown.call_count, 2)
        executor.shutdown.assert_called_with(wait=False, cancel_futures=True)
        item.ack.assert_not_called(); item.nack.assert_not_called(); item.reject.assert_not_called()
        runtime._connect_amqp.assert_called_once_with()

    def test_main_enables_process_deadline_and_preserves_manual_exit_status(self):
        runtime = SimpleNamespace(handle_term=Mock(), run=Mock(side_effect=SettlementFailure()), close=Mock())
        with patch.object(bridge, "BridgeRuntime", return_value=runtime), patch.object(bridge.signal, "signal"), self.assertLogs("push_bridge", level="ERROR") as logs:
            self.assertEqual(bridge.main([], {}), 78)
        runtime.run.assert_called_once_with(fail_stop_exit=True)
        self.assertEqual(logs.output, ["ERROR:push_bridge:push_delivery_unsettled_manual_recovery_required"])
        unit = (SOURCE / "kazoo-push-bridge.service").read_text()
        self.assertIn("\nRestartPreventExitStatus=2 78\n", unit)

    def test_closing_fence_prevents_new_delivery_and_post_after_token_wait(self):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._unsettled_stop = True
        self.assertEqual(runtime.deliver("fixture-secret"), (False, 0, "bridge_closing"))
        runtime._settings = {}
        runtime._check_freshness = Mock(return_value=None)
        runtime.get_access_token = Mock(return_value="fixture-token")
        http = Mock()
        self.assertEqual(runtime._send_fcm_with_session(http, "fixture-token", {}), (False, 0, "bridge_closing"))
        http.post.assert_not_called()
        sender = Mock()
        runtime.get_apns_sender = Mock(return_value=sender)
        self.assertEqual(runtime.deliver_apns(SimpleNamespace(sandbox=False)), (False, 0, "bridge_closing"))
        sender.send.assert_not_called()

    def test_embedded_owner_failure_does_not_arm_a_process_exit(self):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._stop = threading.Event()
        with patch.object(bridge.threading, "Timer") as factory:
            runtime._fail_unsettled(False)
            factory.assert_not_called()
        self.assertTrue(runtime._stop.is_set())
        with self.assertRaises(ValueError): runtime.run(fail_stop_exit=1)

    def test_actual_private_child_exits78_despite_blocked_worker_and_cleanup(self):
        started = time.monotonic()
        result = subprocess.run([sys.executable, "-B", str(Path(__file__).resolve()), "--hanging-cleanup-child"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8, check=False)
        self.assertEqual(result.returncode, 78, result.stderr.decode("utf-8", errors="replace"))
        self.assertLess(time.monotonic() - started, 8)
        self.assertNotIn(b"fixture-secret", result.stdout + result.stderr)


class BrokerWatchdogTests(unittest.TestCase):
    def watchdog(self, *, elapsed, stopped=False):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._settings = {"STALL_TIMEOUT": 60}
        runtime._last_progress = 100
        runtime._stop = Mock()
        runtime._stop.wait.side_effect = [True] if stopped else [False, True]
        with patch.object(bridge.threading, "Thread") as thread, \
                patch.object(bridge.time, "monotonic", return_value=100 + elapsed), \
                patch.object(bridge.os, "_exit", side_effect=SystemExit) as leave:
            runtime.start_self_watchdog()
            self.assertTrue(thread.call_args.kwargs["daemon"])
            target = thread.call_args.kwargs["target"]
            try:
                target()
            except SystemExit:
                pass
            return leave.call_args

    def test_stalled_loop_cannot_request_automatic_replay(self):
        with self.assertLogs("push_bridge", level="ERROR") as logs:
            self.assertEqual(self.watchdog(elapsed=61).args, (78,))
        self.assertIn("manual_recovery_required", logs.output[0])
        unit = (SOURCE / "kazoo-push-bridge.service").read_text()
        self.assertIn("\nRestart=on-failure\n", unit)
        self.assertIn("\nRestartPreventExitStatus=2 78\n", unit)

    def test_healthy_boundary_and_stopped_runtime_do_not_exit(self):
        for elapsed, stopped in ((0, False), (59, False), (60, False), (1000, True)):
            self.assertIsNone(self.watchdog(elapsed=elapsed, stopped=stopped))

    def test_native_watchdog_child_uses_manual_recovery_exit(self):
        result = subprocess.run([sys.executable, "-B", str(Path(__file__).resolve()), "--stalled-loop-child"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=9, check=False)
        self.assertEqual(result.returncode, 78, result.stderr.decode("utf-8", errors="replace"))
        self.assertIn(b"manual_recovery_required", result.stderr)


def stalled_loop_child():
    # Real production watchdog in an isolated process; no provider constructors,
    # socket, AMQP connection, credentials, or fabricated settlement outcome.
    runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
    runtime._settings = {"STALL_TIMEOUT": 60}
    runtime._stop = threading.Event()
    runtime._last_progress = time.monotonic() - 61
    runtime.start_self_watchdog()
    threading.Event().wait()


def hanging_cleanup_child():
    clock = Clock()
    runtime, channel, connection, item = owner_runtime(clock, block_worker=True, block_cleanup=True)
    with patch.object(bridge, "BridgeRuntime", return_value=runtime), \
            patch.object(bridge, "configure_topology", return_value=channel), \
            patch.object(bridge, "OwnerSettlements", partial(OwnerSettlements, deadline_clock=clock)), \
            patch("service_notify.notify_consumer_ready"), patch("service_notify.notify_status"):
        # Real executor thread blocks forever, as does broker cleanup; only the
        # actual daemon fail-stop timer can exit. Parent kills this exact child
        # on timeout. No subprocess descendants, sockets, keys, or provider I/O.
        return bridge.main([], {})


if __name__ == "__main__":
    if sys.argv[1:] == ["--stalled-loop-child"]:
        sys.exit(stalled_loop_child())
    if sys.argv[1:] == ["--hanging-cleanup-child"]:
        sys.exit(hanging_cleanup_child())
    unittest.main()
