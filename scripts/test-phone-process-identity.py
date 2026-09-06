#!/usr/bin/env python3
"""Pure mocks: never reads protected state, opens a pidfd, or sends a signal."""
import contextlib
import errno
import importlib.util
import io
from pathlib import Path
import signal
import sys
import unittest
from unittest.mock import mock_open, patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("identity", Path(__file__).with_name("phone-process-identity.py"))
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)


class ProcessIdentityTests(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.open_fd = self.stack.enter_context(patch.object(identity.os, "pidfd_open", return_value=71))
        self.close_fd = self.stack.enter_context(patch.object(identity.os, "close"))
        self.read = self.stack.enter_context(patch.object(identity, "read_identity", return_value=(400, 12345, "S")))
        self.dead = self.stack.enter_context(patch.object(identity, "descriptor_dead", return_value=False))
        self.send = self.stack.enter_context(patch.object(identity.signal, "pidfd_send_signal"))

    def call(self, operation="check"):
        return identity.action(operation, 500, 12345, 400)

    def test_same_child_alive(self):
        self.assertEqual(self.call(), "alive")
        self.open_fd.assert_called_once_with(500, 0)
        self.close_fd.assert_called_once_with(71)
        self.send.assert_not_called()

    def test_same_child_signal_int(self):
        self.assertEqual(self.call("INT"), "sent")
        self.send.assert_called_once_with(71, signal.SIGINT, None, 0)

    def test_same_child_signal_kill(self):
        self.assertEqual(self.call("KILL"), "sent")
        self.send.assert_called_once_with(71, signal.SIGKILL, None, 0)

    def test_reused_pid_different_birth(self):
        self.read.return_value = (400, 54321, "S")
        for operation in ("check", "INT", "KILL"):
            self.assertEqual(self.call(operation), "foreign")
        self.send.assert_not_called()

    def test_foreign_parent_same_birth(self):
        self.read.return_value = (401, 12345, "S")
        self.assertEqual(self.call("INT"), "foreign")
        self.send.assert_not_called()

    def test_vanished_before_pidfd_open(self):
        self.open_fd.side_effect = ProcessLookupError()
        self.assertEqual(self.call("KILL"), "dead")
        self.read.assert_not_called()
        self.close_fd.assert_not_called()
        self.send.assert_not_called()

    def test_vanished_after_open_requires_dead_descriptor(self):
        self.read.side_effect = FileNotFoundError()
        self.dead.return_value = True
        self.assertEqual(self.call("INT"), "dead")
        self.dead.return_value = False
        self.assertEqual(self.call("INT"), "unknown")
        self.send.assert_not_called()

    def test_zombie_is_dead(self):
        self.read.return_value = (400, 12345, "Z")
        self.assertEqual(self.call("KILL"), "dead")
        self.send.assert_not_called()

    def test_descriptor_exit_is_dead(self):
        self.dead.return_value = True
        self.assertEqual(self.call("INT"), "dead")
        self.send.assert_not_called()

    def test_reuse_after_validation_signals_old_descriptor_only(self):
        # Simulate PID 500 being reused after its /proc identity was checked.
        # The already-open descriptor remains old-task71, not the new task72.
        target_by_pid = {500: 71}
        self.open_fd.side_effect = lambda pid, flags: target_by_pid[pid]
        def validated(pid):
            target_by_pid[pid] = 72
            return (400, 12345, "S")
        self.read.side_effect = validated
        self.assertEqual(self.call("KILL"), "sent")
        self.assertEqual(target_by_pid[500], 72)
        self.send.assert_called_once_with(71, signal.SIGKILL, None, 0)

    def test_exit_between_validation_and_signal(self):
        self.send.side_effect = ProcessLookupError()
        self.assertEqual(self.call("INT"), "dead")

    def test_unavailable_kernel_and_permission_fail_closed(self):
        for code in (errno.ENOSYS, errno.EPERM, errno.EMFILE):
            self.open_fd.side_effect = OSError(code, "opaque failure")
            self.assertEqual(self.call("INT"), "unknown")
            self.assertEqual(identity.main(["--probe"]), 1)
        self.send.assert_not_called()

    def test_unavailable_python_api_fail_closed(self):
        with patch.object(identity.os, "pidfd_open", None):
            self.assertEqual(self.call("INT"), "unknown")
            self.assertEqual(identity.main(["--probe"]), 1)
        self.send.assert_not_called()

    def test_unreadable_or_malformed_identity_fail_closed(self):
        for error in (PermissionError(), ValueError(), UnicodeError()):
            self.read.side_effect = error
            self.assertEqual(self.call("KILL"), "unknown")
        self.send.assert_not_called()

    def test_signal_denied_has_no_fallback(self):
        self.send.side_effect = PermissionError()
        self.assertEqual(self.call("INT"), "unknown")
        self.send.assert_called_once()

    def test_invalid_operation_pid_or_identity_has_no_process_effect(self):
        for values in (("TERM", 500, 12345, 400), ("INT", 1, 12345, 400), ("INT", 500, 0, 400), ("INT", 500, 12345, 1)):
            self.assertEqual(identity.action(*values), "unknown")
        for args in ([], ["INT", "-500", "12345", "400"], ["INT", "500", "0", "400"]):
            self.assertEqual(identity.main(args), 2)
        self.open_fd.assert_not_called()

    def test_stat_parser_handles_spaces_and_closing_parentheses(self):
        fields = ["S", "400"] + ["0"] * 17 + ["12345"]
        with patch("builtins.open", mock_open(read_data="500 (name with ) parens) " + " ".join(fields) + "\n")):
            self.assertEqual(REAL_READ_IDENTITY(500), (400, 12345, "S"))

    def test_probe_uses_only_own_descriptor_and_no_signal(self):
        self.assertEqual(identity.main(["--probe"]), 0)
        self.open_fd.assert_called_once_with(identity.os.getpid(), 0)
        self.read.assert_not_called()
        self.send.assert_not_called()

    def test_cli_fixed_result_no_internal_failure_output(self):
        self.read.side_effect = ValueError("SECRET-DO-NOT-LOG")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(identity.main(["INT", "500", "12345", "400"]), 0)
        self.assertEqual(output.getvalue(), "unknown\n")

    def test_fixture_packaging_gates_precede_unit_write_and_phone_start(self):
        directory = Path(__file__).parent
        installer = (directory / "install-live-test-agents.sh").read_text()
        supervisor = (directory / "run-live-test-agents.sh").read_text()
        self.assertIn("provision-live-test-agents.cjs phone-process-identity.py sip-tests/", installer)
        self.assertLess(installer.index('"$SCRIPT_DIR/phone-process-identity.py" --probe'), installer.index('unit_text >"$UNIT_PATH"'))
        run_service = supervisor.split("run_service() {", 1)[1].split("main() {", 1)[0]
        self.assertIn("flock timeout python3;", run_service)
        self.assertLess(run_service.index('"$PHONE_PROCESS_HELPER" --probe'), run_service.index("    load_state"))
        self.assertNotIn('kill -', supervisor)


REAL_READ_IDENTITY = identity.read_identity
if __name__ == "__main__":
    unittest.main()
