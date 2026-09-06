# Blackhole frame resilience: next-checkpoint proposal

Status, 2026-09-06: source-reviewed proposal only. The changes and tests below
are **not implemented or executed**. The current token-redaction checkpoint is
separate; it does not fix malformed-JSON handling, connection-lifetime token
expiry, or outbound backpressure. No live WebSocket acceptance is claimed here.

## Pinned source findings

Blackhole baseline is `4e3f02a5ab01c09a44c287f4f93b15d2782f5614`.
The current required `scripts/patches/blackhole-token-redaction.patch` removes
specific token/reason/unsupported-frame log sinks without changing dispatch.
Keep that checkpoint frozen until it is committed and its tests are reviewed.

Cowboy is pinned by `make/deps.mk` to `50c21ad`, locally resolved to
`50c21ad6b8170567b86b573b11fc95c38b58fb74` (Cowboy 2.12.0).
Relevant local source and documentation:

- `applications/blackhole/src/blackhole_socket_handler.erl`: successful
  `init_fold/4` supplies only `idle_timeout`; `websocket_handle/2` decodes text
  with `kz_json:decode/1`, then enters the ordinary callback pipeline.
- `core/kazoo_stdlib/src/kz_json.erl:301`: `unsafe_decode/2` wraps decoder
  failures as `invalid_json`. At line 324, the forgiving `decode/2` catches
  common invalid-JSON failures, logs the full original input and returns an
  empty object by default. Consequently malformed text can both expose a token
  in the decoder log and continue as a default `noop` request. This is not
  simply an uncaught-parser-exception finding.
- `deps/cowboy/doc/src/manual/cowboy_websocket.asciidoc:258`: the default
  `max_frame_size` is `infinity`; the limit includes reconstituted fragments.
- `deps/cowboy/src/cowboy_websocket.erl:445`: `parse_header/3` rejects a
  declared frame length above the limit before assembling its payload.
  `dispatch_frame/4`, at line 491, also checks accumulated fragment bytes.
  `websocket_send_close/2`, at line 657, maps `badsize` to close code 1009.
- `deps/cowboy/src/cowboy_websocket.erl:526`: a returned close frame terminates
  the handler through Cowboy's normal lifecycle. Blackhole `terminate/3`
  calls `blackhole_socket_callback:close/1`; the session-close binding invokes
  `bh_events:close/1` and `blackhole_tracking:remove_socket/1`. Tracking also
  has a process-monitor fallback. Cleanup must be tested, not inferred solely
  from these bindings.
- `applications/crossbar/priv/couchdb/schemas/system_config.blackhole.json`
  defines connection count, queued-message count and timeout settings, but no
  incoming frame-size setting.

## Proposed bounded change

Add `max_frame_size_bytes` to Blackhole system configuration, default 65,536
bytes and maximum 1,048,576 bytes. Use the raw configured value and accept
only an integer in the supported positive range. Missing, non-integer,
non-positive or excessive values fall back to the finite default, never
`infinity`. Apply it as Cowboy's `max_frame_size` option when each connection
is initialized; do not change existing idle timeout or enable compression.

A deliberately tiny positive administrator limit is a finite but potentially
unusable policy: even a one-byte limit rejects the smallest JSON object.
Document that tradeoff rather than describing every allowed setting as
compatible. The proposed default also introduces a compatibility boundary for
previously unbounded clients. Before deployment, exercise representative
subscribe/unsubscribe/ping and legacy `action: api` envelopes, including escaped
JSON in `data.body`, large subscription lists and encoded byte-length checks.
`applications/blackhole/src/bh_api.erl` forwards that body as an HTTP request;
fixtures must substitute that HTTP transport and must never contact Crossbar.
If real requirements exceed the default, select and test a finite configured
limit within the supported maximum. No production payload sampling is needed
or authorized by this proposal.

Replace only the text decoder boundary with a small helper using
`kz_json:unsafe_decode/1`. Catch its documented `invalid_json` failure shape
without logging the input or error term, then require `kz_json:is_json_object/1`
before invoking the existing callback. Do not wrap authentication, dispatch or
the whole handler in a catch-all: genuine application exceptions must retain
their existing failure behavior.

| Input | Proposed result |
| --- | --- |
| Valid JSON object within the limit | Existing callback and authorization pipeline |
| Malformed or empty JSON text | Close 1007 with a fixed, non-sensitive reason |
| Valid JSON that is not an object | Close 1003 with a fixed reason |
| Unsupported binary/application frame | Close 1003; never log its payload |
| Bare or payload-bearing ping/pong | Preserve control-frame behavior; no application dispatch |
| Individual or reconstituted frame above the limit | Cowboy close 1009 before application dispatch |

Cowboy already responds to ping payloads before calling the handler, so the
new unsupported-frame branch must explicitly preserve `{ping, Payload}` and
`{pong, Payload}`, not only the existing bare atoms. Return a close frame and
let Cowboy call `terminate/3`; do not invoke cleanup manually and then cause a
second lifecycle close. Close reasons, logs and error replies must not contain
input bytes, decoder reasons or credential-bearing nested terms.

The Blackhole and Crossbar trees are ignored nested source checkouts. Make the
implementation reproducible through pinned-source patches in kz5, without
nested Git commits. Because the socket hunks overlap, use one idempotent final
Blackhole integration patch against the pinned baseline; retain the earlier
redaction patch as review provenance if it is no longer applied independently.
Bind the schema patch to the pinned Crossbar source and preserve unrelated
aggregate hunks. Do not change those frozen artifacts during the current
redaction/docs checkpoint.

## Required offline evidence before deployment review

Prepare a retaining, pinned-source replay runner; compile only private BEAMs
without `TEST` defines. Serialize all execution under the approved resource
guard and a private network namespace. No installed dependency fetch, live
credentials, production socket, live API/RPC, or shared `ebin` writes.

1. Public-handler tests use the actual pinned Jiffy NIF for malformed input,
   empty input, trailing JSON/non-whitespace, whitespace suffixes, escaped
   quotes/backslashes, arrays, scalars and `null`. Do not mock decoding or
   assume `unsafe_decode` rejects trailing data without executing that case.
   Include a secret sentinel and inspect raw logger arguments and emitted
   bytes; rejected inputs must never enter authentication/command dispatch.
2. Positive fixtures retain object routing, authentication outcomes and both
   control-frame forms. A callback deliberately raising an application error
   must still raise, proving the decoder catch does not mask unrelated bugs.
   Check default/custom size settings and malformed configuration fallback.
3. A separate bounded socket smoke uses the existing Cowboy implementation on
   an ephemeral loopback listener inside the isolated namespace. Test exact
   boundary acceptance, oversized declared length without sending the full
   payload, final/intermediate fragmented overrun, fixed close codes and
   connection shutdown. Cowboy's existing `deps/cowboy/test/ws_SUITE.erl:438`
   supplies source-backed frame construction examples, not proof this task ran.
4. Exercise the real close callback with controlled binding/tracking fixtures;
   require one close invocation, removed session tracking and subscription
   cleanup after rejection. Keep provider substitutes explicit. Rerun the
   separate token-redaction tests against the final combined patch.
5. Retain failures, replay/compile logs and source/dependency hashes before and
   after. Keep source tests, private wire-level tests and live acceptance as
   distinct evidence scopes.

This is an inbound frame/application-parse boundary, not a hard bound on total
connection memory or CPU. TCP buffers, JSON expansion, outbound queues and
connection count remain separate concerns. Cowboy WebSocket compression is
currently disabled by default (`cowboy_websocket.erl:189`); HTTP response
compression in Blackhole startup does not itself enable WebSocket compression.
Any future WebSocket compression change needs an independent decompression
budget review. Cached-token expiry/revocation and backpressure remain open;
this proposal does not replace the native event server or redesign auth.

## Separate token-redaction checkpoint: verified offline

The preceding frame-hardening proposal is still unimplemented. The narrower
token-redaction patch passed session `86439` under the 180-second/384-MiB/
768-MiB-reserve guard in a private network namespace. Exact Blackhole baseline
replay matched the modified source, reverse/idempotence checks passed, and six
production modules compiled with `-Werror` and the production Lager transform.
A separate raw-logging compile exercised eight public-entry-point regression
groups, all passing: valid/invalid token outcomes, error frames, unchanged
authorized-context bypass, HTTP upgrade authentication and unsupported binary
frame logging. The auth validator and supporting providers were memory fixtures;
this is not real JWT, connection-lifetime or live WebSocket acceptance.

The tracked patch is `scripts/patches/blackhole-token-redaction.patch`, SHA-256
`e36ac18c19fa9b3f93302566dcd85363aab74da84f7c5ea07e33ef3b9d69323a`.
The installer pins Blackhole, checks the existing checkout identity and applies
this patch before building. No commit was made to the nested Blackhole repository.
Forty-eight source/dependency inputs, seven replay files and thirteen compiled
artifacts retained identical hashes. Thirty-one prebuilt dependency paths were
checked before/after; this does not rebuild all transitive dependencies.

Evidence is retained in `/tmp/kazoo-blackhole-redaction.p28u8e`; EUnit log SHA-256
`010ee25ec96fec20a4af987d4ad6c43bfdd97b43f8a22e9a983fb0bcbe5a6715`.
Earlier runs remain at `31KckI` (guard PATH lacked rg, before compilation) and
`KK59TH` (six passing/two failing tests because the logger metadata mock was
missing). Only the literal-search tool and metadata fixture/dependency pin were
corrected. No pre-fix negative run or live deployment is claimed.
