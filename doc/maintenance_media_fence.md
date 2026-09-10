# Durable media admission fence

This is the media component of INST-06. It does not by itself close the full
cluster ingress, broker/callback/producer drain, checkpoint/restore or rollback
gates. No production runtime pass is implied by the source tests below.

## Implementation

The pinned FreeSWITCH patch `scripts/patches/freeswitch-durable-media-admission.patch`
checks a durable root-owned marker inside the session allocation mutex, before
allocation, duplicate-ID lookup and originate limit exceptions. Both inbound
and outbound allocations, including internal originates, pass this boundary.
Existing sessions are not killed or modified. The check is independent of
fsctl pause/resume and is present from the first allocation after process start;
there is no post-startup re-pause admission window.

Missing marker means open. Filesystem errors, symlinks, malformed ownership/
permissions/type/size and an existing valid marker all deny new sessions.
The fixed parent `/etc/kazoo5-maintenance` must be root-owned0755; the marker
`media.closed` is a root-owned0644 single-link regular file. It contains only
schema_version1, generation32hex and manifest_sha25664hex, never credentials.
The core checks metadata/existence, while the privileged helper additionally
validates its full contents against private durable intent. Two metadata lookups
are added per allocation when the parent exists; no TTS/API/network dependency
is introduced into the media path. Native load acceptance is still required.

The read-only event-socket command `fsctl maintenance_check` observes admission
and the actual allocated session count under the same mutex. It returns
schema_version1, admission (open/closed/error), sessions and core_uuid. An
already-admitted allocator cannot remain uncounted behind a successful closed
observation. This counts allocated sessions, not SQL channel rows. Zero sessions
still does not prove the absence of queued broker commands or callback work.
This is an internal administrative command, not a public Crossbar/OpenAPI route.

## Root coordinator interface

`scripts/kazoo-maintenance-media.cjs` is installed as
`/usr/local/libexec/kazoo5-maintenance-media` on the FreeSWITCH role:

```sh
node /usr/local/libexec/kazoo5-maintenance-media --close /root/private/spec.json
node /usr/local/libexec/kazoo5-maintenance-media --verify GENERATION
node /usr/local/libexec/kazoo5-maintenance-media --status
node /usr/local/libexec/kazoo5-maintenance-media --boot-guard
node /usr/local/libexec/kazoo5-maintenance-media --release GENERATION
```

The spec file is root-owned0600 with a root-owned0700 parent. Private journal
files live under `/var/lib/kazoo5-maintenance/media` (0700/0600), with a kernel
flock, fsynced intent before marker creation, releasing intent before marker
removal, and retained released-generation history. Closing a fresh generation
requires a native open observation from the supported running service. Repeating
the same close is safe; another generation, foreign marker, corrupt intent or
interrupted release is refused. No automatic expiry or reopening exists.

The boot guard restores a lost marker from valid private intent before starting
FreeSWITCH. Interrupted release blocks startup. It also rejects a selected
library without the exported native admission barrier, so an unsupported old
binary cannot silently bypass an active fence during rollback. Ordinary status
and verify do not repair missing state. Native observations check the actual
systemd main process executable, PID/start ticks/host boot identity before and
after a loopback event-socket read, and retain the FreeSWITCH core UUID.
On restricted containers, root can lack permission to read another UID's
`/proc/PID/exe`. The helper first verifies real/effective/saved/filesystem UIDs
against the freeswitch account, then performs only that denied proc read through
runuser as freeswitch. Other proc errors, wrong UIDs and unexpected executables
still fail. It never grants CAP_SYS_PTRACE or changes kernel ptrace policy.

The **cluster coordinator must persist its reopening phase before release** and
must never replay restoration once admission has reopened. A lost release reply
is reconciled only as that same release; it is not permission to restore again.
The local helper does not attest the remote coordinator journal. It does not
change existing directional pause flags; a preexisting operator pause remains.
Downgrade to a binary without this barrier requires a separate safe plan, not
bypassing the startup guard.

New state directories and their parent directory entries are fsynced explicitly,
in addition to each intent/marker file and its containing directory. The initial
normal media build uses source `88bf049`; this directory-durability correction
is helper-only and must be deployed after that build finishes, without changing
the running build's checkout. The C patch and core build fingerprint are unchanged.

## Installer and evidence

- **Normal private retry6 PASS:** source `935d544` completed, with service and
  native helper verification collected in
  `/var/lib/kazoo5-install-lab/freeswitch-install-6.log`. This supersedes the
  failed build5 verifier below; its failed receipt remains unchanged.
- The opt-in call harness now supports
  `node scripts/test-channel-monitor-live.cjs --distributed --media-fence --live`.
  For each real SIP/RTP supervision conversation, it proves a marked internal
  null-endpoint call can answer before fencing, rejects the same endpoint while
  fenced, verifies all three original legs remain allocated, and verifies the
  permitted/forbidden audio window occurs entirely inside the closed interval.
  After release the internal endpoint must answer again, and normal supervisor
  stop must preserve the original conversation. Only the owned private media
  guest is admitted. Exact temporary generations/probe UUIDs are durable in the
  private fixture state; cleanup never selects unrelated calls or generations.
  Offline record/injection/harness/audio checks pass. Native campaign
  `kz5-stage-monitor-media-fence-1` on runner `a2b7946` exited0 on September10:
  all four modes PASS, independently reanalyzed from the protected captures at
  `/var/log/kazoo-monitor-acceptance-xD4WRr` on dev44. All measured post-keypad
  windows fall within the closed interval, all supervisor stops202 preserve the
  original bridge, and cleanup leaves admission open/zero sessions/no fixture.
  This does not test media restart persistence or full coordinator acceptance.

- Native build5 on `88bf049` compiled and started the new media service but
  exited1 during helper verification: root's proc executable-link read returned
  EACCES. Its native admission command already returns open/zero sessions.
  The corrected same-UID helper passes on the actual service without restart
  or privilege changes;24 focused source/helper/installer tests pass. Candidate
  SHA256 `22425b980293fd388b9f30f85efa658d79db56ba958a4f7f82892aab43fe2b4b`.
  The failed deployment remains failed; collect it and rerun the normal installer
  with the corrected helper. Core patch/fingerprint are unchanged, so the normal
  installer can retain that completed media build while refreshing the helper.

The normal FreeSWITCH build applies the patch and changes the build fingerprint,
forcing a real rebuild of older media binaries. Installation packages the
self-contained helper, its Node.js/binutils prerequisites and
`36-kazoo-maintenance-media.conf` with a privileged ExecStartPre hook. Verification
compares helper bytes, checks the effective boot hook and reads native admission.
The existing ingress firewall guard is retained independently.

- 21 focused source/helper/actual-installer-function tests PASS: real-filesystem
  marker metadata cases, native C mutex observation, persistence/release failures,
  unowned state, stale generations, unsupported rollback and startup ordering.
- Both complete modified FreeSWITCH translation units compile with the configured
  native production flags and Werror in an isolated fixture:
  `/tmp/kazoo-media-build.pAHBAa`. Patch hash remained unchanged. No installed
  library or source build checkout was modified by this compile test.
- Main/modular/read-only installer suites PASS in the network-isolated validation
  guard, as do deterministic API artifact/schema/tamper checks after the installer
  source fingerprint changed. The three marker/native/installer test files
  contain21 passing tests. These checks do not call the installed media service.
- Normal private media rebuild, actual internal originate rejection, retained
  active-call survival, restart persistence, scoped release and after-call/load
  acceptance remain pending. These source tests are not a live-call pass.

Normal private deployment of `88bf049` is running as
`kz5-stage-install-freeswitch-5` (MainPID2947, active/running at launch), after
guarded zero-work admission. Protected start log on dev44:
`/var/lib/kazoo5-install-lab/media-admission-deploy-88bf049-1789002406130.log`.
Collect that exact job before changing the guest checkout or running the native
fence/call acceptance. Main44's own media service was not changed.
