#!/usr/bin/env bash
# Static/syntax regression for the staged mod_kazoo originate lifecycle registry.
set -Eeuo pipefail
source_file=${MOD_KAZOO_COMMANDS_SOURCE:-/usr/local/src/kazoo5-installer/freeswitch-1.11.3/src/mod/outoftree/mod_kazoo/kazoo_commands.c}
module_dir=$(cd -- "$(dirname -- "$source_file")" && pwd -P)
fs_root=$(cd -- "$module_dir/../../../.." && pwd -P)
[[ -r $source_file ]] || { echo "missing mod_kazoo source: $source_file" >&2; exit 1; }
[[ -r $fs_root/src/include/switch.h ]] || { echo "missing FreeSWITCH headers under $fs_root" >&2; exit 1; }

gcc -fsyntax-only -Wall -Wextra -Werror -Wno-unused-parameter -D_REENTRANT \
    -I"$module_dir" -I"$fs_root/src/include" -I"$fs_root/libs/libteletone/src" \
    -I/usr/lib64/erlang/lib/erl_interface-5.5.1/include "$source_file"

require_source() {
    local pattern=$1 description=$2
    grep -Eq -- "$pattern" "$source_file" || {
        echo "missing originate reconciliation invariant: $description" >&2
        exit 1
    }
}

require_source 'KZ_ORIGINATE_REGISTRY_MAX[[:space:]]+4096' 'bounded registry'
require_source 'KZ_ORIGINATE_TOKEN_MAX[[:space:]]+512' 'bounded correlation tokens'
require_source 'if \(!entry->request_uuid' 'allocation failure cannot escape as a registered request'
require_source '!kz_originate_token_valid\(argv\[1\]\)' 'direct reconciliation input validation'
require_source '!kz_originate_token_valid\(request_uuid\)' 'direct originate input validation'
require_source 'KZ_ORIGINATE_TOMBSTONE_TTL_US' 'bounded terminal tombstone lifetime'
require_source 'entry->state[[:space:]]*==[[:space:]]*KZ_ORIGINATE_PENDING' 'pending-only cancellation'
require_source 'if \(cancel_requested\)' 'legacy cancellation rejects terminal tombstones'
require_source 'strcmp\(entry->request_id, argv\[2\]\).*strcmp\(entry->caller_uuid, argv\[3\]\)' \
    'exact original request and caller correlation'
require_source '\+OK SETTLED success' 'authoritative successful terminal response'
require_source '\+OK SETTLED failure' 'authoritative failed terminal response'
require_source '\-ERR UNKNOWN' 'absence remains unknown'
require_source 'switch_ivr_originate.*caller_session' 'terminal state follows real originate execution'
require_source 'kz_originate_settle\(request_uuid, KZ_ORIGINATE_SETTLED_SUCCESS' \
    'success tombstone written only on completion path'
