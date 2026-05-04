'use strict';

// Cognito PostConfirmation trigger.
// On email-verified signup, write a user row to xomware-users.
// Idempotent via attribute_not_exists(userId) condition.

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');

const region = process.env.AWS_REGION || 'us-east-1';
const TABLE = process.env.USERS_TABLE_NAME;

const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({ region }), {
  marshallOptions: { removeUndefinedValues: true },
});

exports.handler = async (event) => {
  // Always return event back to Cognito, even on failure — failing this trigger
  // blocks the user from signing up. Log and continue; users-me will 404 and
  // the frontend can retry / handle the missing-row case.
  try {
    const triggerSource = event && event.triggerSource;
    if (
      triggerSource !== 'PostConfirmation_ConfirmSignUp' &&
      triggerSource !== 'PostConfirmation_ConfirmForgotPassword'
    ) {
      // Ignore other trigger sources (e.g. password reset). Just pass through.
      return event;
    }

    const attrs = (event.request && event.request.userAttributes) || {};
    const userId = attrs.sub;
    const email = attrs.email;
    const preferredUsername = attrs.preferred_username || attrs['cognito:username'];

    if (!userId) {
      console.error('users-create: no sub in userAttributes', attrs);
      return event;
    }

    const now = new Date().toISOString();
    const row = {
      userId,
      email: email || null,
      preferredUsername: preferredUsername || null,
      displayName: preferredUsername || null,
      avatarUrl: null,
      profileVisibility: 'public',
      createdAt: now,
      lastSeenAt: now,
    };

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: row,
        ConditionExpression: 'attribute_not_exists(userId)',
      }),
    );
    console.log('users-create: created row for', userId);
  } catch (err) {
    if (err && err.name === 'ConditionalCheckFailedException') {
      console.log('users-create: row already exists, skipping');
    } else {
      console.error('users-create: error writing row', err);
    }
  }

  return event;
};
