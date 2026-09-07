#!/usr/bin/env python3
"""Offline import/startup and native payload tests; no real credentials or I/O."""

import builtins
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import sys
import threading
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import Mock, call, patch


SOURCE = Path(__file__).resolve().parents[1] / "services/push-bridge"
sys.path.insert(0, str(SOURCE))
import bridge
import apns_sender
import push_payload
import validate_config


def wire(**overrides):
    request = {
        "Event-Category": "notification", "Event-Name": "push_req",
        "Account-ID": "fixture-account", "Call-ID": "fixture-call",
        "Token-ID": "fixture-token", "Token-Type": "fcm",
        "Payload": {"call-id": "fixture-call", "caller-id-number": "+15550000123",
                    "caller-id-name": "Fixture Caller", "registration-token": "fixture-registration",
                    "proxy": "sip:proxy.example.invalid:5060"},
    }
    request.update(overrides)
    return json.dumps(request)


def environment():
    values = {
        "SA_FILE": "/fixture/nonexistent.json", "AMQP_HOST": "broker.example.invalid",
        "AMQP_USER": "fixture", "AMQP_PASS": "fixture-secret", "AMQP_VHOST": "/fixture",
        "EXCHANGE": "pushes", "QUEUE": "fixture", "BINDING_KEY": "notification.push.*",
        "FCM_SCOPE": validate_config.FCM_SCOPE, "FCM_URL_TEMPLATE": validate_config.FCM_URL,
    }
    return {validate_config.PREFIX + key: value for key, value in values.items()}


def dependencies(project="fixture-project"):
    modules = {name: ModuleType(name) for name in (
        "amqpstorm", "requests", "google", "google.oauth2", "google.oauth2.service_account",
        "google.auth", "google.auth.transport", "google.auth.transport.requests")}
    credentials = SimpleNamespace(project_id=project, valid=True, token="fixture-access-token", refresh=Mock())
    loader = Mock(return_value=credentials)
    modules["google.oauth2.service_account"].Credentials = SimpleNamespace(from_service_account_file=loader)
    modules["google.oauth2"].service_account = modules["google.oauth2.service_account"]
    modules["google.auth.transport.requests"].Request = Mock()
    # Runtime owns separate FCM and OAuth sessions; never alias both owners.
    modules["requests"].Session = Mock(side_effect=lambda: Mock())
    modules["requests"].RequestException = RuntimeError
    return modules, loader, credentials


class PayloadTests(unittest.TestCase):
    def invalid(self, raw):
        with self.assertRaises(push_payload.InvalidPush) as error:
            push_payload.normalize(raw)
        self.assertEqual(str(error.exception), "invalid_push_payload")

    def test_preserves_all_native_mobile_fields_and_string_payload(self):
        expected = {
            "type": "sip_incoming_call", "call_id": "fixture-call",
            "caller_id_number": "+15550000123", "caller_id_name": "Fixture Caller",
            "registration_token": "fixture-registration", "proxy": "sip:proxy.example.invalid:5060",
        }
        push = push_payload.normalize(wire())
        self.assertEqual(dict(push.data), expected)
        request = json.loads(wire())
        request["Payload"] = json.dumps(request["Payload"])
        self.assertEqual(dict(push_payload.normalize(json.dumps(request)).data), expected)
        with self.assertRaises(TypeError):
            push.data["call_id"] = "mutation"
        self.assertEqual(repr(push), "<NormalizedPush redacted>")

    def test_all_imported_provider_aliases_and_default_route(self):
        for token_type in push_payload.FCM_TYPES:
            self.assertEqual(push_payload.normalize(wire(**{"Token-Type": token_type.upper()})).provider, "fcm")
        request = json.loads(wire())
        del request["Token-Type"]
        self.assertEqual(push_payload.normalize(json.dumps(request)).provider, "fcm")
        for token_type in push_payload.APNS_TYPES | push_payload.APNS_DEV_TYPES:
            push = push_payload.normalize(wire(**{"Token-Type": token_type.upper(), "Token-ID": "app.prefix:" + "AB" * 32}))
            self.assertEqual(push.provider, "apns")
            self.assertEqual(push.sandbox, token_type in push_payload.APNS_DEV_TYPES)
            self.assertEqual(push.token_id, "ab" * 32)

    def test_uuid_stable_across_retries_minutes_display_and_token_changes(self):
        with patch("time.time", return_value=59):
            first = push_payload.normalize(wire())
        request = json.loads(wire())
        request["Token-ID"] = "other-fixture-token"
        request["Payload"]["caller-id-name"] = "Different display name"
        request["Payload"]["utc_unix_timestamp_ms"] = 900000
        with patch("time.time", return_value=900):
            repeated = push_payload.normalize(json.dumps(request, sort_keys=True))
        self.assertEqual(first.call_uuid, repeated.call_uuid)
        self.assertEqual(push_payload.apns_payload(first)["call_uuid"], first.call_uuid)
        self.assertNotEqual(first.call_uuid, push_payload.normalize(wire(**{"Account-ID": "other-account"})).call_uuid)
        self.assertNotEqual(first.call_uuid, push_payload.normalize(wire(**{"Call-ID": "other-call", "Payload": {"call-id": "other-call"}})).call_uuid)

    def test_missing_optional_fields_and_top_level_call_id(self):
        push = push_payload.normalize(wire(Payload=None))
        self.assertEqual(push.data["call_id"], "fixture-call")
        self.assertIsNone(push.data["caller_id_name"])
        self.assertNotIn("caller_id_name", push_payload.apns_payload(push))
        self.invalid(wire(**{"Call-ID": None, "Payload": {}}))
        self.invalid(wire(**{"Call-ID": "conflicting-call"}))

    def test_malformed_json_duplicate_keys_nonobjects_depth_and_utf8(self):
        for raw in (None, 123, [], {}, "[]", "null", "false", "1", "{", b"\xff",
                    '{"Token-ID":"a","Token-ID":"b"}', '{"extra":NaN}',
                    '{"a":' + '[' * 2000 + '0' + ']' * 2000 + '}'):
            self.invalid(raw)
        for value in ([], 42, False, "[]", "null", "{", '{"call-id":"a","call-id":"b"}'):
            self.invalid(wire(Payload=value))

    def test_strict_types_events_tokens_and_unicode_lengths(self):
        for name, value in (("Token-Type", {}), ("Token-Type", None), ("Token-Type", "unknown"),
                            ("Token-ID", 42), ("Token-ID", "bad token"), ("Token-ID", ""),
                            ("Event-Category", "other"), ("Event-Name", "endpoint_push_req"),
                            ("Account-ID", ["bad"]), ("Call-ID", "bad\nvalue")):
            self.invalid(wire(**{name: value}))
        for token in ("", "a", "ab" * 257, "gh" * 32, " :" + "ab" * 32, "a:b:" + "ab" * 32, ["bad"]):
            self.invalid(wire(**{"Token-Type": "apple", "Token-ID": token}))
            self.assertIsNone(apns_sender.ApnsSender.normalize_token(token))
        for field in push_payload.FIELDS:
            for value in ([], 3, True, "bad\nvalue", "bad\u0085value", "\ud800"):
                request = json.loads(wire())
                request["Payload"][field] = value
                self.invalid(json.dumps(request))
        request = json.loads(wire())
        request["Payload"]["caller-id-name"] = "é" * 128
        self.assertEqual(push_payload.normalize(json.dumps(request)).data["caller_id_name"], "é" * 128)
        request["Payload"]["caller-id-name"] += "é"
        self.invalid(json.dumps(request))

    def test_opaque_token_compatibility_does_not_assume_one_device_length_or_alphabet(self):
        for token in ("AB", "AB" * 32, "AB" * 33, "AB" * 256):
            push = push_payload.normalize(wire(**{"Token-Type": "apple", "Token-ID": token}))
            self.assertEqual(push.token_id, token.lower())
        for token in ("opaque+token/with=padding", "opaque:token-with_parts", 'opaque"token\\punctuation'):
            self.assertEqual(push_payload.normalize(wire(**{"Token-ID": token})).token_id, token)

    def test_wire_and_data_bounds(self):
        self.invalid(" " * (push_payload.MAX_BODY_BYTES + 1))
        request = json.loads(wire())
        request["extra"] = "é" * 17000
        self.invalid(json.dumps(request, ensure_ascii=False))
        request = json.loads(wire())
        for field, (_target, maximum) in push_payload.FIELDS.items():
            request["Payload"][field] = "\\" * maximum
        self.invalid(json.dumps(request))
        request = json.loads(wire())
        request["Token-ID"] = "x" * 4097
        self.invalid(json.dumps(request))


class RuntimeTests(unittest.TestCase):
    def test_imports_do_not_read_environment_credentials_start_threads_or_providers(self):
        code = {name: compile((SOURCE / (name + ".py")).read_text(), str(SOURCE / (name + ".py")), "exec")
                for name in ("bridge", "apns_sender")}
        original_import = builtins.__import__

        def guarded_import(name, *args, **kwargs):
            if name.split(".")[0] in ("requests", "amqpstorm", "google", "ecdsa", "h2"):
                raise AssertionError("provider import at module load")
            return original_import(name, *args, **kwargs)

        class ForbiddenEnvironment:
            def __getitem__(self, _key):
                raise AssertionError("environment read at module load")
            get = __getitem__

        with patch("builtins.__import__", side_effect=guarded_import), \
                patch("builtins.open", side_effect=AssertionError("credential I/O at module load")), \
                patch.object(os, "environ", ForbiddenEnvironment()), \
                patch.object(socket, "create_connection", side_effect=AssertionError("network at module load")), \
                patch.object(threading.Thread, "start", side_effect=AssertionError("thread at module load")):
            for name, compiled in code.items():
                exec(compiled, {"__name__": "offline_" + name})

    def test_bad_config_fails_before_any_provider_import(self):
        original_import = builtins.__import__
        imports = []
        def capture(name, *args, **kwargs):
            imports.append(name)
            return original_import(name, *args, **kwargs)
        with patch("builtins.__import__", side_effect=capture):
            with self.assertRaisesRegex(ValueError, "^invalid_bridge_configuration$"):
                bridge.BridgeRuntime({})
            with self.assertRaisesRegex(ValueError, "^invalid_apns_configuration$"):
                apns_sender.ApnsSender()
        self.assertEqual(imports, [])

    def test_explicit_runtime_loads_once_does_not_refresh_or_connect_until_send(self):
        modules, loader, credentials = dependencies()
        with patch.dict(sys.modules, modules), patch("builtins.open", side_effect=AssertionError("real file access")):
            runtime = bridge.BridgeRuntime(environment())
        loader.assert_called_once_with("/fixture/nonexistent.json", scopes=[validate_config.FCM_SCOPE])
        self.assertEqual(modules["requests"].Session.call_args_list, [call(), call()])
        modules["google.auth.transport.requests"].Request.assert_called_once_with(session=runtime._oauth_session)
        self.assertIsNot(runtime.http, runtime._oauth_session._session)
        self.assertEqual(runtime._http_sessions, [runtime.http])
        credentials.refresh.assert_not_called()
        self.assertEqual(runtime.fcm_url, "https://fcm.googleapis.com/v1/projects/fixture-project/messages:send")
        runtime.http.post.assert_not_called()
        runtime._oauth_session._session.request.assert_not_called()
        self.assertFalse(runtime._stop.is_set())
        self.assertIsNone(runtime._conn)
        runtime.close()
        runtime.http.close.assert_called_once_with()
        runtime._oauth_session._session.close.assert_called_once_with()

    def test_runtime_initializes_only_from_the_validated_configuration_snapshot(self):
        proposed = environment()
        original_validate = bridge.validate
        def validate_then_mutate_input(snapshot):
            result = original_validate(snapshot)
            proposed["PUSH_BRIDGE_SA_FILE"] = "/unvalidated/changed.json"
            proposed["PUSH_BRIDGE_FCM_URL_TEMPLATE"] = "https://unvalidated.invalid/{project_id}"
            return result
        modules, loader, _credentials = dependencies()
        with patch.dict(sys.modules, modules), patch.object(bridge, "validate", side_effect=validate_then_mutate_input):
            runtime = bridge.BridgeRuntime(proposed)
        loader.assert_called_once_with("/fixture/nonexistent.json", scopes=[validate_config.FCM_SCOPE])
        self.assertEqual(runtime.fcm_url, "https://fcm.googleapis.com/v1/projects/fixture-project/messages:send")
        runtime.close()

    def test_tls_port_defaults_and_explicit_port_are_preserved(self):
        for tls, explicit_port, expected in ((None, None, 5672), ("false", None, 5672),
                                             ("true", None, 5671), ("true", "15671", 15671),
                                             ("true", "5672", 5672)):
            proposed = environment()
            if tls is not None:
                proposed["PUSH_BRIDGE_AMQP_TLS"] = tls
            if explicit_port is not None:
                proposed["PUSH_BRIDGE_AMQP_PORT"] = explicit_port
            modules, _, _ = dependencies()
            with patch.dict(sys.modules, modules):
                runtime = bridge.BridgeRuntime(proposed)
            self.assertEqual(runtime._settings["AMQP_PORT"], expected)
            self.assertEqual(bool(runtime._amqp_tls_options), tls == "true")
            runtime.close()

    def test_close_defers_session_cleanup_until_inflight_send_finishes_and_is_idempotent(self):
        modules, _loader, _credentials = dependencies()
        with patch.dict(sys.modules, modules):
            runtime = bridge.BridgeRuntime(environment())
        def in_flight(_token, _data):
            runtime.close()
            runtime.close()
            runtime.http.close.assert_not_called()
            runtime._oauth_session._session.close.assert_not_called()
            self.assertEqual(runtime.send_fcm("queued-fixture", {}), (False, 0, "bridge_closing"))
            return True, 200, "provider_response"
        with patch.object(runtime, "_send_fcm", side_effect=in_flight):
            self.assertEqual(runtime.send_fcm("fixture", {}), (True, 200, "provider_response"))
        runtime.http.close.assert_called_once_with()
        runtime._oauth_session._session.close.assert_called_once_with()
        runtime.close()
        runtime.http.close.assert_called_once_with()
        runtime._oauth_session._session.close.assert_called_once_with()
        self.assertEqual(runtime._active_sends, 0)

    def test_inflight_send_exception_still_releases_deferred_session_without_logging_secret(self):
        modules, _loader, _credentials = dependencies()
        with patch.dict(sys.modules, modules):
            runtime = bridge.BridgeRuntime(environment())
        def in_flight(_token, _data):
            runtime.close()
            raise RuntimeError("fixture-provider-secret")
        with patch.object(runtime, "_send_fcm", side_effect=in_flight):
            with self.assertRaises(RuntimeError):
                runtime.send_fcm("fixture", {})
        runtime.http.close.assert_called_once_with()
        runtime._oauth_session._session.close.assert_called_once_with()
        self.assertEqual(runtime._active_sends, 0)

    def test_credential_project_cannot_change_fcm_endpoint(self):
        for project in (None, "../escape", "x/y", "bad?query", "UPPERCASE", "tiny"):
            modules, _loader, _credentials = dependencies(project)
            with patch.dict(sys.modules, modules):
                with self.assertRaisesRegex(ValueError, "^invalid_fcm_project$"):
                    bridge.BridgeRuntime(environment())
            modules["requests"].Session.assert_not_called()

    def test_apns_configuration_is_explicit_and_sandbox_overrides_are_forwarded(self):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._settings = {"APNS_KEY_FILE": "/fixture/main.p8", "APNS_KEY_ID": "ABCDEFGHIJ",
                             "APNS_KEY_FILE_DEV": "/fixture/dev.p8", "APNS_KEY_ID_DEV": "KLMNOPQRST",
                             "APNS_TEAM_ID": "0123456789", "APNS_TOPIC": "invalid.example.fixture",
                             **validate_config.APNS_HOSTS}
        runtime._apns_senders = {}
        runtime._apns_failed = set()
        runtime._apns_lock = threading.Lock()
        with patch.object(apns_sender, "ApnsSender") as factory:
            runtime.get_apns_sender(False)
            runtime.get_apns_sender(True)
            self.assertEqual(factory.call_args_list[0].kwargs["key_file"], "/fixture/main.p8")
            self.assertEqual(factory.call_args_list[1].kwargs["key_file"], "/fixture/dev.p8")
            self.assertEqual(factory.call_args_list[1].kwargs["key_id"], "KLMNOPQRST")
            self.assertEqual(factory.call_args_list[1].kwargs["host_dev"], "api.sandbox.push.apple.com")
            self.assertEqual(factory.call_args_list[1].kwargs["team_id"], "0123456789")
            runtime.get_apns_sender(True)
            self.assertEqual(factory.call_count, 2)

    def test_apns_oversized_or_invalid_body_is_rejected_before_socket(self):
        sender = apns_sender.ApnsSender.__new__(apns_sender.ApnsSender)
        sender._host_prod = validate_config.APNS_HOSTS["APNS_HOST_PROD"]
        sender._open = Mock(side_effect=AssertionError("socket must not open"))
        for payload in (None, [], {"x": "x" * 4096}, {"x": float("nan")}, {"x": "\ud800"}):
            self.assertEqual(sender.send("ab" * 32, payload), (False, 0, "invalid_push_payload"))
        sender._open.assert_not_called()

    def test_delivery_normalizes_before_provider_calls_and_preserves_results(self):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._settings = {}
        runtime.send_fcm = Mock(return_value=(True, 200, "provider_response"))
        runtime.deliver_apns = Mock(return_value=(False, 503, "provider_response"))
        self.assertEqual(runtime.deliver(wire()), (True, 200, "provider_response"))
        data = runtime.send_fcm.call_args.args[1]
        self.assertEqual(data["registration_token"], "fixture-registration")
        self.assertEqual(runtime.deliver(wire(**{"Token-Type": "apple_dev", "Token-ID": "ab" * 32})),
                         (False, 503, "provider_response"))
        self.assertTrue(runtime.deliver_apns.call_args.args[0].sandbox)
        runtime.send_fcm.reset_mock()
        runtime.deliver_apns.reset_mock()
        with self.assertLogs("push_bridge", level="WARNING") as messages:
            self.assertEqual(runtime.deliver('{"secret":"fixture-secret"}'), (False, 0, "invalid_push_payload"))
        self.assertNotIn("fixture", " ".join(messages.output))
        runtime.send_fcm.assert_not_called()
        runtime.deliver_apns.assert_not_called()

    def test_startup_and_test_entrypoints_redact_failures_before_network(self):
        with self.assertLogs("push_bridge", level="ERROR") as messages:
            self.assertEqual(bridge.main([], {}), 2)
            self.assertEqual(bridge.main(["--test", "fixture-token"], {"PUSH_BRIDGE_TEST_PAYLOAD_JSON": "fixture-secret"}), 2)
        self.assertNotIn("fixture", " ".join(messages.output))
        with self.assertLogs("push_bridge.apns", level="ERROR") as messages:
            self.assertEqual(apns_sender.main(["ab" * 32], {"PUSH_BRIDGE_TEST_PAYLOAD_JSON": "fixture-secret"}), 2)
        self.assertNotIn("fixture", " ".join(messages.output))
        with patch.object(bridge, "BridgeRuntime", side_effect=RuntimeError("fixture-secret")), \
                self.assertLogs("push_bridge", level="ERROR") as messages:
            self.assertEqual(bridge.main([], environment()), 2)
        self.assertNotIn("fixture", " ".join(messages.output))


if __name__ == "__main__":
    unittest.main()
