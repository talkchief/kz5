'use strict';
// Source-bound members/devices OpenAPI contract, generated offline.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const ENDPOINT='/accounts/{ACCOUNT_ID}/members/devices';
const digest=b=>crypto.createHash('sha256').update(b).digest('hex');
const ref=name=>({$ref:'#/components/schemas/'+name});
const nullableText={type:'string',nullable:true,maxLength:256,'x-max-utf8-bytes':256};
const timestamp={type:'integer',format:'int64',minimum:0,description:'Unix epoch milliseconds, not seconds or Gregorian seconds.'};
const expiry={...timestamp,nullable:true,minimum:946684800000,maximum:4102444800000,
    description:'Last known unexpired finite binding expiry, in Unix epoch milliseconds. Null or omitted for permanent, absent, expired, or unverified bindings. Never a fabricated cache TTL.'};
const hex={type:'string',pattern:'^[a-f0-9]{32}$'};
const strict=(properties,required=Object.keys(properties))=>({type:'object',properties,required,additionalProperties:false});
function overlay({sourcePath=path.join(__dirname,'../applications/crossbar/src/modules/cb_members.erl'), status='implemented-source-reviewed'}={}) {
    const bytes=fs.readFileSync(sourcePath),source=bytes.toString();
    for(const expected of ['-define(DEVICE_LIMIT, 1000).','-define(REGISTRATION_LIMIT, 10000).','page_size(undefined) -> 25;',
        'N =< 100','search_realm_regs(Realm, <<"detail">>)','registration_expiry(0) -> permanent;',
        'E > Observed','<<"no-store">>','<<"devices_complete">>','<<"custom_realm_not_queried">>',
        'authorized(scoped(Context, <<"users">>))','authorized(scoped(Context, <<"devices">>))'])assert(source.includes(expected),'Candidate source contract changed');
    const reasons={online:['registered','registered_permanent'],offline:['not_registered','registration_expired'],
        unknown:['not_registration_based','non_registration_auth','missing_registration_identity','missing_account_realm',
            'invalid_registration_identity','custom_realm_not_queried','registration_unavailable','expiry_unavailable']};
    const registration=strict({status:{type:'string',enum:Object.keys(reasons)},reason:{type:'string',enum:Object.values(reasons).flat()},
        registrable:{type:'boolean'},observed_at_ms:timestamp,expires_at_ms:expiry},['status','reason','registrable','observed_at_ms']);
    registration.oneOf=[
        {properties:{status:{enum:['online']},reason:{enum:['registered']},registrable:{enum:[true]},expires_at_ms:{...expiry,nullable:false}},required:['expires_at_ms']},
        {properties:{status:{enum:['online']},reason:{enum:['registered_permanent']},registrable:{enum:[true]},expires_at_ms:{type:'integer',nullable:true,enum:[null]}}},
        {properties:{status:{enum:['offline']},reason:{enum:reasons.offline},registrable:{enum:[true]},expires_at_ms:{type:'integer',nullable:true,enum:[null]}}},
        {properties:{status:{enum:['unknown']},reason:{enum:reasons.unknown.slice(0,2)},registrable:{enum:[false]},expires_at_ms:{type:'integer',nullable:true,enum:[null]}}},
        {properties:{status:{enum:['unknown']},reason:{enum:reasons.unknown.slice(2)},registrable:{enum:[true]},expires_at_ms:{type:'integer',nullable:true,enum:[null]}}}
    ];
    registration.description='Registration is distinct from enabled state and call reachability. Offline requires a complete correlated cluster response. Partial peers/parts, timeout and malformed expiry never prove offline. Multiple contacts are online if any finite binding is unexpired or a permanent binding exists. Expired-only rows are offline; expired+unknown-expiry rows remain unknown.';
    const member=strict({id:hex,name:nullableText,first_name:nullableText,last_name:nullableText,enabled:{type:'boolean'},
        devices:{type:'array',maxItems:1000,items:ref('MemberDevice')},devices_complete:{type:'boolean'},
        device_count:{type:'integer',minimum:0,maximum:1000,nullable:true}},['id','enabled','devices','devices_complete']);
    member.oneOf=[{properties:{devices_complete:{enum:[true]},device_count:{type:'integer',minimum:0,maximum:1000}},required:['device_count']},
        {properties:{devices_complete:{enum:[false]},devices:{maxItems:0},device_count:{type:'integer',nullable:true,enum:[null]}}}];
    member.description='One account user, including users with zero devices. Devices are associated only by their owner_id: unassigned devices are excluded from member lists; shared-device memberships and active hotdesk sessions are not expanded into additional owners. Account device_inventory.count still includes unassigned devices. A complete zero-device member has devices=[] and device_count=0. An incomplete inventory has devices=[] with devices_complete=false and null/omitted device_count; do not interpret that as zero devices.';
    const inventory=strict({complete:{type:'boolean'},limit:{type:'integer',enum:[1000]},count:{type:'integer',minimum:0,maximum:1000,nullable:true},
        reason:{type:'string',enum:['complete','limit_exceeded']}},['complete','limit','reason']);
    inventory.oneOf=[{properties:{complete:{enum:[true]},reason:{enum:['complete']},count:{type:'integer',minimum:0,maximum:1000}},required:['count']},
        {properties:{complete:{enum:[false]},reason:{enum:['limit_exceeded']},count:{type:'integer',nullable:true,enum:[null]}}}];
    const snapshot=strict({complete:{type:'boolean'},reason:{type:'string',enum:['complete','not_requested','missing_account_realm','registration_unavailable','invalid_registration_response']},
        started_at_ms:timestamp,observed_at_ms:timestamp,expiry_available:{type:'boolean'},
        source:{type:'string',enum:['cluster_registrar_detail']},semantics:{type:'string',enum:['registration_not_call_reachability']}});
    snapshot.oneOf=[{properties:{complete:{enum:[true]},reason:{enum:['complete']}}},
        {properties:{complete:{enum:[false]},reason:{enum:['not_requested','missing_account_realm','registration_unavailable','invalid_registration_response']},expiry_available:{enum:[false]}}}];
    const data=strict({items:{type:'array',maxItems:100,items:ref('MemberWithDevices')},count:{type:'integer',minimum:0,maximum:100},
        page_size:{type:'integer',minimum:1,maximum:100},has_more:{type:'boolean'},
        next_cursor:{type:'string',nullable:true,maxLength:256,pattern:'^[A-Za-z0-9_-]+$'},
        total_members:{type:'integer',nullable:true,enum:[null]},device_inventory:ref('MemberDeviceInventory'),registration_snapshot:ref('MemberRegistrationSnapshot')},
    ['items','count','page_size','has_more','device_inventory','registration_snapshot']);
    data.oneOf=[{properties:{has_more:{enum:[true]},next_cursor:{type:'string',nullable:false,minLength:1}},required:['next_cursor']},
        {properties:{has_more:{enum:[false]},next_cursor:{type:'string',nullable:true,enum:[null]}}}];
    // Apply page-wide evidence constraints in addition to each local schema and cursor branch.
    const fields=properties=>({type:'object',properties}),each=items=>({type:'array',items});
    data.allOf=[
        {oneOf:[true,false].map(complete=>fields({
            device_inventory:fields({complete:{type:'boolean',enum:[complete]}}),
            items:each(fields({devices_complete:{type:'boolean',enum:[complete]}}))
        }))},
        {oneOf:[
            fields({registration_snapshot:fields({complete:{type:'boolean',enum:[true]}})}),
            fields({registration_snapshot:fields({complete:{type:'boolean',enum:[false]}}),
                items:each(fields({devices:each(fields({registration:fields({status:{type:'string',enum:['unknown']}})}))}))})
        ]}
    ];
    data.description='Member-paginated live listing, not a cross-page database transaction. Count is the current page count; total_members is deliberately unknown. A page includes users with no devices. Optional nullable properties may be omitted by Crossbar envelope null filtering: absent means unknown/not applicable, never zero, false, or an empty complete inventory. Device catalog limit applies to the entire account, not each member. Above1000 account devices, all device inventories are explicitly incomplete; member pagination does not bypass this limit and no device continuation API is currently supplied.';
    const schemas={MemberDeviceRegistration:registration,MemberDevice:strict({id:hex,name:nullableText,type:nullableText,enabled:{type:'boolean'},registration:ref('MemberDeviceRegistration')},['id','enabled','registration']),
        MemberWithDevices:member,MemberDeviceInventory:inventory,MemberRegistrationSnapshot:snapshot,MemberDevicesPage:data,
        MemberDevicesEnvelope:{type:'object',required:['status','data'],properties:{status:{type:'string',enum:['success']},data:ref('MemberDevicesPage')},additionalProperties:true},
        MemberDevicesError:{type:'object',properties:{status:{type:'string'},message:{type:'string'},error:{},data:{type:'object'}},additionalProperties:true}};
    const response=(description,schema)=>({description,content:{'application/json':{schema}}});
    const operation={operationId:'getAccountMembersDevices',summary:'List account members and their devices with fresh registration evidence',tags:['Members'],
        description:'Read-only account endpoint. Requires existing authenticated account access plus users/devices GET authorization and scopes; an allow does not override a global/module stop. No users, devices, registrations or roster are changed. Online means observed unexpired/permanent SIP registration, not successful calling. Device expiry evaluation requires synchronized cluster clocks. No credentials or registrar contact metadata are returned.',
        security:[{CrossbarToken:[]}],parameters:[{name:'ACCOUNT_ID',in:'path',required:true,schema:hex},
            {name:'page_size',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:25},description:'Strict decimal page size; 0, leading-zero strings, fractions and values above100 are rejected.'},
            {name:'cursor',in:'query',schema:{type:'string',maxLength:256,minLength:1},description:'Opaque account-bound cursor from next_cursor; omit on the first page. A malformed or different-account cursor is400. No client-controlled database/key/range is accepted.'}],
        responses:{200:{...response('Fresh member page; per-device evidence may be unknown or inventory explicitly incomplete',ref('MemberDevicesEnvelope')),
            headers:{'Cache-Control':{description:'Fresh observations must not be cached.',schema:{type:'string',enum:['no-store']}}}},
            400:response('Invalid cursor/page size or unknown query parameter',ref('MemberDevicesError')),401:response('Missing or invalid authentication',ref('MemberDevicesError')),
            403:response('Account/resource/scope authorization denied',ref('MemberDevicesError')),404:response('Unknown route',ref('MemberDevicesError')),
            503:response('Unavailable or invalid account users/device inventory',ref('MemberDevicesError'))},
        'x-reject-unknown-query-parameters':true,'x-implementation-status':status,
        'x-contract-review':'source-reviewed','x-runtime-verification':'Source and offline tests only; live acceptance is documented separately.',
        'x-source-sha256':digest(bytes),'x-source-file':path.relative(path.join(__dirname,'..'),sourcePath),
        'x-required-integration':{plugin:'cb_members',built_in_custom_route:'members',preserve_existing_custom_routes:true,
            scopes_rechecked:['members:GET','users:GET','devices:GET'],registrar:'complete correlated peer/part detail responses required',
            application_module_list:true,persisted_crossbar_module_start:true,new_database_views:false},
        'x-validation-boundaries':{member_page_max:100,device_catalog_max:1000,registrar_rows_max:10000,live_authorization_verified:false}};
    return {paths:{[ENDPOINT]:{get:operation}},components:{schemas,securitySchemes:{CrossbarToken:{type:'apiKey',in:'header',name:'X-Auth-Token'}}}};
}
function buildSpec(){return {openapi:'3.0.3',info:{title:'Members/Devices API contract',version:'0.1.0',description:'Source-reviewed contract; runtime acceptance is recorded separately.'},...overlay()};}
function applyMembersDevices({spec,root}) {
    const file='applications/crossbar/src/modules/cb_members.erl';
    const fragment=overlay({sourcePath:path.join(root,file)});
    assert(!spec.paths[ENDPOINT],'Duplicate members/devices endpoint');
    Object.assign(spec.paths,fragment.paths);
    for(const [name,schema] of Object.entries(fragment.components.schemas)) {
        assert(!spec.components.schemas[name],'Duplicate member schema');
        spec.components.schemas[name]=schema;
    }
    return {inputs:[file,'applications/crossbar/src/api_util.erl','scripts/api-docs-members-devices.cjs']
        .map(file=>({file,sha256:digest(fs.readFileSync(path.join(root,file)))}))};
}
module.exports={ENDPOINT,overlay,buildSpec,applyMembersDevices};
