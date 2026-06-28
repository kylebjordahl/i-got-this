import { eq, feeds, getDb } from '@igt/db';
import type { Bindings } from './env.js';
import { ingestFeed } from './services/ingest.js';

/**
 * Cron tick: ingest every active feed whose `refreshMinutes` has elapsed since
 * its last sync. Runs ingestion in the background (waitUntil) so the tick
 * returns quickly. A Queue can later wrap this for at-scale retry/backoff.
 */
export async function scheduled(
  _event: ScheduledController,
  env: Bindings,
  ctx: ExecutionContext,
): Promise<void> {
  const db = getDb(env.DB);
  const now = Date.now();
  const active = await db.select().from(feeds).where(eq(feeds.status, 'active'));

  for (const feed of active) {
    const last = feed.lastSyncedAt?.getTime() ?? 0;
    if (now - last >= feed.refreshMinutes * 60 * 1000) {
      ctx.waitUntil(
        ingestFeed(db, feed).catch((err) =>
          console.error(`scheduled ingest failed for ${feed.id}`, err),
        ),
      );
    }
  }
}
