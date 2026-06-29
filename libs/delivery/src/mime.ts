/**
 * Assemble a single-part text/calendar (iMIP) email as raw RFC 5322 MIME.
 * Includes Date + Message-ID so it passes strict validators (e.g. Cloudflare
 * Email Service). `from` must be on a verified sending domain.
 */
export function buildInviteEmailMime(opts: {
  from: string;
  to: string;
  subject: string;
  ics: string;
  method: 'REQUEST' | 'CANCEL';
}): string {
  const domain = opts.from.split('@')[1] ?? 'localhost';
  const messageId = `<${crypto.randomUUID()}@${domain}>`;
  return [
    `From: ${opts.from}`,
    `To: ${opts.to}`,
    `Subject: ${opts.subject}`,
    `Date: ${new Date().toUTCString()}`,
    `Message-ID: ${messageId}`,
    'MIME-Version: 1.0',
    `Content-Type: text/calendar; method=${opts.method}; charset=UTF-8`,
    'Content-Transfer-Encoding: 7bit',
    '',
    opts.ics,
  ].join('\r\n');
}
