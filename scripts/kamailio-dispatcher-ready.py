#!/usr/bin/env python3
"""Read-only readiness of the effective Kazoo INVITE dispatcher groups."""
import json
import re
import subprocess
import sys


def number(value):
    if not re.fullmatch(r"[0-9]{1,5}", value) or int(value) > 65535:
        raise ValueError("invalid group")
    return int(value)


def parse(text, primary, secondary):
    if len(text) > 1024 * 1024 or primary < 1:
        raise ValueError("invalid inventory")
    root = None
    stack = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        if line == "{" or re.fullmatch(r"[A-Z_0-9]+: \{", line):
            node = {"name": line.split(":", 1)[0] if ":" in line else "root", "values": {}, "children": []}
            if stack:
                stack[-1]["children"].append(node)
            elif root is not None:
                raise ValueError("multiple roots")
            else:
                root = node
            stack.append(node)
        elif line == "}":
            if not stack:
                raise ValueError("unbalanced inventory")
            stack.pop()
        else:
            match = re.fullmatch(r"([A-Z_0-9]+):[ \t]*(.*)", line)
            if not stack or not match or match[1] in stack[-1]["values"]:
                raise ValueError("malformed inventory")
            stack[-1]["values"][match[1]] = match[2]
    if stack or root is None:
        raise ValueError("incomplete inventory")

    def children(node, name):
        return [child for child in node["children"] if child["name"] == name]

    records = children(root, "RECORDS")
    count = number(root["values"]["NRSETS"])
    if len(records) != 1:
        raise ValueError("missing records")
    sets = children(records[0], "SET")
    if len(sets) != count:
        raise ValueError("incomplete sets")
    active = 0
    selected = 0
    seen = set()
    for group in sets:
        group_id = number(group["values"]["ID"])
        targets = children(group, "TARGETS")
        if group_id in seen or len(targets) != 1:
            raise ValueError("invalid set")
        seen.add(group_id)
        for dest in children(targets[0], "DEST"):
            flags = dest["values"]["FLAGS"]
            uri = dest["values"]["URI"]
            if not re.fullmatch(r"[AITD][PX]", flags) or not uri.startswith(("sip:", "sips:")):
                raise ValueError("invalid destination")
            if group_id == primary or (secondary > 0 and group_id == secondary):
                selected += 1
                # Native dispatcher.c prints I/D/T for unavailable entries;
                # P/X indicates probing, not eligibility. AP and AX are active.
                active += flags[0] == "A"
    return {"ready": active > 0, "primary_group": primary, "secondary_group": secondary,
            "selected_destinations": selected, "active_destinations": active}


def rpc(*args):
    return subprocess.run(["/usr/sbin/kamcmd", *args], check=True, capture_output=True,
                          text=True, timeout=5).stdout.strip()


def main():
    if len(sys.argv) != 1:
        raise ValueError("no arguments supported")
    primary = number(rpc("cfg.get", "kazoo", "dispatcher_primary_group"))
    secondary = number(rpc("cfg.get", "kazoo", "dispatcher_secondary_group"))
    result = parse(rpc("dispatcher.list"), primary, secondary)
    print(json.dumps(result))
    return 0 if result["ready"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, KeyError, subprocess.SubprocessError, OSError):
        print("Dispatcher readiness unavailable or invalid; private RPC details withheld", file=sys.stderr)
        sys.exit(1)
