import { and, eq, families, feeds, getDb } from '@igt/db';
import type { Bindings } from './env.js';
import { googleRefresherFor } from './lib/google-oauth.js';
import { getProductionRegistry, syncFamily } from './services/delivery.js';
import { ingestFeed } from './services/ingest.js';
import { buildFeedTasks } from './services/tasks.js';

/**
 * Cron tick, per family: ingest + rebuild any feed whose refresh interval has
 * elapsed, then run a true-up that reconciles every caretaker's calendars to
 * their owned tasks. The reconcile is cheap when nothing drifted (payloadHash
 * skips unchanged events), so it's safe to run every tick.
 */
export async function scheduled(
  _event: ScheduledController,
  env: Bindings,
  ctx: ExecutionContext,
): Promise<void> {
  const db = getDb(env.DB);
  const registry = getProductionRegistry(env);
  const ingestSecrets = { kek: env.KEK, googleRefresh: googleRefresherFor(env) };
  const now = Date.now();

  const allFamilies = await db.select().from(families);
  for (const fam of allFamilies) {
    ctx.waitUntil(
      (async () => {
        try {
          const familyFeeds = await db
            .select()
            .from(feeds)
            .where(and(eq(feeds.familyId, fam.id), eq(feeds.status, 'active')));
          for (const feed of familyFeeds) {
            const last = feed.lastSyncedAt?.getTime() ?? 0;
            if (now - last >= feed.refreshMinutes * 60 * 1000) {
              await ingestFeed(db, feed, ingestSecrets);
              await buildFeedTasks(db, feed);
            }
          }
          await syncFamily(db, registry, env.KEK, fam.id);
        } catch (err) {
          console.error(`scheduled tick failed for family ${fam.id}`, err);
        }
      })(),
    );
  }
}
