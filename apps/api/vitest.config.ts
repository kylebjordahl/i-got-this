import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config';

/**
 * Integration tests run inside workerd with real bindings (D1) provisioned
 * from wrangler.jsonc — the same config the worker deploys with.
 */
export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: './wrangler.jsonc' },
        miniflare: {
          compatibilityFlags: ['nodejs_compat'],
        },
      },
    },
  },
});
