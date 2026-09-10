#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || exit 64
[[ $(readlink /proc/self/ns/net) != "$(readlink /proc/1/ns/net)" ]] || exit 64
gate_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
gate_source=/usr/local/src/kazoo5-installer/freeswitch-1.11.3
[[ $(git -C "$gate_source" rev-parse HEAD) == ef32e205295e29f034f1453ad245ba5efb07b94a ]] || exit 78
[[ -f $gate_source/Makefile ]] || exit 78
gate_stage=$(mktemp -d /tmp/kazoo-media-build.XXXXXX)
git -C "$gate_source" archive HEAD src/include src/switch_core_session.c src/mod/applications/mod_commands/mod_commands.c |
    tar -x -C "$gate_stage"
sha256sum "$gate_repo/scripts/patches/freeswitch-durable-media-admission.patch" > "$gate_stage/patch.sha256"
git -C "$gate_stage" apply --check "$gate_repo/scripts/patches/freeswitch-durable-media-admission.patch"
git -C "$gate_stage" apply "$gate_repo/scripts/patches/freeswitch-durable-media-admission.patch"
# Compile full modified translation units with the configured native build flags.
# The source/build checkout and installed runtime are never written or loaded.
make --no-print-directory -C "$gate_source" -f Makefile -f - kazoo_gate_compile GATE_STAGE="$gate_stage" <<'MAKE'
.PHONY: kazoo_gate_compile
kazoo_gate_compile:
	$(CC) $(DEFS) -I$(GATE_STAGE)/src/include $(DEFAULT_INCLUDES) $(INCLUDES) $(AM_CPPFLAGS) $(CPPFLAGS) $(libfreeswitch_la_CFLAGS) $(CFLAGS) -Werror -c $(GATE_STAGE)/src/switch_core_session.c -o $(GATE_STAGE)/session.o
	$(CC) $(DEFS) -I$(GATE_STAGE)/src/include $(DEFAULT_INCLUDES) $(INCLUDES) $(AM_CPPFLAGS) $(CPPFLAGS) $(libfreeswitch_la_CFLAGS) $(CFLAGS) -Werror -c $(GATE_STAGE)/src/mod/applications/mod_commands/mod_commands.c -o $(GATE_STAGE)/commands.o
MAKE
sha256sum -c "$gate_stage/patch.sha256"
printf 'PASS full native FreeSWITCH translation units; evidence %s\n' "$gate_stage"
