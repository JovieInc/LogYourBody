import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const root = new URL('../../../', import.meta.url);
const calendar = readFileSync(new URL('docs/compliance/claims-policy-review.ics', root), 'utf8');
const policy = readFileSync(new URL('docs/compliance/claims-policy.md', root), 'utf8');

function assertQuarterlyReminder(source: string) {
  // Check the exported calendar's notification contract, without an overdue CI gate.
  assert.ok(source.endsWith('\r\n'), 'calendar must end with CRLF');
  for (const line of source.split('\r\n')) {
    assert.ok(!/[\r\n]/.test(line), 'calendar requires CRLF content lines');
    assert.ok(Buffer.byteLength(line) <= 75, 'calendar lines must be folded');
  }
  const unfolded = source.replace(/\r\n[ \t]/g, '');
  const event = unfolded.split('BEGIN:VEVENT\r\n')[1]?.split('END:VEVENT')[0];
  assert.ok(event, 'calendar needs a review event');
  assert.equal(unfolded.match(/BEGIN:VEVENT/g)?.length, 1);
  const [details, alarm] = event.split('BEGIN:VALARM\r\n');
  const fields = new Map(
    details
      .trim()
      .split('\r\n')
      .map((line) => {
        const colon = line.indexOf(':');
        return [line.slice(0, colon), line.slice(colon + 1)] as const;
      }),
  );
  assert.equal(fields.get('RRULE'), 'FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=27');
  assert.equal(fields.get('DTSTART;VALUE=DATE'), '20261227');
  assert.equal(fields.get('DTEND;VALUE=DATE'), '20261228');
  assert.equal(fields.get('PRIORITY'), '9');
  assert.equal(fields.get('TRANSP'), 'TRANSPARENT');
  assert.match(alarm ?? '', /ACTION:DISPLAY\r\nTRIGGER:-P7D\r\n/);
  assert.match(alarm ?? '', /DESCRIPTION:.+\r\nEND:VALARM/);
  const url = fields.get('URL') ?? '';
  assert.ok(url.endsWith('/docs/compliance/claims-policy.md#recurring-source-review'));
  assert.match(policy, /^## Recurring source review$/m);
  for (const sourceName of ['FDA', 'FTC', 'Apple', 'Tim White']) {
    assert.ok(fields.get('DESCRIPTION')?.includes(sourceName));
  }
  const quarantineIssue = 'https://linear.app/jovie/issue/LYB-190';
  assert.ok(fields.get('DESCRIPTION')?.includes(quarantineIssue));
  assert.ok(policy.includes(quarantineIssue));
}

describe('quarterly claims-policy review reminder (LYB-191)', () => {
  it('exports an ongoing quarterly review with a display alert and GLP-1 follow-up', () => {
    assertQuarterlyReminder(calendar);
  });

  it.each([
    ['one-off event', (text: string) => text.replace(/RRULE:[^\r]+\r\n/, '')],
    ['annual recurrence', (text: string) => text.replace('INTERVAL=3', 'INTERVAL=12')],
    ['missing alert', (text: string) => text.replace(/BEGIN:VALARM[\s\S]+END:VALARM\r\n/, '')],
    ['missing quarantine link', (text: string) => text.replace('issue/LYB-190', 'issue/missing')],
  ] as const)('rejects a %s', (_name, mutate) => {
    expect(() => assertQuarterlyReminder(mutate(calendar))).toThrow();
  });
});
