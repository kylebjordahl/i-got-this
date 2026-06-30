import { and, type Db, eq, families, familyMembers, invites } from '@igt/db';
import { randomToken } from '../lib/crypto.js';

/**
 * Member-claim invites: an admin pre-creates a family member (no login), then
 * shares a link. When an authenticated user accepts it, their existing user is
 * linked to that member (sets family_members.user_id) — no new user is created,
 * so it also works for someone who already has an account in another family.
 */

const INVITE_TTL_MS = 14 * 24 * 60 * 60 * 1000; // 14 days

export type Invite = typeof invites.$inferSelect;

export async function createMemberClaimInvite(
  db: Db,
  familyId: string,
  memberId: string,
  issuedByMemberId: string,
): Promise<Invite> {
  const token = randomToken();
  const [row] = await db
    .insert(invites)
    .values({
      type: 'claim_member',
      familyId,
      memberId,
      issuedByMemberId,
      token,
      status: 'pending',
      expiresAt: new Date(Date.now() + INVITE_TTL_MS),
    })
    .returning();
  return row!;
}

/** Public preview of an invite (family + member names), by token. */
export async function previewInvite(db: Db, token: string) {
  const rows = await db
    .select({ invite: invites, family: families, member: familyMembers })
    .from(invites)
    .innerJoin(families, eq(families.id, invites.familyId))
    .leftJoin(familyMembers, eq(familyMembers.id, invites.memberId))
    .where(eq(invites.token, token))
    .limit(1);
  const row = rows[0];
  if (!row) return null;
  const expired = (row.invite.expiresAt?.getTime() ?? 0) < Date.now();
  return {
    type: row.invite.type,
    status: expired && row.invite.status === 'pending' ? 'expired' : row.invite.status,
    familyName: row.family.name,
    relationName: row.member?.relationName ?? null,
  };
}

export type AcceptResult =
  | { ok: true; familyId: string; memberId: string }
  | { ok: false; error: string; httpStatus: 400 | 404 | 409 | 410 };

/** Link the accepting user to the invite's member. Idempotent for that user. */
export async function acceptMemberClaimInvite(
  db: Db,
  token: string,
  userId: string,
): Promise<AcceptResult> {
  const invite = (
    await db.select().from(invites).where(eq(invites.token, token)).limit(1)
  )[0];
  if (!invite || invite.type !== 'claim_member' || !invite.memberId) {
    return { ok: false, error: 'invite_not_found', httpStatus: 404 };
  }

  const member = (
    await db
      .select()
      .from(familyMembers)
      .where(
        and(
          eq(familyMembers.id, invite.memberId),
          eq(familyMembers.familyId, invite.familyId!),
        ),
      )
      .limit(1)
  )[0];
  if (!member) return { ok: false, error: 'member_not_found', httpStatus: 404 };

  // Already linked to this same user → idempotent success (even once consumed).
  if (member.userId === userId) {
    await db.update(invites).set({ status: 'accepted' }).where(eq(invites.id, invite.id));
    return { ok: true, familyId: invite.familyId!, memberId: member.id };
  }
  if (member.userId && member.userId !== userId) {
    return { ok: false, error: 'member_already_claimed', httpStatus: 409 };
  }
  if (invite.status !== 'pending') {
    return { ok: false, error: 'invite_not_pending', httpStatus: 410 };
  }
  if ((invite.expiresAt?.getTime() ?? 0) < Date.now()) {
    await db.update(invites).set({ status: 'expired' }).where(eq(invites.id, invite.id));
    return { ok: false, error: 'invite_expired', httpStatus: 410 };
  }

  // The user must not already occupy a different member slot in this family.
  const existing = (
    await db
      .select()
      .from(familyMembers)
      .where(
        and(
          eq(familyMembers.familyId, invite.familyId!),
          eq(familyMembers.userId, userId),
        ),
      )
      .limit(1)
  )[0];
  if (existing) return { ok: false, error: 'already_in_family', httpStatus: 409 };

  await db.update(familyMembers).set({ userId }).where(eq(familyMembers.id, member.id));
  await db.update(invites).set({ status: 'accepted' }).where(eq(invites.id, invite.id));
  return { ok: true, familyId: invite.familyId!, memberId: member.id };
}
