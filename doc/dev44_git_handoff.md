# Git handover to the main development server

The main checkout is `/opt/kz5` on `10.1.0.44`, branch `master`, origin
`https://github.com/talkchief/kz5.git`. ACDC remains ordinary source within this
repository, not a separately committed repository.

## Protected authentication

`scripts/kz5-git-credential.cjs` implements a repository-scoped Git credential
helper. It only answers HTTPS requests for `github.com/talkchief/kz5[.git]`.
It refuses other hosts, paths, usernames, ambiguous input and unsafe token
files. The token lives outside Git at `/root/.config/kz5/github.token`, owned
by root with mode0600 and one hard link. Parent directories must be root-owned,
real directories without group/other write access. This is for the root-owned
development checkout; it does not grant ordinary service users Git access.

Do **not** run its `get` operation interactively: successful stdout is the Git
credential protocol and contains the token. Git consumes that output privately.
Do not enable Git/curl tracing, log helper output, add a token to a remote URL,
or put it in argv/environment. Git's `store` and `erase` operations do nothing;
this helper does not save unexpected credentials or delete protected storage.

Provisioning uses `--provision-stdin`, with the token provided over a protected
stdin pipe. It creates new storage exclusively, accepts an identical existing
token without rewriting it, and refuses to overwrite a different token. It
never imports the mixed `/root/key.key` file. Credential rotation is an explicit
operator action; revoking/replacing the token invalidates future pushes but
does not affect running Kazoo services.

Repository-local configuration (after checking for existing custom helpers):

```sh
cd /opt/kz5
git config --local credential.useHttpPath true
git config --local credential.https://github.com.username x-access-token
git config --local credential.helper ''
git config --local --add credential.helper '!/usr/bin/node /opt/kz5/scripts/kz5-git-credential.cjs'
git config --local http.followRedirects false
GIT_TERMINAL_PROMPT=0 git push --dry-run origin master
```

The empty helper entry resets inherited helpers only for this checkout. The
fixed helper still refuses all other repositories. Other checkouts and global
Git settings are unchanged. The final dry-run exercises authenticated push
access without changing remote refs; it is not an actual commit or push.

Offline regression:

```sh
sudo node /opt/kz5/scripts/test-kz5-git-credential.cjs
```

Eleven groups cover exact scope, rejected requests, CLI failure redaction,
exclusive/idempotent provisioning, file modes, symlinks/hard links, parent
permissions, ownership, modern Git challenge metadata and malformed input. Tests use synthetic credentials
in a newly allocated protected directory, never the real token.

## Acceptance record

Source regression258c16 passed the first ten groups. The first real .44 Git
check810c13 refused authentication without any remote ref change: Git2.52 sends
repeated `capability[]` and `wwwauth[]` fields. A field-name-only probe5716a4
confirmed that all four authority fields match and only this metadata caused
the refusal. Source correction `0bdb1c8` ignores these bounded metadata arrays
without allowing duplicate/changed authority fields or new authentication
modes. All eleven groups pass08f6db.

Only the uniquely selected GitHub credential was sent over pinned-host SSH
stdin to .44's provisioner; private readbackc2d432 passed without secret output.
The mixed `/root/key.key` remains absent on .44. Repository-local configuration
is installed as above. Actual .44 authenticated Git push dry-run6aa3fc passed
in694ms (`Everything up-to-date`), with no remote ref change. The main dev host
no longer needs the old server's askpass helper or credential file for pushes.
No Gemini, SSH, production CouchDB, FCM or APNs credential was included in this
Git handover. Provider/TLS runtime secrets previously installed on .44 are
separate, remain outside Git, and were not modified.
