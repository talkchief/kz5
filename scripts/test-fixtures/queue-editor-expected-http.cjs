'use strict';
// Only exact INFO response-envelope messages for this test's recorded negative
// HTTP requests are expected. Never suppress a severity error or another request.
const assert=require('node:assert/strict');
const LABELS=Object.freeze({anonymous_rejected:[401,403],changed_create_request_id_rejected:[409],
    stale_queue_revision_rejected:[409],deleted_queue_absent:[404],deleted_callflow_absent:[404]});
const ERROR_PATTERN=/\[(err|error|crit|critical|alert|emerg|emergency)\]|(^|[^a-z0-9_])(error|fatal|crash|segfault|core dumped)([^a-z0-9_]|$)|badmatch|no amqp connection available|timeout after .* receiving route response|no available handlers/i;
function validate(entry) {
    assert(entry&&Object.hasOwn(LABELS,entry.label)&&LABELS[entry.label].includes(entry.status)
        &&/^[a-f0-9]{32}$/.test(entry.request_id)&&/^[a-z_]{1,80}$/.test(entry.message),'Invalid expected rejection');
    return entry;
}
function record(receipt,response,label) {
    assert(response.body?.status==='error'&&response.body.error===String(response.status),'Not an HTTP error envelope');
    const entry=validate({label,status:response.status,request_id:response.body.request_id,message:response.body.message});
    const prior=receipt.http_rejections||[];
    assert(!prior.some(x=>x.label===label||x.request_id===entry.request_id),'Duplicate rejection receipt');
    receipt.http_rejections=prior.concat(entry);
}
function classify(lines,entries) {
    assert(Array.isArray(lines)&&Array.isArray(entries));
    const expected=new Map();
    for(const entry of entries) {validate(entry);assert(!expected.has(entry.request_id));expected.set(entry.request_id,entry);}
    assert.deepEqual(entries.map(x=>x.label).sort(),Object.keys(LABELS).sort(),'Complete negative-request evidence required');
    const seen=new Set();let unexpected=0;
    for(const line of lines) {
        assert(typeof line==='string');
        if(!ERROR_PATTERN.test(line))continue;
        const match=/^(?:\d\d:\d\d:\d\d\.\d{3} )?\[info\] \|([a-f0-9]{32})\|api_util:\d+\(<\d+\.\d+\.\d+>\) generating error (\d{3}) ([a-z_]{1,80}) response$/.exec(line);
        const entry=match&&expected.get(match[1]);
        if(!entry||entry.status!==Number(match[2])||entry.message!==match[3]||seen.has(match[1]))unexpected++;
        else seen.add(match[1]);
    }
    return {expected_http_rejections:seen.size,missing_expected_rejections:expected.size-seen.size,unexpected_error_lines:unexpected};
}
function classifyJournal(records,fileLines,entries) {
    const verified=classify(fileLines,entries);
    assert(verified.expected_http_rejections===5&&verified.missing_expected_rejections===0&&verified.unexpected_error_lines===0,
        'Journal correlation requires a clean request-ID-verified file window');
    const tuples=new Map(),ids=new Set(entries.map(e=>e.request_id));
    for(const line of fileLines) {
        const m=/^(\d\d:\d\d:\d\d\.\d{3}) \[info\] \|([a-f0-9]{32})\|api_util:(\d+)\(<\d+\.\d+\.\d+>\) generating error (\d{3}) ([a-z_]{1,80}) response$/.exec(line);
        if(!m||!ids.has(m[2]))continue;
        const key=JSON.stringify([m[1],m[3],m[4],m[5]]);
        assert(!tuples.has(key),'Ambiguous timestamp/module/response correlation');tuples.set(key,m[2]);
    }
    assert.equal(tuples.size,5);
    const seen=new Set();let unexpected=0;
    for(const row of records) {
        assert(row&&typeof row.message==='string');
        const line=row.message.replace(/\x1b\[[0-9;]*m/g,'');
        if(/^[0-3]$/.test(row.priority)||/^\d\d:\d\d:\d\d\.\d{3} (error|critical|alert|emergency) /.test(line)) {unexpected++;continue;}
        if(!ERROR_PATTERN.test(line))continue;
        const m=/^(\d\d:\d\d:\d\d\.\d{3}) info api_util\.(\d+) generating error (\d{3}) ([a-z_]{1,80}) response$/.exec(line);
        const id=m&&tuples.get(JSON.stringify(m.slice(1)));
        if(row.priority!=='6'||!id||seen.has(id))unexpected++;
        else seen.add(id);
    }
    return {expected_http_rejections:seen.size,missing_expected_rejections:5-seen.size,unexpected_error_lines:unexpected};
}
module.exports={record,classify,classifyJournal,LABELS};
