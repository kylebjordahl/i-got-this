import {
  and,
  calendarTargets,
  type Db,
  eq,
  externalAccounts,
  familyMembers,
  getDb,
} from '@igt/db';
import {
  CreateCalendarTargetInput,
  UpdateCalendarTargetInput,
} from '@igt/domain';
import { Hono } from 'hono';
import type { HonoEnv } from '../env.js';
import { requireFamilyMember } from '../middleware/auth.js';
import {
  enqueueReconcile,
  getProductionRegistry,
  purgeTargetRemote,
} from '../services/delivery.js';

/** Load a target with the family it belongs to (for tenancy + ownership checks). */
async function loadTarget(db: Db, targetId: string) {
  const rows = await db
    .select({ target: calendarTargets, familyId: familyMembers.familyId })
    .from(calendarTargets)
    .innerJoin(familyMembers, eq(familyMembers.id, calendarTargets.memberId))
    .where(eq(calendarTargets.id, targetId))
    .limit(1);
  return rows[0] ?? null;
}

/** Mounted under /families/:familyId (auth applied by parent router). */
export const targetRoutes = new Hono<HonoEnv>();
targetRoutes.use('*', requireFamilyMember);

/**
 * Create an output feed (calendar target) for a caretaker. `email` targets stand
 * alone. `caldav`/`google` targets draw their credential from a connected
 * `externalAccountId`; the account must belong to the caller (owner-only), its
 * kind must match the method, and it may only target a caretaker member linked to
 * that same owner. The target calendar (addressOrUrl / externalCalendarId) is
 * captured immutably here.
 */
targetRoutes.post('/calendar-targets', async (c) => {
  const parsed = CreateCalendarTargetInput.safeParse(
    await c.req.json().catch(() => null),
  );
  if (!parsed.success) {
    return c.json({ error: 'invalid', issues: parsed.error.issues }, 400);
  }
  const me = c.get('member');
  const d = parsed.data;

  // A member manages their own output feeds; admins may manage anyone's.
  if (d.memberId !== me.id && !me.isAdmin) {
    return c.json({ error: 'forbidden' }, 403);
  }

  const db = getDb(c.env.DB);

  // Target member must belong to this family.
  const targetMember = (
    await db
      .select()
      .from(familyMembers)
      .where(and(eq(familyMembers.id, d.memberId), eq(familyMembers.familyId, me.familyId)))
      .limit(1)
  )[0];
  if (!targetMember) return c.json({ error: 'member_not_found' }, 404);

  let externalAccountId: string | null = null;
  let providerHint: 'icloud' | 'google' | 'generic_caldav' | null = null;

  if (d.method !== 'email') {
    const account = (
      await db
        .select()
        .from(externalAccounts)
        .where(
          and(
            eq(externalAccounts.id, d.externalAccountId!),
            eq(externalAccounts.userId, c.get('user').id),
          ),
        )
        .limit(1)
    )[0];
    if (!account) return c.json({ error: 'account_not_found' }, 404);
    const accountMethod = account.kind === 'google' ? 'google' : 'caldav';
    if (d.method !== accountMethod) return c.json({ error: 'account_kind_mismatch' }, 400);
    // The account's calendars may only feed a caretaker role assigned to the owner.
    if (!targetMember.isCaretaker) return c.json({ error: 'not_a_caretaker' }, 400);
    if (targetMember.userId !== account.userId) return c.json({ error: 'member_not_owned' }, 403);
    externalAccountId = account.id;
    providerHint =
      account.kind === 'icloud' ? 'icloud' : account.kind === 'google' ? 'google' : 'generic_caldav';
  }

  const row = (
    await db
      .insert(calendarTargets)
      .values({
        memberId: d.memberId,
        name: d.name,
        method: d.method,
        providerHint,
        externalAccountId,
        addressOrUrl: d.addressOrUrl,
        externalCalendarId: d.externalCalendarId ?? null,
        alertMinutes: d.alertMinutes ?? null,
      })
      .returning()
  )[0]!;

  // Reflect the owner's existing owned tasks onto the new calendar (queued).
  enqueueReconcile(c, { kind: 'member', memberId: d.memberId });

  return c.json({ target: row }, 201);
});

/** List output feeds (own; admins see the whole family). */
targetRoutes.get('/calendar-targets', async (c) => {
  const db = getDb(c.env.DB);
  const me = c.get('member');

  const projection = {
    id: calendarTargets.id,
    memberId: calendarTargets.memberId,
    memberRelation: familyMembers.relationName,
    name: calendarTargets.name,
    method: calendarTargets.method,
    providerHint: calendarTargets.providerHint,
    externalAccountId: calendarTargets.externalAccountId,
    addressOrUrl: calendarTargets.addressOrUrl,
    externalCalendarId: calendarTargets.externalCalendarId,
    alertMinutes: calendarTargets.alertMinutes,
    active: calendarTargets.active,
  };
  const base = db
    .select(projection)
    .from(calendarTargets)
    .innerJoin(familyMembers, eq(familyMembers.id, calendarTargets.memberId));

  const rows = me.isAdmin
    ? await base.where(eq(familyMembers.familyId, me.familyId))
    : await base.where(eq(calendarTargets.memberId, me.id));

  return c.json({ targets: rows });
});

/**
 * Update an output feed's config (own; any admin). Only name / active / alerts
 * are editable — the method, linked account, and target calendar are immutable
 * (delete + recreate to change them).
 */
targetRoutes.patch('/calendar-targets/:targetId', async (c) => {
  const parsed = UpdateCalendarTargetInput.safeParse(await c.req.json().catch(() => null));
  if (!parsed.success) {
    return c.json({ error: 'invalid', issues: parsed.error.issues }, 400);
  }
  const db = getDb(c.env.DB);
  const me = c.get('member');
  const found = await loadTarget(db, c.req.param('targetId'));
  if (!found || found.familyId !== me.familyId) return c.json({ error: 'not_found' }, 404);
  if (found.target.memberId !== me.id && !me.isAdmin) {
    return c.json({ error: 'forbidden' }, 403);
  }

  const d = parsed.data;
  const set: Partial<typeof calendarTargets.$inferInsert> = {};
  if (d.name !== undefined) set.name = d.name;
  if (d.active !== undefined) set.active = d.active;
  if (d.alertMinutes !== undefined) set.alertMinutes = d.alertMinutes;

  if (Object.keys(set).length > 0) {
    await db.update(calendarTargets).set(set).where(eq(calendarTargets.id, found.target.id));
  }
  const updated = (
    await db.select().from(calendarTargets).where(eq(calendarTargets.id, found.target.id)).limit(1)
  )[0]!;

  // Reconcile after the change (active toggle, alert change, etc.) off the
  // request path so the response returns promptly.
  enqueueReconcile(c, { kind: 'member', memberId: found.target.memberId });

  return c.json({ target: updated });
});

/** Delete an output feed (own; admins any). Its remote events are removed first. */
targetRoutes.delete('/calendar-targets/:targetId', async (c) => {
  const db = getDb(c.env.DB);
  const me = c.get('member');
  const found = await loadTarget(db, c.req.param('targetId'));
  if (!found || found.familyId !== me.familyId) return c.json({ error: 'not_found' }, 404);
  if (found.target.memberId !== me.id && !me.isAdmin) {
    return c.json({ error: 'forbidden' }, 403);
  }

  // Remove the events we put on the remote calendar before dropping the target.
  try {
    await purgeTargetRemote(db, getProductionRegistry(c.env), c.env.KEK, found.target);
  } catch (err) {
    console.error('purgeTargetRemote failed', err);
  }

  await db.delete(calendarTargets).where(eq(calendarTargets.id, found.target.id));
  return c.json({ ok: true });
});
