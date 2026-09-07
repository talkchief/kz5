"""Owner-thread ACK safety and opt-in verified-quorum permanent quarantine.

Workers receive only immutable message bodies, never AMQP message/channel
objects. Transient/uncertain results remain unacknowledged for explicit recovery.
There is no retry or freshness policy here. Reject sends a broker disposition,
not proof that the DLQ has already accepted the message; verified at-least-once
dead-letter topology owns retention until that durable transfer completes.
"""

from concurrent.futures import Future
import threading
from push_payload import MAX_BODY_BYTES


class SettlementFailure(RuntimeError):
    """Fixed failure category without provider exceptions or message content."""

    def __init__(self):
        super().__init__("push_delivery_unsettled")


class OwnerSettlements:
    def __init__(self, limit, quarantine=False):
        if type(limit) is not int or not 1 <= limit <= 128:
            raise ValueError("invalid_settlement_limit")
        if type(quarantine) is not bool:
            raise ValueError("invalid_quarantine_mode")
        # Runtime enables this only after this connection's quorum-v1 topology
        # has been declared and independently verified, never from body/header.
        self._quarantine = quarantine
        self._owner = threading.get_ident()
        self._limit = limit
        self._active = True
        self._failed = False
        self._pending = {}

    def _check_owner(self):
        if threading.get_ident() != self._owner or not self._active:
            raise SettlementFailure()

    @property
    def pending_count(self):
        self._check_owner()
        return len(self._pending)

    def submit(self, executor, worker, message, body, provider=None):
        self._check_owner()
        if (self._failed or len(self._pending) >= self._limit
                or provider is not None and (type(provider) is not str or provider not in ("fcm", "apns"))):
            self._failed = True
            raise SettlementFailure()
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
            # Do not capture message in the submitted callable or a worker-side
            # done callback. Only the owning broker thread may settle delivery.
            future = executor.submit(worker, body)
        except Exception:
            self._failed = True
            raise SettlementFailure() from None
        self._pending[future] = (message, provider)

    def _quarantinable(self, result, provider):
        if (not self._quarantine or type(result) is not tuple or len(result) != 3
                or result[0] is not False or type(result[1]) is not int
                or type(result[2]) is not str):
            return False
        if result[1] == 0:
            return (result[2] in ("invalid_push_payload", "push_freshness_invalid", "push_freshness_expired")
                    or provider == "apns" and result[2] == "invalid_device_token")
        # These are current-request rejections, never a device-token deletion
        # instruction. APNs400 is deliberately excluded: it can mean IdleTimeout.
        # https://firebase.google.com/docs/cloud-messaging/error-codes
        # https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CommunicatingwithAPNs.html
        return result[2] == "provider_response" and (
            provider == "fcm" and result[1] in (400, 404)
            or provider == "apns" and result[1] in (410, 413))

    def drain(self):
        self._check_owner()
        if self._failed:
            raise SettlementFailure()
        failed = False
        for future, (message, provider) in tuple(self._pending.items()):
            if not future.done():
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
            if not accepted and not quarantine:
                failed = True
                continue
            try:
                if quarantine:
                    message.reject(requeue=False)
                else:
                    message.ack()
            except Exception:
                # ACK or reject exceptions are uncertain dispositions, not
                # proof that the broker received nothing. Never replay either.
                failed = True
                continue
            del self._pending[future]
        if failed:
            self._failed = True
            raise SettlementFailure()

    def invalidate(self):
        self._check_owner()
        self._active = False
        # A disconnected generation must never ACK a later completion. Futures
        # do not hold message handles; the broker retains unsettled deliveries.
        self._pending.clear()
