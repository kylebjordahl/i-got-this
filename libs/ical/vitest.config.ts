import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config';

/**
 * Runs the OSS-library spike INSIDE workerd (the real Cloudflare Workers
 * runtime), proving ical.js / ical-generator / tsdav import and execute there.
 */
export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        miniflare: {
          compatibilityDate: '2024-09-23',
          compatibilityFlags: ['nodejs_compat'],
        },
      },
    },
  },
});
