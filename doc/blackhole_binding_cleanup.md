# Blackhole callback cleanup checkpoint

Recorded 2026-09-06. This is a source/replay and offline-test checkpoint, not a deployment or complete authentication/security acceptance claim.

## Source behavior

[bh_events.erl](../applications/blackhole/src/bh_events.erl) now retains the callback module and deduplicated listener requirements accepted for each exact `{ClientBinding, AMQPBindings}` subscription. Unsubscribe and close remove that original module's callback using the owning session ID/PID, instead of always attempting removal through `bh_events`.

The ownership map is a private field in [bh_context.erl](../applications/blackhole/src/bh_context.erl). It is neither populated from client JSON nor emitted in context JSON; client-controlled `metadata` is not used. The existing public binding-pair representation is unchanged.

- Exact duplicate subscriptions and absent/duplicate unsubscriptions do not change listener reference counts.
- Removing one binding retains listeners required by the session's remaining bindings. The existing listener server still owns cross-session reference counting.
- For the same recorded subscription key, later resolver changes to the callback module or listener list do not overwrite the original ownership. This does not promise migration when a resolver changes the AMQP subscription keys themselves.
- A context constructed without an ownership entry falls back to the default callback module. If a remaining binding lacks ownership information, its listeners are conservatively retained until close.

The change is reproducible from nested Blackhole revision `4e3f02a5ab01c09a44c287f4f93b15d2782f5614` through [blackhole-kazoo5-integration.patch](../scripts/patches/blackhole-kazoo5-integration.patch); the additive delta is [blackhole-binding-cleanup.patch](../scripts/patches/blackhole-binding-cleanup.patch). The installer's Blackhole patch-family handling recognizes prior redaction/frame states and validates the complete resulting aggregate before modifying the real source tree.

## ABI and rollout boundary

Appending `binding_resources` changes the private `bh_context` tuple size. Rebuild the coherent Blackhole application and perform a coordinated application/session restart; **do not directly hot-load this change into existing socket processes containing old-size contexts**. The conservative missing-map fixture uses a new-size context constructed with existing setters, not an old-tuple upgrade. This checkpoint provides no state-conversion or live-session rollback proof.

## Retained validation evidence

Root ran the following serialized validations; no deployment is represented by these results.

| Run | Result and retained evidence |
| --- | --- |
| `55325` | Initial fixture compilation failed: two missing tuple-closing braces at fixture lines 83 and 171. Production compilation had completed. Preserved at `/tmp/kazoo-blackhole-cleanup.qPaaqL/compile.log`; this is not a behavior-test pass or a before-fix regression proof. |
| `8279` | After those two fixture-only corrections, all **10 cleanup tests passed**, with fresh production compilation, no-DTEST/module-path checks, pinned replay and before/after dependency checks. Evidence: `/tmp/kazoo-blackhole-cleanup.K1n4Qf/`. |
| `73181` | All **46 source-transition cases passed**, including previous frame integration, cleanup-before-frame, partial-cleanup rejection and missing-cleanup-patch rejection. Evidence: `/tmp/kazoo-source-transition-tests.HCJE0a/results.log`. |
| `83107` | All **10 redaction/public-handler compatibility tests passed** against the updated replay. Evidence: `/tmp/kazoo-blackhole-redaction.y0qhRf/`. |

The [cleanup fixture](../scripts/erlang-tests/blackhole_binding_cleanup_tests.erl) exercises real callback/context code, the actual binding server and actual listener reference-count callbacks. It covers custom/default unsubscribe and close, resolver changes, duplicate/shared bindings, shared sessions, account separation, client metadata isolation and conservative fallback. Broker/configuration providers and listener transport are substituted: this is not a live AMQP, WebSocket, token-expiry or authorization certification.

Corrected cleanup fixture SHA256: `6d92fbe23e5d92b360584daf13298d343d53f300ed15cfc0e2205307d1deef07`. Reproduction entry points are [test-blackhole-binding-cleanup.sh](../scripts/test-blackhole-binding-cleanup.sh), [test-kazoo-source-transition.sh](../scripts/test-kazoo-source-transition.sh) and [test-blackhole-auth-redaction.sh](../scripts/test-blackhole-auth-redaction.sh); use the project's serialized validation guard, not concurrent ad-hoc execution.
