'use strict';

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const region = process.env.AWS_REGION || 'us-east-1';
const TABLE = process.env.USERS_TABLE_NAME;
const HANDLE_INDEX = 'handle-index';

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

exports.handler = async (event) => {
  let body;
  try {
    body = event && event.body ? JSON.parse(event.body) : {};
  } catch (err) {
    return json(400, { error: 'invalid_json' });
  }

  const handle = body && typeof body.handle === 'string' ? body.handle.trim() : '';
  if (!handle) return json(400, { error: 'handle_required' });

  try {
    const { Items } = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        IndexName: HANDLE_INDEX,
        KeyConditionExpression: 'preferredUsername = :h',
        ExpressionAttributeValues: { ':h': handle },
        Limit: 1,
      }),
    );

    if (!Items || Items.length === 0) return json(404, { error: 'user_not_found' });

    const row = Items[0];
    return json(200, {
      userId: row.userId,
      preferredUsername: row.preferredUsername,
      displayName: row.displayName,
      avatarUrl: row.avatarUrl,
      profileVisibility: row.profileVisibility,
    });
  } catch (err) {
    console.error('users-get-by-handle error', err);
    return json(500, { error: 'internal_error' });
  }
};
