#!/usr/bin/env python3
"""Offline checks for ACDC tracked and preserved as kz5 source."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
INSTALLER = (ROOT / "scripts/install-kazoo5.sh").read_text()


def run(args, cwd, **kwargs):
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, timeout=20, **kwargs)


class AcdcSourceOwnershipTests(unittest.TestCase):
    def test_source_is_tracked_as_files_and_build_outputs_are_ignored(self):
        entries = run(["git", "ls-files", "--stage", "--", "applications/acdc"], ROOT)
        self.assertEqual(entries.returncode, 0, entries.stderr)
        self.assertIn("\tapplications/acdc/src/acdc_agent_fsm.erl", entries.stdout)
        self.assertIn("\tapplications/acdc/test/acdc_agent_fsm_tests.erl", entries.stdout)
        self.assertNotIn("160000 ", entries.stdout)
        self.assertFalse((ROOT / "applications/acdc/.git").exists())
        for file in ["applications/acdc/ebin/acdc_agent_fsm.beam", "applications/acdc/.git/config"]:
            self.assertEqual(run(["git", "check-ignore", "-q", file], ROOT).returncode, 0, file)

    def source_gate(self, root, dry=False):
        hook = re.findall(r"^ensure_bundled_acdc_source\(\) \{[\s\S]*?^\}", INSTALLER, re.M)
        self.assertEqual(len(hook), 1)
        code = "set -euo pipefail\ndie(){ printf '%s\\n' \"$*\" >&2; exit 42; }\nlog(){ :; }\n"
        code += "sync_git(){ exit 99; }\n" + hook[0] + "\nensure_bundled_acdc_source\n"
        return run(["bash", "--noprofile", "--norc", "-s"], root, input=code,
                   env={"PATH": os.environ["PATH"], "KAZOO_ROOT": str(root), "DRY_RUN": str(dry).lower()})

    def test_installer_uses_existing_source_and_rejects_missing_or_nested_checkout(self):
        with tempfile.TemporaryDirectory(prefix="acdc-source-gate-") as directory:
            root = Path(directory)
            for file in ["Makefile", "src/acdc_agent_fsm.erl", "src/acdc.app.src"]:
                target = root / "applications/acdc" / file
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("source fixture\n")
            self.assertEqual(run(["git", "init", "-q"], root).returncode, 0)
            self.assertEqual(self.source_gate(root).returncode, 42, "Untracked source must fail")
            self.assertEqual(run(["git", "add", "applications/acdc"], root).returncode, 0)
            self.assertEqual(self.source_gate(root).returncode, 0)
            source = root / "applications/acdc/src/acdc_agent_fsm.erl"
            self.assertEqual(source.read_text(), "source fixture\n")
            nested = root / "applications/acdc/.git"
            nested.mkdir()
            self.assertEqual(self.source_gate(root).returncode, 42)
            nested.rmdir()
            source.unlink()
            self.assertEqual(self.source_gate(root).returncode, 42)
            self.assertEqual(self.source_gate(root, dry=True).returncode, 0)
            self.assertFalse(source.exists(), "A dry run must not recreate source")

    def test_fetch_manifest_excludes_acdc_even_when_directory_is_missing(self):
        with tempfile.TemporaryDirectory(prefix="acdc-fetch-") as directory:
            root = Path(directory)
            (root / "make").mkdir()
            (root / "make/app_urls.mk").write_bytes((ROOT / "make/app_urls.mk").read_bytes())
            (root / "make/apps.mk").write_text("DEPS = acdc crossbar\n")
            (root / "erlang.mk").write_text('fetch-deps:\n\t@printf "%s\\n" "$(DEPS)"\n')
            result = run(["make", "--no-print-directory", "-f", str(ROOT / "make/Makefile.apps"),
                          "ROOT=" + str(root), "MORE_APPS_MK=", "fetch-deps"], root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "crossbar")
            self.assertFalse((root / "applications/acdc").exists())

    def test_deep_clean_targets_preserve_bundled_source(self):
        makefile = (ROOT / "Makefile").read_text()
        clean = makefile[makefile.index(".PHONY: clean-kazoo\n"):makefile.index(".PHONY: clean\n")]
        sparkly = makefile[makefile.index(".PHONY: sparkly-clean\n"):makefile.index(".PHONY: stop-if-changed\n")]
        for target in ["clean-kazoo", "sparkly-clean"]:
            with self.subTest(target=target), tempfile.TemporaryDirectory(prefix="acdc-clean-") as directory:
                root = Path(directory)
                preserved = ["applications/acdc/src/keep.erl", "applications/acdc/include/keep.hrl",
                             "applications/acdc/priv/keep.json", "applications/acdc/test/keep.erl",
                             "applications/acdc/ebin/.placeholder", "applications/acdc/ebin/tracked.app",
                             "applications/acdc/ebin/operator-note.txt"]
                generated = ["applications/acdc/ebin/stale.beam", "applications/acdc/ebin/acdc.app",
                             "applications/acdc/.deps.rules", "applications/acdc/.deps.mk.fixture",
                             "applications/acdc/.apps.mk.fixture", "applications/acdc/.test.deps",
                             "applications/acdc/test/acdc.app"]
                for relative in preserved + generated + ["applications/crossbar/remove.erl", "core/remove.erl", "outside/keep.beam"]:
                    file = root / relative
                    file.parent.mkdir(parents=True, exist_ok=True)
                    file.write_text("fixture\n")
                (root / "applications/acdc/.gitignore").write_bytes((ROOT / "applications/acdc/.gitignore").read_bytes())
                self.assertEqual(run(["git", "init", "-q"], root).returncode, 0)
                tracked = [file for file in preserved if not file.endswith("operator-note.txt")]
                self.assertEqual(run(["git", "add", "-f", *tracked, "applications/acdc/.gitignore"], root).returncode, 0)
                (root / "applications/acdc/ebin/borrowed.beam").symlink_to(root / "outside/keep.beam")
                (root / "Makefile").write_text("ROOT := $(CURDIR)\nAPPS_DIR := $(CURDIR)/applications\nCORE_DIR := $(CURDIR)/core\n" + clean + sparkly +
                                              "\n.PHONY: stop-if-changed clean-release clean-deps clean-tags\n"
                                              "stop-if-changed clean-release clean-deps clean-tags:\n\t@:\n")
                result = run(["make", "--no-print-directory", target], root)
                self.assertEqual(result.returncode, 0, result.stderr)
                for relative in preserved:
                    self.assertEqual((root / relative).read_text(), "fixture\n", relative)
                for relative in generated:
                    self.assertFalse((root / relative).exists(), relative)
                self.assertFalse((root / "applications/acdc/ebin/borrowed.beam").is_symlink())
                self.assertEqual((root / "outside/keep.beam").read_text(), "fixture\n", "Do not follow generated symlinks")
                self.assertFalse((root / "applications/crossbar").exists())
                self.assertFalse((root / "core").exists())

    def test_historical_replay_excludes_uncompiled_tests_but_rejects_runtime_drift(self):
        source = (ROOT / "scripts/test-acdc-gemini-runtime.sh").read_text()
        hook = re.findall(r"^reconstruct_historical_runtime\(\) \{[\s\S]*?^\}", source, re.M)
        self.assertEqual(len(hook), 1)

        def patch(before, after):
            return "".join("diff --git a/{0}/fixture b/{0}/fixture\n--- a/{0}/fixture\n+++ b/{0}/fixture\n"
                           "@@ -1 +1 @@\n-{0}-{1}\n+{0}-{2}\n".format(directory, before, after)
                           for directory in ["src", "test"])

        for drift in [False, True]:
            with self.subTest(runtime_drift=drift), tempfile.TemporaryDirectory(prefix="acdc-runtime-projection-") as directory:
                root = Path(directory)
                acdc = root / "applications/acdc"
                for part in ["src", "include", "priv", "test"]:
                    (acdc / part).mkdir(parents=True, exist_ok=True)
                runtime = acdc / "src/fixture"
                runtime.write_text("src-foreign\n" if drift else "src-atomic\n")
                tests = acdc / "test/fixture"
                tests.write_text("test-unrelated-current-edit\n")
                patches = root / "scripts/patches"
                patches.mkdir(parents=True)
                (patches / "acdc-atomic-answer-runtime.patch").write_text(patch("language", "atomic"))
                (patches / "acdc-language-runtime.patch").write_text(patch("baseline", "language"))
                output = root / "private-replay"
                (output / "source").mkdir(parents=True)
                (output / "integration.patch").write_text(patch("upstream", "baseline"))
                code = "set -euo pipefail\n" + hook[0] + "\nreconstruct_historical_runtime\n"
                result = run(["bash", "--noprofile", "--norc", "-s"], root, input=code,
                             env={"PATH": os.environ["PATH"], "project_root": str(root),
                                  "acdc_repository": str(acdc), "test_dir": str(output)})
                if drift:
                    self.assertNotEqual(result.returncode, 0, "Changed runtime source must fail reverse checks")
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual((output / "source/src/fixture").read_text(), "src-baseline\n")
                self.assertFalse((output / "source/test").exists(), "Uncompiled bundled tests must not be copied")
                self.assertEqual(runtime.read_text(), "src-foreign\n" if drift else "src-atomic\n")
                self.assertEqual(tests.read_text(), "test-unrelated-current-edit\n")

    def test_installer_and_patch_generator_do_not_restore_nested_acdc(self):
        self.assertNotIn("kazoo-community/kazoo-acdc.git", INSTALLER)
        self.assertNotIn('apply_required_source_patch "$acdc_dir"', INSTALLER)
        refresh = (ROOT / "scripts/refresh-kazoo-integration-patches.cjs").read_text()
        self.assertNotIn("{name:'acdc',base:", refresh)
        history_test = (ROOT / "scripts/test-acdc-gemini-runtime.sh").read_text()
        self.assertNotIn('git -C "$acdc_repository"', history_test)


if __name__ == "__main__":
    unittest.main(verbosity=2)
