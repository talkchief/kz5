#!/usr/bin/env bash
# Live lifecycle test. Creates one uniquely named child account and queue,
# verifies ACDC's worker, and removes only those fixtures on exit.
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$script_dir/install-kazoo5.sh"
KAZOO_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
api_base=${KAZOO_TEST_API_URL:-http://127.0.0.1:8000/v2/}
api_base=${api_base%/}
[[ $api_base =~ ^https?://[a-zA-Z0-9._:-]+/v2$ ]] || die 'Invalid KAZOO_TEST_API_URL'
[[ -r $KAZOO_INSTALLER_SECRETS || -n $KAZOO_MASTER_ADMIN_PASSWORD ]] || die 'Existing master credentials are required'
load_or_create_master_credentials
credential_hash=$(printf '%s:%s' "$KAZOO_MASTER_ADMIN_USER" "$KAZOO_MASTER_ADMIN_PASSWORD" | md5sum | cut -d' ' -f1)
auth_body=$(printf '{"data":{"credentials":"%s","method":"md5","realm":"%s"}}' \
    "$credential_hash" "$KAZOO_MASTER_ACCOUNT_REALM" | curl --fail --silent --show-error \
    --connect-timeout 5 --max-time 30 -X PUT -H 'Content-Type: application/json' \
    --data-binary @- "$api_base/user_auth")
token=$(jq -er .auth_token <<<"$auth_body")
master_id=$(jq -er .data.account_id <<<"$auth_body")
[[ $token =~ ^[a-zA-Z0-9._-]+$ && $master_id =~ ^[a-f0-9]{32}$ ]] || die 'Invalid authentication response'
fixture_name="installer-acdc-test-$(openssl rand -hex 8)"
fixture_account=
fixture_queue=

api() {
    local method=$1 path=$2
    local -a body_args=()
    case $method in PUT|POST) body_args=(--data-binary @-) ;; esac
    curl --fail --silent --show-error --connect-timeout 5 --max-time 60 \
        --config <(printf 'header = "X-Auth-Token: %s"\n' "$token") \
        -H 'Content-Type: application/json' -X "$method" "${body_args[@]}" "$api_base/$path"
}

callback_store_probe() {
    local erl_call_bin node_name_type output
    erl_call_bin=$(find_erl_call) || die 'erl_call is required for the callback persistence probe'
    verify_cookie_copy "$KAZOO_RUNTIME_COOKIE_FILE" kazoo
    if [[ $KAZOO_HOSTNAME == *.* ]]; then node_name_type=-name; else node_name_type=-sname; fi
    # The fixture IDs are validated hexadecimal values. No credentials or
    # caller-controlled Erlang expressions are sent through argv or stdout.
    # This probe invokes storage only: it never originates a telephone call.
    output=$(timeout --signal=KILL 90 runuser --user kazoo -- \
        env -u KAZOO_COOKIE -u KAZOO_MASTER_ADMIN_PASSWORD -u KAZOO_COUCHDB_PASSWORD \
        "$erl_call_bin" "$node_name_type" "kazoo_apps@${KAZOO_HOSTNAME}" -e 2>/dev/null <<EOF
begin
  A = <<"${fixture_account}">>, Q = <<"${fixture_queue}">>,
  Db = kzs_util:format_account_db(A),
  {ok, Account} = kz_datamgr:open_doc(Db, A),
  <<"${fixture_name}">> = kz_json:get_value(<<"name">>, Account),
  {ok, Queue} = kz_datamgr:open_doc(Db, Q),
  <<"queue">> = kz_doc:type(Queue),
  put(callback_probe_docs, []),
  try
    put(callback_probe_step, production_mode),
    Options = proplists:get_value(options, acdc_callback_store:module_info(compile), []),
    false = lists:any(fun({d, 'TEST'}) -> true; ({d, 'TEST', _}) -> true; (_) -> false end, Options),
    Now = kz_time:now_s(),
    Registration = kz_json:from_list([{<<"number">>, <<"1001">>}, {<<"enqueued_at">>, Now}
                                     ,{<<"enqueue_sequence">>, 1}]),
    %% Deliberately synthetic storage fixture authority: no endpoint is created
    %% and this probe must never call the routing adapter or originate a call.
    Authority = kz_json:from_list([{<<"id">>, <<"storage-probe-device">>}, {<<"type">>, <<"device">>}
                                  ,{<<"account_realm">>, <<"storage-probe.invalid">>}]),
    Original = <<"${fixture_name}-caller">>,
    put(callback_probe_step, create_and_idempotence),
    {ok, First} = acdc_callback_store:create(A, Q, Original, Registration, Authority),
    Id = kz_doc:id(First), put(callback_probe_docs, [Id]),
    FirstRevision = kz_doc:revision(First),
    {ok, Again} = acdc_callback_store:create(A, Q, Original, Registration, Authority),
    Id = kz_doc:id(Again), FirstRevision = kz_doc:revision(Again),
    {error, registration_conflict} = acdc_callback_store:create(A, Q, Original,
        kz_json:set_value(<<"number">>, <<"1002">>, Registration), Authority),
    put(callback_probe_step, competing_claims),
    {ok, _} = acdc_callback_store:activate(A, Q, Id),
    Parent = self(), Tag = make_ref(),
    [spawn(fun() -> Parent ! {Tag, acdc_callback_store:claim(A, Q, Id, <<"probe-worker">>, 30)} end)
     || _ <- [1,2]],
    Results = [receive {Tag, R} -> R after 15000 -> error(claim_timeout) end || _ <- [1,2]],
    1 = length([ok || {ok, _} <- Results]),
    1 = length([error || {error, Cause} <- Results, Cause =:= busy orelse Cause =:= conflict]),
    {ok, Claimed} = acdc_callback_store:get(A, Q, Id),
    1 = kz_json:get_value(<<"attempts">>, Claimed),
    {error, not_found} = acdc_callback_store:get(A, <<"wrong-queue">>, Id),
    put(callback_probe_step, cancellation),
    {ok, Cancelling} = acdc_callback_store:cancel(A, Q, Id),
    <<"cancelling">> = kz_json:get_value(<<"status">>, Cancelling),
    CancelRevision = kz_doc:revision(Cancelling),
    {ok, CancelAgain} = acdc_callback_store:cancel(A, Q, Id),
    CancelRevision = kz_doc:revision(CancelAgain),
    put(callback_probe_step, queue_listing),
    ListResult = acdc_callback_store:list(A, Q, undefined, 100),
    case ListResult of
      {error, ListReason} when is_atom(ListReason) -> throw({probe_list_error, ListReason});
      _ -> ok
    end,
    {ok, Page, undefined} = ListResult,
    [Id] = [kz_doc:id(Doc) || Doc <- Page],
    ok
  catch
    throw:{probe_list_error, ListError} -> {probe_list_error, ListError};
    ProbeClass:_ -> {probe_failed, get(callback_probe_step), ProbeClass}
  after
    [begin
       {ok, Doc} = acdc_callback_store:get(A, Q, DeleteId),
       <<"${fixture_name}-caller">> = kz_json:get_value(<<"original_call_id">>, Doc),
       {ok, _} = kz_datamgr:del_doc(Db, Doc)
     end || DeleteId <- get(callback_probe_docs)],
    erase(callback_probe_docs), erase(callback_probe_step)
  end
end.
EOF
    ) || die 'Callback persistence RPC transport failed; normal fixture cleanup will run'
    if [[ $output != '{ok, ok}' ]]; then
        # Emit only a known stage label, never a raw RPC error/document.
        local stage
        for stage in production_mode create_and_idempotence competing_claims cancellation queue_listing; do
            [[ $output != *"{probe_failed, ${stage},"* ]] || warn "Callback persistence assertion failed at ${stage}"
        done
        for stage in not_found invalid_view_name invalid_stored_reservation timeout db_not_reachable; do
            [[ $output != *"{probe_list_error, ${stage}}"* ]] || warn "Callback listing failed with ${stage}"
        done
        die 'Callback persistence assertions failed; normal fixture cleanup will run'
    fi
    log 'PASS live CouchDB callback idempotence, conflicting registration, one competing claim winner, cancellation and queue-scoped listing'
}

cleanup_fixture() {
    local result
    [[ -n $fixture_account ]] || return 0
    result=$(api GET "accounts/$fixture_account") || return 1
    [[ $(jq -r .data.name <<<"$result") == "$fixture_name" ]] || {
        warn 'Refusing cleanup: live account name does not match the unique test fixture'; return 1;
    }
    if [[ -n $fixture_queue ]]; then
        api DELETE "accounts/$fixture_account/queues/$fixture_queue" >/dev/null || return 1
        fixture_queue=
    fi
    api DELETE "accounts/$fixture_account" >/dev/null || return 1
    log "Removed temporary ACDC test account ${fixture_account} and its queue"
    fixture_account=
}
finish_test() {
    local test_exit=$?
    cleanup_fixture || {
        warn "Fixture cleanup failed for ${fixture_account}; manual cleanup is needed"
        test_exit=1
    }
    exit "$test_exit"
}
trap finish_test EXIT

result=$(printf '{"data":{"name":"%s","realm":"%s.invalid"}}' "$fixture_name" "$fixture_name" | api PUT "accounts/$master_id")
fixture_account=$(jq -er .data.id <<<"$result")
[[ $fixture_account =~ ^[a-f0-9]{32}$ && $fixture_account != "$master_id" ]] || die 'Invalid fixture account ID'
result=$(printf '{"data":{"name":"%s","strategy":"round_robin"}}' "$fixture_name" | api PUT "accounts/$fixture_account/queues")
fixture_queue=$(jq -er .data.id <<<"$result")
[[ $fixture_queue =~ ^[a-f0-9]{32}$ ]] || die 'Invalid fixture queue ID'
result=$(api GET "accounts/$fixture_account/queues/$fixture_queue")
[[ $(jq -r .data.name <<<"$result") == "$fixture_name" ]] || die 'Created queue could not be read'
deadline=$((SECONDS + 60))
while ((SECONDS < deadline)); do
    workers=$(timeout 10 sup acdc_queues_sup queues_running </dev/null)
    if [[ $workers == *"$fixture_account"* && $workers == *"$fixture_queue"* ]]; then break; fi
    sleep 2
done
[[ $workers == *"$fixture_account"* && $workers == *"$fixture_queue"* ]] || die 'ACDC did not start a worker for the created queue'
if [[ ${KAZOO_TEST_CALLBACK_STORE:-false} == true ]]; then
    callback_store_probe
fi
result=$(printf '{"data":{"name":"%s-updated"}}' "$fixture_name" | api POST "accounts/$fixture_account/queues/$fixture_queue")
[[ $(jq -r .data.name <<<"$result") == "$fixture_name-updated" ]] || die 'Queue update failed'
result=$(api GET "accounts/$fixture_account/agents")
jq -e '.status == "success" and (.data | type == "array")' <<<"$result" >/dev/null || die 'Agent collection failed'
cleanup_fixture
log 'PASS live ACDC account/queue create, read, update, worker startup, agents API, and fixture deletion'
