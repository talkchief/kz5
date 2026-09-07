"""Pure opt-in producer freshness contract; no clocks, I/O or provider imports.

The caller supplies independently sampled Unix/monotonic milliseconds. Legacy
mode does not inspect the body. Strict mode never invents creation time from
arrival, Expires, AMQP timestamps or provider TTL. The lease is local admission
evidence, not durable state, call cancellation or proof of timely mobile display.
"""

from dataclasses import dataclass


MODE = "unix-ms-v1"
MAX_LIFETIME_MS = 60000
MAX_FUTURE_SKEW_MS = 5000
MAX_SAFE_INTEGER = 9007199254740991


class FreshnessFailure(ValueError):
    """Fixed categories only; never retain producer metadata or supplied text."""

    def __init__(self, expired=False):
        self.code = "push_freshness_expired" if expired else "push_freshness_invalid"
        super().__init__(self.code)


def _milliseconds(value):
    # Exact types exclude bool, float, integer subclasses and overloaded math.
    if type(value) is not int or not 0 <= value <= MAX_SAFE_INTEGER:
        raise FreshnessFailure()
    return value


@dataclass(frozen=True, repr=False, slots=True)
class Freshness:
    version: int
    created_at_ms: int
    deadline_ms: int
    _admitted_now_ms: int
    _admitted_monotonic_ms: int
    _admitted_remaining_ms: int

    def __repr__(self):
        return "<Freshness unix-ms-v1 redacted>"

    def remaining_ms(self, *, now_ms, monotonic_ms):
        """Remaining bounded life; raise at equality with either deadline.

        A forward wall-clock adjustment can shorten life. A rollback cannot
        extend it beyond the originally admitted monotonic budget. Monotonic
        clocks from another process/boot must not be substituted for this lease.
        """
        _milliseconds(now_ms)
        _milliseconds(monotonic_ms)
        elapsed = monotonic_ms - self._admitted_monotonic_ms
        if elapsed < 0:
            raise FreshnessFailure()
        remaining = min(self.deadline_ms - now_ms,
                        self._admitted_remaining_ms - elapsed)
        if remaining <= 0:
            raise FreshnessFailure(expired=True)
        return remaining

    def revalidate(self, *, now_ms, monotonic_ms):
        self.remaining_ms(now_ms=now_ms, monotonic_ms=monotonic_ms)
        return self


def capture(request, mode=None, *, now_ms=None, monotonic_ms=None):
    """Capture immutable scalar evidence from a bounded, decoded native body.

    Caller must reject duplicate JSON keys while decoding and enforce the
    existing native body-size limit. This function does not parse raw JSON or
    modify the request. A non-None mode must exactly match the supported mode.
    """
    if mode is None:
        return None
    if type(mode) is not str or mode != MODE:
        raise FreshnessFailure()
    _milliseconds(now_ms)
    _milliseconds(monotonic_ms)
    if type(request) is not dict or any(type(key) is not str for key in request):
        raise FreshnessFailure()
    envelope = request.get("Push-Freshness")
    if (type(envelope) is not dict or any(type(key) is not str for key in envelope)
            or set(envelope) != {"version", "created_at_ms", "deadline_ms"}
            or type(envelope["version"]) is not int or envelope["version"] != 1):
        raise FreshnessFailure()
    created = _milliseconds(envelope["created_at_ms"])
    deadline = _milliseconds(envelope["deadline_ms"])
    lifetime = deadline - created
    if not 1 <= lifetime <= MAX_LIFETIME_MS or created > now_ms + MAX_FUTURE_SKEW_MS:
        raise FreshnessFailure()
    # Tolerated future clock skew must not grant lifetime+skew milliseconds.
    remaining = min(deadline - now_ms, lifetime)
    if remaining <= 0:
        raise FreshnessFailure(expired=True)
    return Freshness(1, created, deadline, now_ms, monotonic_ms, remaining)
