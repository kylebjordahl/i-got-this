import { type Db, eq, externalAccounts } from '@igt/db';
import type { DeliveryCredential } from '@igt/delivery';
import { loadSecret } from './secrets.js';

/**
 * Decrypt a connected external account's stored credential. CalDAV/iCloud
 * accounts hold a `basic` credential (username + app-specific password); Google
 * accounts hold an `oauth` credential (a stored refresh token). Used by both the
 * ingest path (input feeds) and the delivery path (output feeds), which resolve
 * the credential from the feed/target's linked account rather than storing it
 * per-feed. Returns undefined when there's no account, no stored secret, or no
 * KEK configured.
 */
export async function resolveAccountCredential(
  db: Db,
  kek: string | undefined,
  accountId: string | null,
): Promise<DeliveryCredential | undefined> {
  if (!accountId || !kek) return undefined;
  const account = (
    await db
      .select()
      .from(externalAccounts)
      .where(eq(externalAccounts.id, accountId))
      .limit(1)
  )[0];
  if (!account?.credentialsRef) return undefined;
  const raw = await loadSecret(db, kek, account.credentialsRef);
  return raw ? (JSON.parse(raw) as DeliveryCredential) : undefined;
}
