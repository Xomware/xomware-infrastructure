'use strict';

// POST /events/track       — public, unauthenticated (anonymous visitors)
// POST /events/track-user  — Cognito-authorized (signed-in visitors)
//
// Both routes point at this handler. The split exists so identity can be
// trusted without doing crypto here: on the authorized route API Gateway has
// already verified the JWT and populated requestContext.authorizer.claims, so
// `sub` is trustworthy. On the public route there are no claims and every row
// is written as `anon:<visitorId>`. A client-supplied userId is never honoured
// on either route.
//
// Writes pageview / outbound / error rows to xomware-events, the same table
// the Cognito PostAuthentication trigger writes signin rows to. `signin` and
// `signup` are deliberately NOT accepted here: those are authoritative and
// must not be forgeable from a browser.
//
// Validation and shaping live in validate.js so they can be tested without
// the SDK — see validate.test.js. This file is transport only.
//
// This endpoint is public and writes to a PAY_PER_REQUEST table, so the limits
// in validate.js are load-bearing. The regional WAF rate limit
// (waf_associations.tf) is the outer bound.

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, BatchWriteCommand } = require('@aws-sdk/lib-dynamodb');
const { randomUUID } = require('crypto');
const { buildItems } = require('./validate');

const region = process.env.AWS_REGION || 'us-east-1';
const TABLE = process.env.EVENTS_TABLE_NAME;
const RETENTION_DAYS = Number(process.env.EVENTS_RETENTION_DAYS || 90);
const ALLOW_ORIGINS = (process.env.ALLOW_ORIGINS || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({ region }), {
  marshallOptions: { removeUndefinedValues: true },
});

function corsHeaders(event) {
  const origin = event?.headers?.origin || event?.headers?.Origin;
  const allowed = origin && ALLOW_ORIGINS.includes(origin);
  return {
    'Content-Type': 'application/json',
    // Echo only a known origin. Unlike the admin endpoints this route is
    // unauthenticated, so a wildcard would let any page on the internet post
    // into the table from a real user's browser.
    ...(allowed ? { 'Access-Control-Allow-Origin': origin } : {}),
    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
    'Access-Control-Allow-Methods': 'POST,OPTIONS',
  };
}

exports.handler = async (event) => {
  // A tracking endpoint must never surface a failure to the page. Every path
  // below returns 204; problems are logged and swallowed.
  const ok = { statusCode: 204, headers: corsHeaders(event), body: '' };

  try {
    if (!TABLE) return ok;

    const { items, dropped } = buildItems({
      rawBody: event.body,
      claims: event?.requestContext?.authorizer?.claims,
      headers: event?.headers || {},
      now: new Date(),
      retentionDays: RETENTION_DAYS,
      uuid: randomUUID,
    });

    if (dropped) console.warn(`events-track: dropped request (${dropped})`);
    if (items.length === 0) return ok;

    // BatchWrite caps at 25; MAX_EVENTS is 10, so this is always one request.
    await docClient.send(
      new BatchWriteCommand({
        RequestItems: { [TABLE]: items.map((Item) => ({ PutRequest: { Item } })) },
      })
    );
  } catch (err) {
    console.error('events-track: failed to write events', err && err.name, err && err.message);
  }

  return ok;
};
