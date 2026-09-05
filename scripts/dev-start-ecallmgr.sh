#!/bin/sh

cd "$(dirname "$0")" || exit 1

ROOT=$PWD/..

ERL_LIBS="${ERL_LIBS:-}:$ROOT/deps:$ROOT/core:$ROOT/applications"
for rabbitmq_deps in "$ROOT"/deps/rabbitmq_erlang_client-*/deps; do
    [ -d "$rabbitmq_deps" ] && ERL_LIBS="$ERL_LIBS:$rabbitmq_deps"
done
export ERL_LIBS

NODE_NAME=${1:-ecallmgr}
NAME_TYPE=${KAZOO_NODE_NAME_TYPE:--name}
case "$NAME_TYPE" in
    -name|-sname) ;;
    *) echo "Invalid KAZOO_NODE_NAME_TYPE: $NAME_TYPE" >&2; exit 2 ;;
esac
DIST_IP=${KAZOO_ERLANG_DIST_IP:-127.0.0.1}
case "$DIST_IP" in
    ''|*[!0-9.]*) echo "Invalid KAZOO_ERLANG_DIST_IP: $DIST_IP" >&2; exit 2 ;;
esac
DIST_TUPLE=$(awk -F. '
    NF == 4 && $1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 {
        printf "{%d,%d,%d,%d}", $1, $2, $3, $4
    }
' <<EOF
$DIST_IP
EOF
)
[ -n "$DIST_TUPLE" ] || { echo "Invalid KAZOO_ERLANG_DIST_IP: $DIST_IP" >&2; exit 2; }

LOG_ROOT=${KAZOO_LOG_ROOT:-$(cd "$ROOT" && pwd -P)/log/ecallmgr}
case "$LOG_ROOT" in
    /|*[!a-zA-Z0-9_./-]*) echo 'Invalid KAZOO_LOG_ROOT' >&2; exit 2 ;;
    /*) ;;
    *) echo 'KAZOO_LOG_ROOT must be absolute' >&2; exit 2 ;;
esac
umask 0077
mkdir -p "$LOG_ROOT/log" || exit 1
ERL_CRASH_DUMP="$LOG_ROOT/erl_crash.dump"
ERL_CRASH_DUMP_SECONDS=10
ERL_CRASH_DUMP_BYTES=104857600
export ERL_CRASH_DUMP ERL_CRASH_DUMP_SECONDS ERL_CRASH_DUMP_BYTES

export KAZOO_APPS=ecallmgr

case "${KAZOO_ENABLE_RELOADER:-false}" in
    true) set -- -s reloader ;;
    false) set -- ;;
    *) echo 'Invalid KAZOO_ENABLE_RELOADER' >&2; exit 2 ;;
esac

exec erl \
     "$NAME_TYPE" "$NODE_NAME" \
     -args_file "$ROOT/rel/dev.vm.args" \
     -config "$ROOT/rel/sys.config" \
     -lager log_root "\"$LOG_ROOT\"" \
     -kernel inet_dist_use_interface "$DIST_TUPLE" \
     "$@"
