#!/usr/bin/env node
'use strict';
// Root-only offline fixture: synthetic document metadata, no real audio claim,
// no database/provider/SUP connection. Erlang runs only private stub modules.
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path');
const crypto = require('node:crypto');
const helper = require('./refresh-acdc-cardinal-mappings.cjs');
const installer = require('./install-acdc-cardinal-pack.cjs');
const importer = require('./import-acdc-gemini-cardinals.cjs');
const pack = require('./acdc-cardinal-pack.cjs');
const sha = x => crypto.createHash('sha256').update(x).digest('hex');
const clone = x => JSON.parse(JSON.stringify(x));
const rev = '1-' + 'a'.repeat(32);
const template = fs.readFileSync(path.join(__dirname, 'refresh-acdc-cardinal-mappings.erl.template'), 'utf8');
// The shell launcher waits for ALL Node test processes to exit before starting
// the actual private Erlang fixture. Never nest its large VM beneath node:test.
const preparedDirectory = process.env.KAZOO_CARDINAL_MAPPING_TEST_DIR;
assert(typeof preparedDirectory === 'string' && /^\/tmp\/kazoo-cardinal-map-validation\.[A-Za-z0-9]+$/.test(preparedDirectory),
  'Run bash scripts/test-refresh-acdc-cardinal-mappings.sh; the full test requires both sequential phases');
const preparedStat = fs.lstatSync(preparedDirectory);
assert(preparedStat.isDirectory() && !preparedStat.isSymbolicLink() && preparedStat.uid === 0
  && (preparedStat.mode & 0o777) === 0o700 && fs.realpathSync(preparedDirectory) === preparedDirectory,
  'Expected fresh protected mapping test directory');
function installed(row) {
  return {locale: row[0], canonical_id: row[1], prompt_id: row[2], document_id: `${row[0]}/${row[2]}`,
    attachment: row[2] + '.wav', sha256: row[3], revision: rev};
}
function fixture(mixed = true) {
  const states = [], audit = {source_manifest_sha256: '1'.repeat(64), approvals_sha256: installer.APPROVAL,
    runtime_ready: false, native_listening_approved: false, additional_trial_requests: 4};
  const entries = installer.LOCALES.map(locale => {
    const resolved = mixed && locale !== 'en-us', intro = importer.INTROS[locale];
    const records = pack.plan(locale).sort((a, b) => a.id.localeCompare(b.id, 'en'));
    const proofs = [], rows = records.map((p, index) => {
      const wav = sha(locale + '/' + p.id);
      const reused = resolved && locale === 'es-es' && ['acdc-cardinal-v1-number-4', 'acdc-cardinal-v1-number-9'].includes(p.id);
      const kind = reused ? 'reused_supplemental_master' : index === 0 ? 'separate_model_trial' : 'generated_cardinal';
      const model = resolved && kind === 'separate_model_trial' ? 'gemini-3.1-flash-tts-preview' : pack.MODEL;
      if (resolved) proofs.push({id: p.id, resolution: {source_kind: kind, provider: 'google-gemini', voice: 'Sulafat', model,
        master_sha256: '5'.repeat(64), telephony_sha256: wav, transcript_sha256: p.transcript_sha256,
        context_sha256: p.context_sha256, catalog_record_sha256: p.catalog_record_sha256,
        resampling_recipe_sha256: pack.digest(pack.RESAMPLING), runtime_ready: false,
        listening_verified: false, provider_provenance_authenticated: false,
        ...(reused ? {alias_manifest_sha256: 'b'.repeat(64), source_locale: 'es-es',
          source_id: p.id.endsWith('-4') ? 'acdc-number-4' : 'acdc-number-9'} : {})}});
      else proofs.push({id: p.id, entry_sha256: '4'.repeat(64), attempt: 1, master_sha256: '5'.repeat(64), telephony_sha256: wav});
      return [locale, p.id, p.id + '-gemini-sulafat-' + wav.slice(0, 16), wav,
        'md5-AAAAAAAAAAAAAAAAAAAAAA==', 100, p.transcript_sha256, ...(resolved ? [model, kind] : [])];
    });
    const introRow = [locale, intro.canonical_id, intro.canonical_id + '-gemini-sulafat-' + intro.wav_sha256.slice(0, 16),
      intro.wav_sha256, 'md5-AAAAAAAAAAAAAAAAAAAAAA==', 100, intro.transcript_sha256];
    const mapHash = sha(JSON.stringify(resolved ? {schema_version: 1, row_schema: 'cardinal-resolved-row-v1', rows} : rows));
    const summary = {schema_version: 1, owner: importer.OWNER, locale, count: rows.length,
      catalog_sha256: pack.CATALOG_HASH, locale_catalog_sha256: pack.LOCALE_HASHES[locale],
      context_sha256: pack.digest(pack.contexts[locale]), approval_sha256: installer.APPROVAL,
      cardinal_manifest_sha256: '1'.repeat(64), map_sha256: mapHash, historical_artifact_complete: !mixed,
      authoring_approval_declared: true, resampling_provenance_verified: true,
      preserves_original_request_history: true, preserves_210_inventory: true, creates_only_versioned_ids: true,
      runtime_ready: false, full_position_language_ready: false, five_language_release_ready: false, listening_verified: false,
      intro: {...intro, source_bytes_verified: true, document_id: installed(introRow).document_id}, prompts: proofs};
    if (resolved) Object.assign(summary, {map_row_schema: 'cardinal-resolved-row-v1',
      model_trial_index_sha256: '7'.repeat(64), asset_set_kind: 'cardinal-resolved-assets-v1', staged_candidates_only: true,
      native_listening_approved: false, resolved_listening_approval_declared: false, selected_unresolved: 0,
      model_trial_audit: clone(audit), additional_trial_requests: 4, selected_model_trials: 1,
      selected_reused: locale === 'es-es' ? 2 : 0, selected_generated: rows.length - 1 - (locale === 'es-es' ? 2 : 0),
      ...(locale === 'es-es' ? {alias_manifest_sha256: 'b'.repeat(64)} : {})});
    summary.selected_asset_set_sha256 = resolved
      ? pack.digest({schema_version: 1, kind: 'cardinal-resolved-assets-v1', locale, intro, prompts: proofs})
      : pack.digest(proofs.map(p => ({id: p.id, master: p.master_sha256, telephony: p.telephony_sha256})));
    if (resolved) summary.resolved_asset_set_sha256 = summary.selected_asset_set_sha256;
    const prefix = locale === 'en-us' ? 'CARDINAL' : 'CARDINAL_' + locale.slice(0, 2).toUpperCase();
    const tuple = r => '{' + r.map(v => typeof v === 'number' ? v : '<<' + JSON.stringify(v) + '>>').join(',') + '}';
    const map = `-define(${prefix}_ASSETS, [\n` + rows.map(r => '    ' + tuple(r)).join(',\n') + '\n]).\n'
      + (['he-il', 'ar-sa'].includes(locale) ? `-define(${prefix}_INTRO_ASSET, ${tuple(introRow)}).\n` : '');
    const state = {summary, map, installed: rows.map(installed), intro_installed: installed(introRow)};
    states.push(state);
    return {locale, header: () => state.map, plan: {summary: () => clone(state.summary), renderMap: () => state.map,
      install: () => { throw new Error('must not perform import from mapping fixture'); }}};
  });
  const receipt = {schema_version: 1, owner: 'kazoo5-acdc-cardinal-installer', scope: 'all-locales', mode: 'VERIFY_ONLY',
    database_verified: true, verified: 584, count: 584, source_complete: true, catalog_sha256: pack.CATALOG_HASH,
    approval_sha256: installer.APPROVAL, cardinal_manifest_sha256: '1'.repeat(64), runtime_ready: false,
    five_language_release_ready: false, full_position_language_ready: false, listening_verified: false,
    queue_configuration_changed: false, preserves_210_inventory: true,
    locales: states.map(s => ({...clone(s.summary), mode: 'VERIFY_ONLY', created: 0, verified: s.summary.count,
      intro_installed_verified: true, installed: clone(s.installed), intro_installed: clone(s.intro_installed)}))};
  return {entries, receipt, states};
}
test('strict modes/node/receipt/resolution arguments and result counters', () => {
  const args = ['--check', '--node', 'kazoo_apps@example.invalid', '--receipt', '/tmp/receipt'];
  assert.equal(helper.parseArgs(args).mode, 'check');
  for (const bad of [[...args, '--activate'], [...args, '--node', 'x@y'], [...args, '--unknown'],
    args.map(x => x === 'kazoo_apps@example.invalid' ? "bad'node@host" : x),
    [...args, '--model-trial-index', '/tmp/index']]) assert.throws(() => helper.parseArgs(bad));
  assert.equal(helper.validateResult('{ok,{ok,{cardinal_mapping_verified,activate,586,1172,1172,no_database_writes}}}', 'activate'), 1172);
  assert.equal(helper.validateResult('{ok,{ok,{cardinal_mapping_verified,check,586,1172,0,no_database_writes}}}', 'check'), 0);
  for (const bad of ['{ok,{ok,{cardinal_mapping_verified,check,586,1172,1,no_database_writes}}}',
    '{ok,{ok,{cardinal_mapping_verified,activate,586,1172,1173,no_database_writes}}}',
    '{ok,{error,cardinal_mapping_verification_failed_safely}}', 'noise']) assert.throws(() => helper.validateResult(bad, 'check'));
});
test('actual five-locale preflight admits exact synthetic586 scope and mixed model lineage', () => {
  for (const mixed of [false, true]) {
    const f = fixture(mixed), expected = helper.expectedDocuments(f.entries, f.receipt);
    assert.equal(expected.length, 586);
    assert.equal(expected.filter(e => e.source_voice.canonical_prompt_id.startsWith('acdc-cardinal-intro')).length, 2);
    assert.equal(expected.filter(e => e.source_voice.model === 'gemini-3.1-flash-tts-preview').length, mixed ? 4 : 0);
    assert.equal(expected.filter(e => e.source_cardinal_resolution?.source_kind === 'reused_supplemental_master').length, mixed ? 2 : 0);
    assert(expected.every(e => e.expected_path === '/system_media/' + encodeURIComponent(e._id)));
  }
});
test('missing/stale intro revision, duplicate cardinal, incomplete and changed source fail closed', () => {
  const f = fixture();
  const changes = [r => { delete r.locales.find(l => l.locale === 'he-il').intro_installed; },
    r => { r.locales.find(l => l.locale === 'ar-sa').intro_installed.revision = 'bad'; },
    r => { r.locales[0].installed[0].sha256 = 'c'.repeat(64); },
    r => { r.locales[0].installed[0] = r.locales[0].installed[1]; },
    r => { r.locales[1].prompts[0].resolution.model = pack.MODEL; },
    r => { r.verified = 583; }, r => { r.database_verified = false; }, r => { r.locales.pop(); }];
  for (const change of changes) { const r = clone(f.receipt); change(r); assert.throws(() => helper.expectedDocuments(f.entries, r)); }
  const original = f.states[0].map; f.states[0].map = original.replace('number-0', 'not-catalog');
  assert.throws(() => helper.expectedDocuments(f.entries, f.receipt));
});
test('receipt reader rejects symlink/hardlink/writable/oversized or nonregular inputs', () => {
  const dir = fs.mkdtempSync('/tmp/cardinal-map-receipt-test.'), file = path.join(dir, 'receipt.json');
  try {
    fs.writeFileSync(file, '{}', {mode: 0o600}); assert.deepEqual(helper.protectedReceipt(file), {});
    fs.linkSync(file, path.join(dir, 'hard')); assert.throws(() => helper.protectedReceipt(file)); fs.unlinkSync(path.join(dir, 'hard'));
    fs.symlinkSync(file, path.join(dir, 'link')); assert.throws(() => helper.protectedReceipt(path.join(dir, 'link'))); fs.unlinkSync(path.join(dir, 'link'));
    fs.chmodSync(file, 0o666); assert.throws(() => helper.protectedReceipt(file)); fs.chmodSync(file, 0o600);
    assert.throws(() => helper.protectedReceipt(dir));
    fs.truncateSync(file, 8 * 1024 * 1024 + 1); assert.throws(() => helper.protectedReceipt(file));
  } finally { fs.unlinkSync(file); fs.rmdirSync(dir); }
});
test('SUP wrapper renders protected file, exact node and bounded RPC without provider/DB credentials', () => {
  const f = fixture(), dir = fs.mkdtempSync('/tmp/cardinal-map-wrapper-test.'); let rpc = 0, file;
  try {
    const result = helper.execute({mode: 'activate', node: 'kazoo_apps@example.invalid'}, {
      entries: f.entries, receipt: f.receipt, temporaryParent: dir,
      spawn(command, args, options) {
        if (command === 'getent') return {status: 0, stdout: 'kazoo:x:987:\n'};
        assert.equal(command, '/usr/local/bin/sup'); assert.equal(args[args.indexOf('-n') + 1], 'kazoo_apps');
        assert.equal(args[args.indexOf('-t') + 1], '180'); assert.equal(options.timeout, 190000);
        file = JSON.parse(args.at(-1)); assert.equal(fs.statSync(file).mode & 0o777, 0o640);
        assert.equal(fs.statSync(file).gid, 987); assert.equal(fs.statSync(path.dirname(file)).mode & 0o777, 0o750);
        const code = fs.readFileSync(file, 'utf8'), sidecar = path.join(path.dirname(file), 'expected.json');
        assert(code.includes('<<"kazoo_apps@example.invalid">>')); assert(Buffer.byteLength(code) < 16384);
        assert(!code.includes('@@')); assert.equal(fs.statSync(sidecar).mode & 0o777, 0o640);
        assert.equal(fs.statSync(sidecar).uid, 0); assert.equal(fs.statSync(sidecar).gid, 987);
        const sidecarBytes = fs.readFileSync(sidecar);
        assert.equal(JSON.parse(sidecarBytes).length, 586);
        assert(code.includes(crypto.createHash('sha256').update(sidecarBytes).digest('base64'))); rpc++;
        return {status: 0, stdout: '{ok,{ok,{cardinal_mapping_verified,activate,586,1172,1172,no_database_writes}}}'};
      }});
    assert.equal(rpc, 1); assert.equal(result.documents_verified, 586); assert.equal(result.database_writes, false);
    assert.equal(fs.existsSync(file), false); assert.deepEqual(fs.readdirSync(dir), []);
  } finally { fs.rmdirSync(dir); }
});
test('template never calls lazy prompt resolver, database write, global flush or service control', () => {
  const f = fixture(), expected = helper.expectedDocuments(f.entries, f.receipt);
  const sidecar = {path: '/tmp/kazoo-cardinal-map.fixture/expected.json', gid: 987};
  const rendered = helper.render(template, expected, 'check', 'nonode@nohost', sidecar);
  const code = rendered.replace(/^\s*%%.*$/gm, '');
  assert(!/save_doc|ensure_saved|update_doc|del_doc|put_attachment|delete_all_objects|:flush\(|restart|:prompt_path\(/.test(code));
  assert(code.includes('Modules = [media_map, kz_media_map]'));
  assert(Buffer.byteLength(rendered) < 16384); assert(!rendered.includes(Buffer.from(JSON.stringify(expected)).toString('base64')));
  assert.throws(() => helper.render(template, expected.slice(1), 'check', 'nonode@nohost', sidecar));
  for (const bad of [undefined, {path: '/tmp/../expected.json', gid: 987}, {path: '/tmp/expected.json', gid: -1},
    {path: '/tmp/quote"/expected.json', gid: 987}]) assert.throws(() => helper.render(template, expected, 'check', 'nonode@nohost', bad));
  const oversized = clone(expected); oversized[0].extra = 'x'.repeat(8 * 1024 * 1024);
  assert.throws(() => helper.render(template, oversized, 'check', 'nonode@nohost', sidecar));
});
test('prepare actual Erlang template:586 docs/1172 maps and all negative cases; execution is mandatory phase2', () => {
  const f = fixture(), expected = helper.expectedDocuments(f.entries, f.receipt);
  const directory = preparedDirectory;
  console.log('Retained private cardinal mapping fixture: ' + directory);
  const docs = Object.fromEntries(expected.map(e => [e._id, {_id: e._id, _rev: e._rev,
    pvt_type: 'media', pvt_account_db: 'system_media', prompt_id: e.prompt_id, language: e.language,
    source_type: e.source_type, content_length: e.content_length, content_type: 'audio/wav', streamable: true,
    source_voice: e.source_voice, ...(e.source_cardinal_resolution ? {source_cardinal_resolution: e.source_cardinal_resolution} : {}),
    _attachments: {[e.attachment]: {content_type: 'audio/wav', digest: e.digest, length: e.content_length}}}]));
  fs.writeFileSync(path.join(directory, 'docs.json'), JSON.stringify(docs), {flag: 'wx', mode: 0o600});
  const sidecar = {path: path.join(directory, 'expected.json'), gid: fs.statSync(directory).gid};
  fs.writeFileSync(sidecar.path, JSON.stringify(expected), {flag: 'wx', mode: 0o640});
  fs.chmodSync(sidecar.path, 0o640); fs.chmodSync(directory, 0o750);
  for (const mode of ['activate', 'check']) fs.writeFileSync(path.join(directory, mode + '.erl'),
    helper.render(template, expected, mode, 'nonode@nohost', sidecar), {flag: 'wx', mode: 0o600});
  const runner = `-module(cardinal_mapping_runner).
-export([run/1]).
run(Dir) ->
  true = string:prefix(code:which(kz_datamgr), Dir) =/= nomatch,
  {ok,B} = file:read_file(filename:join(Dir,"docs.json")), Docs = maps:from_list(kz_json:to_proplist(kz_json:decode(B))),
  [register(M,spawn(fun()->receive stop->ok end end)) || M <- [media_map,kz_media_map]],
  [ets:new(M,[named_table,set,protected,{keypos,2}]) || M <- [media_map,kz_media_map]],
  Check=filename:join(Dir,"check.erl"), Act=filename:join(Dir,"activate.erl"),
  Reset=fun() -> erase(),put(docs,Docs),[ets:delete_all_objects(M)||M<-[media_map,kz_media_map]],ok end,
  Sidecar=filename:join(Dir,"expected.json"),{ok,OriginalBytes}=file:read_file(Sidecar),
  FailBeforeReads=fun() -> Reset(),{ok,{error,cardinal_mapping_verification_failed_safely}}=file:script(Act),
    undefined=get(writes),[]= [K || {K,_} <- get(),is_tuple(K),tuple_size(K)=:=2,element(1,K)=:=reads] end,
  ok=file:write_file(Sidecar,<<"tampered">>),FailBeforeReads(),ok=file:write_file(Sidecar,OriginalBytes),
  ok=file:change_mode(Sidecar,8#660),FailBeforeReads(),ok=file:change_mode(Sidecar,8#640),
  {ok,Large}=file:open(Sidecar,[write,binary,raw]),{ok,8388608}=file:position(Large,8388608),
  ok=file:write(Large,<<0>>),ok=file:close(Large),FailBeforeReads(),ok=file:write_file(Sidecar,OriginalBytes),
  Alias=filename:join(Dir,"expected-hard.json"),ok=file:make_link(Sidecar,Alias),FailBeforeReads(),ok=file:delete(Alias),
  Saved=filename:join(Dir,"expected-real.json"),ok=file:rename(Sidecar,Saved),ok=file:make_symlink(Saved,Sidecar),
  FailBeforeReads(),ok=file:delete(Sidecar),ok=file:rename(Saved,Sidecar),
  io:format("PASS bounded sidecar hash,permissions,oversize,hardlink,symlink refusals before any document/map access~n"),
  Reset(),{ok,{error,cardinal_mapping_verification_failed_safely}}=file:script(Check),undefined=get(writes),
  Custom={media_map,<<"system_media/customer-prompt">>,<<"system_media">>,<<"customer-prompt">>,kz_json:from_list([{<<"en-us">>,<<"/customer-voice">>}])},
  ets:insert(media_map,Custom),
  {ok,{ok,{cardinal_mapping_verified,activate,586,1172,1172,no_database_writes}}}=file:script(Act),1172=get(writes),
  [Custom]=ets:lookup(media_map,<<"system_media/customer-prompt">>),
  {ok,{ok,{cardinal_mapping_verified,check,586,1172,0,no_database_writes}}}=file:script(Check),1172=get(writes),
  {ok,{ok,{cardinal_mapping_verified,activate,586,1172,0,no_database_writes}}}=file:script(Act),1172=get(writes),
  [Id|_]=lists:sort(maps:keys(Docs)),Doc=maps:get(Id,Docs),
  lists:foreach(fun({Key,Value})->Reset(),put(docs,maps:put(Id,kz_json:set_value(Key,Value,Doc),Docs)),
    {ok,{error,cardinal_mapping_verification_failed_safely}}=file:script(Act),undefined=get(writes)
  end,[{<<"_rev">>,<<"2-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>},{<<"_conflicts">>,[<<"2-cccccccccccccccccccccccccccccccc">>]},
       {<<"source_type">>,<<"foreign">>},{<<"pvt_deleted">>,true},{<<"content_length">>,-1},
       {[<<"source_voice">>,<<"model">>],<<"wrong-model">>},{<<"source_cardinal_resolution">>,kz_json:new()}]),
  Reset(),put(race,{Id,2}),{ok,{error,cardinal_mapping_verification_failed_safely}}=file:script(Act),undefined=get(writes),
  Reset(),put(race,{Id,3}),{ok,{error,cardinal_mapping_verification_failed_safely}}=file:script(Act),1172=get(writes),
  Reset(),Prompt=kz_json:get_value(<<"prompt_id">>,Doc),Lang=kz_json:get_value(<<"language">>,Doc),
  Bad={media_map,<<"system_media/",Prompt/binary>>,<<"system_media">>,Prompt,kz_json:from_list([{Lang,<<"/foreign">>}])},
  ets:insert(media_map,Bad),{ok,{error,cardinal_mapping_verification_failed_safely}}=file:script(Act),
  undefined=get(writes),[Bad]=ets:lookup(media_map,<<"system_media/",Prompt/binary>>),
  io:format("PASS exact586/1172, check-no-write, idempotence, custom preservation,7metadata failures,2revision races,conflict refusal~n"),halt(0).
`;
  fs.writeFileSync(path.join(directory, 'cardinal_mapping_runner.erl'), runner, {flag: 'wx', mode: 0o600});
  console.log('PHASE1 ONLY: Erlang fixture prepared; launcher must complete standalone phase2 before claiming full PASS');
});
