# tools

Build/codegen utilities.

## OpenAPI → Dart client (planned)

The TS API (`apps/api`) publishes an **OpenAPI spec generated from the Zod
schemas in `libs/domain`** (the single source of truth for the contract). The
Flutter client's typed API layer is generated from that spec into
`apps/mobile/lib/api/generated/` (git-ignored).

Intended pipeline (wired up in Phase 1 alongside the first real endpoints):

1. Emit `openapi.json` from `libs/domain` Zod schemas (e.g. `zod-to-openapi`).
2. Generate the Dart client (e.g. `openapi-generator-cli` with the `dart-dio`
   generator, matching the app's `dio` dependency).

Since TS and Dart can't share source, this codegen is the bridge.
