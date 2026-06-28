import { and, eq, familyMemberFeeds, familyMembers, feeds, getDb } from '@igt/db';
import { CreateFeedInput, MemberFeedLinkInput } from '@igt/domain';
import { Hono } from 'hono';
import type { HonoEnv } from '../env.js';
import { requireAdmin, requireFamilyMember } from '../middleware/auth.js';
import { ingestFamilyFeeds, ingestFeed } from '../services/ingest.js';
import { buildFeedTasks } from '../services/tasks.js';

/** Mounted under /families/:familyId/feeds (auth applied by parent router). */
export const feedRoutes = new Hono<HonoEnv>();
feedRoutes.use('*', requireFamilyMember);

/** Create an input feed (admin). */
feedRoutes.post('/', requireAdmin, async (c) => {
  const parsed = CreateFeedInput.safeParse(await c.req.json().catch(() => null));
  if (!parsed.success) {
    return c.json({ error: 'invalid', issues: parsed.error.issues }, 400);
  }
  const feed = (
    await getDb(c.env.DB)
      .insert(feeds)
      .values({
        familyId: c.get('member').familyId,
        url: parsed.data.url,
        kind: parsed.data.kind,
        mode: parsed.data.mode,
        refreshMinutes: parsed.data.refreshMinutes,
      })
      .returning()
  )[0]!;
  return c.json({ feed }, 201);
});

/** List a family's feeds. */
feedRoutes.get('/', async (c) => {
  const rows = await getDb(c.env.DB)
    .select()
    .from(feeds)
    .where(eq(feeds.familyId, c.get('member').familyId));
  return c.json({ feeds: rows });
});

/** Link a dependent to a feed, with an optional baseline for exception feeds (admin). */
feedRoutes.post('/:feedId/member-links', requireAdmin, async (c) => {
  const parsed = MemberFeedLinkInput.safeParse(await c.req.json().catch(() => null));
  if (!parsed.success) {
    return c.json({ error: 'invalid', issues: parsed.error.issues }, 400);
  }
  const db = getDb(c.env.DB);
  const familyId = c.get('member').familyId;
  const feedId = c.req.param('feedId');

  // Tenancy: both the feed and the member must belong to this family.
  const feed = (
    await db
      .select()
      .from(feeds)
      .where(and(eq(feeds.id, feedId), eq(feeds.familyId, familyId)))
      .limit(1)
  )[0];
  const member = (
    await db
      .select()
      .from(familyMembers)
      .where(
        and(
          eq(familyMembers.id, parsed.data.familyMemberId),
          eq(familyMembers.familyId, familyId),
        ),
      )
      .limit(1)
  )[0];
  if (!feed || !member) return c.json({ error: 'not_found' }, 404);

  const link = (
    await db
      .insert(familyMemberFeeds)
      .values({
        familyId,
        feedId,
        familyMemberId: parsed.data.familyMemberId,
        weekdayMask: parsed.data.weekdayMask ?? null,
        dayStart: parsed.data.dayStart ?? null,
        dayEnd: parsed.data.dayEnd ?? null,
        generatesTypes: parsed.data.generatesTypes ?? null,
        defaultAttendance: parsed.data.defaultAttendance ?? null,
      })
      .returning()
  )[0]!;
  return c.json({ link }, 201);
});

/** Force-refresh a single feed now. */
feedRoutes.post('/:feedId/refresh', async (c) => {
  const db = getDb(c.env.DB);
  const familyId = c.get('member').familyId;
  const feedId = c.req.param('feedId');

  const feed = (
    await db
      .select()
      .from(feeds)
      .where(and(eq(feeds.id, feedId), eq(feeds.familyId, familyId)))
      .limit(1)
  )[0];
  if (!feed) return c.json({ error: 'not_found' }, 404);

  await db
    .update(feeds)
    .set({ lastRefreshRequestedAt: new Date() })
    .where(eq(feeds.id, feed.id));

  const ingest = await ingestFeed(db, feed);
  const build = await buildFeedTasks(db, feed);
  return c.json({ ingest, build });
});

/** Force-refresh all of a family's feeds now (ingest + rebuild tasks). */
feedRoutes.post('/refresh-all', async (c) => {
  const db = getDb(c.env.DB);
  const familyId = c.get('member').familyId;
  const ingest = await ingestFamilyFeeds(db, familyId);

  const familyFeeds = await db.select().from(feeds).where(eq(feeds.familyId, familyId));
  const build = [];
  for (const feed of familyFeeds) {
    build.push(await buildFeedTasks(db, feed));
  }
  return c.json({ ingest, build });
});
