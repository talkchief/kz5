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
