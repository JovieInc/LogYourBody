import { z } from 'zod';

/** Sole outbound decision for program revisions and training MCP v1 (LYB-281). */
export const TRAINING_OUTBOUND_POLICY = Object.freeze({
  response: 'structured_records_only',
  coachMessage: false,
  notification: false,
  send: false,
  forbiddenFields: Object.freeze([
    'message',
    'messages',
    'coachmessage',
    'coachmessages',
    'prose',
    'text',
    'content',
    'notification',
    'notifications',
    'send',
    'sendmessage',
    'push',
    'pushnotification',
    'chatpost',
  ]),
} as const);

/** Inspect raw records before a schema can strip unknown keys, including in diffs. */
export function structuredTrainingRecord<T extends z.ZodType>(schema: T) {
  return z
    .unknown()
    .superRefine((value, context) => {
      function visit(record: unknown, path: Array<string | number>) {
        if (!record || typeof record !== 'object') return;
        for (const [key, child] of Object.entries(record)) {
          const childPath = [...path, Array.isArray(record) ? Number(key) : key];
          const normalized = key.replace(/[_-]/g, '').toLowerCase();
          if (TRAINING_OUTBOUND_POLICY.forbiddenFields.some((field) => field === normalized)) {
            context.addIssue({
              code: 'custom',
              path: childPath,
              message: 'Training records cannot contain coach messages or delivery instructions',
            });
          }
          visit(child, childPath);
        }
      }
      visit(value, []);
    })
    .pipe(schema);
}
