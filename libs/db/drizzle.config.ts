import { defineConfig } from 'drizzle-kit';

/**
 * Drizzle Kit generates SQL migrations from ./src/schema.ts into ./migrations.
 * Migrations are applied to D1 via Wrangler:
 *   wrangler d1 migrations apply <DB> [--local|--remote]
 * (see apps/api). We only generate here; Wrangler owns application + state.
 */
export default defineConfig({
  dialect: 'sqlite',
  driver: 'd1-http',
  schema: './src/schema.ts',
  out: './migrations',
});
