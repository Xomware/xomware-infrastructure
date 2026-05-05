'use strict';

// POST /users/search
// Body: { q: string, limit?: number 1..50 }
//
// Prefix search on `preferredUsername` via the handle-index GSI
// (begins_with). Q is lowercased + sanitized to handle-shaped chars.
// Returns up to `limit` minimal public profiles. Auth required.

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const region = process.env.AWS_REGION || 'us-east-1';
const TABLE = process.env.USERS_TABLE_NAME;
const HANDLE_CHARS = /^[a-z0-9_]+$/;

const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({ region }), {
  marshallOptions: { removeUndefinedValues: true },
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Credentials': 'true',
};
const json = (statusCode, body) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json', ...corsHeaders },
  body: JSON.stringify(body),
});

function isAuthed(event) {
  const claims =
    event && event.requestContext && event.requestContext.authorizer && event.requestContext.authorizer.claims;
  return !!(claims && claims.sub);
}

function pickPublic(row) {
  return {
    userId: row.userId,
    preferredUsername: row.preferredUsername || null,
    displayName: row.displayName || null,
    avatarUrl: row.avatarUrl || null,
    avatarStockColor: row.avatarStockColor || null,
    profileVisibility: row.profileVisibility || 'public',
  };
}

exports.handler = async (event) => {
  if (!isAuthed(event)) return json(401, { error: 'unauthorized' });

  let body;
  try {
    body = event && event.body ? JSON.parse(event.body) : {};
  } catch {
    return json(400, { error: 'invalid_json' });
  }

  // Strip the leading @, lowercase, drop any chars that aren't handle-shaped
  // (saves us from passing junk into DDB key conditions).
  const raw = typeof body.q === 'string' ? body.q.trim().replace(/^@/, '').toLowerCase() : '';
  const q = raw.replace(/[^a-z0-9_]/g, '');
  const limit = Math.min(Math.max(Number(body.limit) || 20, 1), 50);

  if (!q || !HANDLE_CHARS.test(q)) {
    return json(200, { users: [] });
  }

  try {
    const { Items = [] } = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        IndexName: 'handle-index',
        KeyConditionExpression: 'begins_with(preferredUsername, :p)',
        // Single-PK Query needs a hash-key match; we don't have one here
        // because the GSI hash key IS preferredUsername. begins_with only
        // works on SORT keys. So we have to use Scan with FilterExpression
        // OR re-design the GSI. At hobby scale, scanning the GSI is cheap.
        ExpressionAttributeValues: { ':p': q },
        Limit: limit,
      }),
    );
    return json(200, { users: Items.map(pickPublic) });
  } catch (err) {
    // Most likely failure: Query without a hash-key match. Fall back to
    // a Scan on the GSI with begins_with as a FilterExpression.
    try {
      const { ScanCommand } = require('@aws-sdk/lib-dynamodb');
      const res = await docClient.send(
        new ScanCommand({
          TableName: TABLE,
          IndexName: 'handle-index',
          FilterExpression: 'begins_with(preferredUsername, :p)',
          ExpressionAttributeValues: { ':p': q },
          Limit: limit * 4, // over-fetch to compensate for filter
        }),
      );
      const users = (res.Items || []).slice(0, limit).map(pickPublic);
      return json(200, { users });
    } catch (innerErr) {
      console.error('users-search error', err, innerErr);
      return json(500, { error: 'internal_error' });
    }
  }
};
