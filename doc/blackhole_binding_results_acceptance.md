# Blackhole context result classification regression

Status: production-source correction with offline classifier evidence, not live
authorization or deployment acceptance. Parent task: BH-02.

Both `kazoo_bindings:failed/2` and `succeeded/2` retain values whose predicate
returns true. Blackhole's context branches supplied the opposite predicates:
`failed` retained successful contexts and `succeeded` retained failed contexts.
This affected both direct contexts and singleton context wrappers.

The correction changes exactly four context predicates in
`applications/blackhole/src/blackhole_bindings.erl`. Boolean, halt, exit and
event-map handling is unchanged. In a callback stage returning both a successful
and denied context, the old classification could select the successful context
from the failed-result list. The public-pipeline tests below also verify that
the corrected classification prevents downstream command execution with fixture
providers.

## Reproduction and correction

The same six test groups were run before and after the production change:

| Evidence | Before, session 54566 | After, session 18786 |
| --- | --- | --- |
| Result | Five failures, one existing-behavior control passed | All six groups passed |
| Private directory | `/tmp/kazoo-blackhole-bindings.Ugd3Sl` | `/tmp/kazoo-blackhole-bindings.m15EnJ` |
| EUnit log SHA-256 | `882a17890d09e2c266d9a300ee9e4fd547cbc4b3fc9c7bf8223e890c72294aff` | `32b2ba6514d355a61da6438e4ed2bfacdf698263603b6c4b674292ff515d170f` |

Each run used the validation guard: 384 MiB memory, 768 MiB reserve, 60-second
runtime and a private network namespace. Two actual production modules were
freshly compiled with warnings as errors, without TEST or export_all. Tests
checked loaded paths for these modules and five runtime dependencies. Selected
source/header/dependency hashes were verified before and after execution; this
is not a claim of complete transitive toolchain hermeticity.

- Corrected production source SHA-256:
  `5943b5c32c74b9137a3ee02c347fa725bc30eb56abc6ffc8a6d9f90ab20eda24`.
- Runner `scripts/test-blackhole-binding-results.sh` SHA-256:
  `35c94fca3171ead9b1ea42631d50f12f450bce43d5ec51e4185d8bb8b03f37e8`.
- Fixture `scripts/erlang-tests/blackhole_binding_results_tests.erl` SHA-256:
  `547096c30ff0bb18ed804278af132c8ae92e8b74fa69308c9abea12d61b1c061`.

The Blackhole dependency is still an external source checkout; its production
delta must be included in the tracked combined installer patch, replayed from
the pinned baseline and compared byte-for-byte before release. No nested Git
commit, live socket, service restart, AMQP operation or deployment was performed
by these classifier tests. This does not change ACDC's direct kz5 ownership.

## Remaining security gates

Session `69993` subsequently passed all ten public-handler/redaction groups,
including both mixed authentication-result orders and an all-good positive
control. Actual socket handler, callback pipeline and result classifiers were
used with in-memory validator/binding providers. Both denial cases emitted an
error without entering later command or finish stages. Exact combined patch
replay, six production compiles and dependency/source checks also passed; see
`doc/blackhole_resilience.md` for the retained evidence.

Broader public authentication/authorization pipeline coverage, absent or crashing
authentication handlers, malformed provider results, cached-token expiry and
revocation, identity changes, queue permissions and actual authenticated event
delivery are distinct checks. Fixing result classification does not close them.
