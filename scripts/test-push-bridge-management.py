#!/usr/bin/env python3
"""Offline HTTP evidence fixtures; no real credentials, broker or network."""
import copy
import json
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "services/push-bridge"))
import amqp_management as probe


class Response:
    def __init__(self, body, status=200, raw=None, headers=None):
        self.body = json.dumps(body).encode() if raw is None else raw
        self.status_code = status
        self.headers = {"Content-Type": "application/json"} if headers is None else headers
        self.closed = False
        self.reads = 0

    def iter_content(self, chunk_size):
        for offset in range(0, len(self.body), chunk_size):
            self.reads += 1
            yield self.body[offset:offset + chunk_size]

    def close(self):
        self.closed = True


class Session:
    def __init__(self, responses):
        self.responses = responses
        self.calls = []
        self.closed = False

    def get(self, url, **kwargs):
        self.calls.append((url, kwargs))
        response = self.responses[len(self.calls) - 1]
        kwargs["hooks"]["response"](response)
        return response

    def close(self):
        self.closed = True


class ManagementTests(unittest.TestCase):
    def setUp(self):
        self.settings = {"TOPOLOGY": "quorum-v1", "AMQP_MANAGEMENT_URL": "https://broker.fixture.invalid:15671",
                         "AMQP_HOST": "broker.fixture.invalid",
                         "AMQP_USER": "fixture", "AMQP_PASS": "SYNTHETIC_SECRET", "AMQP_VHOST": "/fixture space"}
        self.plan = SimpleNamespace(work_queue="mobile.quorum-v1", dead_queue="mobile.quorum-v1.dlq",
                                    dead_exchange="mobile.quorum-v1.dlx", dead_routing_key="dead",
                                    ingress_exchange="pushes", work_arguments={"x-queue-type": "quorum", "x-delivery-limit": 3},
                                    dead_arguments={"x-queue-type": "quorum"})
        def queue(name, args):
            return {"name": name, "vhost": self.settings["AMQP_VHOST"], "type": "quorum", "durable": True,
                    "auto_delete": False, "exclusive": False, "state": "running", "arguments": args,
                    "policy": "", "operator_policy": None, "effective_policy_definition": {}}
        def exchange(name, kind):
            return {"name": name, "vhost": self.settings["AMQP_VHOST"], "type": kind,
                    "durable": True, "auto_delete": False, "internal": False}
        self.bodies = [queue(self.plan.work_queue, self.plan.work_arguments), queue(self.plan.dead_queue, self.plan.dead_arguments),
                       exchange(self.plan.dead_exchange, "direct"), exchange(self.plan.ingress_exchange, "topic"),
                       [{"source": self.plan.dead_exchange, "vhost": self.settings["AMQP_VHOST"], "destination": self.plan.dead_queue,
                         "destination_type": "queue", "routing_key": "dead", "arguments": {}}],
                       [{"name": "stream_queue", "state": "enabled"}]]

    def invoke(self, responses=None):
        self.responses = responses or [Response([]), Response([])] + [Response(body) for body in self.bodies]
        self.session = Session(self.responses)
        with patch("requests.Session", return_value=self.session):
            return probe.verify_topology(self.settings, self.plan)

    def reject(self, responses=None):
        with self.assertRaisesRegex(probe.ManagementVerificationFailure, "^amqp_topology_not_verified$"):
            self.invoke(responses)
        self.assertTrue(self.session.closed)

    def test_fresh_read_only_evidence_and_tls(self):
        self.assertIs(self.invoke(), True)
        self.assertEqual(len(self.session.calls), 8)
        self.assertFalse(self.session.trust_env)
        self.assertEqual(self.session.proxies, {})
        self.assertIn("/api/queues/%2Ffixture%20space/mobile.quorum-v1", self.session.calls[2][0])
        self.assertTrue(all(r.closed for r in self.responses))
        self.assertTrue(self.session.closed)
        for url, options in self.session.calls:
            self.assertNotIn("SYNTHETIC_SECRET", url)
            self.assertEqual(options["auth"], ("fixture", "SYNTHETIC_SECRET"))
            self.assertIs(options["verify"], True)
            self.assertIs(options["allow_redirects"], False)
            self.assertIs(options["stream"], True)
            self.assertEqual(options["timeout"], (3.05, 5))
        self.assertIs(self.invoke(), True)
        self.assertEqual(len(self.session.calls), 8)  # No cached evidence.

    def test_explicit_ca_and_local_http(self):
        self.settings["AMQP_MANAGEMENT_CA_FILE"] = "/etc/kazoo-push-bridge/ca.pem"
        self.assertTrue(self.invoke())
        self.assertEqual(self.session.calls[0][1]["verify"], self.settings["AMQP_MANAGEMENT_CA_FILE"])
        del self.settings["AMQP_MANAGEMENT_CA_FILE"]
        for base in ("http://127.0.0.1:15672", "http://[::1]:15672", "http://localhost:15672"):
            self.settings["AMQP_MANAGEMENT_URL"] = base
            self.settings["AMQP_HOST"] = probe.urlsplit(base).hostname
            self.assertTrue(self.invoke())

    def test_unsafe_url_rejected_before_session(self):
        for value in ("http://10.1.0.28:15672", "ftp://localhost", "https://u:p@localhost", "https://localhost/path",
                      "https://localhost?q=secret", "https://localhost#fragment", "https://localhost:0", "https://localhost:65536",
                      "https://localhost\n", "https://local\\host", "https://[::1%25lo]", ""):
            with self.subTest(value=value), patch("requests.Session") as factory:
                self.settings["AMQP_MANAGEMENT_URL"] = value
                with self.assertRaises(probe.ManagementVerificationFailure):
                    probe.verify_topology(self.settings, self.plan)
                factory.assert_not_called()

    def test_wrong_queue_or_arguments_refused(self):
        for index in (0, 1):
            for key, value in (("name", "other"), ("vhost", "/other"), ("type", "classic"), ("durable", 1),
                               ("auto_delete", True), ("exclusive", True), ("state", "down"), ("arguments", {})):
                original = copy.deepcopy(self.bodies)
                self.bodies[index][key] = value
                self.reject()
                self.bodies = original
        self.bodies[0]["arguments"] = {"x-queue-type": "quorum", "x-delivery-limit": True}
        self.reject()

    def test_policy_overrides_or_missing_evidence_refused(self):
        for key in ("policy", "operator_policy", "effective_policy_definition"):
            for index in (0, 1):
                original = copy.deepcopy(self.bodies)
                self.bodies[index][key] = {"overflow": "drop-head"} if key == "effective_policy_definition" else "operator-policy"
                self.reject()
                del self.bodies[index][key]
                self.assertIs(self.invoke(), True)
                self.bodies = original
        self.bodies[0]["effective_policy_definition"] = None
        self.reject()

    def test_fresh_policy_lists_override_stale_empty_queue_statistics(self):
        for replies in ([Response([{"name": "unsafe"}])],
                        [Response([]), Response([{"name": "unsafe"}])],
                        [Response({})], [Response([]), Response({}, status=403)]):
            self.reject(replies)
            self.assertLessEqual(len(self.session.calls), 2)

    def test_exchange_and_dlx_routing_verified(self):
        for index in (2, 3):
            original = copy.deepcopy(self.bodies)
            self.bodies[index]["type"] = "fanout"
            self.reject()
            self.bodies = original
        for value in ([], [dict(self.bodies[4][0], destination="foreign")], self.bodies[4] * 2):
            self.bodies[4] = value
            self.reject()

    def test_feature_flag_enabled_and_unique(self):
        for flags in ([], [{"name": "stream_queue", "state": "disabled"}], self.bodies[5] * 2, {}):
            self.bodies[5] = flags
            self.reject()

    def test_bad_http_status_and_redirect_never_read(self):
        for status in (301, 302, 307, 308, 400, 401, 403, 404, 500):
            response = Response("SYNTHETIC_SECRET", status=status)
            self.reject([response])
            self.assertTrue(response.closed)
            self.assertEqual(response.reads, 0)
            self.assertEqual(len(self.session.calls), 1)

    def test_response_bounds_and_strict_json(self):
        for response in (Response({}, raw=b"x" * (probe.MAX_BYTES + 1)),
                         Response({}, raw=b"{\"name\":1,\"name\":2}"), Response({}, raw=b"{\"x\":NaN}"),
                         Response({}, raw=b"\xff"), Response({}, headers={"Content-Type": "text/html"}),
                         Response({}, headers={"Content-Type": "application/json", "Content-Length": str(probe.MAX_BYTES + 1)})):
            self.reject([response])
            self.assertTrue(response.closed)

    def test_deadline_prevents_requests_and_discards_late_body(self):
        with patch.object(probe.time, "monotonic", side_effect=[0, 31]):
            self.reject()
        self.assertEqual(self.session.calls, [])
        with patch.object(probe.time, "monotonic", side_effect=[0, 1, 31]):
            self.reject()
        self.assertEqual(len(self.session.calls), 1)
        self.assertTrue(self.responses[0].closed)

    def test_transport_error_is_fixed_and_session_closed(self):
        with patch.object(Session, "get", side_effect=RuntimeError("SYNTHETIC_SECRET")):
            self.reject()


if __name__ == "__main__":
    unittest.main()
