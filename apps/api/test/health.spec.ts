import {
  createExecutionContext,
  env,
  waitOnExecutionContext,
} from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import app from '../src/index.js';

async function call(path: string, init?: RequestInit) {
  const ctx = createExecutionContext();
  const res = await app.fetch(new Request(`https://api.test${path}`, init), env, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

describe('api health', () => {
  it('GET /health returns ok', async () => {
    const res = await call('/health');
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean; service: string };
    expect(body.ok).toBe(true);
    expect(body.service).toBe('igt-api');
  });

  it('GET /health/db reaches the D1 binding', async () => {
    const res = await call('/health/db');
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ db: 'up' });
  });

  it('POST /feeds/:id/refresh accepts the request (202)', async () => {
    const res = await call('/feeds/abc/refresh', { method: 'POST' });
    expect(res.status).toBe(202);
    const body = (await res.json()) as { feedId: string; queued: boolean };
    expect(body.feedId).toBe('abc');
    expect(body.queued).toBe(true);
  });

  it('unknown routes 404', async () => {
    const res = await call('/nope');
    expect(res.status).toBe(404);
  });
});
