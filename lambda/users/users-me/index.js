'use strict';

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');

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

function getUserId(event) {
  const claims =
    event && event.requestContext && event.requestContext.authorizer && event.requestContext.authorizer.claims;
  return claims && claims.sub ? claims.sub : null;
}

exports.handler = async (event) => {
  const userId = getUserId(event);
  if (!userId) return json(401, { error: 'unauthorized' });

  try {
    const { Item } = await docClient.send(
      new GetCommand({ TableName: TABLE, Key: { userId } }),
    );
    if (!Item) return json(404, { error: 'user_not_found' });

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
  } catch (err) {
    console.error('users-me error', err);
    return json(500, { error: 'internal_error' });
  }
};
