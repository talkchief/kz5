"""Read-only, startup-time proof for explicitly selected quorum topology.

No provider calls, broker writes, cached evidence or policy precedence guesses.
This is a point-in-time observation, not ongoing policy enforcement or a hard
wall-clock bound on platform DNS/TLS. Socket waits and response sizes are bounded.
"""
import ipaddress
import json
import time
from urllib.parse import quote, urlsplit


MAX_BYTES = 128 * 1024
PROBE_SECONDS = 30


class ManagementVerificationFailure(Exception):
    def __init__(self, phase="unknown", http_status=None):
        super().__init__("amqp_topology_not_verified")
        self.phase = phase if phase in ("preflight", "work_queue", "dead_queue", "dead_exchange",
                                       "ingress_exchange", "dead_bindings", "feature_flags", "policies",
                                       "operator_policies") else "unknown"
        self.http_status = http_status if type(http_status) is int and 100 <= http_status <= 599 else None


def _require(condition):
    if not condition:
        raise ManagementVerificationFailure()


def _base(settings):
    value = settings.get("AMQP_MANAGEMENT_URL", "")
    _require(isinstance(value, str) and 0 < len(value) <= 512)
    _require(all(32 < ord(c) < 127 for c in value))
    try:
        url = urlsplit(value)
        host, port = url.hostname, url.port
        _require(url.scheme in ("https", "http") and host and not url.username
                 and not url.password and not url.path and not url.query and not url.fragment
                 and (port is None or 1 <= port <= 65535))
        _require(isinstance(settings.get("AMQP_HOST"), str)
                 and host.lower() == settings["AMQP_HOST"].lower())
        if url.scheme == "http":
            try:
                loopback = ipaddress.ip_address(host).is_loopback
            except ValueError:
                loopback = host == "localhost"
            _require(loopback and not settings.get("AMQP_MANAGEMENT_CA_FILE"))
        _require("%" not in host and "\\" not in host)
    except ManagementVerificationFailure:
        raise
    except Exception:
        raise ManagementVerificationFailure() from None
    return value


def _object(pairs):
    value = {}
    for key, item in pairs:
        _require(key not in value)
        value[key] = item
    return value


def _redirect(response, *args, **kwargs):
    if 300 <= response.status_code < 400:
        response.close()
        raise ManagementVerificationFailure()
    return response


def _exact(actual, expected):
    # JSON booleans must not impersonate integer topology limits.
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return actual.keys() == expected.keys() and all(_exact(actual[k], v) for k, v in expected.items())
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(_exact(a, b) for a, b in zip(actual, expected))
    return actual == expected


def verify_topology(settings, plan):
    """Obtain fresh authenticated broker evidence; return exact True or fail.

    Management must refer to the same RabbitMQ cluster/vhost as AMQP. The
    hostname must match the AMQP host; different service ports still depend on
    the operator's same-cluster routing. Reuse of AMQP credentials requires management-read
    authorization. Remote HTTP, redirects and environment proxies are refused.
    """
    session = None
    phase, http_status = "preflight", None
    try:
        import requests
        base = _base(settings)
        _require(settings.get("TOPOLOGY") == "quorum-v1")
        for key in ("AMQP_USER", "AMQP_PASS", "AMQP_VHOST"):
            _require(isinstance(settings.get(key), str) and bool(settings[key]))
        session = requests.Session()
        session.trust_env = False
        session.proxies = {}
        deadline = time.monotonic() + PROBE_SECONDS
        vhost = settings["AMQP_VHOST"]
        vpath = quote(vhost, safe="")

        def get(resource):
            nonlocal http_status
            http_status = None
            remaining = deadline - time.monotonic()
            _require(remaining > 0)
            response = session.get(base + "/api/" + resource,
                auth=(settings["AMQP_USER"], settings["AMQP_PASS"]),
                headers={"Accept": "application/json"},
                timeout=(min(3.05, remaining), min(5, remaining)),
                verify=settings.get("AMQP_MANAGEMENT_CA_FILE") or True,
                allow_redirects=False, stream=True, hooks={"response": _redirect})
            try:
                http_status = response.status_code
                _require(response.status_code == 200)
                _require(response.headers.get("Content-Type", "").split(";", 1)[0].lower() == "application/json")
                declared = response.headers.get("Content-Length")
                if declared is not None:
                    _require(isinstance(declared, str) and declared.isascii() and declared.isdecimal()
                             and len(declared) <= 9 and int(declared) <= MAX_BYTES)
                body = bytearray()
                for chunk in response.iter_content(chunk_size=8192):
                    _require(time.monotonic() < deadline and isinstance(chunk, bytes))
                    _require(len(body) + len(chunk) <= MAX_BYTES)
                    body.extend(chunk)
                _require(time.monotonic() < deadline)
                return json.loads(body.decode("utf-8"), object_pairs_hook=_object,
                                  parse_constant=lambda _: _require(False))
            finally:
                response.close()

        # Queue statistics can lag both declaration and a policy change. These
        # endpoints query rabbit_policy directly, not the statistics cache.
        # V1 deliberately requires a policy-free vhost; no PCRE/precedence guesses.
        for endpoint, label in (("policies", "policies"), ("operator-policies", "operator_policies")):
            phase = label
            _require(_exact(get(endpoint + "/" + vpath), []))
        for name, arguments in ((plan.work_queue, dict(plan.work_arguments)),
                                (plan.dead_queue, dict(plan.dead_arguments))):
            phase = "work_queue" if name == plan.work_queue else "dead_queue"
            queue = get("queues/" + vpath + "/" + quote(name, safe=""))
            _require(isinstance(queue, dict) and queue.get("name") == name and queue.get("vhost") == vhost)
            _require(queue.get("type") == "quorum" and queue.get("durable") is True
                     and queue.get("auto_delete") is False and queue.get("exclusive") is False
                     and queue.get("state") == "running")
            _require(_exact(queue.get("arguments"), arguments))
            # Refuse policy-managed topology in this version rather than
            # silently miscompute operator-policy/client argument precedence.
            # Omitted statistics are allowed only after both fresh direct policy
            # lists proved empty. Present contradictory metadata still refuses.
            for field in ("policy", "operator_policy"):
                _require(queue.get(field) in (None, ""))
            _require("effective_policy_definition" not in queue
                     or _exact(queue["effective_policy_definition"], {}))
        for name, kind in ((plan.dead_exchange, "direct"), (plan.ingress_exchange, "topic")):
            phase = "dead_exchange" if name == plan.dead_exchange else "ingress_exchange"
            exchange = get("exchanges/" + vpath + "/" + quote(name, safe=""))
            _require(isinstance(exchange, dict) and exchange.get("name") == name
                     and exchange.get("vhost") == vhost and exchange.get("type") == kind
                     and exchange.get("durable") is True and exchange.get("auto_delete") is False
                     and exchange.get("internal") is False)
        phase = "dead_bindings"
        bindings = get("exchanges/" + vpath + "/" + quote(plan.dead_exchange, safe="") + "/bindings/source")
        _require(isinstance(bindings, list) and len(bindings) == 1)
        binding = bindings[0]
        _require(isinstance(binding, dict) and binding.get("source") == plan.dead_exchange
                 and binding.get("vhost") == vhost and binding.get("destination") == plan.dead_queue
                 and binding.get("destination_type") == "queue"
                 and binding.get("routing_key") == plan.dead_routing_key and binding.get("arguments") == {})
        phase = "feature_flags"
        flags = get("feature-flags")
        _require(isinstance(flags, list) and len(flags) <= 1024)
        required = [flag for flag in flags if isinstance(flag, dict) and flag.get("name") == "stream_queue"]
        _require(len(required) == 1 and required[0].get("state") == "enabled")
        return True
    except Exception:
        raise ManagementVerificationFailure(phase, http_status) from None
    finally:
        if session is not None:
            try:
                session.close()
            except Exception:
                pass
