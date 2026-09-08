'use strict';
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const FIELD = 'call_forward_confirmation';
const ROUTE = '/accounts/{ACCOUNT_ID}';
const locales = ['en-us', 'he-il', 'ar-sa', 'es-es', 'fr-fr'];
function applyCallForwardConfirmation({spec, root}) {
    const files = ['scripts/api-docs-call-forward-confirmation.cjs',
        'applications/crossbar/priv/couchdb/schemas/accounts.json',
        'applications/crossbar/src/modules/cb_accounts.erl',
        'applications/crossbar/src/cb_account_call_forward_confirmation.erl',
        'core/kazoo_media/src/kz_call_forward_confirmation.erl',
        'core/kazoo_media/src/call_forward_confirmation_assets.hrl'];
    const inputs = files.map(file => ({file, sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex')}));
    const accountSchema = JSON.parse(fs.readFileSync(path.join(root, files[1]), 'utf8'));
    const stored = structuredClone(accountSchema.properties[FIELD]);
    delete stored['kz:skip_subproperty_builder'];
    const schemas = spec.components.schemas;
    schemas.ForwardedCallConfirmation = stored;
    schemas.accounts.properties[FIELD] = {$ref: '#/components/schemas/ForwardedCallConfirmation'};
    const update = structuredClone(schemas.accounts);
    update.properties[FIELD] = {type: 'object', additionalProperties: false, required: ['language'], properties: {
        language: {type: 'string', enum: [...locales, null], nullable: true,
            description: 'en-us, he-il, ar-sa, es-es or fr-fr selects a packaged recording. Explicit null deletes the stored preference and restores the existing prompt resolver. Omission preserves the saved preference, including on POST.'}
    }};
    delete update.required;
    schemas.AccountConfirmationPatchData = update;
    schemas.AccountConfirmationPostData = structuredClone(update);
    if (schemas.accounts.required) schemas.AccountConfirmationPostData.required = schemas.accounts.required;
    const description = 'Forwarded-call confirmation: data.call_forward_confirmation.language selects en-us, he-il, ar-sa, es-es or fr-fr for the account owning the forwarding rule. ' +
        'It applies only where forwarding/failover already requires key 1; forwarding enablement, keypress settings, timeouts, caller ID and other prompt languages are unchanged. ' +
        'No preference retains the existing call/endpoint-language and custom-media resolver. Explicit selection uses immutable shared recordings; no online synthesis occurs on save or calls. ' +
        'Use PATCH with the data envelope for this setting. Omission preserves its current value even on a full account POST; language:null explicitly clears it. ' +
        'Each account/sub-account has its own preference with no new automatic parent inheritance. Existing legs retain their prompt; new legs observe changes after normal account-cache invalidation. ' +
        'Changes/reset require an authenticated account administrator, account API-auth principal, or system administrator with the applicable tenant/hierarchy and token scopes. ' +
        'Unsupported/invalid values return 400, forbidden changes 403 and unavailable or corrupt selected audio 503 without saving. Account/token/transport failures retain the existing Crossbar behavior. ' +
        'Stored/read values never contain the reset null. Ordinary account fields and their existing requirements remain authoritative. This source contract is not evidence of deployed or physical-cellphone acceptance.';
    const ref = name => ({$ref: '#/components/schemas/' + name});
    const response = schema => ({description: 'Success; standard Crossbar envelope and account data', content: {'application/json': {schema: {
        type: 'object', required: ['data'], properties: {data: schema, status: {type: 'string'}, request_id: {type: 'string'}}
    }}}});
    for (const method of ['get', 'patch', 'post']) {
        const op = spec.paths[ROUTE][method];
        op.description = [op.description, description].filter(Boolean).join('\n\n');
        op.security = [{CrossbarToken: []}];
        op['x-contract-review'] = 'source-reviewed for forwarded-call confirmation; other account behavior remains upstream-described';
        op['x-source-file'] = files[3];
        op.responses[200] = response(ref('accounts'));
        for (const [code, text] of Object.entries({400: 'Invalid account or preference', 401: 'Invalid or expired authentication',
            403: 'Tenant, token scope or account administrator permission denied', 404: 'Account not found',
            409: 'Account revision conflict', 503: 'Selected recording or datastore unavailable; no preference saved'}))
            op.responses[code] = {description: text, content: {'application/json': {schema: ref('CrossbarError')}}};
        if (method !== 'get') {
            const dataSchema = ref(method === 'patch' ? 'AccountConfirmationPatchData' : 'AccountConfirmationPostData');
            op.requestBody = {required: true, content: {'application/json': {schema: {type: 'object', required: ['data'], properties: {data: dataSchema}}}}};
        }
    }
    spec.paths[ROUTE].patch.requestBody.content['application/json'].examples = {
        english: {value: {data: {[FIELD]: {language: 'en-us'}}}},
        hebrew: {value: {data: {[FIELD]: {language: 'he-il'}}}},
        arabic: {value: {data: {[FIELD]: {language: 'ar-sa'}}}},
        spanish: {value: {data: {[FIELD]: {language: 'es-es'}}}},
        french: {value: {data: {[FIELD]: {language: 'fr-fr'}}}},
        reset: {value: {data: {[FIELD]: {language: null}}}}
    };
    spec.paths[ROUTE].patch['x-codeSamples'] = [{lang: 'JavaScript', label: 'Custom frontend: change confirmation language', source:
        "async function setConfirmationLanguage(apiBase, accountId, token, language) {\n" +
        "  const response = await fetch(`${apiBase}/accounts/${encodeURIComponent(accountId)}`, {\n" +
        "    method: 'PATCH', headers: {'Content-Type': 'application/json', 'X-Auth-Token': token},\n" +
        "    body: JSON.stringify({data: {call_forward_confirmation: {language}}})\n" +
        "  });\n  const result = await response.json();\n" +
        "  if (!response.ok) throw new Error(result.message || 'Language change failed');\n" +
        "  return result.data.call_forward_confirmation?.language ?? null;\n}\n" +
        "// apiBase is your HTTPS Crossbar URL ending in /v2.\n// language: 'en-us', 'he-il', 'ar-sa', 'es-es', 'fr-fr', or null to reset. Keep token in runtime state only."
    }];
    return {inputs};
}
module.exports = {applyCallForwardConfirmation, FIELD, ROUTE, locales};
