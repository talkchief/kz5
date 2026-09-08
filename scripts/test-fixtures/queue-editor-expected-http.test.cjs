'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),h=require('./queue-editor-expected-http.cjs');
function fixture(){const receipt={};let n=0;for(const [label,codes] of Object.entries(h.LABELS))h.record(receipt,{status:codes[0],
    body:{status:'error',error:String(codes[0]),message:'expected_fixture_response',request_id:String(++n).padStart(32,'0')}},label);return receipt.http_rejections;}
const line=e=>'12:34:56.789 [info] |'+e.request_id+'|api_util:1980(<0.123.0>) generating error '+e.status+' '+e.message+' response';
test('only all five exact recorded INFO negative responses are accepted',()=>{
    const entries=fixture();assert.deepEqual(h.classify(entries.map(line),entries),{expected_http_rejections:5,missing_expected_rejections:0,unexpected_error_lines:0});
});
test('different request, code, reason, module or severity is never allowlisted',()=>{
    const entries=fixture(),lines=entries.map(line);
    for(const changed of [lines[0].replace(entries[0].request_id,'f'.repeat(32)),lines[0].replace('401','500'),
        lines[0].replace('expected_fixture_response','other'),lines[0].replace('api_util','other_module'),lines[0].replace('[info]','[error]')])
        assert.equal(h.classify([changed,...lines.slice(1)],entries).unexpected_error_lines,1);
});
test('missing/duplicate observations and unrelated failures remain visible',()=>{
    const entries=fixture(),lines=entries.map(line);
    assert.equal(h.classify(lines.slice(1),entries).missing_expected_rejections,1);
    assert.equal(h.classify([...lines,lines[0]],entries).unexpected_error_lines,1);
    assert.equal(h.classify([...lines,'[error] unrelated crash'],entries).unexpected_error_lines,1);
});
test('partial or fabricated rejection envelope metadata is refused',()=>{
    const entries=fixture();assert.throws(()=>h.classify([],entries.slice(1)));
    for(const body of [{status:'success',error:'401'}, {status:'error',error:'401',message:'private data here',request_id:'a'.repeat(32)},
        {status:'error',error:'401',message:'invalid_credentials',request_id:'bad'}])assert.throws(()=>h.record({},{status:401,body},'anonymous_rejected'));
});
function journalFixture(){const entries=fixture(),files=entries.map((e,i)=>line(e).replace('56.789','56.00'+i));
    const records=files.map(l=>({priority:'6',message:l.replace('[info] |','\x1b[1;37minfo |').replace(/\|[a-f0-9]{32}\|api_util:(\d+)\(<\d+\.\d+\.\d+>\) /,'api_util.$1 \x1b[0m')}));
    return {entries,files,records};}
test('coloured journal INFO correlates one-to-one with exact request-ID file evidence',()=>{
    const f=journalFixture();assert.deepEqual(h.classifyJournal(f.records,f.files,f.entries),
        {expected_http_rejections:5,missing_expected_rejections:0,unexpected_error_lines:0});
});
test('journal priority, timestamp, response, duplicates and unrelated failures are not ignored',()=>{
    const f=journalFixture();for(const row of [{...f.records[0],priority:'3'},
        {...f.records[0],message:f.records[0].message.replace('56.000','55.000')},
        {...f.records[0],message:f.records[0].message.replace('401','500')}])
        assert.equal(h.classifyJournal([row,...f.records.slice(1)],f.files,f.entries).unexpected_error_lines,1);
    assert.equal(h.classifyJournal([...f.records,f.records[0]],f.files,f.entries).unexpected_error_lines,1);
    assert.equal(h.classifyJournal(f.records.slice(1),f.files,f.entries).missing_expected_rejections,1);
    assert.equal(h.classifyJournal([...f.records,{priority:'3',message:'error unrelated runtime failure'}],f.files,f.entries).unexpected_error_lines,1);
    assert.equal(h.classifyJournal([...f.records,{priority:'2',message:'halt requested'}],f.files,f.entries).unexpected_error_lines,1);
    assert.equal(h.classifyJournal([...f.records,{priority:'6',message:'12:34:56.999 critical runtime stopped'}],f.files,f.entries).unexpected_error_lines,1);
});
test('ambiguous or incomplete file evidence cannot authorize journal exceptions',()=>{
    const f=journalFixture();assert.throws(()=>h.classifyJournal(f.records,f.files.slice(1),f.entries));
    f.files[4]=f.files[4].replace('56.004','56.003');
    assert.throws(()=>h.classifyJournal(f.records,f.files,f.entries),/Ambiguous/);
});
