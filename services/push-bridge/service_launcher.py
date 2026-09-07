#!/usr/bin/env python3
"""Load protected deployment JSON as data; never shell-source credentials."""
import argparse
import grp
import json
from importlib import metadata
import os
from pathlib import Path
import stat
import ssl
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_config import PREFIX, validate

CONFIG = Path("/etc/kazoo-push-bridge/config.json")
CREDENTIAL_KEYS = ("PUSH_BRIDGE_SA_FILE", "PUSH_BRIDGE_APNS_KEY_FILE",
                   "PUSH_BRIDGE_APNS_KEY_FILE_DEV")
TRUST_KEYS = ("PUSH_BRIDGE_AMQP_CA_FILE", "PUSH_BRIDGE_AMQP_MANAGEMENT_CA_FILE")
PROTECTED_FILE_KEYS = CREDENTIAL_KEYS + TRUST_KEYS


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate_configuration_key")
        result[key] = value
    return result


def protected_read(filename, limit, service_group=None):
    path = Path(filename)
    if not path.is_absolute() or str(path) != str(filename) or ".." in path.parts:
        raise ValueError("invalid_configuration_path")
    for directory in reversed(path.parents):
        info = directory.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            raise ValueError("unprotected_configuration_parent")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(descriptor)
        permissions = stat.S_IMODE(info.st_mode)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0
                or permissions not in (0o600, 0o640)
                or (permissions == 0o640 and info.st_gid != service_group)
                or info.st_size > limit):
            raise ValueError("unprotected_configuration_file")
        with os.fdopen(descriptor, "rb", closefd=False) as handle:
            result = handle.read(limit + 1)
        if len(result) > limit:
            raise ValueError("configuration_too_large")
        return result
    finally:
        os.close(descriptor)


def load_configuration():
    try:
        service_group = grp.getgrnam("kazoo-push-bridge").gr_gid
    except KeyError:
        service_group = None
    configuration = json.loads(protected_read(CONFIG, 32768, service_group),
                               object_pairs_hook=unique_object)
    if (not isinstance(configuration, dict)
            or any(not key.startswith(PREFIX) for key in configuration)
            or validate(configuration)):
        raise ValueError("invalid_configuration")
    for key in PROTECTED_FILE_KEYS:
        filename = configuration.get(key)
        if not filename:
            continue
        if Path(filename).parent != CONFIG.parent:
            raise ValueError("credentials_must_use_service_directory")
        raw = protected_read(filename, 65536, service_group)
        if key == "PUSH_BRIDGE_SA_FILE":
            account = json.loads(raw, object_pairs_hook=unique_object)
            if (not isinstance(account, dict) or account.get("type") != "service_account"
                    or not all(isinstance(account.get(field), str) and account[field]
                               for field in ("project_id", "private_key", "client_email"))
                    or account.get("token_uri") != "https://oauth2.googleapis.com/token"):
                raise ValueError("invalid_service_account")
        elif key in TRUST_KEYS:
            try:
                if b"-----BEGIN CERTIFICATE-----" not in raw or b"PRIVATE KEY-----" in raw:
                    raise ValueError()
                # Parse the exact bounded protected bytes during installer
                # preflight, before any service/permission mutation. No sockets
                # or third-party dependencies are needed for this trust check.
                ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT).load_verify_locations(cadata=raw.decode("ascii"))
            except Exception:
                raise ValueError("invalid_amqp_ca_bundle") from None
        elif b"PRIVATE KEY-----" not in raw:
            raise ValueError("invalid_apns_key")
    return configuration


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--prepare-permissions", action="store_true")
    parser.add_argument("--check-dependencies", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.check_dependencies:
            for line in (Path(__file__).resolve().parent / "requirements.lock").read_text().splitlines():
                if not line or line.startswith("#"):
                    continue
                match = re.fullmatch(r"([A-Za-z0-9_-]+)==([0-9.]+)(?: --hash=sha256:[0-9a-f]{64})+", line)
                if match is None or metadata.version(match[1]) != match[2]:
                    raise ValueError("dependency_lock_mismatch")
            print("push_bridge_dependency_versions_match_lock")
            return 0
        configuration = load_configuration()
        if args.prepare_permissions:
            if os.geteuid() != 0:
                raise ValueError("root_required")
            group = grp.getgrnam("kazoo-push-bridge").gr_gid
            directory = os.open(CONFIG.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                os.fchown(directory, 0, group)
                os.fchmod(directory, 0o750)
            finally:
                os.close(directory)
            # Exact validated files only; no recursive chmod or credential copies.
            for filename in [str(CONFIG)] + [configuration[key] for key in PROTECTED_FILE_KEYS
                                             if configuration.get(key)]:
                descriptor = os.open(filename, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
                try:
                    os.fchown(descriptor, 0, group)
                    os.fchmod(descriptor, 0o640)
                finally:
                    os.close(descriptor)
            return 0
        if args.check:
            print("push_bridge_protected_configuration_valid; provider_access_unverified")
            return 0
        from bridge import main as bridge_main
        return bridge_main([], configuration)
    except Exception:
        print("push_bridge_configuration_or_startup_failed", file=sys.stderr)
        return 78


if __name__ == "__main__":
    sys.exit(main())
