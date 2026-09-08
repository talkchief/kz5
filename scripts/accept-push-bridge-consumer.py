#!/usr/bin/env python3
"""Opt-in registered-consumer proof using only local UUID-isolated resources.

Reuses the protected setup/receipt/cleanup of accept-push-bridge-retry.py.
Exercises BridgeRuntime.run, real basic.consume and real owner settlements.
Only construction and provider delivery are substituted: no provider clients,
credentials, devices or production bridge configuration are loaded.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import threading
import time

HERE = Path(__file__).resolve()
spec = importlib.util.spec_from_file_location(
    "isolated_retry_acceptance", HERE.with_name("accept-push-bridge-retry.py"))
proof = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proof)
from bridge import BridgeRuntime
from delivery_retry import delivery_count

proof.FAILURES = proof.FAILURES | frozenset((
    "consumer_used_basic_get", "consumer_prefetch_changed", "consumer_registration_changed",
    "consumer_owner_invalid", "consumer_stopped_early", "consumer_case_deadline",
    "consumer_shutdown_deadline", "consumer_runtime_failed", "consumer_source_changed"))


class ConsumerProof(proof.RetryProof):
    """Broker owner loop is production code; wrappers record wire operations."""

    def run(self):
        import amqpstorm
        driver = self
        bodies = {name: self.body(name) for name in ("retry-success", "companion", "exhaustion")}
        labels = {body: name for name, body in bodies.items()}
        registered, terminal = threading.Event(), threading.Event()
        events, errors, counters, registered_threads = [], [], {}, []
        source = HERE.parents[1] / "services/push-bridge"
        inputs = [HERE, HERE.with_name("accept-push-bridge-retry.py"),
                  *[source / name for name in ("bridge.py", "push_payload.py", "service_notify.py")]]
        pins = {str(file): hashlib.sha256(file.read_bytes()).hexdigest() for file in inputs}
        self.receipt["consumer_source_sha256"] = pins
        self.receipt["registered_consumer_tested"] = False
        self.receipt["work_queue_basic_get_calls"] = 0
        self.receipt["consumer_counters"] = counters

        class Message(proof.TrackedMessage):
            def __init__(self, message, label, count):
                super().__init__(message, time.monotonic)
                self.label, self.count = label, count

            @property
            def body(self):
                proof.require(threading.get_ident() == self.owner, "message_outside_owner")
                return self.message.body

            def _settle(self, action, **kwargs):
                super()._settle(action, **kwargs)
                with driver.lock:
                    events.append((self.label, self.count, action, time.monotonic(), kwargs))

        class Basic:
            def __init__(self, basic): self.raw = basic

            def __getattr__(self, name): return getattr(self.raw, name)

            def get(self, *args, **kwargs):
                # The actual consumer must never fall back to Basic.Get.
                driver.receipt["work_queue_basic_get_calls"] += 1
                raise proof.ProofFailure("consumer_used_basic_get")

            def qos(self, **kwargs):
                proof.require(kwargs == {"prefetch_count": 2}, "consumer_prefetch_changed")
                return self.raw.qos(**kwargs)

            def consume(self, callback, **kwargs):
                proof.require(kwargs == {"queue": driver.settings["QUEUE"], "no_ack": False},
                              "consumer_registration_changed")
                registered_threads.append(threading.get_ident())

                def measured(message):
                    body = message.body
                    proof.require(body in labels, "body_changed")
                    label = labels[body]
                    count = delivery_count(message.properties, message.redelivered)
                    with driver.lock:
                        sequence = counters.setdefault(label, [])
                        proof.require(count == len(sequence), "broker_counter_unexpected")
                        sequence.append(count)
                        proof.require(len(sequence) <= (3 if label == "exhaustion" else
                                                       2 if label == "retry-success" else 1),
                                      "fourth_dispatch")
                    callback(Message(message, label, count))

                result = self.raw.consume(measured, **kwargs)
                registered.set()  # Actual broker ConsumeOk has returned.
                return result

        class Channel:
            def __init__(self, channel):
                self.raw, self.basic = channel, Basic(channel.basic)
            def __getattr__(self, name): return getattr(self.raw, name)

        class Connection:
            def __init__(self, connection): self.raw = connection
            def __getattr__(self, name): return getattr(self.raw, name)
            def channel(self, *args, **kwargs): return Channel(self.raw.channel(*args, **kwargs))

        class SyntheticRuntime(BridgeRuntime):
            def _connect_amqp(self):
                return Connection(super()._connect_amqp())

            def deliver(self, raw_body, freshness=None):
                proof.require(threading.get_ident() != driver.owner, "worker_not_separate_thread")
                proof.require(raw_body in labels and freshness is not None, "worker_body_changed")
                label = labels[raw_body]
                with driver.lock:
                    count = driver.dispatches.get(label, 0) + 1
                    driver.dispatches[label] = count
                if label == "exhaustion" or label == "retry-success" and count == 1:
                    return False, 503, "provider_response"
                return True, 200, "provider_response"

        # Deliberately bypass credential/HTTP construction. The inherited run,
        # AMQP connection, topology verification, pools, admission, freshness,
        # retry policy, owner settlements and watchdog remain unmodified.
        runtime = SyntheticRuntime.__new__(SyntheticRuntime)
        runtime.amqpstorm = amqpstorm
        runtime._settings = dict(self.settings, WORKERS=1, APNS_WORKERS=1,
                                 STALL_TIMEOUT=70, DELIVERY_TIMEOUT=60)
        runtime._amqp_tls_options = {}
        runtime._stop, runtime._conn = threading.Event(), None
        runtime._last_progress = time.monotonic()

        def consume():
            driver.owner = threading.get_ident()
            try:
                runtime.run()
            except BaseException:
                errors.append("consumer_runtime_failed")
            finally:
                terminal.set()

        worker = threading.Thread(target=consume, name="isolated-bridge-owner", daemon=True)

        def wait_for(predicate, seconds=15):
            until = min(driver.limit, time.monotonic() + seconds)
            while time.monotonic() < until:
                proof.require(not terminal.is_set() and not errors, "consumer_stopped_early")
                with driver.lock:
                    if predicate(): return
                time.sleep(0.02)
            raise proof.ProofFailure("consumer_case_deadline")

        def disposition(label, count, action):
            return any(event[:3] == (label, count, action) for event in events)

        try:
            # Publisher/DLQ channel is owned exclusively by this main thread.
            self.open_channel()
            worker.start()
            wait_for(registered.is_set)
            proof.require(len(registered_threads) == 1 and registered_threads[0] != threading.get_ident(),
                          "consumer_owner_invalid")
            self.receipt["phase"] = "registered_consumer_progress"
            self.publish(bodies["retry-success"])
            self.publish(bodies["companion"])
            wait_for(lambda: disposition("retry-success", 1, "ack") and disposition("companion", 0, "ack"))
            with self.lock:
                companion = next(event for event in events if event[:3] == ("companion", 0, "ack"))
                nack = next(event for event in events if event[:3] == ("retry-success", 0, "nack"))
                proof.require(companion[3] < nack[3], "retry_blocked_other_settlement")
                proof.require(nack[4] == {"requeue": True}, "wrong_disposition")
            self.receipt["checks"].append("registered_consumer_503_to_200_and_companion_ack_before_retry")

            self.receipt["phase"] = "registered_consumer_exhaustion"
            self.publish(bodies["exhaustion"])
            wait_for(lambda: disposition("exhaustion", 2, "reject"), seconds=20)
            # Basic.Get is permitted ONLY for the DLQ verifier, never work.
            self.receive(self.wanted.dead_queue, bodies["exhaustion"]).ack()
            with self.lock:
                proof.require([(event[1], event[2], event[4]) for event in events if event[0] == "exhaustion"] ==
                              [(0, "nack", {"requeue": True}), (1, "nack", {"requeue": True}),
                               (2, "reject", {"requeue": False})], "wrong_exhaustion_disposition")
                proof.require(self.dispatches == {"retry-success": 2, "companion": 1, "exhaustion": 3},
                              "dispatch_budget_changed")
                proof.require(counters == {"retry-success": [0, 1], "companion": [0], "exhaustion": [0, 1, 2]},
                              "broker_counter_unexpected")
            self.receipt["checks"].append("registered_consumer_counter_0_1_2_three_dispatches_and_dlq")
        finally:
            runtime._stop.set()
            if worker.ident is not None: worker.join(timeout=15)
            proof.require(not worker.is_alive(), "consumer_shutdown_deadline")

        proof.require(not errors and len(registered_threads) == 1, "consumer_runtime_failed")
        # Connection close round-trips before this queue check: any unacked
        # messages would have returned to work rather than disappearing.
        self.empty()
        proof.require(all(hashlib.sha256(Path(name).read_bytes()).hexdigest() == digest
                          for name, digest in pins.items()), "consumer_source_changed")
        self.receipt["consumer_source_stable"] = True
        self.receipt["registered_consumer_tested"] = True
        self.receipt["consumer_registrations"] = len(registered_threads)
        self.receipt["consumer_counters"] = counters
        self.receipt["checks"].append("consumer_closed_no_ready_messages_and_no_work_basic_get")


def main(argv=None):
    arguments = sys.argv[1:] if argv is None else argv
    proof.require(arguments == ["--run-isolated-local-consumer-proof"] and not os.environ.get("NOTIFY_SOCKET"),
                  "explicit_standalone_consumer_proof_required")
    # Reuse the already reviewed setup/receipt/cleanup implementation verbatim.
    # Only its bounded case-driver class changes, never broker authority scope.
    proof.RetryProof = ConsumerProof
    proof.main(["--run-isolated-local-proof"])


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("Isolated consumer acceptance failed; see protected receipt.", file=sys.stderr)
        sys.exit(1)
