#!/usr/bin/env node
'use strict';
// Read-only runtime proof: current account directory/authority/native endpoint
// builder, without creating a reservation, publishing AMQP or dialing a phone.
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const [account, queue, number] = process.argv.slice(2);
assert(process.argv.length === 5 && /^[0-9a-f]{32}$/.test(account)
    && /^[0-9a-f]{32}$/.test(queue) && /^[0-9]{1,6}$/.test(number));
const expression = `(fun() ->
    A = <<"${account}">>, Qid = <<"${queue}">>, Number = <<"${number}">>,
    case kz_datamgr:open_doc(kzs_util:format_account_db(A), Qid) of
      {ok,Q} ->
        case acdc_callback_policy:authorize_registration(A,Q,Number) of
          {ok,Authority} ->
            Target = kz_json:get_value(<<"internal_target">>,Authority),
            Reservation = kz_json:from_list([
                {<<"_id">>,<<"acdc-callback-0000000000000000000000000000000000000000000000000000000000000000">>},
                {<<"pvt_type">>,<<"acdc_callback">>}, {<<"pvt_account_id">>,A},
                {<<"queue_id">>,Qid}, {<<"number">>,Number}, {<<"status">>,<<"dialing">>},
                {<<"attempts">>,1}, {<<"pvt_caller_call_id">>,<<"11111111111111111111111111111111">>},
                {<<"pvt_authority_id">>,kz_json:get_value(<<"id">>,Authority)},
                {<<"pvt_authority_type">>,kz_json:get_value(<<"type">>,Authority)},
                {<<"pvt_account_realm">>,kz_json:get_value(<<"account_realm">>,Authority)},
                {<<"pvt_internal_target">>,Target}]),
            case acdc_callback_policy:build_request(A,Q,Reservation,<<"read-only-callback-probe">>) of
              {ok,R} -> {ok,internal_registration_authorized,native_request_valid,
                         length(kz_json:get_list_value(<<"Endpoints">>,R,[])),
                         kz_api:event_type(R),kz_json:get_value(<<"Originate-Immediate">>,R)};
              {error,Reason} -> {request_failed,Reason}
            end;
          {error,Reason} -> {registration_failed,Reason}
        end;
      _ -> queue_read_failed
    end
end)().`;
try {
    const ast = cp.execFileSync('/usr/bin/erl', ['+S','1:1','+SDcpu','1','+SDio','1','+A','1',
        '-no_dot_erlang','-noshell','-eval',
        '{ok,T,_}=erl_scan:string(os:getenv("KAZOO_CALLBACK_PROBE_EXPRESSION")),{ok,E}=erl_parse:parse_exprs(T),io:format("~w",[E]),halt().'],
        {encoding:'utf8',env:{...process.env,KAZOO_CALLBACK_PROBE_EXPRESSION:expression},timeout:15000,maxBuffer:1024*1024}).trim();
    const result = cp.execFileSync('/usr/local/bin/sup', ['-n','kazoo_apps','-t','30','-e','erl_eval','exprs',ast,'[]'],
        {encoding:'utf8',timeout:40000,maxBuffer:1024*1024,stdio:['ignore','pipe','pipe']}).trim();
    // Only the fixed, deliberately limited return value leaves the process.
    const safe = result.replace(/\s/g,'');
    assert(/^\{value,\{(?:ok,internal_registration_authorized,native_request_valid,[1-9][0-9]*,\{<<"resource">>,<<"originate_req">>\},false|(?:request|registration)_failed,[a-z_]+)\},\[\]\}$/.test(safe));
    console.log(safe);
    assert(safe.startsWith('{value,{ok,'), 'Runtime callback probe did not pass');
    console.log('PASS current account authority and internal endpoint construction; no reservation, AMQP publish or call');
} catch (_) {
    console.error('Read-only internal callback probe failed; no raw runtime payload emitted.');
    process.exitCode = 1;
}
