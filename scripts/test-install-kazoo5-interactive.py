#!/usr/bin/env python3
"""Regression for the installer's interactive menu, on a real pseudo-terminal.

install-kazoo5.sh is the only installation entry point: one component, several
or all. On a terminal with no component named it offers a menu; without a
terminal its behaviour is unchanged, so automation is not affected. Every path
here is a dry run, a quit or a refusal, against a private deployment
configuration: nothing on the host is installed, restarted or written.
"""
import base64
import os
import pty
import select
import socket
import subprocess
import sys
import tempfile
import time

ROOT = os.path.realpath(os.path.join(os.path.dirname(__file__), ".."))
INSTALLER = os.path.join(ROOT, "scripts", "install-kazoo5.sh")
COMPONENTS = ["couchdb", "rabbitmq", "haproxy", "kazoo-apps", "ecallmgr",
              "freeswitch", "kamailio", "monster-ui", "push-bridge"]
passed = 0


def fail(message, output=""):
    sys.stderr.write(output + "\nFAIL: " + message + "\n")
    sys.exit(1)


def ok(message):
    global passed
    passed += 1
    print("PASS: " + message)


def environment(work):
    host = subprocess.run(["hostname", "-f"], capture_output=True, text=True).stdout.strip() or socket.gethostname()
    config = os.path.join(work, "deployment.env")
    with open(config, "w") as handle:
        handle.write("KAZOO_NODE_HOST=%s\n" % base64.b64encode(host.encode()).decode())
    os.chmod(config, 0o600)
    env = dict(os.environ)
    env.update(KAZOO_DEPLOYMENT_CONFIG=config, KAZOO_CONFIG_DIR=os.path.join(work, "etc"))
    return env


def on_terminal(arguments, answers, env, timeout=240):
    """Run the installer with a pseudo-terminal as stdin/stdout; answer each prompt."""
    pid, master = pty.fork()
    if pid == 0:
        os.execvpe("bash", ["bash", INSTALLER] + arguments, env)
    output, pending, deadline = "", list(answers), time.time() + timeout
    prompts = ("separated by spaces): ", "Action [1-3]: ", "Type yes to proceed: ")
    answered = 0
    while time.time() < deadline:
        ready, _, _ = select.select([master], [], [], 1.0)
        if ready:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            output += chunk.decode(errors="replace")
        if pending and sum(output.count(prompt) for prompt in prompts) > answered:
            os.write(master, (pending.pop(0) + "\n").encode())
            answered += 1
    else:
        os.kill(pid, 9)
        fail("timed out: " + " ".join(arguments), output)
    _, status = os.waitpid(pid, 0)
    os.close(master)
    return os.waitstatus_to_exitcode(status), output.replace("\r", "")


def without_terminal(arguments, env):
    run = subprocess.run(["bash", INSTALLER] + arguments, stdin=subprocess.DEVNULL,
                         capture_output=True, text=True, env=env, timeout=240)
    return run.returncode, run.stdout + run.stderr


def main():
    if os.geteuid() != 0:
        print("SKIP: the installer's dry run requires root")
        return
    with tempfile.TemporaryDirectory(prefix="kazoo-interactive.") as work:
        env = environment(work)

        code, out = on_terminal([], ["haproxy", "3"], env)
        if code != 0 or "Resolved components: haproxy" not in out or "Dry run complete" not in out:
            fail("menu selection by name with a dry run", out)
        for number, component in enumerate(COMPONENTS, 1):
            if not any(line.strip().startswith("%d) %s" % (number, component)) for line in out.splitlines()):
                fail("menu does not list %d) %s" % (number, component), out)
        if "installed, " not in out and "not installed on this host" not in out:
            fail("menu does not show what is installed on this host", out)
        if "Type yes to proceed" in out:
            fail("a dry run must not ask for the install confirmation", out)
        ok("no component on a terminal opens the menu; all nine components with their state; a named dry run resolves only that component")

        code, out = on_terminal(["--interactive", "--dry-run"], ["1, rabbit"], env)
        resolved = [line for line in out.splitlines() if "Resolved components:" in line]
        if code != 0 or not resolved or set(resolved[0].split(": ", 1)[1].split()) != {"couchdb", "rabbitmq"}:
            fail("numbers, names, aliases and commas select several components", out)
        if "Action [1-3]" in out:
            fail("--dry-run on the command line must not be asked again", out)
        ok("several components by number, alias and comma; a command-line action is not asked again")

        code, out = on_terminal(["--dry-run"], ["a"], env)
        resolved = [line for line in out.splitlines() if "Resolved components:" in line]
        if code != 0 or not resolved or set(resolved[0].split(": ", 1)[1].split()) != set(COMPONENTS):
            fail("'a' selects every component", out)
        ok("'a' resolves all nine components")

        code, out = on_terminal([], ["haproxy", "1", "no"], env)
        if code != 0 or "Not confirmed; nothing was changed" not in out or "Resolved components" in out:
            fail("an install that is not confirmed with 'yes' must stop before anything runs", out)
        if "restarts their services" not in out:
            fail("the confirmation does not warn about restarts", out)
        code, out = on_terminal([], ["q"], env)
        if code != 0 or "nothing was changed" not in out or "Resolved components" in out:
            fail("quit must change nothing", out)
        ok("install asks for a literal yes after warning about restarts; anything else, or quit, changes nothing")

        code, out = on_terminal([], ["bogus", "7 nonsense", "99x"], env)
        if code == 0 or out.count("Unknown component") != 3 or "No valid component selection after three attempts" not in out:
            fail("three invalid selections must refuse", out)
        code, out = on_terminal([], ["haproxy", "9"], env)
        if code == 0 or "Unknown action: 9" not in out or "Resolved components" in out:
            fail("an unknown action must refuse", out)
        ok("invalid components are re-asked three times and then refused; an unknown action refuses")

        code, out = without_terminal([], env)
        if code != 2 or "Usage:" not in out or "Components (numbers" in out:
            fail("without a terminal and without a component the usage and exit 2 are unchanged", out)
        code, out = without_terminal(["--interactive"], env)
        if code == 0 or "--interactive needs a terminal" not in out:
            fail("--interactive without a terminal must refuse instead of waiting", out)
        code, out = on_terminal(["--interactive", "haproxy"], [], env)
        if code == 0 or "do not also name them" not in out:
            fail("--interactive with a named component is ambiguous and must refuse", out)
        code, out = without_terminal(["--dry-run", "haproxy"], env)
        if code != 0 or "Resolved components: haproxy" not in out or "Components (numbers" in out:
            fail("naming a component must never open the menu", out)
        ok("automation is unchanged: no terminal means usage/exit 2, named components never open the menu")

        usage = without_terminal(["--help"], env)[1]
        if "only installation entry point" not in usage or "--interactive" not in usage:
            fail("usage does not document the menu", usage)
        ok("usage documents the single entry point and the menu")
    print("All %d interactive installer groups passed" % passed)


if __name__ == "__main__":
    main()
