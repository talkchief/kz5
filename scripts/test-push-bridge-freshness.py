#!/usr/bin/env python3
"""Pure offline freshness boundaries: synthetic clocks, no I/O or providers."""

from dataclasses import FrozenInstanceError
from pathlib import Path
import sys
from types import MappingProxyType
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "services/push-bridge"
sys.path.insert(0, str(SOURCE))
import freshness
import validate_config as config


NOW = 1800000000000
MONO = 100000


def request(created=NOW, deadline=NOW + 60000):
    return {"Call-ID": "fixture-private-call", "Token-ID": "fixture-private-token",
            "Push-Freshness": {"version": 1, "created_at_ms": created, "deadline_ms": deadline}}


def capture(body=None, **clocks):
    return freshness.capture(request() if body is None else body, freshness.MODE,
                             **{"now_ms": NOW, "monotonic_ms": MONO, **clocks})


def environment():
    values = {"SA_FILE": "/fixture/nonexistent.json", "AMQP_HOST": "fixture.invalid",
              "AMQP_USER": "fixture", "AMQP_PASS": "fixture-private-secret", "AMQP_VHOST": "/fixture",
              "EXCHANGE": "fixture.pushes", "QUEUE": "fixture.quorum-v1", "BINDING_KEY": "notification.push.*",
              "FCM_SCOPE": config.FCM_SCOPE, "FCM_URL_TEMPLATE": config.FCM_URL,
              "TOPOLOGY": "quorum-v1", "AMQP_MANAGEMENT_URL": "https://fixture.invalid",
              "FRESHNESS": "unix-ms-v1"}
    return {config.PREFIX + key: value for key, value in values.items()}


class FreshnessTests(unittest.TestCase):
    def assertFailure(self, fn, code="push_freshness_invalid"):
        with self.assertRaises(freshness.FreshnessFailure) as caught:
            fn()
        self.assertEqual(caught.exception.code, code)
        self.assertEqual(str(caught.exception), code)
        self.assertNotIn("fixture-private", repr(caught.exception))

    def test_legacy_does_not_inspect_or_modify_inputs_or_require_clocks(self):
        class Uninspectable:
            def __getattribute__(self, _name): raise AssertionError("legacy inspected body")
        for body in (None, Uninspectable(), {}, {"Push-Freshness": "bad"}, request(deadline=NOW - 1)):
            self.assertIsNone(freshness.capture(body))
        body = request(); envelope = body["Push-Freshness"]
        self.assertIsNone(freshness.capture(body, now_ms="not a clock", monotonic_ms=None))
        self.assertIs(body["Push-Freshness"], envelope)

    def test_lifetime_bounds_expiry_equality_and_remaining_method(self):
        for lifetime in (1, 60000):
            lease = capture(request(deadline=NOW + lifetime))
            self.assertEqual(lease.remaining_ms(now_ms=NOW, monotonic_ms=MONO), lifetime)
            self.assertIs(lease.revalidate(now_ms=NOW, monotonic_ms=MONO), lease)
            self.assertEqual(lease.remaining_ms(now_ms=NOW + lifetime - 1,
                                                monotonic_ms=MONO + lifetime - 1), 1)
            self.assertFailure(lambda: lease.remaining_ms(now_ms=NOW + lifetime,
                                                          monotonic_ms=MONO + lifetime), "push_freshness_expired")
        for lifetime in (-1, 0, 60001):
            self.assertFailure(lambda: capture(request(deadline=NOW + lifetime)))
        self.assertFailure(lambda: capture(request(created=NOW - 60000, deadline=NOW)), "push_freshness_expired")
        self.assertFailure(lambda: capture(request(created=NOW - 60001, deadline=NOW - 1)), "push_freshness_expired")
        lease = capture(request(created=NOW - 59999, deadline=NOW + 1))
        self.assertEqual(lease.remaining_ms(now_ms=NOW, monotonic_ms=MONO), 1)

    def test_future_tolerance_never_adds_skew_to_allowed_lifetime(self):
        for ahead in (1, 4999, 5000):
            for lifetime in (1, 1000, 60000):
                lease = capture(request(created=NOW + ahead, deadline=NOW + ahead + lifetime))
                self.assertEqual(lease.remaining_ms(now_ms=NOW, monotonic_ms=MONO), lifetime)
                self.assertFailure(lambda: lease.remaining_ms(now_ms=NOW, monotonic_ms=MONO + lifetime),
                                   "push_freshness_expired")
        self.assertFailure(lambda: capture(request(created=NOW + 5001, deadline=NOW + 5002)))

    def test_wall_clock_rollback_cannot_extend_admitted_monotonic_life(self):
        lease = capture(request(created=NOW - 20000, deadline=NOW + 40000))
        self.assertEqual(lease.remaining_ms(now_ms=NOW - 3600000, monotonic_ms=MONO + 10000), 30000)
        self.assertEqual(lease.remaining_ms(now_ms=NOW - 1, monotonic_ms=MONO + 39999), 1)
        self.assertFailure(lambda: lease.remaining_ms(now_ms=NOW - 3600000, monotonic_ms=MONO + 40000),
                           "push_freshness_expired")
        self.assertFailure(lambda: lease.revalidate(now_ms=NOW - 3600000, monotonic_ms=MONO + 40001),
                           "push_freshness_expired")

    def test_forward_wall_clock_shortens_life_and_monotonic_regression_fails(self):
        lease = capture()
        self.assertEqual(lease.remaining_ms(now_ms=NOW + 59000, monotonic_ms=MONO + 1), 1000)
        self.assertFailure(lambda: lease.remaining_ms(now_ms=NOW + 60000, monotonic_ms=MONO + 1),
                           "push_freshness_expired")
        self.assertFailure(lambda: lease.remaining_ms(now_ms=NOW, monotonic_ms=MONO - 1))
        self.assertFailure(lambda: lease.revalidate(now_ms=NOW, monotonic_ms=MONO - 1))

    def test_missing_malformed_wrong_version_and_no_fallback_fields(self):
        for body in (None, [], "{}", b"{}", {}, {"Expires": NOW + 60000},
                     {"Timestamp-MS": NOW, "Payload": {"utc_unix_timestamp_ms": str(NOW)}},
                     {"headers": {"created_at_ms": NOW, "deadline_ms": NOW + 60000}}):
            self.assertFailure(lambda: freshness.capture(body, freshness.MODE, now_ms=NOW, monotonic_ms=MONO))
        for envelope in (None, [], "fixture-private-value", False, 1, MappingProxyType(request()["Push-Freshness"])):
            body = request(); body["Push-Freshness"] = envelope
            self.assertFailure(lambda: capture(body))
        for key in ("version", "created_at_ms", "deadline_ms"):
            body = request(); del body["Push-Freshness"][key]
            self.assertFailure(lambda: capture(body))
        body = request(); body["Push-Freshness"]["extra"] = True
        self.assertFailure(lambda: capture(body))
        for version in (None, False, True, 0, 2, "1", 1.0):
            body = request(); body["Push-Freshness"]["version"] = version
            self.assertFailure(lambda: capture(body))
        for mode in ("", "legacy", "UNIX-MS-V1", "v1", False, 1, {}):
            self.assertFailure(lambda: freshness.capture(request(), mode, now_ms=NOW, monotonic_ms=MONO))

    def test_strict_scalar_types_ranges_and_overloads_cannot_impersonate_metadata(self):
        class IntTrap(int):
            def __eq__(self, _other): raise AssertionError("overloaded integer equality")
        class StrTrap(str):
            def __eq__(self, _other): raise AssertionError("overloaded string equality")
            __hash__ = str.__hash__
        class DictTrap(dict):
            def get(self, *_args): raise AssertionError("overloaded dictionary")
        for field in ("created_at_ms", "deadline_ms"):
            for value in (None, True, False, str(NOW), float(NOW), -1,
                          freshness.MAX_SAFE_INTEGER + 1, float("nan"), float("inf"), IntTrap(NOW)):
                body = request(); body["Push-Freshness"][field] = value
                self.assertFailure(lambda: capture(body))
        body = request(); body["Push-Freshness"]["version"] = IntTrap(1)
        self.assertFailure(lambda: capture(body))
        self.assertFailure(lambda: capture(DictTrap(request())))
        body = request(); body["Push-Freshness"] = DictTrap(body["Push-Freshness"])
        self.assertFailure(lambda: capture(body))
        self.assertFailure(lambda: freshness.capture(request(), StrTrap(freshness.MODE), now_ms=NOW, monotonic_ms=MONO))
        body = {StrTrap("Push-Freshness"): request()["Push-Freshness"]}
        self.assertFailure(lambda: capture(body))

    def test_clock_inputs_are_exact_bounded_integers(self):
        lease = capture()
        for name in ("now_ms", "monotonic_ms"):
            for value in (None, True, False, "100000", 100000.0, -1, freshness.MAX_SAFE_INTEGER + 1):
                clocks = {"now_ms": NOW, "monotonic_ms": MONO, name: value}
                self.assertFailure(lambda: capture(**clocks))
                self.assertFailure(lambda: lease.remaining_ms(**clocks))
        maximum = freshness.MAX_SAFE_INTEGER
        lease = capture(request(created=maximum - 1, deadline=maximum), now_ms=maximum - 1)
        self.assertEqual(lease.remaining_ms(now_ms=maximum - 1, monotonic_ms=MONO), 1)

    def test_capture_is_detached_frozen_redacted_and_has_no_implicit_clock_or_io(self):
        body = request()
        with patch("time.time", side_effect=AssertionError("implicit wall clock")), \
                patch("time.time_ns", side_effect=AssertionError("implicit wall clock")), \
                patch("time.monotonic", side_effect=AssertionError("implicit monotonic clock")), \
                patch("time.monotonic_ns", side_effect=AssertionError("implicit monotonic clock")), \
                patch("builtins.open", side_effect=AssertionError("implicit file I/O")):
            lease = capture(body)
            lease.revalidate(now_ms=NOW + 1, monotonic_ms=MONO + 1)
        body["Push-Freshness"]["deadline_ms"] += 999999
        body["Push-Freshness"].clear(); body.clear()
        self.assertEqual((lease.version, lease.created_at_ms, lease.deadline_ms), (1, NOW, NOW + 60000))
        self.assertEqual(lease.remaining_ms(now_ms=NOW + 1, monotonic_ms=MONO + 1), 59999)
        self.assertEqual(repr(lease), "<Freshness unix-ms-v1 redacted>")
        for field in ("version", "created_at_ms", "deadline_ms", "_admitted_remaining_ms"):
            with self.assertRaises(FrozenInstanceError): setattr(lease, field, 999999)

    def test_config_is_explicit_quorum_only_and_no_tunable_lifetime_bypass(self):
        self.assertEqual(config.validate(environment()), ())
        candidate = environment(); del candidate[config.PREFIX + "FRESHNESS"]
        self.assertEqual(config.validate(candidate), ())
        for mode in (None, "legacy", ""):
            candidate = environment()
            if mode is None: del candidate[config.PREFIX + "TOPOLOGY"]
            else: candidate[config.PREFIX + "TOPOLOGY"] = mode
            self.assertIn("FRESHNESS:requires_quorum", config.validate(candidate))
        for mode in ("", "legacy", "false", "UNIX-MS-V1", "v2", None, True):
            candidate = environment(); candidate[config.PREFIX + "FRESHNESS"] = mode
            self.assertIn("FRESHNESS:invalid_mode", config.validate(candidate))
        for key in ("FRESHNESS_MAX_LIFETIME_MS", "FRESHNESS_ALLOW_MISSING", "FRESHNESS_FALLBACK"):
            candidate = environment(); candidate[config.PREFIX + key] = "fixture-private-value"
            self.assertIn("unknown_or_test_setting", config.validate(candidate))
            self.assertNotIn("fixture-private", repr(config.validate(candidate)))


if __name__ == "__main__":
    unittest.main()
