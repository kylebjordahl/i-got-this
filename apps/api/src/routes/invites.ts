import { getDb } from '@igt/db';
import { Hono } from 'hono';
import type { HonoEnv } from '../env.js';
import { authMiddleware } from '../middleware/auth.js';
import { acceptMemberClaimInvite, previewInvite } from '../services/invites.js';

/** Mounted at /invites. Accepting requires a session but NOT family membership. */
export const inviteRoutes = new Hono<HonoEnv>();

/** Public preview so the invitee can see what they're joining before login. */
inviteRoutes.get('/:token', async (c) => {
  const preview = await previewInvite(getDb(c.env.DB), c.req.param('token'));
  if (!preview) return c.json({ error: 'invite_not_found' }, 404);
  return c.json({ invite: preview });
});

/** Link the logged-in user to the invite's pre-created family member. */
inviteRoutes.post('/:token/accept', authMiddleware, async (c) => {
  const user = c.get('user');
  const result = await acceptMemberClaimInvite(
    getDb(c.env.DB),
    c.req.param('token'),
    user.id,
  );
  if (!result.ok) return c.json({ error: result.error }, result.httpStatus);
  return c.json({ ok: true, familyId: result.familyId, memberId: result.memberId });
});
