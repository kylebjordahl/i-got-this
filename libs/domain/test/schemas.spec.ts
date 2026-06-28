import { describe, expect, it } from 'vitest';
import {
  CreateClassificationRuleInput,
  CreateFeedInput,
  TimeOfDay,
} from '../src/index.js';

describe('domain schemas', () => {
  it('applies the default refresh interval (~6h)', () => {
    const parsed = CreateFeedInput.parse({
      url: 'https://example.com/cal.ics',
      mode: 'exception',
    });
    expect(parsed.refreshMinutes).toBe(360);
    expect(parsed.kind).toBe('ics');
  });

  it('rejects an invalid feed mode', () => {
    expect(() =>
      CreateFeedInput.parse({ url: 'https://x/c.ics', mode: 'nope' }),
    ).toThrow();
  });

  it('validates HH:MM times', () => {
    expect(TimeOfDay.safeParse('08:00').success).toBe(true);
    expect(TimeOfDay.safeParse('24:00').success).toBe(false);
    expect(TimeOfDay.safeParse('8:00').success).toBe(false);
  });

  it('accepts a no-school exception rule', () => {
    const rule = CreateClassificationRuleInput.parse({
      matchField: 'summary',
      matchOp: 'contains',
      matchValue: 'Closed',
      effect: 'cancel',
    });
    expect(rule.priority).toBe(100);
    expect(rule.effect).toBe('cancel');
  });
});
