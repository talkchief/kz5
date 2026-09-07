"""Pure explicit retry policy; no clocks, broker/provider I/O or mutable counts.

The RabbitMQ counter is admission evidence, not an exactly-once receipt. Actual
broker counter durability/semantics remain a release acceptance requirement.
"""

MODE = "quorum-counted-v1"
MAX_DISPATCHES = 3
DELAYS_MS = (2000, 5000)


class RetryMetadataFailure(ValueError):
    def __init__(self):
        super().__init__("push_retry_metadata_invalid")


def delivery_count(properties, redelivered):
    """Missing counter means zero ONLY on explicit first delivery.

    Do not use producer JSON, x-death, or a process-local retry counter. A
    redelivery lacking an exact positive integer counter must fail stopped.
    """
    if type(properties) is not dict or type(redelivered) is not bool:
        raise RetryMetadataFailure()
    headers = properties.get("headers")
    if headers is None:
        headers = {}
    if type(headers) is not dict or any(type(k) is not str for k in headers):
        raise RetryMetadataFailure()
    if "x-delivery-count" not in headers:
        if redelivered:
            raise RetryMetadataFailure()
        return 0
    count = headers["x-delivery-count"]
    if (type(count) is not int or not 0 <= count <= 2**63 - 1
            or redelivered != (count > 0)):
        raise RetryMetadataFailure()
    return count


def completed_transient(result, provider):
    """Only FCM500/503 with no Retry-After (guarded by transport).

    APNs/unknown/transport/timeout/auth/429 and header-directed backoff stop.
    """
    return (type(provider) is str and provider == "fcm"
            and type(result) is tuple and len(result) == 3
            and result[0] is False and type(result[1]) is int
            and result[1] in (500, 503) and type(result[2]) is str
            and result[2] == "provider_response")
