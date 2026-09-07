# OAuth HTTP bounds and ownership candidate

Root acceptance September7: all103 bridge tests pass under the installed
pinned venv in a network-isolated guard `325b4d/session96820/c536f1`, including
all15 new OAuth cases; installer dispatch also passes. Main-SH deployment
`3f5035/session60404/aa39ab` installs release
`5d3745fd54bc8297f586c8ebb9c8e917de410957d9f02b6c04070c75997b5afa`.
Independent main-SH verification and the15 OAuth tests in the new venv pass
`67c5ba/session51989/a1b50e`. Service active/running PID301642, automatic
restarts0; all8 checked services active (`89bb9d`). Previous release retained.
No production operation or provider notification occurred. The scoped request
bounds below are deployed; total operation/deadline and real-delivery gates
remain OPEN. This supersedes only the editing-agent unexecuted status below.

The bridge now owns one reusable OAuth Requests session and one Google-auth
Request adapter for its lifetime. Every token HTTP request uses a 3.05-second
connect timeout and a 5-second read timeout, refuses redirects, and accepts at
most 65,536 decoded response bytes before Google-auth parses the response.
This is an HTTP-request bound, **not a total token-refresh, send, worker, or
shutdown deadline**.

Only source was edited for this handoff. No test, credential access, provider
request, deployment, commit, or operation against production 10.1.0.28 was
performed by the editing agent. Root must run the guarded offline suites before
accepting this candidate.

## Pinned source findings

The installed immutable release inspected was
`/usr/local/lib/kazoo-push-bridge/releases/c36d971f6f8a1630af942cc1e8b7ee51c3adced67d6d124c500caea329a04db2/venv`.
Its dependency pins are Google-auth 2.57.1, Requests 2.34.2 and urllib3 2.7.0,
matching `services/push-bridge/requirements.lock`. These locally installed
primary implementation files were read:

- `google/auth/transport/requests.py`: `Request.__call__` defaults to 120 seconds,
  forwards timeout to its supplied session, wraps the resulting response, and
  exposes response `.content` through `_Response.data`. `Request.__del__` closes
  even an explicitly supplied session.
- `google/oauth2/service_account.py` and `google/oauth2/_client.py`: the scoped
  service-account refresh uses the JWT grant, reads/parses the response body,
  and may repeat eligible token-endpoint responses with exponential backoff.
- `requests/sessions.py` and `requests/adapters.py`: response hooks precede
  redirect processing; `allow_redirects=False` alone can still prepare a next
  request and consume its body. The HTTP adapter translates a timeout tuple to
  urllib3's separate connect/read timeouts.
- `google/auth/_helpers.py`: optional response logging can parse response JSON,
  so the body cap must apply before the Google Request adapter receives it.

Previously, each refresh constructed a fresh Google Request with an implicitly
created session while holding the token lock. The new dedicated owner avoids
constructing a transport on each refresh. Passing an FCM worker's leased session
to Google Request would have given its destructor authority to close that lease;
the implementation uses a separate session instead.

## Request and response contract

`BoundedOAuthSession` is the session-shaped owner supplied to Google's real
Request adapter. It accepts only POST to
`https://oauth2.googleapis.com/token`, matching the service launcher's existing
service-account endpoint restriction. It rejects extra request overrides, and
enforces its timeout even if Google supplies the default 120 or a caller passes
`None`. Requests environment proxy/netrc behavior is disabled with `trust_env=False`.
TLS verification remains enabled.

Every request explicitly sets `stream=True`, `allow_redirects=False`, and an
OAuth-specific response hook. Every 300..399 response is closed and rejected
inside that hook before Requests can follow or prepare the redirect and before
its body is read. A redirect is not returned to Google's endpoint retry logic.
No assertion, token, or payload is forwarded to its Location target.

For other statuses, an oversized numeric Content-Length rejects the response
before reading its body. Missing, false or malformed lengths cannot bypass the
actual streamed-body check. Decoded data is read in 4,096-byte chunks and checked
against the 65,536-byte cap before accumulation; the single chunk that crosses
the limit is discarded. The resulting byte cache is provided to Google's pinned
response adapter only after it passes the cap. This also bounds the bytes exposed
to Google's optional response logger and JSON parser. Responses close in a
finally block after consumption or failure.

The cap is on decoded application response bytes, including gzip decoding. It
does not claim to bound all TLS, HTTP-header, Requests, urllib3 or decompressor
internal buffering. OAuth responses are expected to be small; a larger response
is a categorized failure rather than an implicit increase in the cap.

## Token caching, session leases and close

The existing token lock still serializes validity checks and refresh. A valid
cached token causes no OAuth HTTP request; later refreshes reuse the same Google
Request and session. The OAuth session is outside `_http_sessions` and `_idle_http`.
FCM worker-count capacity, exclusive leases, retry handling and lease return
semantics are unchanged.

The runtime's existing closing fence rejects new sends and defers HTTP cleanup
until its last active send completes. That cleanup now also closes the OAuth
owner. Its close is idempotent, so Google's later Request destructor cannot close
the underlying session twice. Its own lock prevents direct close from racing
an HTTP request. Startup failure while constructing the Google adapter closes
both newly created HTTP owners. Failure closing one transport does not skip
cleanup of the other.

OAuth transport errors are exposed as fixed categories:
`oauth_request_rejected`, `oauth_transport_closed`, `oauth_redirect_rejected`,
`oauth_response_too_large`, and `oauth_transport_error`. Other credential refresh
exceptions, including Google errors containing provider bodies, become
`oauth_refresh_error`. FCM send returns the category with status -1 and does not
perform its FCM retry for these OAuth failures. The bridge does not log the raw
refresh exception, provider URL, assertion or response body in that path.

## Limits that remain

A Requests read timeout is an inactivity timeout, not an absolute elapsed-time
budget. DNS resolution, connection attempts to multiple addresses, a slow stream
that continually produces data, Google-auth endpoint retries/backoff, token-lock
wait and session-close wait can make elapsed time exceed either timeout value.
This change does not disable or reimplement Google's endpoint retry policy.
It does not bound the total FCM two-attempt operation or broker settlement,
and it does not change the existing forced signal shutdown. A true operation
deadline/cancellation design remains separate work.

## Prepared offline verification

`scripts/test-push-bridge-oauth-transport.py` uses the installed pinned Google
service-account credential flow with a synthetic keyless Signer, the real Google
Request adapter, real Requests Session/Response handling, and a local adapter
fixture that cannot contact a provider. A separate case exercises the real
Requests HTTPAdapter down to a stubbed urllib3 connection to check timeout
translation. Gzip coverage uses the real installed urllib3 response decoder.
Tests verify redirects cannot cause a second outbound request or body read,
response caps, fixed errors, cached tokens, repeat/concurrent refresh behavior,
distinct session owners, Google-destructor idempotence, and deferred close during
an active refresh/send. Sockets are additionally forbidden in the fixtures;
run them within the normal network-isolated validation guard.

The existing `scripts/test-push-bridge-runtime.py` fixture now creates distinct
mock sessions per factory call, expects exactly the FCM and OAuth startup
sessions, and asserts cleanup/deferred cleanup for both. It still asserts no
startup refresh, network send or real credential read. FCM transport tests were
inspected and require no behavioral weakening or lease-policy changes.

Handoff status: prepared source and tests, not an executed pass. Run all existing
bridge tests plus the new OAuth suite with the installed venv before deployment;
retain exact resulting source pins and guarded test evidence.
