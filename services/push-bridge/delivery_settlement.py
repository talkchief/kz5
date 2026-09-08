"""Owner-thread ACK safety and opt-in verified-quorum permanent quarantine.

Workers receive only immutable message bodies, never AMQP message/channel
objects. Transient/uncertain results remain unacknowledged for explicit recovery.
Explicit retry mode only reschedules completed500/503 via counted broker NACK.
Reject sends a broker disposition,
not proof that the DLQ has already accepted the message; verified at-least-once
dead-letter topology owns retention until that durable transfer completes.
"""

from concurrent.futures import Future
import threading
import time
from push_payload import MAX_BODY_BYTES
from delivery_retry import MAX_DISPATCHES, DELAYS_MS, delivery_count, completed_transient
from freshness import Freshness, FreshnessFailure
from freshness_runtime import clocks


class SettlementFailure(RuntimeError):
    """Fixed failure category without provider exceptions or message content."""

    def __init__(self):
        super().__init__("push_delivery_unsettled")


class OwnerSettlements:
    def __init__(self, limit, quarantine=False, retry=False, clock=None,
                 delivery_timeout=60, deadline_clock=None):
        if type(limit) is not int or not 1 <= limit <= 128:
            raise ValueError("invalid_settlement_limit")
        if type(quarantine) is not bool:
            raise ValueError("invalid_quarantine_mode")
        if type(retry) is not bool or retry and not quarantine:
            raise ValueError("invalid_retry_mode")
        if clock is not None and not callable(clock):
            raise ValueError("invalid_retry_clock")
        if type(delivery_timeout) is not int or not 10 <= delivery_timeout <= 300:
            raise ValueError("invalid_delivery_timeout")
        if deadline_clock is not None and not callable(deadline_clock):
            raise ValueError("invalid_delivery_clock")
        self._deadline_clock = (lambda: time.monotonic_ns() // 1000000) if deadline_clock is None else deadline_clock
        self._delivery_timeout_ms = delivery_timeout * 1000
        self._last_deadline_time = None
        self._worker_deadlines = {}
        # Runtime enables this only after this connection's quorum-v1 topology
        # has been declared and independently verified, never from body/header.
        self._quarantine = quarantine
        self._retry = retry
        self._clock = clocks if clock is None else clock
        self._retry_states = {}
        self._owner = threading.get_ident()
        self._limit = limit
        self._active = True
        self._failed = False
        self._pending = {}

    def _check_owner(self):
        if threading.get_ident() != self._owner or not self._active:
            raise SettlementFailure()

    def _deadline_now(self):
        # Admission and elapsed time use only a private monotonic clock, never
        # producer timestamps, broker headers, wall time, or retry scheduling.
        try:
            now = self._deadline_clock()
            if (type(now) is not int or now < 0
                    or self._last_deadline_time is not None and now < self._last_deadline_time):
                raise ValueError()
        except Exception:
            self._failed = True
            raise SettlementFailure() from None
        self._last_deadline_time = now
        return now

    @property
    def pending_count(self):
        self._check_owner()
        return len(self._pending)

    def submit(self, executor, worker, message, body, provider=None, freshness=None):
        self._check_owner()
        if (self._failed or len(self._pending) >= self._limit
                or provider is not None and (type(provider) is not str or provider not in ("fcm", "apns"))):
            self._failed = True
            raise SettlementFailure()
        state = None
        if self._retry:
            try:
                count = delivery_count(message.properties, message.redelivered)
            except Exception:
                self._failed = True
                raise SettlementFailure() from None
            state = (count, freshness, None)
            outcome = None
            if count >= MAX_DISPATCHES:
                outcome = (False, 0, "push_retry_exhausted")
            elif type(freshness) is not Freshness:
                outcome = (False, 0, "push_freshness_invalid")
            else:
                try:
                    freshness.remaining_ms(**self._clock())
                except FreshnessFailure as error:
                    if error.code != "push_freshness_expired":
                        self._failed = True
                        raise SettlementFailure() from None
                    outcome = (False, 0, error.code)
                except Exception:
                    self._failed = True
                    raise SettlementFailure() from None
            if outcome is not None:
                future = Future()
                future.set_result(outcome)
                self._pending[future] = (message, provider)
                self._retry_states[future] = state
                return
        if not isinstance(body, (str, bytes)) or len(body) > MAX_BODY_BYTES:
            if not self._quarantine:
                self._failed = True
                raise SettlementFailure()
            # Preserve the same bounded pending/owner-drain path, with no
            # provider worker or a body copy in its Future. The original AMQP
            # message necessarily remains pending until the owner rejects it.
            future = Future()
            future.set_result((False, 0, "invalid_push_payload"))
            self._pending[future] = (message, provider)
            return
        try:
            deadline = self._deadline_now() + self._delivery_timeout_ms
            # Do not capture message in the submitted callable or a worker-side
            # done callback. Only the owning broker thread may settle delivery.
            future = executor.submit(worker, body)
        except Exception:
            self._failed = True
            raise SettlementFailure() from None
        self._pending[future] = (message, provider)
        self._worker_deadlines[future] = deadline
        if state is not None:
            self._retry_states[future] = state

    def _quarantinable(self, result, provider):
        if (not self._quarantine or type(result) is not tuple or len(result) != 3
                or result[0] is not False or type(result[1]) is not int
                or type(result[2]) is not str):
            return False
        if result[1] == 0:
            return (result[2] in ("invalid_push_payload", "push_freshness_invalid", "push_freshness_expired")
                    or self._retry and result[2] == "push_retry_exhausted"
                    or provider == "apns" and result[2] == "invalid_device_token")
        # These are current-request rejections, never a device-token deletion
        # instruction. APNs400 is deliberately excluded: it can mean IdleTimeout.
        # https://firebase.google.com/docs/cloud-messaging/error-codes
        # https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CommunicatingwithAPNs.html
        return result[2] == "provider_response" and (
            provider == "fcm" and result[1] in (400, 404)
            or provider == "apns" and result[1] in (410, 413))

    def _retry_action(self, future):
        count, lease, due = self._retry_states[future]
        if count >= MAX_DISPATCHES - 1:
            return "quarantine"
        now = self._clock()
        try:
            left = lease.remaining_ms(**now)
        except FreshnessFailure as error:
            if error.code == "push_freshness_expired":
                return "quarantine"
            raise SettlementFailure() from None
        if due is None:
            delay = DELAYS_MS[count]
            if left <= delay:
                return "quarantine"
            due = now["monotonic_ms"] + delay
            self._retry_states[future] = (count, lease, due)
        return "retry" if now["monotonic_ms"] >= due else "wait"

    def drain(self):
        self._check_owner()
        if self._failed:
            raise SettlementFailure()
        failed = False
        for future, (message, provider) in tuple(self._pending.items()):
            if not future.done():
                try:
                    if self._deadline_now() >= self._worker_deadlines[future]:
                        failed = True
                except Exception:
                    failed = True
                # Timeout proves neither acceptance nor absence of a send.
                # Keep this delivery unacknowledged; never retry/quarantine it.
                continue
            try:
                result = future.result()
                accepted = (type(result) is tuple and len(result) == 3
                            and result[0] is True and type(result[1]) is int
                            and result[1] == 200 and type(result[2]) is str
                            and result[2] == "provider_response")
            except BaseException:
                # A worker's SystemExit/KeyboardInterrupt is still a failed
                # worker result, not an instruction to interrupt this owner.
                accepted = False
                result = None
            quarantine = self._quarantinable(result, provider)
            retry = False
            if not accepted and not quarantine and self._retry and completed_transient(result, provider):
                try:
                    action = self._retry_action(future)
                except Exception:
                    failed = True
                    continue
                if action == "wait":
                    continue  # Prefetch slot remains owned; never sleep here.
                retry = action == "retry"
                quarantine = action == "quarantine"
            if not accepted and not quarantine and not retry:
                failed = True
                continue
            try:
                if retry:
                    message.nack(requeue=True)
                elif quarantine:
                    message.reject(requeue=False)
                else:
                    message.ack()
            except Exception:
                # ACK, NACK or reject exceptions are uncertain dispositions, not
                # proof that the broker received nothing. Never replay either.
                failed = True
                continue
            del self._pending[future]
            self._retry_states.pop(future, None)
            self._worker_deadlines.pop(future, None)
        if failed:
            self._failed = True
            raise SettlementFailure()

    def invalidate(self):
        self._check_owner()
        self._active = False
        # A disconnected generation must never ACK a later completion. Futures
        # do not hold message handles; the broker retains unsettled deliveries.
        self._pending.clear()
        self._retry_states.clear()
        self._worker_deadlines.clear()
