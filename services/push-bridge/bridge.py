#!/usr/bin/env python3
"""Sanitized internal push bridge candidate; NOT activation-ready (see README)."""

import json
import logging
import os
import re
import signal
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from push_payload import InvalidPush, apns_payload, normalize
from validate_config import NUMBERS, PREFIX, validate
from delivery_settlement import OwnerSettlements, SettlementFailure


RECONNECT_DELAY = 5
HEARTBEAT = 30
log = logging.getLogger("push_bridge")


class BridgeRuntime:
    """Explicit startup owns dependencies, credential I/O and mutable state.

    Importing this module does none of these things. Construct only inside a
    sanitized startup boundary; this remains the unaccepted delivery engine.
    """

    def __init__(self, environment):
        # Validate and initialize from one snapshot, not a live mutable environ.
        environment = dict(environment)
        if validate(environment):
            raise ValueError("invalid_bridge_configuration")
        # Third-party imports and credential loading happen only after the
        # complete environment has passed offline validation.
        import amqpstorm
        import requests
        from google.oauth2 import service_account
        from google.auth.transport.requests import Request as GoogleAuthRequest

        self.amqpstorm = amqpstorm
        self.requests = requests
        self.google_request = GoogleAuthRequest
        self._settings = {key[len(PREFIX):]: value for key, value in environment.items()
                          if isinstance(key, str) and key.startswith(PREFIX)}
        for name, (default, _low, _high) in NUMBERS.items():
            self._settings[name] = int(self._settings.get(name, default))
        self.credentials = service_account.Credentials.from_service_account_file(
            self._settings["SA_FILE"], scopes=[self._settings["FCM_SCOPE"]])
        project = self.credentials.project_id
        if not isinstance(project, str) or not re.fullmatch(r"[a-z][a-z0-9-]{4,28}[a-z0-9]", project):
            raise ValueError("invalid_fcm_project")
        self.fcm_url = self._settings["FCM_URL_TEMPLATE"].format(project_id=project)
        self._token_lock = threading.Lock()
        self._stop = threading.Event()
        self._last_progress = time.monotonic()
        self._conn = None
        self._apns_senders = {}
        self._apns_lock = threading.Lock()
        self._apns_failed = set()
        self._lifecycle_lock = threading.Lock()
        self._active_sends = 0
        self._closing = False
        self._http_closed = False
        # Last startup operation: later failures in main always close it.
        self.http = requests.Session()

    def mark_progress(self):
        self._last_progress = time.monotonic()

    def start_self_watchdog(self):
        """Preserved broker-loop watchdog; it does not prove delivery progress."""
        def loop():
            while not self._stop.wait(5):
                stalled = time.monotonic() - self._last_progress
                if stalled > self._settings["STALL_TIMEOUT"]:
                    log.error("broker_loop_stalled seconds=%.1f", stalled)
                    os._exit(1)
        threading.Thread(target=loop, name="push-watchdog", daemon=True).start()

    def get_access_token(self):
        with self._token_lock:
            if not self.credentials.valid:
                self.credentials.refresh(self.google_request())
            return self.credentials.token

    def send_fcm(self, token_id, data):
        with self._lifecycle_lock:
            if self._closing:
                return False, 0, "bridge_closing"
            self._active_sends += 1
        try:
            return self._send_fcm(token_id, data)
        finally:
            with self._lifecycle_lock:
                self._active_sends -= 1
                close_http = self._closing and self._active_sends == 0 and not self._http_closed
                if close_http:
                    self._http_closed = True
            if close_http:
                self._close_http()

    def _send_fcm(self, token_id, data):
        message = {
            "message": {
                "token": token_id,
                "android": {"priority": "HIGH", "ttl": "60s"},
                "data": {key: str(value) for key, value in data.items() if value is not None},
            },
        }
        last_status, last_text = 0, ""
        for attempt in (1, 2):
            try:
                response = self.http.post(
                    self.fcm_url,
                    headers={"Authorization": "Bearer {}".format(self.get_access_token())},
                    json=message, timeout=5,
                )
                try:
                    last_status, last_text = response.status_code, "provider_response"
                    if response.status_code == 200:
                        return True, last_status, last_text
                    if response.status_code < 500:
                        return False, last_status, last_text
                finally:
                    response.close()
            except self.requests.RequestException:
                last_status, last_text = -1, "provider_transport_error"
            if attempt == 1 and not self._stop.is_set():
                self._stop.wait(0.5)
        return False, last_status, last_text

    def get_apns_sender(self, sandbox):
        environment = "dev" if sandbox else "prod"
        if environment in self._apns_senders:
            return self._apns_senders[environment]
        if environment in self._apns_failed:
            return None
        with self._apns_lock:
            if environment not in self._apns_senders and environment not in self._apns_failed:
                try:
                    from apns_sender import ApnsSender
                    key_file = self._settings.get("APNS_KEY_FILE")
                    key_id = self._settings.get("APNS_KEY_ID")
                    if sandbox:
                        key_file = self._settings.get("APNS_KEY_FILE_DEV", key_file)
                        key_id = self._settings.get("APNS_KEY_ID_DEV", key_id)
                    self._apns_senders[environment] = ApnsSender(
                        key_file=key_file, key_id=key_id,
                        team_id=self._settings.get("APNS_TEAM_ID"),
                        topic=self._settings.get("APNS_TOPIC"),
                        host_prod=self._settings.get("APNS_HOST_PROD"),
                        host_dev=self._settings.get("APNS_HOST_DEV"),
                    )
                except Exception:
                    self._apns_failed.add(environment)
                    log.error("apns_initialization_failed environment=%s", environment)
        return self._apns_senders.get(environment)

    def deliver_apns(self, push):
        sender = self.get_apns_sender(push.sandbox)
        if sender is None:
            return False, 0, "apns_initialization_failed"
        result = sender.send(push.token_id, apns_payload(push), sandbox=push.sandbox)
        ok, status, _text = result
        if ok:
            log.info("apns_delivery_accepted")
        elif status in (400, 403, 410):
            log.warning("apns_delivery_rejected status=%s", status)
        else:
            log.error("apns_delivery_failed status=%s", status)
        return result

    def deliver(self, raw_body):
        try:
            push = normalize(raw_body)
        except InvalidPush:
            log.warning("invalid_push_payload")
            return False, 0, "invalid_push_payload"
        if push.provider == "apns":
            return self.deliver_apns(push)
        result = self.send_fcm(push.token_id, push.data)
        ok, status, _text = result
        if ok:
            log.info("fcm_delivery_accepted")
        elif status in (400, 404):
            log.warning("fcm_delivery_rejected status=%s", status)
        else:
            log.error("fcm_delivery_failed status=%s", status)
        return result

    def run(self):
        settings = self._settings
        pool = ThreadPoolExecutor(max_workers=settings["WORKERS"])
        apns_pool = ThreadPoolExecutor(max_workers=settings["APNS_WORKERS"])
        self.mark_progress()
        self.start_self_watchdog()

        try:
            while not self._stop.is_set():
                connection = None
                settlements = None
                generation = {"settlements": None, "failed": False}

                def on_message(message, generation=generation):
                    # Bind this dictionary to the callback's generation. A late
                    # callback from a closed channel cannot use its successor's
                    # settlement controller or acquire a new worker slot.
                    if generation["failed"]:
                        return
                    try:
                        body = message.body
                        target = pool
                        try:
                            if normalize(body).provider == "apns":
                                target = apns_pool
                        except InvalidPush:
                            pass
                        generation["settlements"].submit(target, self.deliver, message, body)
                    except Exception:
                        # Libraries may catch callback exceptions internally;
                        # retain a fixed owner-loop failure instead of relying
                        # on exception propagation or logging a raw traceback.
                        generation["failed"] = True

                try:
                    connection = self.amqpstorm.Connection(
                        settings["AMQP_HOST"], settings["AMQP_USER"], settings["AMQP_PASS"],
                        port=settings["AMQP_PORT"], virtual_host=settings["AMQP_VHOST"],
                        heartbeat=HEARTBEAT, timeout=10)
                    channel = connection.channel()
                    self._conn = connection
                    try:
                        channel.exchange.declare(exchange=settings["EXCHANGE"], passive=True)
                    except self.amqpstorm.AMQPChannelError:
                        channel = connection.channel()
                        channel.exchange.declare(exchange=settings["EXCHANGE"], exchange_type="topic")
                    channel.queue.declare(queue=settings["QUEUE"], durable=True)
                    channel.queue.bind(queue=settings["QUEUE"], exchange=settings["EXCHANGE"],
                                       routing_key=settings["BINDING_KEY"])
                    limit = settings["WORKERS"] * 2
                    settlements = OwnerSettlements(limit)
                    generation["settlements"] = settlements
                    channel.basic.qos(prefetch_count=limit)
                    channel.basic.consume(on_message, queue=settings["QUEUE"], no_ack=False)
                    from service_notify import notify_consumer_ready
                    notify_consumer_ready()
                    log.info("consumer_started workers=%d apns_workers=%d",
                             settings["WORKERS"], settings["APNS_WORKERS"])
                    while not self._stop.is_set() and channel.is_open:
                        settlements.drain()
                        channel.process_data_events(to_tuple=False)
                        if generation["failed"]:
                            raise SettlementFailure()
                        # Even a completed provider acceptance cannot be ACKed
                        # through a channel that disappeared during dispatch.
                        if not channel.is_open and settlements.pending_count:
                            raise SettlementFailure()
                        settlements.drain()
                        self.mark_progress()
                        self._stop.wait(0.5)
                    if not self._stop.is_set() and settlements.pending_count:
                        raise SettlementFailure()
                except SettlementFailure:
                    self._stop.set()
                    raise
                except Exception:
                    # Do not replay an uncertain generation while its workers
                    # can still reach providers. No unconditional requeue or
                    # automatic reconnect is safe for these pending messages.
                    if settlements is not None and settlements.pending_count:
                        self._stop.set()
                        raise SettlementFailure() from None
                    if not self._stop.is_set():
                        log.error("amqp_loop_failed reconnect_seconds=%d", RECONNECT_DELAY)
                        self.mark_progress()
                        self._stop.wait(RECONNECT_DELAY)
                finally:
                    from service_notify import notify_status
                    notify_status(False)
                    if settlements is not None:
                        settlements.invalidate()
                    try:
                        if connection and connection.is_open:
                            connection.close()
                    except Exception:
                        pass
        finally:
            pool.shutdown(wait=False)
            apns_pool.shutdown(wait=False)

    def handle_term(self, *_):
        log.info("shutdown_requested")
        self._stop.set()
        try:
            if self._conn and self._conn.is_open:
                self._conn.close()
        except Exception:
            pass
        threading.Timer(3, lambda: os._exit(0)).start()

    def close(self):
        # shutdown(wait=False) leaves workers in flight. Do not close their
        # session underneath them or allow queued work to start a new send.
        # This fence does not wait for workers or implement delivery recovery.
        self._stop.set()
        with self._lifecycle_lock:
            self._closing = True
            close_http = self._active_sends == 0 and not self._http_closed
            if close_http:
                self._http_closed = True
        if close_http:
            self._close_http()

    def _close_http(self):
        try:
            self.http.close()
        except Exception:
            log.error("bridge_http_close_failed")


def main(argv=None, environment=None):
    if argv is None:
        argv = sys.argv[1:]
    if environment is None:
        environment = os.environ
    runtime = None
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stdout)
    try:
        if argv:
            if len(argv) != 2 or argv[0] != "--test":
                print("usage: bridge.py [--test DEVICE_TOKEN]", file=sys.stderr)
                return 2
            # Explicit REAL-send compatibility mode. Test payload is the native
            # Payload object, not arbitrary provider data; normalize before I/O.
            test_payload = environment.get("PUSH_BRIDGE_TEST_PAYLOAD_JSON")
            raw = json.dumps({"Token-ID": argv[1], "Payload": test_payload})
            normalize(raw)
            service_environment = dict(environment)
            service_environment.pop("PUSH_BRIDGE_TEST_PAYLOAD_JSON", None)
            runtime = BridgeRuntime(service_environment)
            ok, status, _text = runtime.deliver(raw)
            print("test_result", ok, status)
            return 0 if ok else 1
        runtime = BridgeRuntime(environment)
        signal.signal(signal.SIGTERM, runtime.handle_term)
        signal.signal(signal.SIGINT, runtime.handle_term)
        runtime.run()
        return 0
    except SettlementFailure:
        log.error("push_delivery_unsettled_manual_recovery_required")
        # A future service unit must prevent automatic restarts for this status
        # until durable bounded retry/dead-letter policy is implemented.
        return 78
    except Exception:
        log.error("bridge_startup_or_runtime_failed")
        return 2
    finally:
        if runtime is not None:
            try:
                runtime.close()
            except Exception:
                log.error("bridge_close_failed")


if __name__ == "__main__":
    sys.exit(main())
