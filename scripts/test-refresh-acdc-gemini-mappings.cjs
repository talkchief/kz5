'use strict';
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs');
const path = require('node:path'), cp = require('node:child_process');
const helper = require('./refresh-acdc-gemini-mappings.cjs');
const toolDirectory = process.env.KAZOO_TEST_TOOL_DIR || __dirname;
const sourceRoot = path.resolve(toolDirectory, '..');
const fixed = path.join(toolDirectory, 'assets/acdc-gemini-fixed-20260905');
const completion = path.join(toolDirectory, 'assets/acdc-gemini-completion-20260905');
const importer = require(path.join(toolDirectory, 'import-acdc-gemini-voices.cjs'));
const {validateReceipt} = require(path.join(toolDirectory, 'validate-acdc-gemini-receipt.cjs'));
const fullPlan = importer.loadPlan(fixed, completion, ['en-us','ar-sa','he-il','es-es','fr-fr']);
const original = fullPlan.map(asset => { const doc=importer.document(asset,0); return {id:asset.id,
  prompt_id:asset.prompt_id, language:asset.locale, source_voice:doc.source_voice, source_type:doc.source_type,
  content_length:asset.bytes.length, digest:asset.md5, attachment:asset.attachment,
  expected_path:'/system_media/'+encodeURIComponent(asset.id)}; });
const revision = '1-' + 'a'.repeat(32);
const expected = original.map(e => { const {id, ...rest} = e; return {_id: id, _rev: revision, ...rest}; });
const template = fs.readFileSync(path.join(__dirname, 'refresh-acdc-gemini-mappings.erl.template'), 'utf8');
test('exact node, explicit check/activation, absolute receipt and source paths required', () => {
  const argv = ['--check', '--node', 'kazoo_apps@example.invalid', '--receipt', '/tmp/receipt', '--fixed-pack', '/tmp/fixed', '--completion-pack', '/tmp/complete'];
  assert.equal(helper.parseArgs(argv).mode, 'check');
  assert.throws(() => helper.parseArgs([...argv, '--activate']));
  assert.throws(() => helper.parseArgs([...argv, '--unknown']));
  assert.throws(() => helper.parseArgs(argv.map(x => x === 'kazoo_apps@example.invalid' ? "bad'node@host" : x)));
});
test('verified result parser rejects incomplete, wrong mode, negative counts and noisy/error output', () => {
  assert.equal(helper.validateResult('{ok,{ok,{gemini_mapping_verified,activate,165,330,330,no_database_writes}}}', 'activate'), 330);
  assert.equal(helper.validateResult('{ok,{ok,{gemini_mapping_verified,check,165,330,0,no_database_writes}}}', 'check'), 0);
  for (const bad of ['{ok,{ok,{gemini_mapping_verified,check,165,330,1,no_database_writes}}}',
    '{ok,{ok,{gemini_mapping_verified,activate,165,330,331,no_database_writes}}}',
    '{ok,{error,gemini_mapping_verification_failed_safely}}', 'noise']) assert.throws(() => helper.validateResult(bad, 'check'));
});
test('receipt is root-owned, bounded, non-writable and cannot be symlinked', () => {
  const dir = fs.mkdtempSync('/tmp/gemini-receipt-permission-test.'), file = path.join(dir, 'r.json');
  fs.writeFileSync(file, '{}', {mode: 0o600}); assert.deepEqual(helper.protectedReceipt(file), {});
  fs.chmodSync(file, 0o666); assert.throws(() => helper.protectedReceipt(file));
  fs.chmodSync(file, 0o644); fs.symlinkSync(file, path.join(dir, 'alias')); assert.throws(() => helper.protectedReceipt(path.join(dir, 'alias')));
  fs.unlinkSync(path.join(dir, 'alias')); fs.unlinkSync(file); fs.rmdirSync(dir);
});
test('generated Erlang has fixed scope and no data mutation/restart/global flush calls', () => {
  const rendered = helper.render(template, expected, 'activate', 'nonode@nohost');
  assert(!rendered.includes('@@'));
  assert(!/save_doc|ensure_saved|update_doc|del_doc|put_attachment|delete_all_objects|:flush\(|restart|stop\(/.test(rendered.replace(/^\s*%%.*$/gm, '')));
  assert(rendered.includes('Modules = [media_map, kz_media_map]'));
  assert(rendered.includes('<<"_rev">>'));
  assert.throws(() => helper.render(template, expected.slice(1), 'activate', 'nonode@nohost'));
});
test('portable wrapper validates exact receipts and uses protected SUP without credential/node mistakes', () => {
  const plan = fullPlan;
  const receipt = {schema_version:1,owner:importer.OWNER,created:0,preserved:165,verified:165,
    queue_configuration_changed:false,runtime_ready:false,full_position_language_ready:false,
    prompts:plan.map(p=>({locale:p.locale,canonical_id:p.canonical_id,prompt_id:p.prompt_id,
      document_id:p.id,attachment:p.attachment,sha256:p.sha256,revision}))};
  assert.equal(helper.expectedDocuments(plan,receipt,importer,validateReceipt).length,165);
  const bad=JSON.parse(JSON.stringify(receipt));bad.prompts[0].prompt_id='custom-recording';
  assert.throws(()=>helper.expectedDocuments(plan,bad,importer,validateReceipt));
  const dir=fs.mkdtempSync('/tmp/gemini-wrapper-test.'), file=path.join(dir,'receipt.json');
  fs.writeFileSync(file,JSON.stringify(receipt),{mode:0o600});
  const opts={mode:'activate',node:'kazoo_apps@example.invalid',receipt:file,
    fixed,completion,toolDirectory};
  let rpc=0, renderedFile;
  function spawn(command,args) {
    if(command==='getent'){assert.deepEqual(args,['group','kazoo']);return {status:0,stdout:'kazoo:x:987:\n'};}
    assert.equal(command,'/usr/local/bin/sup');assert.equal(args[args.indexOf('-n')+1],'kazoo_apps');
    assert.deepEqual(args.slice(-3,-1),['file','script']);renderedFile=JSON.parse(args.at(-1));
    assert.equal(fs.statSync(renderedFile).mode&0o777,0o640);assert.equal(fs.statSync(renderedFile).gid,987);
    assert(fs.readFileSync(renderedFile,'utf8').includes('<<"kazoo_apps@example.invalid">>'));
    rpc++;return {status:0,stdout:'{ok,{ok,{gemini_mapping_verified,activate,165,330,330,no_database_writes}}}'};
  }
  const result=helper.execute(opts,{spawn,temporaryParent:dir,templateDirectory:__dirname});
  assert.equal(rpc,1);assert.equal(result.mappings_verified,330);assert.equal(result.database_writes,false);
  assert.equal(fs.existsSync(renderedFile),false);assert.deepEqual(fs.readdirSync(dir),['receipt.json']);
  fs.unlinkSync(file);fs.rmdirSync(dir);
});
test('actual Erlang template validates activation, check, revisions and custom-map preservation', () => {
  const dir = fs.mkdtempSync('/tmp/gemini-portable-erlang-tests.');
  fs.writeFileSync(path.join(dir, 'expectations.json'), JSON.stringify(original));
  for (const mode of ['activate', 'check']) fs.writeFileSync(path.join(dir, mode + '.erl'), helper.render(template, expected, mode, 'nonode@nohost'));
  // Reuse isolated test stubs only, never Kazoo's running processes or database.
  const names = ['kz_datamgr.erl', 'gen_listener.erl', 'media_map.erl', 'kz_media_map.erl'];
  const runner = `-module(portable_runner).
-export([run/1]).
run(Dir) ->
  true = string:prefix(code:which(kz_datamgr), Dir) =/= nomatch,
  {ok,B}=file:read_file(filename:join(Dir,"expectations.json")), E=kz_json:decode(B),
  [register(M,spawn(fun()->receive stop->ok end end))||M<-[media_map,kz_media_map]],
  [ets:new(M,[named_table,set,protected,{keypos,2}])||M<-[media_map,kz_media_map]],
  Docs=maps:from_list([{kz_json:get_value(<<"id">>,X),runner:document(X)}||X<-E]),
  put(docs,Docs), Check=filename:join(Dir,"check.erl"), Act=filename:join(Dir,"activate.erl"),
  {ok,{error,gemini_mapping_verification_failed_safely}}=file:script(Check), undefined=get(writes),
  Custom={media_map,<<"system_media/acdc-callback-success">>,<<"system_media">>,<<"acdc-callback-success">>,kz_json:from_list([{<<"en-us">>,<<"/custom-recording">>}])},
  ets:insert(media_map,Custom),
  {ok,{ok,{gemini_mapping_verified,activate,165,330,330,no_database_writes}}}=file:script(Act),
  330=get(writes), [Custom]=ets:lookup(media_map,<<"system_media/acdc-callback-success">>),
  {ok,{ok,{gemini_mapping_verified,check,165,330,0,no_database_writes}}}=file:script(Check),330=get(writes),
  {ok,{ok,{gemini_mapping_verified,activate,165,330,0,no_database_writes}}}=file:script(Act),
  [First|_]=E, Id=kz_json:get_value(<<"id">>,First),
  put(docs,maps:put(Id,kz_json:set_value(<<"_rev">>,<<"2-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>,maps:get(Id,Docs)),Docs)),
  put(writes,0),{ok,{error,gemini_mapping_verification_failed_safely}}=file:script(Act),0=get(writes),
  io:format("PASS template missing/check,330-map activation,idempotence,custom preservation,receipt revision guards~n"), halt(0).
`;
  fs.writeFileSync(path.join(dir, 'portable_runner.erl'), runner);
  const stubDirectory = path.join(__dirname, 'gemini-cache-test-stubs');
  const oldRunner = fs.readFileSync(path.join(stubDirectory, 'runner.erl'), 'utf8').replace('-export([run/1]).', '-export([run/1, document/1]).');
  fs.writeFileSync(path.join(dir, 'runner.erl'), oldRunner);
  const env = {...process.env, ERL_LIBS: path.join(sourceRoot,'deps')+':'+path.join(sourceRoot,'core'), ERL_FLAGS: '+S 1:1 +SDcpu 1 +SDio 1 +A 1', ERL_CRASH_DUMP: '/dev/null'};
  let r = cp.spawnSync('erlc', ['-Werror', '-o', dir, ...names.map(n => path.join(stubDirectory,n)), path.join(dir, 'runner.erl'), path.join(dir, 'portable_runner.erl')], {env, encoding: 'utf8'});
  assert.equal(r.status, 0, r.stdout + r.stderr);
  r = cp.spawnSync('erl', ['-pa', dir, '-noshell', '-eval', 'portable_runner:run("' + dir + '").'], {env, encoding: 'utf8', timeout: 60000});
  assert.equal(r.status, 0, r.stdout + r.stderr);
});
