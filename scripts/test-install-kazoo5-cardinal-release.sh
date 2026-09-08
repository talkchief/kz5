#!/usr/bin/env bash
# Installer control-flow fixture: no packages, network, database or services.
set -Eeuo pipefail
cardinal_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export KAZOO_DEPLOYMENT_CONFIG=/nonexistent/cardinal-release-fixture.env
source "$cardinal_root/scripts/install-kazoo5.sh"
cardinal_fixture=$(mktemp -d /tmp/kazoo-cardinal-shell.XXXXXX)
trap 'printf "Cardinal shell fixture: %s\n" "$cardinal_fixture"' EXIT
DRY_RUN=false
install_nodejs_toolchain() { :; }
run() {
    [[ "$*" == 'dnf -y install sox' ]] || return 91
    printf '%s\n' dependency:sox >>"$cardinal_fixture/events"
    [[ ${CARDINAL_REJECT_DEPENDENCY:-false} != true ]]
}
ensure_system_media_database() { printf '%s\n' database >>"$cardinal_fixture/events"; }
write_file() { printf 'write:%s\n' "$2" >>"$cardinal_fixture/events"; /usr/bin/cat >/dev/null; }
validate_acdc_language_receipt() { /usr/bin/cat >/dev/null; }
node() {
    if [[ $1 == */import-acdc-gemini-voices.cjs ]]; then
        printf 'fixed:%s\n' "$2" >>"$cardinal_fixture/events"
        printf '%s\n' '{"mode":"PLAN_ONLY_NO_DATABASE_ACCESS","count":210,"creates_only_versioned_ids":true,"preserves_legacy_and_custom_media":true,"runtime_ready":false}'
    elif [[ $1 == */install-acdc-cardinal-pack.cjs ]]; then
        printf 'cardinal:%s\n' "$2" >>"$cardinal_fixture/events"
        [[ $3 == --all-locales && $4 == --model-trial-index && $6 == --model-trial-index-sha256
            && $8 == --supplemental-pack && ${10} == --alias-file && ${12} == --alias-sha256 ]]
        [[ $5 == "$SCRIPT_DIR/assets/acdc-gemini-cardinal-model-trials-20260907/index.json"
            && $7 == b6c4e2a2ef515be72d378a239086b4421992a095447003c1c397c925d98c1e51 ]]
        [[ ${13} == f1338ba60bbb360a91491fcf3be0d161ca25ff267a2f7ec32c2faacc49ca1b6d ]]
        if [[ ${CARDINAL_REJECT_PLAN:-false} == true && $2 == --plan ]]; then return 78; fi
        /usr/bin/node -e '
          const mode=process.argv[1], plan=mode==="--plan", counts={"en-us":31,"he-il":131,"fr-fr":161,"es-es":53,"ar-sa":208};
          console.log(JSON.stringify({owner:"kazoo5-acdc-cardinal-installer",scope:"all-locales",
            mode:plan?"PLAN_ONLY_NO_DATABASE_ACCESS":mode==="--import"?"IMPORT_AND_VERIFY":"VERIFY_ONLY",
            count:584,source_complete:true,resolution_mode:"indexed-model-trials-v1",resolution_complete:true,
            runtime_ready:false,five_language_release_ready:false,listening_verified:false,queue_configuration_changed:false,
            database_verified:!plan,verified:plan?undefined:584,locales:Object.entries(counts).map(([locale,count])=>
              ({locale,count,mode:"VERIFY_ONLY",verified:count,created:0,intro_installed_verified:true}))}));' -- "$2"
    else return 91; fi
}
# A missing final source/map must reject before system_media creation or fixed
# imports, including reruns against an existing remote CouchDB.
if (export CARDINAL_REJECT_DEPENDENCY=true; install_acdc_language_packs); then
    die 'Missing source-verification dependency was accepted'
fi
[[ $(<"$cardinal_fixture/events") == dependency:sox ]]
: >"$cardinal_fixture/events"
if (export CARDINAL_REJECT_PLAN=true; install_acdc_language_packs); then
    die 'Incomplete cardinal source was accepted'
fi
[[ $(<"$cardinal_fixture/events") == $'dependency:sox\nfixed:--plan\ncardinal:--plan' ]]
: >"$cardinal_fixture/events"
install_acdc_language_packs
[[ $(<"$cardinal_fixture/events") == $'dependency:sox\nfixed:--plan\ncardinal:--plan\ndatabase\nfixed:--import\nfixed:--verify-only\nwrite:/usr/local/share/kazoo5-installer/acdc-gemini-media.json\ncardinal:--import\ncardinal:--verify-only\nwrite:/usr/local/share/kazoo5-installer/acdc-cardinal-media.json' ]]
# Actual receipt predicate rejects missing/duplicate locales and readiness claims.
valid=$(node "$SCRIPT_DIR/install-acdc-cardinal-pack.cjs" --verify-only --all-locales --model-trial-index \
    "$SCRIPT_DIR/assets/acdc-gemini-cardinal-model-trials-20260907/index.json" --model-trial-index-sha256 \
    b6c4e2a2ef515be72d378a239086b4421992a095447003c1c397c925d98c1e51 --supplemental-pack x \
    --alias-file y --alias-sha256 f1338ba60bbb360a91491fcf3be0d161ca25ff267a2f7ec32c2faacc49ca1b6d)
validate_acdc_cardinal_receipt VERIFY_ONLY <<<"$valid"
for mutation in '.locales |= .[0:4]' '.locales[4] = .locales[0]' '.locales[4].count = 207' '.verified = 583' '.runtime_ready = true' '.listening_verified = true' '.database_verified = false'; do
    if jq "$mutation" <<<"$valid" | validate_acdc_cardinal_receipt VERIFY_ONLY; then die 'Invalid cardinal receipt accepted'; fi
done
printf '%s\n' 'PASS five-language cardinal shell preflight, exact flags, separate import/readback and receipt rejection'
