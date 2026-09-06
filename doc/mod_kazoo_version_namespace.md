# mod_kazoo version namespace build correction

Status: source correction passes full-translation-unit, real-header compilation;
installer source-transition regressions pass. Native linking, execution and
deployment acceptance remain open. Nothing has been installed, loaded,
restarted, or changed in the existing native source tree for this fix.

## Reproduced failure

On 2026-09-06, isolated native compilation session `71491` checked twelve complete
private C translation units against the configured FreeSWITCH headers and flags.
Eleven passed. `kazoo_dptools.c` failed under `-Werror` because `kazoo_ei.h`
redefined the generic `VERSION` macro supplied by the standalone build.
The retained evidence is
`/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/native-real-tu.MmLnKw/real-tu-proof.ijCctG`.
All 461 compiler-selected dependency hashes and lexical path identities, plus
the fixed source/native inputs, remained unchanged. This is a failed build
checkpoint, not native acceptance.

The conflicting header is tracked upstream, not generated: it defines the
module identity `mod_kazoo v1.5.0-1 community`. Separately, `configure.ac` defines
the standalone package version as `1.7.0`, which becomes a command-line
`-DVERSION`. Neither value is the Kazoo applications platform version.

## Correction and deployment integration

The repository patch `scripts/patches/mod-kazoo-version-namespace.patch` renames
only the module macro to `KAZOO_MODULE_VERSION` and updates its three consumers:
the CLI status output, the `Kazoo-Version` fetch header, and the Erlang version
request response. The external module-identity string, release and bundle stay
byte-for-byte unchanged. The patch neither undefines nor overwrites the separate
package `VERSION`, and it does not suppress compiler warnings.

`prepare_mod_kazoo_source` applies the combined required module integration.
The FreeSWITCH build fingerprint now includes `version-namespace-v1`,
so a prior build marker cannot be mistaken for the corrected build. This is
part of kz5's installer source; no commit is made to a nested mod_kazoo or ACDC
repository.

## Repeat-install failure and correction

Actual installer-helper regression `33490` reproduced a repeat-install failure:
the cookie-redaction patch's reverse-check context contained the old `VERSION`
identifier. Its context is now trimmed without changing the C result. The next
run, `47015`, exposed a pre-existing overlap: the later originate-reconcile patch
changes code introduced by originate-compatibility, so checking every earlier
patch individually in reverse cannot recognize the completed integration.
Both failed checkpoints are retained at `/tmp/kazoo-version-namespace.1M7Pa9`
and `/tmp/kazoo-version-namespace.xcEVft` respectively.

The installer now uses the existing protected whole-integration preflight helper
for mod_kazoo, with its explicit canonical source directory. The original namespace
checkpoint covered fourteen C/header files; the atomic-intercept integration below
adds its explicit fifteenth file. Supported source states are:

| State | Action |
| --- | --- |
| Clean pinned source | Apply `mod-kazoo-kz5-integration.patch` |
| Current complete integration | No source rewrite |
| Previous twelve-patch integration | Apply namespace and atomic-intercept deltas |
| Namespace-only thirteen-patch integration | Apply only atomic-intercept |
| Atomic-intercept without namespace | Apply only namespace |
| Partial or unknown integration | Stop without attempting implicit repair |

`mod-kazoo-before-version.patch` and `mod-kazoo-kz5-integration.patch` were
constructed from local pinned upstream commit
`0878e13e02db5db7bde765d61a9453b3cf279399`. The regression independently applies
the twelve-patch baseline and all fourteen current individual patches and compares complete source bytes/modes
against these aggregate results. When changing an individual patch, maintain
the aggregate artifacts and rerun this test; the individual files are retained
as auditable source inputs, not independently replayed during installation.
Unrelated source edits survive supported transitions. Private originals and
desired copies are retained; this is not a crash-atomic filesystem transaction.

## Verification, 2026-09-06

Guarded run `87250` passed eleven actual-installer-helper cases, including fresh
application, idempotence, prior-version upgrade, unrelated-edit preservation,
partial-state rejection, exact namespace-only changes and fingerprint behavior.
Evidence: `/tmp/kazoo-version-namespace.0TYe9p/receipt.json`, SHA-256
`27a3f494ef7117dfa9ba37ed8be2d45c82c4c83fd0f61b9aaddefdcbcd77b3f3`.
Inputs remained unchanged. This test substitutes only `sync_git` with a checked
offline fixture; it does not certify actual fetch/checkout or a full deployment.
Run it with an existing local mod_kazoo repository containing the pinned object:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 \
  --runtime-sec 90 -- /usr/bin/unshare --net -- /usr/bin/node \
  /opt/kz5/scripts/test-mod-kazoo-version-namespace.cjs \
  /usr/local/src/kazoo5-installer/freeswitch-1.11.3/src/mod/outoftree/mod_kazoo
```

Shared-helper regression `33997` then passed all 42 existing Blackhole/Crossbar
transition cases, including failed staging, inherited Git redirects and unsafe
paths. Evidence: `/tmp/kazoo-source-transition-tests.RhuupY`.

Expanded mod_kazoo run `46313` passed all fifteen cases, adding missing aggregate,
symlinked explicit source, hardlinked source and out-of-inventory patch rejection.
Each rejection verifies unchanged target bytes; linked targets/sentinels remain
intact. Evidence: `/tmp/kazoo-version-namespace.Oyb2Sc/receipt.json`, SHA-256
`624b8908b0cfb3454a0d7101bc8c8c248959c4e12bb00faeaa8910da773afc90`.
Inputs remained unchanged; the same offline scope applies.

Main installer smoke `85725` also passed after the shared-helper change:
syntax, pins, aliases, modular selection, security gates, ALL dry-run and error
paths. It ran in a private network namespace under the same 384-MiB cap. It does
not install components or perform live health acceptance.

Corrected private native run `13867` passed all fifteen complete C translation
units, including the three changed version consumers, using the actual
configured headers/flags and `-Werror`. All 464 compiler-selected dependencies,
fixed inputs and path identities remained unchanged. Evidence:
`/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/native-version-tu.RAKTfm/real-tu-proof.AqUSZu/receipt.json`,
SHA-256 `4a1c5c7819c3e141b40bbdc2516c2e7fc9566e870904005e199bdc24d858dbfa`.
The derivative driver also fixes a discovered allocation-error guard (separating
the checked `mktemp` assignment from `readonly`); its three allocation-failure
cases pass. The failed original proof and its driver were not overwritten.

The native run produced no linked libraries, loaded no modules and executed no
native call path. Callback audio, resource lifetime, bridge safety, full native
linking and deployment correctness are not established by compilation. Private
owned-audio admission remains closed pending those separate acceptance gates.

## Atomic-intercept installer reconciliation — 2026-09-06

Source integration passes the updated guarded regression. The earlier receipts
above prove only their frozen inputs; the new receipt below binds this update.

The existing tracked `mod-kazoo-atomic-intercept.patch` was present in the private
callback/installed-source trees but absent from the default installer aggregate.
The current aggregate now includes that exact patch's header, registration,
initializer, shutdown declaration and `remove_kz_dptools()` call. The patch itself
is unchanged. `prepare_mod_kazoo_source` requires it, and the build fingerprint
adds `atomic-intercept-v1`; the namespace identifier and external version bytes
remain unchanged.

For known earlier source states, the helper selects only missing namespace and
intercept deltas. Their file sets are disjoint. Every selected change is applied
to private copies and checked against the complete current aggregate before the
first real source write. Partial header/cleanup states are rejected, not repaired
implicitly. The namespace regression preserves its original fifteen cases and
adds six cases covering both one-delta upgrades, the new fingerprint, missing
patch and incomplete header/shutdown source. Fresh and repeat checks compare the
full tree to fourteen independent patches and verify complete interception.

This integrates existing atomic answering, not the private owned-audio candidate;
no audio admission, transport ownership or both-leg bridge gate is enabled.

Run `68919` passed all 21 cases, using a 128-MiB cap, unchanged 768-MiB reserve,
90-second deadline and private network namespace. Receipt:
`/tmp/kazoo-version-namespace.pDz78a/receipt.json`, SHA256
`532a0a7d01411707c13f6a99be6c42d2b899ec27d453bf313b9de5e81e3c0c09`.
All 18 input hashes stayed unchanged. The source is extracted from the actual
installer; only Git synchronization is replaced with checked local fixture data.
The aggregate equals fourteen independent source patches, including the unchanged
atomic patch, whose complete reverse application is also exercised.

The initial run `87727` failed before fresh application because two authored
aggregate hunks had incorrect context. Evidence remains at
`/tmp/kazoo-version-namespace.xHrwXN/receipt.json`, SHA256
`3cd3e185ef486dea3c5e72c4447179c7439452bf42dea8e4744f18270f8b9fa2`.
Only the exact long-description context and unchanged trailing header context
were corrected; no relaxed patch matching or C semantic changes were used.

Shared-helper run `84663` passed all 42 Blackhole/Crossbar transition cases at
`/tmp/kazoo-source-transition-tests.Hitp0d`; input-pin manifest SHA256
`0b65c57d37652c34bbfbf0499cd5e5e770da3136560ef12d809b54515a521692`.
Installer smoke `78269` passed syntax, pins, aliases, modular/security/error paths
and ALL dry-run. Both used the same installer bytes as the successful 21-case
run, with 128-MiB caps, 768-MiB reserve and network isolation. These checks do not
compile/install modules, restart services or certify callback audio.
