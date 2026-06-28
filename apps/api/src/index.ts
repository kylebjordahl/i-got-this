import { Hono } from 'hono';
import { getDb } from '@igt/db';
import type { HonoEnv } from './env.js';

/**
 * API worker entrypoint. Phase 0 stands up the worker + D1 binding and a
 * couple of health endpoints; feeds/tasks/delivery routes are filled in across
 * Phases 2–4. A `family_id` tenant-guard middleware (Phase 1) will wrap every
 * tenant-scoped route.
 */
const app = new Hono<HonoEnv>();

app.get('/health', (c) =>
  c.json({
    ok: true,
    service: 'igt-api',
    environment: c.env.ENVIRONMENT,
    time: new Date().toISOString(),
  }),
);

// Confirms the D1 binding is wired and reachable.
app.get('/health/db', async (c) => {
  const row = await c.env.DB.prepare('select 1 as ok').first<{ ok: number }>();
  return c.json({ db: row?.ok === 1 ? 'up' : 'down' });
});

// --- Feed refresh (force) — Phase 2 implements the enqueue/parse -----------

app.post('/feeds/:id/refresh', async (c) => {
  const id = c.req.param('id');
  // Phase 2: mark feed.last_refresh_requested_at + enqueue a parse job.
  void getDb; // db wired here in Phase 2
  return c.json({ feedId: id, queued: true, note: 'stub — implemented in Phase 2' }, 202);
});

app.post('/feeds/refresh-all', (c) =>
  c.json({ queued: true, note: 'stub — implemented in Phase 2' }, 202),
);

app.notFound((c) => c.json({ error: 'not_found' }, 404));

export default app;
