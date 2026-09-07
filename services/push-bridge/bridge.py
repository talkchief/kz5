#!/usr/bin/env python3
"""Sanitized internal push bridge import; see README before any activation."""

import json
import logging
import os
import signal
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import amqpstorm
import requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request as GoogleAuthRequest


def required(name):
    value = os.environ.get(name)
    if not value:
        raise ValueError("missing required environment variable: " + name)
    return value


SA_FILE = required("PUSH_BRIDGE_SA_FILE")
AMQP_HOST = required("PUSH_BRIDGE_AMQP_HOST")
AMQP_PORT = int(os.environ.get("PUSH_BRIDGE_AMQP_PORT", "5672"))
AMQP_USER = required("PUSH_BRIDGE_AMQP_USER")
AMQP_PASS = required("PUSH_BRIDGE_AMQP_PASS")
AMQP_VHOST = required("PUSH_BRIDGE_AMQP_VHOST")
WORKERS = int(os.environ.get("PUSH_BRIDGE_WORKERS", "32"))
STALL_TIMEOUT = int(os.environ.get("PUSH_BRIDGE_STALL_TIMEOUT", "70"))
APNS_WORKERS = int(os.environ.get("PUSH_BRIDGE_APNS_WORKERS", "8"))

# No deployment-specific exchange, queue, binding or provider endpoint defaults.
FCM_SCOPE = required("PUSH_BRIDGE_FCM_SCOPE")
EXCHANGE = required("PUSH_BRIDGE_EXCHANGE")
QUEUE = required("PUSH_BRIDGE_QUEUE")
BINDING_KEY = required("PUSH_BRIDGE_BINDING_KEY")
FCM_URL_TEMPLATE = required("PUSH_BRIDGE_FCM_URL_TEMPLATE")

APNS_TOKEN_TYPES = ("apple", "apns", "ios")
APNS_DEV_TOKEN_TYPES = ("apple_dev", "apple_sandbox")
RECONNECT_DELAY = 5
HEARTBEAT = 30

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stdout)
log = logging.getLogger("push_bridge")

credentials = service_account.Credentials.from_service_account_file(SA_FILE, scopes=[FCM_SCOPE])
PROJECT_ID = credentials.project_id
FCM_URL = FCM_URL_TEMPLATE.format(project_id=PROJECT_ID)

http = requests.Session()
_token_lock = threading.Lock()
_stop = threading.Event()
_last_progress = time.time()
_conn = None


def mark_progress():
    global _last_progress
    _last_progress = time.time()


def start_self_watchdog():
    """Preserved broker-loop watchdog; it does not prove delivery progress."""
    def loop():
        while not _stop.wait(5):
            stalled = time.time() - _last_progress
            if stalled > STALL_TIMEOUT:
                log.error("broker_loop_stalled seconds=%.1f", stalled)
                os._exit(1)
    threading.Thread(target=loop, name="push-watchdog", daemon=True).start()


def get_access_token():
    with _token_lock:
        if not credentials.valid:
            credentials.refresh(GoogleAuthRequest())
        return credentials.token


def send_fcm(token_id, data):
    message = {
        "message": {
            "token": token_id,
            "android": {"priority": "HIGH", "ttl": "60s"},
            "data": {k: str(v) for k, v in data.items() if v is not None},
        },
    }
    last_status, last_text = 0, ""
    for attempt in (1, 2):
        try:
            resp = http.post(
                FCM_URL,
                headers={"Authorization": "Bearer {}".format(get_access_token())},
                json=message,
                timeout=5,
            )
            # Provider response text is deliberately not retained or logged.
            last_status, last_text = resp.status_code, "provider_response"
            if resp.status_code == 200:
                return True, last_status, last_text
            if resp.status_code < 500:
                return False, last_status, last_text
        except requests.RequestException:
            last_status, last_text = -1, "provider_transport_error"
        if attempt == 1 and not _stop.is_set():
            time.sleep(0.5)
    return False, last_status, last_text


_apns_senders = {}
_apns_lock = threading.Lock()
_apns_failed = set()


def get_apns_sender(sandbox):
    env = "dev" if sandbox else "prod"
    if env in _apns_senders:
        return _apns_senders[env]
    if env in _apns_failed:
        return None
    with _apns_lock:
        if env not in _apns_senders and env not in _apns_failed:
            try:
                import apns_sender as mod
                if sandbox:
                    _apns_senders[env] = mod.ApnsSender(key_file=mod.KEY_FILE_DEV, key_id=mod.KEY_ID_DEV)
                else:
                    _apns_senders[env] = mod.ApnsSender()
            except Exception:
                _apns_failed.add(env)
                log.error("apns_initialization_failed environment=%s", env)
    return _apns_senders.get(env)


def build_apns_payload(data):
    import uuid
    call_id = data.get("call_id")
    if call_id:
        bucket = "%s:%d" % (call_id, int(time.time()) // 60)
        call_uuid = str(uuid.uuid5(uuid.NAMESPACE_URL, bucket))
    else:
        call_uuid = str(uuid.uuid4())
    payload = {k: v for k, v in data.items() if v is not None}
    payload["call_uuid"] = call_uuid
    return payload


def deliver_apns(req, token_id, sandbox):
    sender = get_apns_sender(sandbox)
    if sender is None:
        return
    payload = build_apns_payload(build_data(req))
    ok, status, _text = sender.send(token_id, payload, sandbox=sandbox)
    if ok:
        log.info("apns_delivery_accepted")
    elif status in (400, 403, 410):
        log.warning("apns_delivery_rejected status=%s", status)
    else:
        log.error("apns_delivery_failed status=%s", status)


def build_data(req):
    payload = req.get("Payload") or {}
    if isinstance(payload, str):
        try:
            payload = json.loads(payload)
        except ValueError:
            payload = {"raw": payload}
    return {
        "type": "sip_incoming_call",
        "call_id": payload.get("call-id") or req.get("Call-ID"),
        "caller_id_number": payload.get("caller-id-number"),
        "caller_id_name": payload.get("caller-id-name"),
        "registration_token": payload.get("registration-token"),
        "proxy": payload.get("proxy"),
    }


def deliver(raw_body):
    try:
        req = json.loads(raw_body)
    except (ValueError, TypeError):
        log.warning("invalid_push_json")
        return
    token_id = req.get("Token-ID")
    token_type = req.get("Token-Type", "")
    if not token_id:
        log.warning("missing_push_token")
        return
    normalized = str(token_type).lower()
    if normalized in APNS_TOKEN_TYPES or normalized in APNS_DEV_TOKEN_TYPES:
        deliver_apns(req, token_id, sandbox=normalized in APNS_DEV_TOKEN_TYPES)
        return
    if token_type and normalized not in ("firebase", "android", "fcm"):
        log.info("unsupported_push_token_type")
        return
    data = build_data(req)
    ok, status, _text = send_fcm(token_id, data)
    if ok:
        log.info("fcm_delivery_accepted")
    elif status in (400, 404):
        log.warning("fcm_delivery_rejected status=%s", status)
    else:
        log.error("fcm_delivery_failed status=%s", status)


def run():
    global _conn
    pool = ThreadPoolExecutor(max_workers=WORKERS)
    apns_pool = ThreadPoolExecutor(max_workers=APNS_WORKERS)
    mark_progress()
    start_self_watchdog()

    def on_message(message):
        def work():
            try:
                deliver(message.body)
            finally:
                # Imported behavior, NOT accepted reliability semantics:
                # provider failures are acknowledged, not redelivered.
                try:
                    message.ack()
                except Exception:
                    pass

        target = pool
        try:
            req = json.loads(message.body)
            if str(req.get("Token-Type", "")).lower() in (APNS_TOKEN_TYPES + APNS_DEV_TOKEN_TYPES):
                target = apns_pool
        except Exception:
            pass
        target.submit(work)

    while not _stop.is_set():
        connection = None
        try:
            connection = amqpstorm.Connection(AMQP_HOST, AMQP_USER, AMQP_PASS, port=AMQP_PORT,
                virtual_host=AMQP_VHOST, heartbeat=HEARTBEAT, timeout=10)
            _conn = connection
            channel = connection.channel()
            try:
                channel.exchange.declare(exchange=EXCHANGE, passive=True)
            except amqpstorm.AMQPChannelError:
                channel = connection.channel()
                channel.exchange.declare(exchange=EXCHANGE, exchange_type="topic")
            channel.queue.declare(queue=QUEUE, durable=True)
            channel.queue.bind(queue=QUEUE, exchange=EXCHANGE, routing_key=BINDING_KEY)
            channel.basic.qos(prefetch_count=WORKERS * 2)
            channel.basic.consume(on_message, queue=QUEUE, no_ack=False)
            log.info("consumer_started workers=%d apns_workers=%d", WORKERS, APNS_WORKERS)
            while not _stop.is_set() and channel.is_open:
                channel.process_data_events(to_tuple=False)
                mark_progress()
                time.sleep(0.5)
        except Exception:
            if not _stop.is_set():
                log.error("amqp_loop_failed reconnect_seconds=%d", RECONNECT_DELAY)
                mark_progress()
                _stop.wait(RECONNECT_DELAY)
        finally:
            try:
                if connection and connection.is_open:
                    connection.close()
            except Exception:
                pass
    pool.shutdown(wait=False)
    apns_pool.shutdown(wait=False)


def _handle_term(*_):
    log.info("shutdown_requested")
    _stop.set()
    try:
        if _conn and _conn.is_open:
            _conn.close()
    except Exception:
        pass
    threading.Timer(3, lambda: os._exit(0)).start()


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--test":
        # Existing explicit provider-test mode retained, without embedded
        # caller identities or endpoints. Never run this during offline QA.
        okd, st, _tx = send_fcm(sys.argv[2], json.loads(required("PUSH_BRIDGE_TEST_PAYLOAD_JSON")))
        print("test_result", okd, st)
        sys.exit(0 if okd else 1)
    signal.signal(signal.SIGTERM, _handle_term)
    signal.signal(signal.SIGINT, _handle_term)
    run()
