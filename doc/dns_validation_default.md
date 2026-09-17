# kazoo_web `should_validate_dns` defaults to false

Operator decision, September 17, 2026: hostname DNS validation for URL-typed
fields (webhooks, pivot, media URLs and similar) is **off by default**, in the
build and in existing deployments.

## Where the default lives

| Place | Owner | Change |
| --- | --- | --- |
| `kz_json_schema_extensions:is_valid_dns/1` compiled default | fetched `core` | required patch `scripts/patches/kazoo-dns-validation-default.patch` |
| `system_config.kazoo_web.json`, `swagger.json`, `oas3-schemas.yml` | fetched `crossbar` | required patch `scripts/patches/crossbar-dns-validation-default.patch` |
| Published catalog `scripts/assets/api-docs/openapi.json` | kz5 | regenerated with `build-api-docs.cjs`, verified |
| Stored `system_config/kazoo_web` value | each deployment's database | installer step below |

`kapps_config` persists whatever default it first read, so an existing database
keeps an explicit `true` and the compiled default alone would change nothing.
`install_kazoo_apps` therefore runs `ensure_dns_validation_disabled` (store
`false`, flush, reread) and `verify_kazoo_apps` runs the read-only
`verify_dns_validation_disabled`. `--verify-only` never writes. An operator who
needs validation on one system sets the value after installation; the next
kazoo-apps installation sets it back to `false` by design.

## Verification and deployment

`bash scripts/test-kazoo-dns-validation-default.sh` passes six groups: both
patches replayed through the real `apply_required_source_patch` on pinned
source (apply, idempotent reapply, drift refusal); exact patched values in
source, schema, swagger, OAS3 source and the published catalog; installer wiring;
the real ensure/verify functions against a stubbed `sup`, including five refusal
cases. Installer base/modular/deployment/read-only/production-BEAM suites and
`verify-api-docs.cjs`/`test-api-docs.cjs` pass.

Applied natively on September 17 without any restart: main dev44 stack
`true` -> `false` (reread after flush); private lab pair `false` on both nodes.
Running VMs still carry the old compiled default until their next normal build;
it is unreachable while the stored value is an explicit `false`.
