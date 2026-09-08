#!/usr/bin/env python3
"""Exercise the actual fixed-scope Erlang audit with offline RPC fixtures.

Only temporary test modules are compiled. No live services, cookies or database
connections are used. Run through run-kazoo-validation.sh.
"""
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent

FIXTURE = r'''
-module(compat_audit_fixture).
-export([call/5, check/1]).

check(Scenario) ->
    put(scenario, Scenario), put(phase, before), put(restores, 0),
    put(aggregate_calls, 0),
    Result = try company_compat_rpc_under_test:run(["audit-refresh-writes"], lab) of
        _ -> success
    catch _:_ -> failure end,
    Expected = case Scenario of normal -> success; unchanged -> success; _ -> failure end,
    Expected = Result,
    ExpectedRestores = case Scenario of wrong_scope -> 0; _ -> 1 end,
    ExpectedRestores = get(restores),
    ExpectedAggregate = case Expected of success -> 1; failure -> 0 end,
    ExpectedAggregate = get(aggregate_calls),
    io:format("fixture=~p passed=true~n", [Scenario]).

call(lab, kz_datamgr, db_classification, [Db], _) ->
    account_db() = Db,
    case get(scenario) of wrong_scope -> system; _ -> account end;
call(lab, kz_datamgr, open_doc, [Db, <<"_design/numbers">>], _) ->
    account_db() = Db,
    {ok, case get(phase) of
        before -> #{rev => <<"1-a">>, body => generated};
        static -> #{rev => <<"2-b">>, body => static};
        restored -> #{rev => <<"3-c">>, body => case get(scenario) of
            wrong_body -> different_generated;
            missing_view -> static;
            _ -> generated end}
    end};
call(lab, kz_datamgr, open_doc, [<<"accounts">>, Id], _) ->
    account_id() = Id,
    {ok, #{rev => case get(aggregate_calls) of 0 -> <<"1-a">>; _ -> <<"2-b">> end,
           body => aggregate}};
call(lab, kz_datamgr, refresh_views, [Db], _) ->
    account_db() = Db, put(phase, static),
    case get(scenario) of refresh_failure -> {badrpc, timeout}; _ -> true end;
call(lab, kazoo_numbers_maintenance, update_number_services_view, [Id], _) ->
    account_id() = Id, put(restores, get(restores) + 1), put(phase, restored),
    case get(scenario) of restore_failure -> {error, conflict}; unchanged -> no_return; _ -> ok end;
call(lab, kapps_maintenance, ensure_aggregate_account, [Id], _) ->
    account_id() = Id, put(aggregate_calls, get(aggregate_calls) + 1), ok;
call(lab, kz_json, get_ne_binary_value, [[<<"views">>, <<"reconcile_services">>, Key], Doc], _)
  when Key =:= <<"map">>; Key =:= <<"reduce">> ->
    case maps:get(body, Doc) of static -> undefined; _ -> <<"fixture">> end;
call(lab, kz_doc, delete_revision, [Doc], _) -> maps:remove(rev, Doc);
call(lab, kz_doc, revision, [Doc], _) -> maps:get(rev, Doc);
call(lab, kz_json, are_equal, [A, B], _) -> A =:= B;
call(_, _, _, _, _) -> error(unexpected_rpc).

account_id() -> <<"d8520ce3f29c5b6db692289e782c92af">>.
account_db() -> <<"account%2Fd8%2F52%2F0ce3f29c5b6db692289e782c92af">>.
'''.replace('account_db() = Db', 'true = account_db() =:= Db').replace(
    'account_id() = Id', 'true = account_id() =:= Id')


class RefreshAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='compat-refresh-audit-')
        cls.env = dict(os.environ, ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 2',
                       ERL_CRASH_DUMP=cls.temp.name + '/erl_crash.dump')
        for key in ['ERL_AFLAGS', 'ERL_ZFLAGS', 'ERL_COMPILER_OPTIONS', 'ERL_INETRC']:
            cls.env.pop(key, None)
        source = (ROOT / 'company-compat-rpc.escript').read_text().splitlines(True)[2:]
        production = '-module(company_compat_rpc_under_test).\n-compile(export_all).\n' + ''.join(source)
        # Substitute transport only: run/2, try/after recovery and all readback
        # validation are the actual production source, not a duplicated model.
        production = production.replace('rpc:call(', 'compat_audit_fixture:call(')
        base = pathlib.Path(cls.temp.name)
        (base / 'company_compat_rpc_under_test.erl').write_text(production)
        (base / 'compat_audit_fixture.erl').write_text(FIXTURE)
        subprocess.run(['erlc', '-W0', '-o', str(base),
                        str(base / 'company_compat_rpc_under_test.erl'),
                        str(base / 'compat_audit_fixture.erl')],
                       env=cls.env, check=True, timeout=30)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_actual_audit_success_and_failure_recovery(self):
        for scenario in ['normal', 'unchanged', 'refresh_failure', 'restore_failure',
                         'wrong_body', 'missing_view', 'wrong_scope']:
            with self.subTest(scenario=scenario):
                result = subprocess.run(['erl', '-pa', self.temp.name, '-noshell', '-eval',
                    'compat_audit_fixture:check(%s), halt().' % scenario],
                    env=self.env, check=True, capture_output=True, text=True, timeout=15)
                self.assertIn('fixture=%s passed=true' % scenario, result.stdout)

    def test_return_classifier(self):
        result = subprocess.run(['escript', str(ROOT / 'company-compat-rpc.escript'), 'self-test'],
                                env=self.env, check=True, capture_output=True, text=True, timeout=15)
        self.assertIn('number_view_return_tests=6 passed=true', result.stdout)

    def test_host_namespace_refused_before_credentials(self):
        result = subprocess.run(['escript', str(ROOT / 'company-compat-rpc.escript'), 'audit-refresh-writes'],
                                env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 1)
        self.assertIn('failed at namespace', result.stderr)


if __name__ == '__main__':
    unittest.main()
