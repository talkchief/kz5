#!/usr/bin/env python3
"""Explicit UUID-isolated local unbound-DLQ retention proof; no real pushes."""
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import sys
import uuid
from types import SimpleNamespace

BASE_FILE = Path(__file__).resolve().with_name("accept-push-bridge-retry.py")
spec = importlib.util.spec_from_file_location("dlq_retention_lifecycle", BASE_FILE)
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
from amqp_management import ManagementVerificationFailure
from delivery_settlement import OwnerSettlements

FAILURES = base.FAILURES | frozenset(("invalid_isolated_settings", "unbound_not_verified",
    "unbound_ready_message", "case_deadline", "synthetic_result_not_completed",
    "synthetic_result_changed", "unexpected_synthetic_dispatch", "binding_restore_unverified",
    "binding_restore_failed", "recovery_deadline"))
CHANNEL_RPC_SECONDS = 10
RECOVERY_SECONDS = 240
CASE_SECONDS = 300


class BoundedConnection:
    """Only this isolated harness's channels; never alter the shared broker."""
    def __init__(self, connection):
        self.connection = connection

    def channel(self):
        # AMQPStorm Connection.timeout is a socket timeout; channel RPC has its
        # own default60s. Use its supported public API for every proof channel.
        return self.connection.channel(rpc_timeout=CHANNEL_RPC_SECONDS)


class DlqRetentionProof(base.RetryProof):
    def __init__(self, connection, settings, channel_error, verify, receipt,
                 *, checkpoint=lambda: None, **kwargs):
        base.require(callable(checkpoint), "invalid_isolated_settings")
        identity = receipt["owner"]
        base.require(type(identity) is str and base.RESOURCE.fullmatch(identity)
            and settings.get("AMQP_HOST") == "127.0.0.1"
            and settings.get("AMQP_PORT") == 5672
            and settings.get("AMQP_MANAGEMENT_URL") == "http://127.0.0.1:15672"
            and settings.get("AMQP_VHOST") == identity and settings.get("AMQP_USER") == identity
            and settings.get("QUEUE") == "fixture.mobile.quorum-v1"
            and settings.get("EXCHANGE") == "fixture.pushes", "invalid_isolated_settings")
        super().__init__(BoundedConnection(connection), settings, channel_error, verify, receipt, **kwargs)
        self.checkpoint = checkpoint
        self.limit = self.monotonic() + CASE_SECONDS

    def deadline(self):
        base.require(self.monotonic() < self.limit, "case_deadline")

    def bind_dead(self):
        self.channel.queue.bind(queue=self.wanted.dead_queue, exchange=self.wanted.dead_exchange,
                                routing_key=self.wanted.dead_routing_key)

    def ready_empty(self):
        # Ready counts are NOT an internal retained-message count. Only later
        # exact readback, without republishing, proves this case's retention.
        for queue in (self.wanted.work_queue, self.wanted.dead_queue):
            state = self.channel.queue.declare(queue=queue, passive=True)
            base.require(type(state) is dict and type(state.get("message_count")) is int
                         and state["message_count"] == 0, "unbound_ready_message")

    def run(self):
        receipt = self.receipt
        receipt.update(proof_kind="temporarily_unbound_dlq", unavailable_dlq_tested=False,
                       full_dlq_tested=False, publisher_confirms=0, original_republished=False,
                       binding_restore_attempted=False, binding_restored=False)
        receipt["bounds_seconds"] = {"case": CASE_SECONDS, "recovery": RECOVERY_SECONDS,
                                     "channel_rpc": CHANNEL_RPC_SECONDS}
        self.open_channel()
        self.deadline()
        body = self.body("permanent-unbound-dlq")
        receipt["synthetic_body_sha256"] = hashlib.sha256(body.encode("utf-8")).hexdigest()
        self.publish(body)
        receipt["publisher_confirms"] = 1
        delivered = self.receive(self.wanted.work_queue, body)
        self.observe("permanent-before-unbind", delivered, 0)
        owner = OwnerSettlements(1, quarantine=True)
        unbound = False
        try:
            with self.executor_factory(max_workers=1) as executor:
                # Complete the sole synthetic result before removing the route.
                # No provider dispatch, worker retry or republish occurs during
                # the fault interval; only the owning thread rejects once.
                holder = SimpleNamespace(future=None)
                def submit(worker, raw):
                    holder.future = executor.submit(worker, raw)
                    return holder.future
                outcome = (False, 404, "provider_response")
                owner.submit(SimpleNamespace(submit=submit), self.worker("permanent", body, outcome),
                             delivered, body, provider="fcm")
                until = min(self.limit, self.monotonic() + 10)
                while not holder.future.done():
                    base.require(self.monotonic() < until, "synthetic_result_not_completed")
                    self.sleep(0.01)
                base.require(holder.future.result() == outcome, "synthetic_result_changed")
                base.require(self.dispatches == {"permanent": 1}, "unexpected_synthetic_dispatch")
                self.deadline()
                receipt["phase"] = "remove_owned_dead_binding"
                self.checkpoint()
                # Set before the command: even uncertain unbind must attempt
                # restoring this exact owned binding before vhost cleanup.
                unbound = True
                started = self.monotonic()
                receipt["unbind_started_monotonic_ms"] = int(started * 1000)
                self.channel.queue.unbind(queue=self.wanted.dead_queue, exchange=self.wanted.dead_exchange,
                                          routing_key=self.wanted.dead_routing_key)
                receipt["unbind_confirmed_monotonic_ms"] = int(self.monotonic() * 1000)
                try:
                    self.verify(self.settings, self.wanted)
                except ManagementVerificationFailure as error:
                    base.require(error.phase == "dead_bindings" and error.http_status == 200,
                                 "unbound_not_verified")
                else:
                    raise base.ProofFailure("unbound_not_verified")
                receipt["unbound_verified"] = True
                self.checkpoint()
                self.deadline()
                self.drain(owner)
                base.require([event[0] for event in delivered.events] == ["reject"]
                             and delivered.events[0][2] == {"requeue": False}, "wrong_disposition")
                receipt["reject_monotonic_ms"] = int(delivered.events[0][1] * 1000)
                receipt["phase"] = "hold_unbound"
                hold_until = self.monotonic() + 5
                while self.monotonic() < hold_until:
                    self.deadline(); self.ready_empty(); self.sleep(0.1)
                base.require(self.dispatches == {"permanent": 1}, "unexpected_synthetic_dispatch")
                receipt["dispatches_during_unbound"] = 0
                receipt["retries_during_unbound"] = 0
                receipt["phase"] = "restore_owned_dead_binding"
                receipt["binding_restore_attempted"] = True
                receipt["rebind_started_monotonic_ms"] = int(self.monotonic() * 1000)
                receipt["confirmed_unbound_before_restore_ms"] = (
                    receipt["rebind_started_monotonic_ms"] - receipt["unbind_confirmed_monotonic_ms"])
                self.checkpoint()
                self.bind_dead()
                ended = self.monotonic()
                receipt["rebind_confirmed_monotonic_ms"] = int(ended * 1000)
                receipt["unbind_request_to_rebind_confirmed_ms"] = int((ended - started) * 1000)
                unbound = False
                base.require(self.verify(self.settings, self.wanted) is True, "binding_restore_unverified")
                receipt["binding_restored"] = True
                self.checkpoint()
                self.deadline()
                receipt["phase"] = "await_retained_message"
                receipt["recovery_started_monotonic_ms"] = int(self.monotonic() * 1000)
                self.checkpoint()
                until = min(self.limit, self.monotonic() + RECOVERY_SECONDS)
                dead = None
                while self.monotonic() < until:
                    message = self.channel.basic.get(queue=self.wanted.dead_queue, no_ack=False)
                    if message is not None:
                        base.require(message.body == body, "body_changed")
                        dead = base.TrackedMessage(message, self.monotonic)
                        break
                    self.sleep(0.1)
                base.require(dead is not None, "recovery_deadline")
                receipt["recovered_monotonic_ms"] = int(self.monotonic() * 1000)
                dead.ack()
                base.require(self.dispatches == {"permanent": 1}, "unexpected_synthetic_dispatch")
                self.empty()
                receipt["checks"].append("confirmed_single_publish_permanent_reject_unbound_then_exact_dlq_readback")
                receipt["unavailable_dlq_tested"] = True
                receipt["synthetic_dispatches"] = dict(self.dispatches)
                receipt["phase"] = "cases_complete"
        finally:
            owner.invalidate()
            if unbound:
                receipt["binding_restore_attempted"] = True
                try: self.bind_dead()
                except Exception: receipt["binding_restore_uncertain"] = True


def main(argv=None):
    base.require((sys.argv[1:] if argv is None else argv) == ["--run-isolated-local-dlq-proof"]
                 and os.geteuid() == 0, "explicit_root_development_proof_required")
    import amqpstorm
    from amqp_management import verify_topology
    identity = base.PREFIX + str(uuid.uuid4())
    parent = Path("/var/log/kazoo-acceptance")
    stat = parent.lstat()
    base.require(parent.is_dir() and not parent.is_symlink() and parent.resolve() == parent
                 and stat.st_uid == 0 and not stat.st_mode & 0o022, "unsafe_receipt_parent")
    directory = parent / identity
    directory.mkdir(mode=0o700)
    receipt = {"schema_version": 1, "owner": identity, "broker": "127.0.0.1", "vhost": identity, "user": identity,
        "started_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "checks": [],
        "counter_observations": [], "synthetic_dispatches": {}, "created": [], "removed": [],
        "provider_calls": 0, "production_touched": False, "complete": False,
        "proof_kind": "temporarily_unbound_dlq", "broker_restart_tested": False, "lost_ack_tested": False,
        "full_dlq_tested": False, "unavailable_dlq_tested": False,
        "automatic_process_recovery_tested": False, "phone_delivery_verified": False}
    source = Path(__file__).resolve().parents[1] / "services/push-bridge"
    files = [Path(__file__).resolve(), BASE_FILE, *[source / name for name in (
        "delivery_retry.py", "delivery_settlement.py", "freshness.py", "freshness_runtime.py", "push_payload.py",
        "amqp_topology.py", "amqp_management.py", "validate_config.py", "requirements.lock")]]
    receipt["source_sha256"] = {str(file): hashlib.sha256(file.read_bytes()).hexdigest() for file in files}
    def save():
        temporary = directory / ("receipt-" + str(uuid.uuid4()) + ".tmp")
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(receipt, stream, indent=2); stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, directory / "receipt.json")
        fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try: os.fsync(fd)
        finally: os.close(fd)
    def ctl(*args): base.control_command(args, receipt, save)
    connection, driver = None, None
    save()
    try:
        password = secrets.token_urlsafe(32)
        ctl("add_vhost", identity); receipt["created"].append("vhost"); save()
        ctl("add_user", identity, password); receipt["created"].append("user"); save()
        ctl("set_permissions", "-p", identity, identity, ".*", ".*", ".*")
        ctl("set_user_tags", identity, "monitoring")
        settings = {"TOPOLOGY": "quorum-v1", "AMQP_HOST": "127.0.0.1", "AMQP_PORT": 5672,
            "AMQP_USER": identity, "AMQP_PASS": password, "AMQP_VHOST": identity,
            "AMQP_MANAGEMENT_URL": "http://127.0.0.1:15672", "EXCHANGE": "fixture.pushes",
            "QUEUE": "fixture.mobile.quorum-v1", "BINDING_KEY": "fixture.only"}
        connection = amqpstorm.Connection("127.0.0.1", identity, password, virtual_host=identity,
                                         port=5672, heartbeat=30, timeout=10)
        channel = connection.channel(rpc_timeout=CHANNEL_RPC_SECONDS)
        channel.exchange.declare(exchange=settings["EXCHANGE"], exchange_type="topic", durable=True)
        channel.close()
        driver = DlqRetentionProof(connection, settings, amqpstorm.AMQPChannelError, verify_topology, receipt,
                                   checkpoint=save)
        driver.run()
        receipt["complete"] = True
    except Exception as error:
        receipt["failure"] = error.code if isinstance(error, base.ProofFailure) and error.code in FAILURES else "isolated_dlq_proof_failed"
    finally:
        if driver is not None: receipt["synthetic_dispatches"] = dict(driver.dispatches)
        if connection is not None:
            try: connection.close()
            except Exception: receipt["connection_close_uncertain"] = True
        receipt["removed"], failed = base.cleanup_created(ctl, identity, receipt["created"])
        if failed: receipt["cleanup_failed"] = failed; receipt["complete"] = False
        receipt["finished_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        try:
            receipt["source_stable"] = all(hashlib.sha256(file.read_bytes()).hexdigest()
                == receipt["source_sha256"][str(file)] for file in files)
        except Exception: receipt["source_stable"] = False
        if not receipt["source_stable"]: receipt["complete"] = False
        save()
        print(json.dumps({"receipt": str(directory / "receipt.json"), "complete": receipt["complete"],
                         "checks": receipt["checks"], "removed": receipt["removed"]}))
    base.require(receipt["complete"], "isolated_dlq_proof_incomplete")


if __name__ == "__main__":
    try: main()
    except Exception:
        print("Isolated DLQ acceptance failed; see protected receipt.", file=sys.stderr)
        sys.exit(1)
