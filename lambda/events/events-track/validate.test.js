'use strict';

// Run with:  node --test lambda/events/events-track/
//
// Uses the Node built-in test runner deliberately: this repo has no package.json
// and no test framework, and the validation worth testing here needs neither.

const test = require('node:test');
const assert = require('node:assert');
const { buildItems, MAX_EVENTS } = require('./validate');

const NOW = new Date('2026-08-14T15:04:05.123Z');
let n = 0;
const uuid = () => `uuid-${++n}`;

const build = (body, opts = {}) => {
  n = 0;
  return buildItems({
    rawBody: typeof body === 'string' ? body : JSON.stringify(body),
    now: NOW,
    retentionDays: 90,
    uuid,
    ...opts,
  });
};

test('accepts the three public event types', () => {
  const { items } = build({
    visitorId: 'v1',
    events: [{ type: 'pageview' }, { type: 'outbound' }, { type: 'error' }],
  });
  assert.deepStrictEqual(items.map((i) => i.eventType), ['pageview', 'outbound', 'error']);
});

test('rejects forged signin and signup events', () => {
  // These are written by the Cognito trigger and are the basis of the audit
  // trail. A browser must not be able to fabricate one.
  const { items } = build({
    visitorId: 'v1',
    events: [{ type: 'signin' }, { type: 'signup' }, { type: 'pageview' }],
  });
  assert.strictEqual(items.length, 1);
  assert.strictEqual(items[0].eventType, 'pageview');
});

test('rejects unknown event types', () => {
  const { items } = build({ visitorId: 'v1', events: [{ type: 'nonsense' }, { type: '' }, {}] });
  assert.strictEqual(items.length, 0);
});

test('ignores a client-supplied userId', () => {
  const { items } = build({
    visitorId: 'v1',
    userId: 'someone-elses-cognito-sub',
    events: [{ type: 'pageview' }],
  });
  assert.strictEqual(items[0].userId, 'anon:v1');
});

test('uses the verified sub when claims are present', () => {
  const { items } = build(
    { visitorId: 'v1', events: [{ type: 'pageview' }] },
    { claims: { sub: 'real-cognito-sub' } },
  );
  assert.strictEqual(items[0].userId, 'real-cognito-sub');
});

test('always sets userId so rows survive the by-user index', () => {
  // A GSI silently drops items missing its hash key.
  const { items } = build({ events: [{ type: 'pageview' }] });
  assert.strictEqual(items[0].userId, 'anon:unknown');
});

test('caps the number of events per request', () => {
  const events = Array.from({ length: 50 }, () => ({ type: 'pageview' }));
  const { items } = build({ visitorId: 'v1', events });
  assert.strictEqual(items.length, MAX_EVENTS);
});

test('drops an absurd body without throwing', () => {
  const { items, dropped } = build({ visitorId: 'v1', events: [{ type: 'error', stack: 'x'.repeat(70000) }] });
  assert.strictEqual(items.length, 0);
  assert.strictEqual(dropped, 'body-too-large');
});

test('trims a deep stack rather than dropping the whole report', () => {
  // Regression: the body cap used to be 8KB, below what a legitimate batch can
  // be, so a deep stack lost the entire error instead of being truncated.
  const { items, dropped } = build({
    visitorId: 'v1',
    events: [{ type: 'error', message: 'boom', stack: 'at frame\n'.repeat(1200) }],
  });
  assert.strictEqual(dropped, null);
  assert.strictEqual(items.length, 1);
  assert.strictEqual(items[0].stack.length, 2048);
});

test('accepts a full batch at the field limits', () => {
  const events = Array.from({ length: 10 }, () => ({
    type: 'error',
    message: 'm'.repeat(500),
    stack: 's'.repeat(2048),
    path: 'p'.repeat(512),
  }));
  const { items, dropped } = build({ visitorId: 'v1', events });
  assert.strictEqual(dropped, null);
  assert.strictEqual(items.length, 10);
});

test('drops unparseable JSON without throwing', () => {
  const { items, dropped } = build('{not json');
  assert.strictEqual(items.length, 0);
  assert.strictEqual(dropped, 'unparseable');
});

test('truncates oversized strings rather than rejecting the row', () => {
  const { items } = build({
    visitorId: 'v1',
    events: [{ type: 'error', message: 'm'.repeat(9000), stack: 's'.repeat(3000) }],
  });
  assert.strictEqual(items[0].message.length, 500);
  assert.strictEqual(items[0].stack.length, 2048);
});

test('only puts type-specific fields on their own type', () => {
  const { items } = build({
    visitorId: 'v1',
    events: [{ type: 'pageview', target: 'https://evil.test', message: 'x', stack: 'y' }],
  });
  assert.strictEqual(items[0].target, undefined);
  assert.strictEqual(items[0].message, undefined);
  assert.strictEqual(items[0].stack, undefined);
});

test('builds the sort key so ISO order and the day prefix both work', () => {
  // by-type queries use begins_with(eventTimeId, 'YYYY-MM-DD'), and by-day
  // sorts on this key — both depend on the exact `${ISO}#${uuid}` shape.
  const { items } = build({ visitorId: 'v1', events: [{ type: 'pageview' }] });
  assert.strictEqual(items[0].eventTimeId, '2026-08-14T15:04:05.123Z#uuid-1');
  assert.strictEqual(items[0].eventDate, '2026-08-14');
  assert.ok(items[0].eventTimeId.startsWith(items[0].eventDate));
});

test('sets a ttl the configured number of days out', () => {
  const { items } = build({ visitorId: 'v1', events: [{ type: 'pageview' }] });
  assert.strictEqual(items[0].ttl, Math.floor(NOW.getTime() / 1000) + 90 * 86400);
});

test('accepts a single bare event as well as a batch', () => {
  const { items } = build({ type: 'pageview', path: '/apps', visitorId: 'v1' });
  assert.strictEqual(items.length, 1);
  assert.strictEqual(items[0].path, '/apps');
});
