'use strict';

// Cognito PostConfirmation trigger.
// On email-verified signup, write a user row to xomware-users AND a
// signup event row to xomware-events for the /admin portal audit log.
// Both writes are best-effort — failures don't block the user.

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');
const { randomUUID } = require('crypto');

const region = process.env.AWS_REGION || 'us-east-1';
const TABLE = process.env.USERS_TABLE_NAME;
const EVENTS_TABLE = process.env.EVENTS_TABLE_NAME;
const RETENTION_DAYS = Number(process.env.EVENTS_RETENTION_DAYS || 90);

const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({ region }), {
  marshallOptions: { removeUndefinedValues: true },
});

async function writeSignupEvent({ userId, email, identityProvider, clientId }) {
  if (!EVENTS_TABLE) return;
  const now = new Date();
  const eventId = randomUUID();
  const eventTime = now.toISOString();
  const eventDate = eventTime.slice(0, 10);
  const ttl = Math.floor(now.getTime() / 1000) + RETENTION_DAYS * 86400;
  try {
    await docClient.send(
      new PutCommand({
        TableName: EVENTS_TABLE,
        Item: {
          eventId,
          eventType: 'signup',
          eventTime,
          eventDate,
          eventTimeId: `${eventTime}#${eventId}`,
          userId,
          email: email || null,
          identityProvider: identityProvider || 'cognito',
          appClientId: clientId,
          ttl,
        },
      }),
    );
  } catch (err) {
    console.error('users-create: failed to write signup event', err && err.name, err && err.message);
  }
}

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
    const meta = (event.request && event.request.clientMetadata) || {};
    const userId = attrs.sub;
    const email = attrs.email;
    // preferred_username is an alias attribute, so the frontend cannot pass it
    // as a userAttribute during SignUp (Cognito only sets aliases on confirmed
    // accounts). It comes through here via clientMetadata. Fall back to the
    // userAttribute for any flow that does set it (e.g. federated sign-up,
    // pick-handle-after-confirm).
    const preferredUsername =
      meta.preferred_username || attrs.preferred_username || null;

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

    let createdNew = false;
    try {
      await docClient.send(
        new PutCommand({
          TableName: TABLE,
          Item: row,
          ConditionExpression: 'attribute_not_exists(userId)',
        }),
      );
      createdNew = true;
      console.log('users-create: created row for', userId);
    } catch (err) {
      if (err && err.name === 'ConditionalCheckFailedException') {
        console.log('users-create: row already exists, skipping');
      } else {
        console.error('users-create: error writing row', err);
      }
    }

    // Only emit the signup event when the row didn't already exist —
    // PostConfirmation also fires for password-reset confirmations
    // (handled above) and on idempotent retries.
    if (createdNew) {
      await writeSignupEvent({
        userId,
        email,
        identityProvider: 'cognito',
        clientId: event.callerContext && event.callerContext.clientId,
      });
    }
  } catch (err) {
    console.error('users-create: outer error', err);
  }

  return event;
};
