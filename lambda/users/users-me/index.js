'use strict';

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
} = require('@aws-sdk/lib-dynamodb');

const region = process.env.AWS_REGION || 'us-east-1';
const TABLE = process.env.USERS_TABLE_NAME;

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

function getClaims(event) {
  return (event && event.requestContext && event.requestContext.authorizer && event.requestContext.authorizer.claims) || null;
}

// Build a fresh user row from JWT claims. Used to JIT-provision federated
// users whose Cognito flow skips PostConfirmation (Google sign-up never
// fires it). Native users get their row from the users-create
// PostConfirmation trigger and never hit this path.
function rowFromClaims(claims) {
  const now = new Date().toISOString();
  const fullName = claims.name || [claims.given_name, claims.family_name].filter(Boolean).join(' ') || null;
  return {
    userId: claims.sub,
    email: claims.email || null,
    preferredUsername: null,
    displayName: fullName,
    avatarUrl: claims.picture || null,
    profileVisibility: 'public',
    createdAt: now,
    lastSeenAt: now,
  };
}

exports.handler = async (event) => {
  const claims = getClaims(event);
  const userId = claims && claims.sub;
  if (!userId) return json(401, { error: 'unauthorized' });

  try {
    const { Item } = await docClient.send(
      new GetCommand({ TableName: TABLE, Key: { userId } }),
    );

    if (Item) {
      // Fire-and-forget lastSeenAt update — don't block the response.
      const now = new Date().toISOString();
      docClient
        .send(
          new UpdateCommand({
            TableName: TABLE,
            Key: { userId },
            UpdateExpression: 'SET lastSeenAt = :now',
            ExpressionAttributeValues: { ':now': now },
          }),
        )
        .catch((err) => console.error('users-me: lastSeenAt update failed', err));
      return json(200, Item);
    }

    // JIT-provision: federated users (Google) bypass PostConfirmation, so
    // first /users/me hit creates their row from the JWT claims.
    const row = rowFromClaims(claims);
    try {
      await docClient.send(
        new PutCommand({
          TableName: TABLE,
          Item: row,
          ConditionExpression: 'attribute_not_exists(userId)',
        }),
      );
      console.log('users-me: JIT-created row for', userId);
    } catch (putErr) {
      // Race: row created between Get and Put. Re-read.
      if (putErr && putErr.name === 'ConditionalCheckFailedException') {
        const reread = await docClient.send(
          new GetCommand({ TableName: TABLE, Key: { userId } }),
        );
        return json(200, reread.Item || row);
      }
      throw putErr;
    }
    return json(200, row);
  } catch (err) {
    console.error('users-me error', err);
    return json(500, { error: 'internal_error' });
  }
};
