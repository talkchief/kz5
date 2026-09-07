#!/usr/bin/env python3
"""Explicit local, UUID-isolated broker proof; synthetic outcomes, no providers.

No production configuration/keys, real notifications, broker restart, topology
migration or broad cleanup. A protected receipt is retained on every outcome.
"""
import datetime
from concurrent.futures import ThreadPoolExecutor
import json
import hashlib
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import threading
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "services/push-bridge"))
from amqp_topology import configure, plan
from delivery_retry import delivery_count
from delivery_settlement import OwnerSettlements
from freshness import capture, FreshnessFailure

PREFIX = "kz5-retry-proof-"
RESOURCE = re.compile(r"kz5-retry-proof-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\Z")
FAILURES = frozenset(("invalid_cleanup_scope", "message_outside_owner", "settlement_outside_owner",
    "publish_unconfirmed", "body_changed", "receive_deadline", "broker_counter_metadata_invalid",
    "broker_counter_unexpected", "worker_not_separate_thread", "worker_body_changed", "settlement_deadline",
    "ready_messages_remaining", "wrong_disposition", "retry_blocked_other_settlement", "dispatch_budget_changed",
    "acceptance_not_acked", "wrong_exhaustion_disposition", "fourth_dispatch", "invalid_fixture_freshness",
    "channel_close_dispatched_held_message", "channel_close_settlement_changed", "expired_dispatched",
    "isolated_broker_command_failed"))
CONTROL_COMMANDS = frozenset(("add_vhost", "add_user", "set_permissions", "set_user_tags", "delete_vhost", "delete_user"))


class ProofFailure(RuntimeError):
    def __init__(self, code):
        super().__init__("isolated_retry_proof_failed")
        self.code = code


def require(ok, code):
    if not ok:
        raise ProofFailure(code)


def control_output_category(stdout, stderr):
    """Allowlisted categories only; no raw output, argv, key or user value."""
    if type(stdout) is not bytes or type(stderr) is not bytes:
        return "UNKNOWN"
    text = (stderr[:65536] + b"\n" + stdout[:65536]).lower()
    groups = (
        ("command_syntax", (b"invalid option", b"unknown option", b"unrecognized option", b"bad argument",
                            b"argument validation", b"not enough arguments", b"too few arguments",
                            b"too many arguments", b"invalid number of arguments")),
        ("credential_policy", (b"password validation", b"credential validation", b"password does not",
                               b"minimum password", b"password is not")),
        ("already_exists", (b"already exists", b"user_already_exists")),
        ("node_unavailable_or_auth", (b"unable to perform an operation on node", b"nodedown",
                                     b"authentication failed", b"erlang cookie")),
        ("local_permission", (b"permission denied",)),
    )
    matches = [category for category, patterns in groups if any(pattern in text for pattern in patterns)]
    return matches[0] if len(matches) == 1 else "UNKNOWN"


def control_command(args, receipt, save, runner=None):
    """Record command name/state BEFORE execution, sanitized result afterward.

    Do not stringify subprocess exceptions: add_user argv contains a temporary
    credential and RabbitMQ CLI parser errors may echo it. Cleanup appends its
    own records without overwriting the first failed setup command.
    """
    require(type(args) is tuple and args and type(args[0]) is str and args[0] in CONTROL_COMMANDS,
            "isolated_broker_command_failed")
    record = {"command": args[0], "status": "RUNNING", "returncode": None, "output_category": None}
    receipt.setdefault("broker_commands", []).append(record); save()
    invoke = subprocess.run if runner is None else runner
    try:
        result = invoke(["/usr/sbin/rabbitmqctl", "-q", *args],
            env=dict(os.environ, RABBITMQ_CTL_ERL_ARGS="+S 1:1 +A 1"),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False)
    except subprocess.TimeoutExpired:
        record.update(status="TIMED_OUT", output_category="deadline")
        save(); raise ProofFailure("isolated_broker_command_failed") from None
    except Exception:
        record.update(status="LOCAL_ERROR", output_category="local_execution")
        save(); raise ProofFailure("isolated_broker_command_failed") from None
    status = result.returncode
    record["returncode"] = status if type(status) is int and -255 <= status <= 255 else "UNKNOWN"
    succeeded = type(status) is int and status == 0
    record["status"] = "SUCCEEDED" if succeeded else "FAILED"
    record["output_category"] = None if succeeded else control_output_category(result.stdout, result.stderr)
    save()
    require(succeeded, "isolated_broker_command_failed")


def cleanup_created(ctl, identity, created):
    require(type(identity) is str and RESOURCE.fullmatch(identity), "invalid_cleanup_scope")
    require(type(created) is list and all(type(k) is str and k in ("vhost", "user") for k in created)
            and len(created) == len(set(created)), "invalid_cleanup_scope")
    removed, failed = [], []
    for kind, command in (("vhost", "delete_vhost"), ("user", "delete_user")):
        if kind in created:
            try:
                ctl(command, identity)
                removed.append(kind)
            except Exception:
                failed.append(kind)
    return removed, failed


class TrackedMessage:
    """All dispositions still execute on the actual AMQPStorm message."""
    def __init__(self, message, clock):
        self.message, self.clock = message, clock
        self.owner, self.events = threading.get_ident(), []

    @property
    def properties(self):
        require(threading.get_ident() == self.owner, "message_outside_owner")
        return self.message.properties

    @property
    def redelivered(self):
        require(threading.get_ident() == self.owner, "message_outside_owner")
        return self.message.redelivered

    def _settle(self, action, **kwargs):
        require(threading.get_ident() == self.owner, "settlement_outside_owner")
        getattr(self.message, action)(**kwargs)
        self.events.append((action, self.clock(), kwargs))

    def ack(self):
        self._settle("ack")

    def nack(self, requeue=True):
        self._settle("nack", requeue=requeue)

    def reject(self, requeue=True):
        self._settle("reject", requeue=requeue)


class RetryProof:
    """Injectable bounded case driver; the CLI supplies only loopback resources."""
    def __init__(self, connection, settings, channel_error, verify, receipt, *,
                 monotonic=time.monotonic, wall_ms=lambda: time.time_ns() // 1000000,
                 sleep=time.sleep, executor_factory=ThreadPoolExecutor):
        self.connection, self.settings = connection, settings
        self.channel_error, self.verify, self.receipt = channel_error, verify, receipt
        self.monotonic, self.wall_ms, self.sleep = monotonic, wall_ms, sleep
        self.executor_factory = executor_factory
        self.wanted, self.channel = plan(settings), None
        self.limit = monotonic() + 90
        self.dispatches, self.lock = {}, threading.Lock()
        self.owner = threading.get_ident()

    def clocks(self):
        return {"now_ms": self.wall_ms(), "monotonic_ms": int(self.monotonic() * 1000)}

    def open_channel(self):
        self.channel = configure(self.connection, self.settings, self.channel_error, self.verify)
        self.channel.basic.qos(prefetch_count=2)
        self.channel.confirm_deliveries()

    def body(self, label, expired=False):
        now = self.wall_ms()
        return json.dumps({"Token-ID": "synthetic-not-a-device", "Call-ID": self.receipt["owner"] + "-" + label,
                           "Push-Freshness": {"version": 1, "created_at_ms": now - 2000 if expired else now,
                                              "deadline_ms": now - 1000 if expired else now + 60000}}, sort_keys=True)

    def publish(self, body):
        require(self.channel.basic.publish(body, exchange=self.settings["EXCHANGE"], routing_key="fixture.only",
                                           properties={"delivery_mode": 2}) is True, "publish_unconfirmed")

    def receive(self, queue, body):
        until = min(self.limit, self.monotonic() + 10)
        while self.monotonic() < until:
            message = self.channel.basic.get(queue=queue, no_ack=False)
            if message is not None:
                require(message.body == body, "body_changed")
                return TrackedMessage(message, self.monotonic)
            self.sleep(0.02)
        raise ProofFailure("receive_deadline")

    def observe(self, label, message, expected):
        properties, redelivered = message.properties, message.redelivered
        headers = properties.get("headers") if type(properties) is dict else None
        present = type(headers) is dict and "x-delivery-count" in headers
        raw = headers["x-delivery-count"] if present else None
        # Fixed categories and small integer counters only, never raw headers.
        self.receipt["counter_observations"].append({"case": label,
            "redelivered": redelivered if type(redelivered) is bool else "UNKNOWN",
            "counter_present": present, "counter": raw if type(raw) is int and 0 <= raw <= 3 else None if not present else "UNKNOWN"})
        try:
            count = delivery_count(properties, redelivered)
        except Exception:
            raise ProofFailure("broker_counter_metadata_invalid") from None
        require(count == expected, "broker_counter_unexpected")

    def worker(self, label, expected_body, outcome):
        owner, lock, dispatches = self.owner, self.lock, self.dispatches
        def synthetic(body):
            require(threading.get_ident() != owner, "worker_not_separate_thread")
            require(body == expected_body, "worker_body_changed")
            with lock:
                dispatches[label] = dispatches.get(label, 0) + 1
            return outcome
        return synthetic

    def submit(self, owner, executor, message, body, label, outcome):
        try:
            lease = capture(json.loads(body), "unix-ms-v1", **self.clocks())
        except FreshnessFailure as error:
            require(error.code == "push_freshness_expired", "invalid_fixture_freshness")
            lease = None
        owner.submit(executor, self.worker(label, body, outcome), message, body,
                     provider="fcm", freshness=lease)

    def drain(self, owner):
        until = min(self.limit, self.monotonic() + 12)
        while owner.pending_count:
            require(self.monotonic() < until, "settlement_deadline")
            owner.drain()
            if owner.pending_count:
                self.sleep(0.01)

    def empty(self):
        for queue in (self.wanted.work_queue, self.wanted.dead_queue):
            state = self.channel.queue.declare(queue=queue, passive=True)
            require(type(state) is dict and state.get("message_count") == 0, "ready_messages_remaining")

    def run(self):
        accepted, transient = (True, 200, "provider_response"), (False, 503, "provider_response")
        self.open_channel()
        with self.executor_factory(max_workers=2) as executor:
            self.receipt["phase"] = "continued_processing"
            owner = OwnerSettlements(2, quarantine=True, retry=True, clock=self.clocks)
            retry_body, companion_body = self.body("retry-success"), self.body("companion")
            self.publish(retry_body); self.publish(companion_body)
            first = self.receive(self.wanted.work_queue, retry_body)
            companion = self.receive(self.wanted.work_queue, companion_body)
            self.observe("retry-success-first", first, 0); self.observe("companion-first", companion, 0)
            self.submit(owner, executor, first, retry_body, "retry-success", transient)
            self.submit(owner, executor, companion, companion_body, "companion", accepted)
            self.drain(owner)
            require([e[0] for e in first.events] == ["nack"] and [e[0] for e in companion.events] == ["ack"], "wrong_disposition")
            require(companion.events[0][1] < first.events[0][1], "retry_blocked_other_settlement")
            again = self.receive(self.wanted.work_queue, retry_body)
            self.observe("retry-success-redelivery", again, 1)
            self.submit(owner, executor, again, retry_body, "retry-success", accepted); self.drain(owner)
            require(self.dispatches.get("retry-success") == 2 and self.dispatches.get("companion") == 1, "dispatch_budget_changed")
            require([e[0] for e in again.events] == ["ack"], "acceptance_not_acked")
            self.empty()
            self.receipt["checks"].append("real_503_to_200_counter_0_to_1_and_companion_progress")

            self.receipt["phase"] = "exhaustion"
            exhaust_body = self.body("exhaustion"); self.publish(exhaust_body)
            for count in (0, 1, 2):
                delivered = self.receive(self.wanted.work_queue, exhaust_body)
                self.observe("exhaustion-" + str(count), delivered, count)
                self.submit(owner, executor, delivered, exhaust_body, "exhaustion", transient); self.drain(owner)
                require([e[0] for e in delivered.events] == (["nack"] if count < 2 else ["reject"]), "wrong_exhaustion_disposition")
            dead = self.receive(self.wanted.dead_queue, exhaust_body); dead.ack()
            require(self.dispatches.get("exhaustion") == 3, "fourth_dispatch")
            self.empty(); self.receipt["checks"].append("real_counter_0_1_2_three_dispatches_exhaustion_dlq_no_fourth")

            # Hold count1 unacked, close that channel, and obtain the unchanged
            # message on a new independently verified channel. No broker restart.
            self.receipt["phase"] = "channel_close"
            close_body = self.body("channel-close"); self.publish(close_body)
            delivered = self.receive(self.wanted.work_queue, close_body)
            self.observe("channel-close-first", delivered, 0)
            self.submit(owner, executor, delivered, close_body, "channel-close", transient); self.drain(owner)
            held = self.receive(self.wanted.work_queue, close_body)
            self.observe("channel-close-held", held, 1)
            owner.invalidate(); self.channel.close(); self.open_channel()
            owner = OwnerSettlements(2, quarantine=True, retry=True, clock=self.clocks)
            restored = self.receive(self.wanted.work_queue, close_body)
            self.observe("channel-close-restored", restored, 2)
            self.submit(owner, executor, restored, close_body, "channel-close", accepted); self.drain(owner)
            require(self.dispatches.get("channel-close") == 2, "channel_close_dispatched_held_message")
            require(not held.events and [e[0] for e in restored.events] == ["ack"], "channel_close_settlement_changed")
            self.empty(); self.receipt["checks"].append("channel_close_redelivery_preserves_and_increments_broker_count")

            self.receipt["phase"] = "expiry"
            expired_body = self.body("expired", expired=True); self.publish(expired_body)
            expired = self.receive(self.wanted.work_queue, expired_body); self.observe("expired-first", expired, 0)
            self.submit(owner, executor, expired, expired_body, "expired", accepted); self.drain(owner)
            dead = self.receive(self.wanted.dead_queue, expired_body); dead.ack()
            require(self.dispatches.get("expired", 0) == 0 and [e[0] for e in expired.events] == ["reject"], "expired_dispatched")
            self.empty(); owner.invalidate()
            self.receipt["checks"].append("expired_original_deadline_quarantined_before_worker")
        self.receipt["synthetic_dispatches"] = dict(self.dispatches)
        self.receipt["phase"] = "cases_complete"


def main(argv=None):
    require((sys.argv[1:] if argv is None else argv) == ["--run-isolated-local-proof"] and os.geteuid() == 0,
            "explicit_root_development_proof_required")
    import amqpstorm
    from amqp_management import verify_topology
    identity = PREFIX + str(uuid.uuid4())
    base = Path("/var/log/kazoo-acceptance")
    stat = base.lstat()
    require(base.is_dir() and not base.is_symlink() and base.resolve() == base
            and stat.st_uid == 0 and not stat.st_mode & 0o022,
            "unsafe_receipt_parent")
    directory = base / identity; directory.mkdir(mode=0o700)
    receipt = {"schema_version": 1, "owner": identity, "broker": "127.0.0.1", "vhost": identity, "user": identity,
               "started_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "checks": [],
               "counter_observations": [], "synthetic_dispatches": {}, "created": [], "removed": [],
               "provider_calls": 0, "production_touched": False, "complete": False,
               "broker_restart_tested": False, "lost_ack_tested": False, "full_dlq_tested": False,
               "automatic_process_recovery_tested": False, "phone_delivery_verified": False}
    source = Path(__file__).resolve().parents[1] / "services/push-bridge"
    source_files = [Path(__file__).resolve(), *[source / name for name in (
        "delivery_retry.py", "delivery_settlement.py", "freshness.py", "freshness_runtime.py",
        "amqp_topology.py", "amqp_management.py", "validate_config.py", "requirements.lock")]]
    receipt["source_sha256"] = {str(file): hashlib.sha256(file.read_bytes()).hexdigest() for file in source_files}
    def save():
        temporary = directory / ("receipt-" + str(uuid.uuid4()) + ".tmp")
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(receipt, stream, indent=2); stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, directory / "receipt.json")
        fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try: os.fsync(fd)
        finally: os.close(fd)
    def ctl(*args):
        control_command(args, receipt, save)
    connection, driver = None, None; save()
    try:
        password = secrets.token_urlsafe(32)
        ctl("add_vhost", identity); receipt["created"].append("vhost"); save()
        ctl("add_user", identity, password); receipt["created"].append("user"); save()
        ctl("set_permissions", "-p", identity, identity, ".*", ".*", ".*")
        ctl("set_user_tags", identity, "monitoring")
        settings = {"TOPOLOGY": "quorum-v1", "RETRY": "quorum-counted-v1", "FRESHNESS": "unix-ms-v1",
                    "AMQP_HOST": "127.0.0.1", "AMQP_PORT": 5672, "AMQP_USER": identity, "AMQP_PASS": password,
                    "AMQP_VHOST": identity, "AMQP_MANAGEMENT_URL": "http://127.0.0.1:15672",
                    "EXCHANGE": "fixture.pushes", "QUEUE": "fixture.mobile.quorum-v1", "BINDING_KEY": "fixture.only"}
        connection = amqpstorm.Connection("127.0.0.1", identity, password, virtual_host=identity,
                                         port=5672, heartbeat=30, timeout=10)
        channel = connection.channel()
        channel.exchange.declare(exchange=settings["EXCHANGE"], exchange_type="topic", durable=True); channel.close()
        driver = RetryProof(connection, settings, amqpstorm.AMQPChannelError, verify_topology, receipt)
        driver.run()
        receipt["complete"] = True
    except Exception as error:
        receipt["failure"] = error.code if isinstance(error, ProofFailure) and error.code in FAILURES else "isolated_retry_proof_failed"
    finally:
        if driver is not None:
            receipt["synthetic_dispatches"] = dict(driver.dispatches)
        if connection is not None:
            try: connection.close()
            except Exception: receipt["connection_close_uncertain"] = True
        receipt["removed"], failed = cleanup_created(ctl, identity, receipt["created"])
        if failed: receipt["cleanup_failed"] = failed; receipt["complete"] = False
        receipt["finished_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        try:
            receipt["source_stable"] = all(hashlib.sha256(file.read_bytes()).hexdigest() == receipt["source_sha256"][str(file)]
                                           for file in source_files)
        except Exception:
            receipt["source_stable"] = False
        if not receipt["source_stable"]:
            receipt["complete"] = False
        save()
        print(json.dumps({"receipt": str(directory / "receipt.json"), "complete": receipt["complete"],
                          "checks": receipt["checks"], "removed": receipt["removed"]}))
    require(receipt["complete"], "isolated_retry_proof_incomplete")


if __name__ == "__main__":
    try: main()
    except Exception:
        print("Isolated retry acceptance failed; see protected receipt.", file=sys.stderr)
        sys.exit(1)
