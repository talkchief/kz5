#!/usr/bin/bash
# Offline checks of the actual installer helper; no network or package changes.
set -euo pipefail
source_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test-kazoo-calls.sh
eval "$(sed -n '/^ensure_sipp_version_tag() {/,/^}/p' "$source_path")"
SIPP_VERSION=3.7.7 SIPP_COMMIT=369b3c187f0ff96f3ec9795650820e80cf17c776
SIPP_SOURCE=/fixture-readonly
die() { printf '%s\n' "$*" >&2; exit 1; }
git() {
    [[ $1 == -C && $2 == "$SIPP_SOURCE" ]] || exit 90
    shift 2
    case "$1" in
        show-ref)
            [[ "$*" == 'show-ref --verify --quiet refs/tags/v3.7.7' ]] || exit 91
            [[ $case_name == existing || $case_name == wrong ]]
            ;;
        fetch)
            [[ "$*" == 'fetch -q --depth 1 origin refs/tags/v3.7.7:refs/tags/v3.7.7' ]] || exit 92
            fetched=true
            [[ $case_name != fetch_failure ]]
            ;;
        rev-parse)
            [[ "$*" == 'rev-parse refs/tags/v3.7.7^{commit}' ]] || exit 93
            if [[ $case_name == wrong || $case_name == fetched_wrong ]]; then
                printf 'different-commit\n'
            else printf '%s\n' "$SIPP_COMMIT"; fi
            ;;
        *) exit 94 ;;
    esac
}
for case_name in existing missing; do
    fetched=false
    ensure_sipp_version_tag
    if [[ $case_name == existing ]]; then [[ $fetched == false ]]; else [[ $fetched == true ]]; fi
done
for case_name in wrong fetched_wrong fetch_failure; do
    if (ensure_sipp_version_tag) 2>/dev/null; then die "Accepted $case_name"; fi
done
printf 'PASS existing/missing release tag, exact fetch scope, pinned commit mismatch and fetch failure\n'
