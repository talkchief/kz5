# Prerecorded wait-time runtime preparation

Source candidate; no deployment, live SIP or listening acceptance is established
by this change. Existing fixed210 audio, maps and media records are unchanged.

Root validation `0c9112/session4453/21885e` passes all five focused suites:
wait-time3, cardinal19, callback scheduler/worker12, announcement/ecallmgr15,
language7 (56 EUnit cases total, with internal multi-locale/asset loops).
Wait-time input SHA256
`bac88d118a57090743ea660e7d4643f41fd1b569a17862095a385e5f1b545f9a`;
private production/test outputs `/tmp/kazoo-wait-time-media.z71tf3`.
Cardinal input SHA256
`ebcfbf0a02f3e9e4b4ef4b4689087303a64a96503c296c1de94ec3e336ed2bd1`;
private outputs `/tmp/kazoo-cardinal-media.JAQvGJ`. Expected killed-worker
supervisor reports are isolated lifecycle-test events, not live service crashes.

`acdc_wait_time_media:prepare/3` resolves ten existing fixed assets per supported
locale: increase-in-volume and estimated-wait headers plus eight duration
buckets. It reuses the immutable Gemini default/account-override checker.
Absent built-in defaults become exact versioned `PLAY` paths. Explicit header
settings, including stock-looking IDs, remain account-scoped overrides. Legacy
and canonical account prompt overrides retain priority. Invalid metadata,
missing assets or unavailable account checks fail the complete preflight.

The actual announcement worker now resolves wait-time audio once after callback
and position preflight. All use the original worker start timestamp; a failed
wait-time pack disables only wait-time announcements. Position and callback
settings, delays and intervals are preserved. Built-in wait-time playback no
longer emits canonical prompt aliases or falls back to native SAY.

`acdc_wait_time_media:playlist/4` is pure and used by the actual interval branch.
It preserves the original thresholds (less than60 seconds; at most300/600/900/
1800/2700/3600; otherwise at least an hour), volume-increase comparison and last
valid sample behavior. A complete built-in sentence contains two or three PLAY
commands; customer overrides may remain explicit PROMPT commands. Invalid or
incomplete input emits nothing and preserves the last sample. This does not
change the existing AMQP average-wait-statistics lookup or claim a deadline for
synchronous preflight datastore calls.

Reproduction commands (root-serialized validation):

- `bash scripts/test-acdc-wait-time-media.sh`: private production/test compile;
  actual fixed-map metadata, all five locales/ten assets, threshold boundaries,
  missing/wrong assets, account lookup failure, explicit/account overrides,
  pure interval expansion and independent-clock failures.
- Re-run cardinal, callback-announcement, announcement-media and language
  suites. Their launchers now include the new production module. The old
  language callback fixture now uses exact fixed-map metadata and refuses each
  missing one of the42 Arabic callback prerequisites; attachment length alone
  is no longer presented as immutable proof.

The future development runtime probe can call the production `prepare/3` and
`playlist/4` APIs directly, without creating a queue, starting an announcement
worker or issuing a call command. Such a probe establishes deployed function
testability only; a genuine live call and native listening remain separate.
