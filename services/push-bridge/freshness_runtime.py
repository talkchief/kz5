"""Clock and bounded-body adapter for the pure versioned freshness contract."""

import time

from freshness import Freshness, FreshnessFailure, capture
from push_payload import InvalidPush, _object


def clocks():
    return {"now_ms": time.time_ns() // 1000000,
            "monotonic_ms": time.monotonic_ns() // 1000000}


def capture_body(body, mode):
    if mode is None or type(mode) is str and mode == "legacy":
        return None
    try:
        request = _object(body)
    except InvalidPush:
        raise FreshnessFailure() from None
    return capture(request, mode, **clocks())


def remaining(lease):
    if type(lease) is not Freshness:
        raise FreshnessFailure()
    return lease.remaining_ms(**clocks())
