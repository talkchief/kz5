# Installing Kazoo 5 modules on a remote server from Jenkins

`scripts/install-kazoo5.sh` stays the only installation entry point. Jenkins adds what
the installer cannot do for a machine it is not on yet: choose a server, ship one pinned
commit to it, hand over that server's settings, run the installer there, and check the
result. The pipeline is `jenkins/Jenkinsfile`; all host access goes through
`scripts/remote-install-kazoo5.sh`, which can also be run by hand.

## What a run does on the target

1. Refuses unless the target is Rocky Linux 9, the SSH user is root, no other remote
   installation is running there and, for `install` and `verify-only`, FreeSWITCH carries
   no live channel (override: `ALLOW_ACTIVE_CALLS`).
2. Places the exact commit in `/opt/kz5` from a git bundle (the target needs no access
   to the repository host). Refuses when tracked files were edited on the target.
3. Copies the server's settings root-only, starts
   `install-kazoo5.sh [--dry-run|--verify-only] MODULES` **as a systemd unit**
   (`kz5-remote-install-<time>-<commit>`), so an SSH or Jenkins interruption cannot kill an
   installation half way, and follows its `[kazoo5]` status lines. The full log stays on
   the target in `/var/log/kazoo-remote-install/` (root-only); only status lines reach
   Jenkins.
4. After `install`: every selected service must be **enabled** and **active**, and
   `kazoo5-stack-health` must pass.
5. Removes the settings file again, also when the run failed.

It never runs `sup`, never restarts or enables a service itself and never touches cluster
wiring. After adding an eCallMgr or FreeSWITCH, the operator wires it in by hand
(`sup -n ecallmgr ecallmgr_maintenance add_fs_node …`, Kamailio dispatcher, ACLs), exactly
as on Kazoo 4.

## Defining a server in Jenkins

Per server, its login and its settings (Manage Jenkins -> Credentials):

| Kind | Content |
| --- | --- |
| Username with password, **or** SSH Username with private key | the server's root login. With a password, `ssh` is asked through a private `SSH_ASKPASS` helper: the password is never an argument, never in a remote command and never in the build log, and nothing extra (no `sshpass`) is needed on the Jenkins host |
| Secret file | that server's installer inputs, `KEY=value` lines |

Example settings for a new eCallMgr + FreeSWITCH server joining an existing cluster
(`install-kazoo5.sh --help` lists every input; values here are placeholders):

```
KAZOO_PUBLIC_IP=10.0.0.21
KAZOO_ERLANG_DIST_IP=10.0.0.21
KAZOO_AMQP_HOST=10.0.0.12
KAZOO_RABBITMQ_USER=kazoo
KAZOO_RABBITMQ_PASSWORD=...
KAZOO_COUCHDB_HOST=10.0.0.11
KAZOO_COUCHDB_USER=admin
KAZOO_COUCHDB_PASSWORD=...
KAZOO_FREESWITCH_NODES=freeswitch@fs2.example.net
KAZOO_BOOTSTRAP_MASTER_ACCOUNT=false
```

Only `KAZOO_*`, `KAMAILIO_*`, `FREESWITCH_*`, `COUCHDB_*`, `RABBITMQ_*`, `MONSTER_*`,
`PUSH_BRIDGE_*` and `ACDC_*` assignments are accepted, and no `$` or backticks: the file
is given to systemd as an `EnvironmentFile`, never evaluated by a shell. The Erlang cookie
must be the cluster's (`KAZOO_COOKIE_FILE` content on the existing nodes). On a repeat
install the settings credential can be left empty: the server keeps its saved settings.

## Credentials in Jenkins

The job reads this repository with the credential id `github-pat`. Credential names are
generic on purpose, so other projects can reuse them. `scripts/jenkins-import-credentials.py`
creates them from a root-only key file (ids and kinds are printed, never a value):

```sh
sudo python3 scripts/jenkins-import-credentials.py --key-file /root/key --dry-run     # what it would create
sudo python3 scripts/jenkins-import-credentials.py --key-file /root/key --insecure    # --insecure: self-signed Jenkins certificate
```

`github_pat` becomes `github-pat` (Git credential for any GitHub repository the token covers)
and `github-pat-text` (secret text for API calls); `<x>_user_<y>` + `<x>_pass_<y>` pairs become
one "Username with password" credential `<x>-<y>`, which is also the kind the job's
`SSH_PASSWORD_CREDENTIAL` parameter accepts. A server's own root login is added the same way,
with any id you like (for example `fs2-root`).

## Running it

Build with parameters: `TARGET_HOST`, one login credential (password or key), the settings
credential, the action, and tick the modules. Start with `dry-run`; `install` asks for approval before anything restarts.
One build at a time. The build is named after the action and host and keeps
`remote-install.log` as its receipt.

By hand, from a clean checkout:

```sh
bash scripts/remote-install-kazoo5.sh --host 10.0.0.21 --identity ~/.ssh/kz5_deploy \
     --env-file fs2.env --action dry-run ecallmgr freeswitch
```

## Proof

`bash scripts/test-remote-install-kazoo5.sh` (8 groups, recording ssh/scp stand-ins, no
host contacted): exact commit, one installer unit, settings handed over and always
removed, fourteen unsafe requests refused before the installer starts, failed installer
and not-enabled service fail the run, only a commit is deployed, unit names match the
installer. `bash scripts/test-single-install-entry-point.sh` holds the wrapper and the
Jenkinsfile to the single-entry-point rule.
