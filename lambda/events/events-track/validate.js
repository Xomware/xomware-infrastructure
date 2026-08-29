'use strict';

// Pure validation/shaping for events-track. Split out of index.js so it can be
// tested without the AWS SDK or a live table — this is the security-relevant
// half of the endpoint (what a browser is allowed to write, and whose name it
// is allowed to write it under), so it is the half worth testing.

// Only these three. signin/signup are written by the Cognito trigger and must
// not be forgeable from a browser.
const ALLOWED_TYPES = new Set(['pageview', 'outbound', 'error']);

// Sized above what a legitimate full batch can be, so per-field truncation is
// what actually governs. MAX_EVENTS events at the LIMITS below come to roughly
// 41KB; an 8KB cap here would have silently dropped whole error reports with
// deep stacks — precisely the reports worth having — instead of trimming them.
// This is a backstop against absurd payloads, not the real limiter.
const MAX_BODY_BYTES = 64 * 1024;
const MAX_EVENTS = 10;
const LIMITS = {
  path: 512,
  referrer: 512,
  target: 512,
  app: 64,
  message: 500,
  stack: 2048,
  userAgent: 256,
  visitorId: 64,
};

const str = (v, max) => (typeof v === 'string' && v ? v.slice(0, max) : undefined);

/**
 * Identity comes from verified JWT claims or not at all. A `userId` in the
 * request body is ignored by construction — it is never read.
 */
function resolveUserId(claims, visitorId) {
  const sub = claims && claims.sub;
  if (typeof sub === 'string' && sub) return sub;
  // Anonymous rows still need a userId: it is the `by-user` GSI hash key, and
  // DynamoDB drops items from an index entirely when the key is absent.
  return `anon:${visitorId}`;
}

/**
 * Turn a raw request into the rows to write. Returns [] for anything invalid —
 * callers treat that as "nothing to do", never as an error to surface.
 *
 * @param {object} args
 * @param {string} args.rawBody      unparsed request body
 * @param {object} [args.claims]     verified JWT claims, when the authorized route was used
 * @param {object} [args.headers]    request headers
 * @param {Date}   args.now
 * @param {number} args.retentionDays
 */
function buildItems({ rawBody, claims, headers = {}, now, retentionDays, uuid }) {
  if (Buffer.byteLength(rawBody || '', 'utf8') > MAX_BODY_BYTES) {
    return { items: [], dropped: 'body-too-large' };
  }

  let body;
  try {
    body = JSON.parse(rawBody || '{}');
  } catch {
    return { items: [], dropped: 'unparseable' };
  }

  const incoming = Array.isArray(body.events) ? body.events : [body];
  if (incoming.length === 0) return { items: [], dropped: null };

  const visitorId = str(body.visitorId, LIMITS.visitorId) || 'unknown';
  const userId = resolveUserId(claims, visitorId);
  const userAgent = str(headers['User-Agent'] || headers['user-agent'], LIMITS.userAgent);
  const country = str(
    headers['CloudFront-Viewer-Country'] || headers['cloudfront-viewer-country'],
    8,
  );

  const eventTime = now.toISOString();
  const eventDate = eventTime.slice(0, 10);
  const ttl = Math.floor(now.getTime() / 1000) + retentionDays * 86400;

  const items = [];
  for (const e of incoming.slice(0, MAX_EVENTS)) {
    const eventType = e && typeof e.type === 'string' ? e.type : '';
    if (!ALLOWED_TYPES.has(eventType)) continue;

    const eventId = uuid();
    items.push({
      eventId,
      eventType,
      eventTime,
      eventDate,
      eventTimeId: `${eventTime}#${eventId}`,
      userId,
      visitorId,
      path: str(e.path, LIMITS.path),
      referrer: str(e.referrer, LIMITS.referrer),
      target: eventType === 'outbound' ? str(e.target, LIMITS.target) : undefined,
      app: eventType === 'outbound' ? str(e.app, LIMITS.app) : undefined,
      message: eventType === 'error' ? str(e.message, LIMITS.message) : undefined,
      stack: eventType === 'error' ? str(e.stack, LIMITS.stack) : undefined,
      userAgent,
      country,
      ttl,
    });
  }

  return { items, dropped: null };
}

module.exports = { buildItems, resolveUserId, ALLOWED_TYPES, MAX_EVENTS, MAX_BODY_BYTES, LIMITS };
