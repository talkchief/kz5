#!/usr/bin/env python3
"""Explicit development-only synthetic quorum/DLQ acceptance.

Creates its own UUID-named local vhost/user, never imports production settings,
starts a provider worker or restarts RabbitMQ. Deletes only resources created by
this invocation; retains a protected receipt even on failure.
"""
import datetime
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import traceback
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "services/push-bridge"))
import amqpstorm
from amqp_management import ManagementVerificationFailure, verify_topology
from amqp_topology import configure, plan


def main():
    if sys.argv[1:] != ["--run-isolated-local-proof"] or os.geteuid() != 0:
        raise RuntimeError("explicit_root_development_proof_required")
    identity = "kz5-topology-proof-" + str(uuid.uuid4())
    directory = Path("/var/log/kazoo-acceptance") / identity
    directory.mkdir(mode=0o700)
    receipt = {"schema_version": 1, "owner": identity,
               "started_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "broker": "127.0.0.1", "vhost": identity, "user": identity,
               "provider_calls": 0, "production_touched": False, "checks": [],
               "created": [], "removed": [], "complete": False,
               "fault_injection_complete": False, "phone_delivery_verified": False}
    def save():
        target = directory / "receipt.json"
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(receipt, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
    def ctl(*args):
        environment = dict(os.environ, RABBITMQ_CTL_ERL_ARGS="+S 1:1 +A 1")
        result = subprocess.run(["/usr/sbin/rabbitmqctl", "-q", *args], env=environment,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False)
        if result.returncode != 0:
            raise RuntimeError("isolated_broker_setup_failed")
    connection = None
    save()
    try:
        password = secrets.token_urlsafe(32)
        ctl("add_vhost", identity)
        receipt["created"].append("vhost"); save()
        ctl("add_user", identity, password)
        receipt["created"].append("user"); save()
        ctl("set_permissions", "-p", identity, identity, ".*", ".*", ".*")
        ctl("set_user_tags", identity, "monitoring")
        settings = {"TOPOLOGY": "quorum-v1", "AMQP_HOST": "127.0.0.1", "AMQP_PORT": 5672,
                    "AMQP_USER": identity, "AMQP_PASS": password, "AMQP_VHOST": identity,
                    "AMQP_MANAGEMENT_URL": "http://127.0.0.1:15672", "EXCHANGE": "fixture.pushes",
                    "QUEUE": "fixture.mobile.quorum-v1", "BINDING_KEY": "fixture.only"}
        connection = amqpstorm.Connection("127.0.0.1", identity, password,
                                         virtual_host=identity, port=5672, heartbeat=30, timeout=10)
        channel = connection.channel()
        channel.exchange.declare(exchange=settings["EXCHANGE"], exchange_type="topic", durable=True)
        channel.close()
        channel = configure(connection, settings, amqpstorm.AMQPChannelError, verify_topology)
        receipt["checks"].append("real_declare_and_live_management_verification")
        wanted = plan(settings)
        channel.confirm_deliveries()
        payload = json.dumps({"fixture": identity, "synthetic": True})
        if channel.basic.publish(payload, exchange=settings["EXCHANGE"], routing_key="fixture.only",
                                 properties={"delivery_mode": 2}) is not True:
            raise RuntimeError("synthetic_publish_not_confirmed")
        def receive(queue):
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                message = channel.basic.get(queue=queue, no_ack=False)
                if message is not None:
                    return message
                time.sleep(0.1)
            raise RuntimeError("synthetic_message_not_received")
        message = receive(wanted.work_queue)
        if message.body != payload:
            raise RuntimeError("synthetic_message_mismatch")
        message.reject(requeue=False)
        dead = receive(wanted.dead_queue)
        if dead.body != payload:
            raise RuntimeError("synthetic_dead_letter_mismatch")
        dead.ack()
        receipt["checks"].append("confirmed_synthetic_publish_reject_and_dead_letter_readback")
        ctl("set_policy", "-p", identity, "fixture-unsafe-overflow", "^fixture\\.mobile\\.quorum-v1$",
            '{"overflow":"drop-head"}', "--apply-to", "quorum_queues")
        try:
            verify_topology(settings, wanted)
        except ManagementVerificationFailure:
            receipt["checks"].append("unsafe_effective_policy_refused")
        else:
            raise RuntimeError("unsafe_policy_was_accepted")
        ctl("clear_policy", "-p", identity, "fixture-unsafe-overflow")
        if verify_topology(settings, wanted) is not True:
            raise RuntimeError("restored_policy_not_verified")
        receipt["checks"].append("restored_topology_verified")
        receipt["complete"] = True
    except Exception as error:
        # Fixed known types only, never command output, passwords or payloads.
        receipt["failure_type"] = type(error).__name__
        nested = error
        for _ in range(8):
            if isinstance(nested, ManagementVerificationFailure):
                if nested.phase != "unknown":
                    receipt["probe_phase"] = nested.phase
                    receipt["probe_http_status"] = nested.http_status
                receipt.setdefault("probe_source_lines", []).extend(
                    frame.lineno for frame in traceback.extract_tb(nested.__traceback__)
                    if Path(frame.filename).name == "amqp_management.py")
            nested = getattr(nested, "__context__", None)
        raise RuntimeError("isolated_quorum_proof_failed") from None
    finally:
        if connection is not None:
            try:
                connection.close()
            except Exception:
                pass
        for kind, command in (("vhost", "delete_vhost"), ("user", "delete_user")):
            if kind in receipt["created"]:
                try:
                    ctl(command, identity)
                    receipt["removed"].append(kind)
                except Exception:
                    receipt["complete"] = False
                    receipt["cleanup_failed"] = True
        receipt["finished_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        save()
        print(json.dumps({"receipt": str(directory / "receipt.json"), "complete": receipt["complete"],
                          "checks": receipt["checks"], "removed": receipt["removed"]}))
    if not receipt["complete"]:
        raise RuntimeError("isolated_quorum_cleanup_incomplete")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("Isolated quorum acceptance failed; see protected receipt.", file=sys.stderr)
        sys.exit(1)
