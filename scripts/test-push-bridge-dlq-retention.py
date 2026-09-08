#!/usr/bin/env python3
"""Offline driver regressions; simulated retention is NOT live broker proof."""
import importlib.util
from pathlib import Path
import socket
import unittest
from unittest.mock import Mock, patch

DIRECTORY = Path(__file__).resolve().parent
def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, DIRECTORY / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
proof = load("dlq_retention_acceptance", "accept-push-bridge-dlq-retention.py")
fixture = load("dlq_retention_baseline_fixture", "test-accept-push-bridge-retry.py")


class Message(fixture.Message):
    def reject(self, requeue=True):
        assert requeue is False
        broker = self.channel.broker
        broker.rejects += 1
        self.channel.pending.remove(self)
        if broker.drop: return
        broker.release_due = broker.clock.monotonic() + broker.retry_delay
        (broker.dead if broker.bound else broker.retained).append(self.record)


class Channel(fixture.Channel):
    def publish(self, *args, **kwargs):
        self.broker.publishes += 1
        return super().publish(*args, **kwargs)
    def get(self, queue, no_ack):
        assert no_ack is False
        self.broker.release()
        records = self.broker.dead if queue.endswith(".dlq") else self.broker.work
        return Message(self, records.pop(0)) if records else None
    def binding_args(self, queue, exchange, routing_key):
        assert queue == "fixture.mobile.quorum-v1.dlq"
        assert exchange == "fixture.mobile.quorum-v1.dlx"
        assert routing_key == "dead"
    def unbind(self, **kwargs):
        self.binding_args(**kwargs)
        self.broker.mutations.append("unbind")
        if self.broker.unbind_error: raise RuntimeError("fixture-private-broker-error")
        self.broker.bound = False
    def bind(self, **kwargs):
        self.binding_args(**kwargs)
        self.broker.mutations.append("bind")
        if self.broker.bind_error: raise RuntimeError("fixture-private-broker-error")
        self.broker.bound = True
        self.broker.release()


class Broker(fixture.Broker):
    def __init__(self):
        super().__init__()
        self.bound = True
        self.retained, self.mutations = [], []
        self.drop = self.wrong_body = self.unbind_error = self.bind_error = False
        self.rejects = self.publishes = 0
        self.rpc_timeouts = []
        self.retry_delay = self.release_due = 0
        self.clock = None
    def release(self):
        if not self.bound or self.clock.monotonic() < self.release_due: return
        if self.wrong_body:
            for record in self.retained: record["body"] = "fixture-private-wrong-body"
        self.dead.extend(self.retained)
        self.retained.clear()
    def channel(self, *, rpc_timeout):
        self.rpc_timeouts.append(rpc_timeout)
        channel = Channel(self)
        self.channels.append(channel)
        return channel


def setup():
    old, _broker, clock, receipt, _verify, _configure = fixture.fixture()
    broker = Broker()
    broker.clock = clock
    def verifier(_settings, _plan):
        if not broker.bound:
            raise proof.ManagementVerificationFailure("dead_bindings", 200)
        return True
    verify = Mock(side_effect=verifier)
    checkpoints = []
    driver = proof.DlqRetentionProof(broker, old.settings, RuntimeError, verify, receipt,
        monotonic=clock.monotonic, wall_ms=clock.wall_ms, sleep=clock.sleep,
        executor_factory=fixture.Executor, checkpoint=lambda: checkpoints.append(receipt["phase"]))
    def configure(connection, actual, _error, verification):
        assert isinstance(connection, proof.BoundedConnection) and connection.connection is broker and actual == old.settings
        if verification(actual, proof.base.plan(actual)) is not True:
            raise RuntimeError("fixture verification failed")
        return connection.channel()
    return driver, broker, clock, receipt, verify, configure, checkpoints


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.network = patch.object(socket, "socket", side_effect=AssertionError("offline socket forbidden"))
        self.network.start(); self.addCleanup(self.network.stop)
        self.process = patch.object(proof.base.subprocess, "run", side_effect=AssertionError("offline brokerctl forbidden"))
        self.process.start(); self.addCleanup(self.process.stop)

    def test_single_permanent_rejection_retained_then_recovered_without_republish(self):
        driver, broker, clock, receipt, verify, configure, checkpoints = setup()
        with patch.object(proof.base, "configure", configure): driver.run()
        self.assertEqual((broker.publishes, broker.rejects), (1, 1))
        self.assertEqual(broker.mutations, ["unbind", "bind"])
        self.assertEqual(broker.work + broker.dead + broker.retained, [])
        self.assertTrue(all(not channel.pending for channel in broker.channels))
        self.assertEqual(driver.dispatches, {"permanent": 1})
        self.assertEqual(receipt["dispatches_during_unbound"], 0)
        self.assertEqual(receipt["retries_during_unbound"], 0)
        self.assertTrue(receipt["binding_restored"])
        self.assertTrue(receipt["unavailable_dlq_tested"])
        self.assertFalse(receipt["full_dlq_tested"])
        self.assertFalse(receipt["original_republished"])
        self.assertEqual(receipt["publisher_confirms"], 1)
        self.assertEqual(receipt["provider_calls"], 0)
        self.assertGreaterEqual(receipt["confirmed_unbound_before_restore_ms"], 5000)
        self.assertGreaterEqual(receipt["unbind_request_to_rebind_confirmed_ms"], 5000)
        self.assertEqual(verify.call_count, 3)
        self.assertIn("restore_owned_dead_binding", checkpoints)
        self.assertLess(clock.value, 6)
        self.assertEqual(broker.rpc_timeouts, [10])
        self.assertEqual(receipt["bounds_seconds"], {"case": 300, "recovery": 240, "channel_rpc": 10})
        self.assertIn("await_retained_message", checkpoints)

    def test_broker_180_second_no_route_retry_recovers_without_republish(self):
        driver, broker, clock, receipt, verify, configure, checkpoints = setup()
        broker.retry_delay = 180
        with patch.object(proof.base, "configure", configure): driver.run()
        self.assertGreaterEqual(clock.value, 180)
        self.assertLess(clock.value, 181)
        self.assertGreaterEqual(receipt["recovered_monotonic_ms"], 180000)
        self.assertTrue(receipt["unavailable_dlq_tested"])
        self.assertEqual((broker.publishes, broker.rejects), (1, 1))
        self.assertEqual(driver.dispatches, {"permanent": 1})
        self.assertEqual(broker.work + broker.dead + broker.retained, [])

    def test_every_opened_driver_channel_uses_supported_bounded_rpc_argument(self):
        driver, broker, clock, receipt, verify, configure, checkpoints = setup()
        with patch.object(proof.base, "configure", configure):
            driver.open_channel()
            driver.channel.close()
            driver.open_channel()
        self.assertEqual(broker.rpc_timeouts, [10, 10])

    def test_recovery_window_is_capped_by_remaining_case_budget(self):
        driver, broker, clock, receipt, verify, configure, checkpoints = setup()
        broker.retry_delay = 1000
        # Model200s spent before entering the case. The original absolute case
        # deadline remains300; recovery must not reset it to now+240.
        clock.value = 200
        with patch.object(proof.base, "configure", configure), self.assertRaises(proof.base.ProofFailure) as error:
            driver.run()
        self.assertEqual(error.exception.code, "recovery_deadline")
        self.assertGreaterEqual(clock.value, 300)
        self.assertLess(clock.value, 301)
        self.assertEqual(broker.publishes, 1)

    def test_lost_internal_message_cannot_pass_on_empty_ready_counts(self):
        driver, broker, clock, receipt, verify, configure, _ = setup()
        broker.drop = True
        with patch.object(proof.base, "configure", configure), self.assertRaises(proof.base.ProofFailure) as error:
            driver.run()
        self.assertEqual(error.exception.code, "recovery_deadline")
        self.assertFalse(receipt["unavailable_dlq_tested"])
        self.assertEqual((broker.publishes, broker.rejects), (1, 1))
        self.assertGreaterEqual(clock.value, 240)
        self.assertLess(clock.value, 246)
        self.assertTrue(broker.bound)

    def test_changed_recovered_body_refused_without_ack_or_republish(self):
        driver, broker, clock, receipt, verify, configure, _ = setup()
        broker.wrong_body = True
        with patch.object(proof.base, "configure", configure), self.assertRaises(proof.base.ProofFailure) as error:
            driver.run()
        self.assertEqual(error.exception.code, "body_changed")
        self.assertFalse(receipt["unavailable_dlq_tested"])
        self.assertEqual(broker.publishes, 1)
        self.assertEqual(len(broker.channels[0].pending), 1)

    def test_unbind_uncertainty_attempts_only_exact_binding_restore_and_no_reject(self):
        driver, broker, clock, receipt, verify, configure, _ = setup()
        broker.unbind_error = True
        with patch.object(proof.base, "configure", configure), self.assertRaises(RuntimeError): driver.run()
        self.assertEqual(broker.mutations, ["unbind", "bind"])
        self.assertEqual(broker.rejects, 0)
        self.assertFalse(receipt["unavailable_dlq_tested"])

    def test_restore_failure_does_not_claim_retention_and_preserves_pending_internal_message(self):
        driver, broker, clock, receipt, verify, configure, _ = setup()
        broker.bind_error = True
        with patch.object(proof.base, "configure", configure), self.assertRaises(RuntimeError): driver.run()
        self.assertTrue(receipt["binding_restore_uncertain"])
        self.assertFalse(receipt["binding_restored"])
        self.assertEqual(len(broker.retained), 1)
        self.assertFalse(receipt["unavailable_dlq_tested"])

    def test_wrong_verifier_failure_is_not_evidence_of_unbound_route(self):
        for phase, status in (("dead_bindings", 503), ("work_queue", 200), ("unknown", None)):
            driver, broker, clock, receipt, verify, configure, _ = setup()
            verify.side_effect = [True, proof.ManagementVerificationFailure(phase, status)]
            with patch.object(proof.base, "configure", configure), self.assertRaises(proof.base.ProofFailure): driver.run()
            self.assertEqual(broker.rejects, 0)
            self.assertEqual(broker.mutations, ["unbind", "bind"])
            self.assertFalse(receipt["unavailable_dlq_tested"])

    def test_unconfirmed_publish_cannot_remove_binding_or_dispatch(self):
        driver, broker, clock, receipt, verify, configure, _ = setup()
        broker.confirm = False
        with patch.object(proof.base, "configure", configure), self.assertRaises(proof.base.ProofFailure): driver.run()
        self.assertEqual(broker.mutations, [])
        self.assertEqual(driver.dispatches, {})

    def test_driver_refuses_nonisolated_scope_before_any_channel(self):
        old, broker, clock, receipt, verify, configure, _ = setup()
        for changes in ({"AMQP_HOST": "10.1.0.28"}, {"AMQP_PORT": 5673}, {"AMQP_USER": "guest"},
                        {"AMQP_VHOST": "/"}, {"AMQP_MANAGEMENT_URL": "http://127.0.0.1:15673"}):
            settings = {**old.settings, **changes}
            with self.assertRaises(proof.base.ProofFailure):
                proof.DlqRetentionProof(broker, settings, RuntimeError, verify, receipt)
            self.assertEqual(broker.channels, [])

    def test_cli_explicit_local_flag_and_root_are_required_before_setup(self):
        for argv, uid in (([], 0), (["--run-isolated-local-dlq-proof"], 1000), (["--broker", "10.1.0.28"], 0)):
            with patch.object(proof.os, "geteuid", return_value=uid), \
                    patch.object(proof.Path, "mkdir", side_effect=AssertionError("no setup allowed")), \
                    self.assertRaises(proof.base.ProofFailure): proof.main(argv)


if __name__ == "__main__":
    unittest.main()
