# Installer host concurrency guard

All real `scripts/install-kazoo5.sh` invocations, including `--verify-only`,
now acquire an exclusive, nonblocking host lock before preflight, packages,
source updates, service changes or deployment-config writes. Different module
selections and different checkout paths still share this lock because they
share host resources. Help/list and dry-run remain non-mutating.

The lock lives at `/run/kazoo5-installer/host.lock`, beneath a root-owned 0700
directory. Linked files, hardlinks and unsafe directory ownership/permissions
are rejected. Contention produces an explicit error rather than starting a
second deployment. The open descriptor releases when the invocation and any
inheriting build children exit; interruption cannot leave a stale PID lock.
Never delete the lock file to bypass a running installer: replacing its inode
would let two installations run concurrently. Inspect the existing process and
let it finish or terminate it deliberately before retrying.

Validation: `node scripts/test-installer-host-lock.cjs` executes the actual
installer helper with only its fixed runtime path relocated into a private
temporary directory. On September 9 it passed contention, dry-run, SIGTERM and
failure release, stable inode, unsafe directory, symlink, hardlink and main
preflight-order checks (eef29c). No installed service or configuration changed.

This fixes same-host installer concurrency, not cluster-wide admission control,
database rollback, crash-atomic source publication or rolling upgrades. Those
distributed release gates remain separate. Installations started using older
code do not own this new lock: finish those before launching the updated script.
