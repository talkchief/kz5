"""Owner-thread-only ACK safety; NOT a retry/dead-letter implementation.

Workers receive only immutable message bodies, never AMQP message/channel
objects. A failed/uncertain result is left unacknowledged for explicit recovery.
"""

import threading
from push_payload import MAX_BODY_BYTES


class SettlementFailure(RuntimeError):
    """Fixed failure category without provider exceptions or message content."""

    def __init__(self):
        super().__init__("push_delivery_unsettled")


class OwnerSettlements:
    def __init__(self, limit):
        if type(limit) is not int or not 1 <= limit <= 128:
            raise ValueError("invalid_settlement_limit")
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

    def submit(self, executor, worker, message, body):
        self._check_owner()
        if (self._failed or len(self._pending) >= self._limit
                or not isinstance(body, (str, bytes)) or len(body) > MAX_BODY_BYTES):
            self._failed = True
            raise SettlementFailure()
        try:
            # Do not capture message in the submitted callable or a worker-side
            # done callback. Only the owning broker thread may settle delivery.
            future = executor.submit(worker, body)
        except Exception:
            self._failed = True
            raise SettlementFailure() from None
        self._pending[future] = message

    def drain(self):
        self._check_owner()
        if self._failed:
            raise SettlementFailure()
        failed = False
        for future, message in tuple(self._pending.items()):
            if not future.done():
                continue
            try:
                result = future.result()
                accepted = (isinstance(result, tuple) and len(result) == 3
                            and result[0] is True and type(result[1]) is int
                            and result[1] == 200 and result[2] == "provider_response")
            except BaseException:
                # A worker's SystemExit/KeyboardInterrupt is still a failed
                # worker result, not an instruction to interrupt this owner.
                accepted = False
            if not accepted:
                failed = True
                continue
            try:
                message.ack()
            except Exception:
                # An ACK exception is an uncertain disposition, not proof that
                # the broker received nothing. Never retry that ACK blindly.
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
