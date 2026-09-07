#!/usr/bin/python3
"""Parse the effective Kamailio URI from stdin; never emit credentials or URI."""
import ipaddress
import json
import re
import sys
from urllib.parse import unquote, urlsplit


def endpoint(uri):
    if not uri or len(uri) > 16384 or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in uri):
        raise ValueError()
    if re.search(r"%(?![0-9a-fA-F]{2})", uri) or any(c in uri for c in "\\\"'!?#"):
        raise ValueError()
    parsed = urlsplit(uri)
    if parsed.scheme not in ("amqp", "amqps") or not parsed.hostname or parsed.netloc.count("@") > 1:
        raise ValueError()
    host = parsed.hostname
    if ":" in host:
        host = str(ipaddress.IPv6Address(host))
        if "%" in host:
            raise ValueError()
    elif not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9.-]*", host):
        raise ValueError()
    if parsed.netloc.endswith(":"):
        raise ValueError()
    port = parsed.port if parsed.port is not None else (5671 if parsed.scheme == "amqps" else 5672)
    if not 1 <= port <= 65535 or (parsed.path and not re.fullmatch(r"/[^/]*", parsed.path)):
        raise ValueError()
    # The omitted vhost defaults to '/'; an explicit trailing slash means the
    # empty vhost. Decode exactly once (/%252F is the literal vhost '%2F').
    vhost = unquote(parsed.path[1:], errors="strict") if parsed.path else "/"
    if any(ord(c) < 32 or ord(c) == 127 for c in vhost):
        raise ValueError()
    return {"host": host, "port": port, "vhost": vhost,
            "protocol": "amqp/ssl" if parsed.scheme == "amqps" else "amqp"}


if __name__ == "__main__":
    try:
        result = endpoint(sys.stdin.read(16385))
    except (ValueError, UnicodeError):
        print("Invalid or unsupported effective Kamailio AMQP URI", file=sys.stderr)
        sys.exit(1)
    print(json.dumps(result, ensure_ascii=True))
