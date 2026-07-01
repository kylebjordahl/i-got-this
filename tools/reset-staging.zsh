#!/usr/bin/env zsh
# One-off DESTRUCTIVE reset of the STAGING D1 database for the #26 data-model
# change (external accounts + input/output feeds). Wipes ALL data, then
# re-applies the fresh single baseline migration. There are no real customers,
# so this is intentionally not a safe/clean migration.
#
# NEVER run this against production.
#
# Usage (from the repo root):
#   tools/reset-staging.zsh
#   ENV=staging DB=DB tools/reset-staging.zsh   # override the wrangler env/binding
set -euo pipefail

ENV="${ENV:-staging}"
DB="${DB:-DB}"                       # the D1 *binding* in apps/api/wrangler.jsonc
DIR="${0:A:h}"                       # this script's directory (repo/tools)
API_DIR="${DIR:h}/apps/api"          # wrangler.jsonc lives here

print "⚠️  This DESTROYS all data in the '${ENV}' D1 database. Ctrl-C to abort."
print "→ dropping all tables (remote)…"
( cd "$API_DIR" && npx wrangler d1 execute "$DB" --env "$ENV" --remote --yes --file "$DIR/reset-staging.sql" )

print "→ re-applying the baseline migration…"
( cd "$API_DIR" && npx wrangler d1 migrations apply "$DB" --env "$ENV" --remote )

print "✓ ${ENV} D1 reset complete."
