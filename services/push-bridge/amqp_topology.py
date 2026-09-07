"""Explicit versioned quorum topology, not delivery retry/freshness readiness.

Legacy declarations remain unchanged. Quorum activation requires a live broker
verifier on every connection; AMQP DeclareOk alone cannot verify effective
policies. This module never reads credentials or obtains evidence itself.
"""

from dataclasses import dataclass
from types import MappingProxyType

from validate_config import TOPOLOGY_LIMITS, topology_errors


class TopologyFailure(RuntimeError):
    def __init__(self):
        super().__init__("push_bridge_topology_unverified")


@dataclass(frozen=True, repr=False)
class TopologyPlan:
    work_queue: str
    dead_exchange: str
    dead_queue: str
    dead_routing_key: str
    ingress_exchange: str
    binding_key: str
    work_arguments: object
    dead_arguments: object

    def __repr__(self):
        return "<TopologyPlan quorum-v1 redacted>"


def plan(settings):
    """Construct a detached immutable plan from already validated settings."""
    if topology_errors(settings, set(settings)):
        raise TopologyFailure()
    if settings.get("TOPOLOGY", "legacy") == "legacy":
        return None
    limits = {key: int(settings.get(key, default))
              for key, (default, _low, _high) in TOPOLOGY_LIMITS.items()}
    queue = settings["QUEUE"]
    dead = {"x-queue-type": "quorum", "x-overflow": "reject-publish",
            "x-max-length": limits["TOPOLOGY_DLQ_MAX_MESSAGES"],
            "x-max-length-bytes": limits["TOPOLOGY_DLQ_MAX_BYTES"]}
    # RabbitMQ v3.13.7 rabbit_quorum_queue.erl capabilities/0 explicitly
    # supports x-dead-letter-strategy; dead_letter_handler/2 selects
    # at_least_once only with effective reject_publish. Its overflow policy
    # can override the argument, hence mandatory live policy verification.
    # https://github.com/rabbitmq/rabbitmq-server/blob/v3.13.7/deps/rabbit/src/rabbit_quorum_queue.erl
    work = {"x-queue-type": "quorum", "x-overflow": "reject-publish",
            "x-max-length": limits["TOPOLOGY_WORK_MAX_MESSAGES"],
            "x-max-length-bytes": limits["TOPOLOGY_WORK_MAX_BYTES"],
            "x-delivery-limit": 3, "x-message-ttl": 60000,
            "x-dead-letter-strategy": "at-least-once",
            "x-dead-letter-exchange": queue + ".dlx",
            "x-dead-letter-routing-key": "dead"}
    return TopologyPlan(queue, queue + ".dlx", queue + ".dlq", "dead",
                        settings["EXCHANGE"], settings["BINDING_KEY"],
                        MappingProxyType(work), MappingProxyType(dead))


def configure(connection, settings, channel_error, verify=None):
    """Declare and verify before ingress binding; return the owning channel.

    The injected verifier must fetch live broker evidence for this connection's
    configured broker and return exactly True. No saved evidence is accepted as
    a parameter here. The runtime supplies the production management verifier,
    not a configuration-selectable function. Checks are point-in-time only.
    """
    wanted = plan(settings)
    if wanted is None:
        channel = connection.channel()
        try:
            channel.exchange.declare(exchange=settings["EXCHANGE"], passive=True)
        except channel_error:
            channel = connection.channel()
            channel.exchange.declare(exchange=settings["EXCHANGE"], exchange_type="topic")
        channel.queue.declare(queue=settings["QUEUE"], durable=True)
        channel.queue.bind(queue=settings["QUEUE"], exchange=settings["EXCHANGE"],
                           routing_key=settings["BINDING_KEY"])
        return channel
    if not callable(verify):
        raise TopologyFailure()
    try:
        channel = connection.channel()
        # The source exchange belongs to the operator. Never create or change
        # it implicitly in the opt-in mode or delete/migrate a legacy queue.
        channel.exchange.declare(exchange=wanted.ingress_exchange, passive=True)
        channel.exchange.declare(exchange=wanted.dead_exchange, exchange_type="direct",
                                 durable=True, auto_delete=False)
        channel.queue.declare(queue=wanted.dead_queue, durable=True, exclusive=False,
                              auto_delete=False, arguments=dict(wanted.dead_arguments))
        channel.queue.bind(queue=wanted.dead_queue, exchange=wanted.dead_exchange,
                           routing_key=wanted.dead_routing_key)
        channel.queue.declare(queue=wanted.work_queue, durable=True, exclusive=False,
                              auto_delete=False, arguments=dict(wanted.work_arguments))
        if verify(settings, wanted) is not True:
            raise TopologyFailure()
        channel.queue.bind(queue=wanted.work_queue, exchange=wanted.ingress_exchange,
                           routing_key=wanted.binding_key)
        return channel
    except Exception:
        # No raw AMQP/HTTP exception can reveal broker credentials or contents.
        # Leave declared durable resources for explicit operator inspection.
        raise TopologyFailure() from None
