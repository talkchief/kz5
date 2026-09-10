'use strict';
// One source for the OpenAPI instructions and the separately linked how-to page.
const modes = [
    {name: 'Whisper', action: 'whisper', text: 'Coach the agent privately. The supervisor hears the conversation and speaks only to the targeted agent; the customer cannot hear the supervisor.'},
    {name: 'Barge', action: 'barge', text: 'Speak to both parties in the active conversation. Both the agent and the customer hear the supervisor.'},
    {name: 'Join', action: 'join', text: 'Join the active conversation with full two-way audio. Currently this is the same audio mode as Barge, not a separate conference-room API.'},
    {name: 'Listen', action: 'eavesdrop', text: 'Listen silently. The supervisor hears both parties; neither party hears the supervisor. The API action is eavesdrop, not listen.'}
];
const endpoint = 'POST /v2/accounts/{ACCOUNT_ID}/channels/{UUID}';
const setup = 'Use an account administrator token whose authenticated account exactly equals ACCOUNT_ID (also for resellers). Select a currently answered, bridged call in that account. UUID is the original agent-side call-leg identifier, not the caller number, queue ID, user ID or device ID. Read GET /v2/accounts/{ACCOUNT_ID}/channels and GET /v2/accounts/{ACCOUNT_ID}/channels/{UUID} to inspect current calls; correlate the leg to the intended agent/device rather than choosing the first result. If the leg identity is uncertain, do not start supervision. SUPERVISOR_DEVICE_ID is the enabled account-owned sip_device or softphone on which the supervisor will answer, using that account SIP realm; it must be registered and reachable. It is not the agent device ID. Replace every placeholder below. Keep the token server-side in Next.js and obtain it from a protected secret/session, not client bundles or shared logs.';
function body(action) {
    return JSON.stringify({data: {action, device_id: 'SUPERVISOR_DEVICE_ID', timeout: 20}}, null, 2);
}
function curl(action) {
    return `curl --request POST 'https://YOUR_KAZOO_HOST/v2/accounts/ACCOUNT_ID/channels/AGENT_CALL_ID' \\\n  --header "X-Auth-Token: $KAZOO_TOKEN" \\\n  --header 'Content-Type: application/json' \\\n  --data '${body(action)}'`;
}
const connected = 'Answer the incoming call on the supervisor device within timeout seconds (default 20; allowed 5–60). HTTP 202 only means the request was accepted; it does not prove the supervisor answered or audio connected. Save data.request_id and data.supervisor_call_id from the response (not the top-level HTTP request_id). Observe the returned supervisor channel through GET /v2/accounts/{ACCOUNT_ID}/channels/{supervisor_call_id} and live call events. Do not display Connected until the correlated supervisor call is answered and connected; a channel lookup alone cannot prove audio privacy. No keypad escalation between monitoring modes is enabled.';
const stop = `curl --request POST 'https://YOUR_KAZOO_HOST/v2/accounts/ACCOUNT_ID/channels/SUPERVISOR_CALL_ID' \\\n  --header "X-Auth-Token: $KAZOO_TOKEN" \\\n  --header 'Content-Type: application/json' \\\n  --data '{"data":{"action":"stop_monitoring","request_id":"MONITOR_REQUEST_ID"}}'`;
const stopping = 'Use data.supervisor_call_id from the start response in the stop URL, and that same response’s data.request_id as MONITOR_REQUEST_ID. Never put the original agent/customer call ID in the stop URL. A successful stop is accepted with HTTP 202; verify the supervisor leg ends and the original conversation remains. Do not blindly retry a start or stop after an ambiguous timeout; reconcile the correlated channel first. To change mode, stop and verify the previous supervisor leg has ended before starting another mode.';
const errors = '400: invalid fields/device/timeout. 401: invalid authentication. 403: wrong account, non-admin, or invalid stop ownership. 404: target/device absent. 409: ambiguous channel ownership. 503: route, live ownership or execution could not be verified. Treat these as unsuccessful, not connected. A lost response does not establish that no supervisor call was created. Do not use the legacy /queues/eavesdrop endpoints: they deliberately return 503. Do not send arbitrary dial strings, endpoints, FreeSWITCH node names, headers or raw commands.';
const proof = 'Actual distributed SIP/RTP acceptance passed on 2026-09-09: Listen/eavesdrop, Whisper, Barge and Join, using separate applications, controllers, Kamailio and FreeSWITCH roles in an isolated lab. Synthetic tones verified both permitted audio and forbidden leakage before/after keypad 3, authorization denials, and supervisor-only stop with the original bridge surviving. This is real call/audio evidence, not only HTTP 202. It does not certify failover during supervision or indefinite production load. Repository evidence: doc/channel_monitor_acceptance.md; private native run /var/log/kazoo-monitor-acceptance-6xZDTb on dev44.';
function description() {
    return '## Before you start\n\n' + setup + '\n\n' + modes.map(m =>
        `## ${m.name}\n\n${m.text}\n\n**How to call:** \`${endpoint}\` with \`data.action=${m.action}\`.\n\n\`\`\`sh\n${curl(m.action)}\n\`\`\`\n\n**How to use:** ${connected}\n\n**How to stop ${m.name}:** ${stopping}\n\n\`\`\`sh\n${stop}\n\`\`\``).join('\n\n') +
        '\n\n## Errors and safety\n\n' + errors + '\n\n## Actual-call testing\n\n' + proof +
        '\n\nThe same POST also accepts legacy non-monitoring actions; those remain a separate, incompletely typed contract.';
}
const escape = s => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
function html() {
    return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Whisper, Barge, Join and Listen — Kazoo API</title><link rel="icon" href="data:,"><link rel="stylesheet" href="./portal.css"></head>
<body><main class="portal supervision"><h1>Call supervision</h1>
<nav><a href="./index.html">OpenAPI reference</a>${modes.map(m => `<a href="#${m.name.toLowerCase()}">${m.name}</a>`).join('')}<a href="#testing">Actual-call testing</a></nav>
<p>Choose a feature below. Each section includes its request and complete operating steps. This page is read-only and never executes calls.</p>
<h2>Before you start</h2><p>${escape(setup)}</p>
${modes.map(m => `<section id="${m.name.toLowerCase()}"><h2>${m.name}</h2><p>${escape(m.text)}</p><h3>How to call ${m.name}</h3><p><code>${escape(endpoint)}</code> — action <code>${m.action}</code></p><pre><code>${escape(curl(m.action))}</code></pre><h3>How to use ${m.name}</h3><p>${escape(connected)}</p><h3>How to stop ${m.name}</h3><p>${escape(stopping)}</p><pre><code>${escape(stop)}</code></pre></section>`).join('\n')}
<h2>Errors and safety</h2><p>${escape(errors)}</p><section id="testing"><h2>Actual-call testing</h2><p>${escape(proof)}</p></section>
</main></body></html>\n`;
}
module.exports = {modes, description, html};
