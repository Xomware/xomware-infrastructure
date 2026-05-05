'use strict';

// POST /users/batch-get
// Body: { userIds: string[] }    1..100 IDs
//
// Returns the public-facing slice for each user that exists. Used by
// consumer apps (xomappetit etc.) to enrich feed items with the
// author's display name + avatar in a single round trip instead of
// N+1 GetItem fetches.
//
// `profileVisibility` is included for the caller to decide how to
// link/render the user; the returned fields themselves are minimal
// and never include `email` or any private profile data.

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, BatchGetCommand } = require('@aws-sdk/lib-dynamodb');

const region = process.env.AWS_REGION || 'us-east-1';
const TABLE = process.env.USERS_TABLE_NAME;
const MAX_IDS = 100;

const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({ region }), {
  marshallOptions: { removeUndefinedValues: true },
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Credentials': 'true',
};

function json(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
    body: JSON.stringify(body),
  };
}

function isAuthed(event) {
  const claims =
    event && event.requestContext && event.requestContext.authorizer && event.requestContext.authorizer.claims;
  return !!(claims && claims.sub);
}

function pickPublic(row) {
  if (!row) return null;
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

  const ids = Array.isArray(body.userIds) ? body.userIds : null;
  if (!ids) return json(400, { error: 'userIds (string[]) is required' });

  // De-dupe + drop empties + cap.
  const unique = [...new Set(ids.filter((s) => typeof s === 'string' && s))];
  if (unique.length === 0) return json(200, { users: [] });
  if (unique.length > MAX_IDS) {
    return json(400, { error: `too many ids (max ${MAX_IDS})` });
  }

  try {
    const { Responses = {} } = await docClient.send(
      new BatchGetCommand({
        RequestItems: {
          [TABLE]: {
            Keys: unique.map((userId) => ({ userId })),
            // Only the fields the public slice needs. Saves DDB capacity
            // + KMS decrypts on attributes the caller never sees.
            ProjectionExpression:
              'userId, preferredUsername, displayName, avatarUrl, avatarStockColor, profileVisibility',
          },
        },
      }),
    );
    const rows = Responses[TABLE] || [];
    const users = rows.map(pickPublic).filter(Boolean);
    return json(200, { users });
  } catch (err) {
    console.error('users-batch-get error', err);
    return json(500, { error: 'internal_error' });
  }
};
