'use strict';

// Cognito PostAuthentication trigger — writes a `signin` event to
// xomware-events.
//
// Failures are swallowed. PostAuthentication blocks the user's sign-in
// if the trigger throws, and audit logging is non-critical metadata.

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');
const { randomUUID } = require('crypto');

const region = process.env.AWS_REGION || 'us-east-1';
const TABLE = process.env.EVENTS_TABLE_NAME;
const RETENTION_DAYS = Number(process.env.EVENTS_RETENTION_DAYS || 90);

const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({ region }), {
  marshallOptions: { removeUndefinedValues: true },
});

exports.handler = async (event) => {
  try {
    const triggerSource = event && event.triggerSource;
    if (
      triggerSource !== 'PostAuthentication_Authentication' &&
      triggerSource !== 'PostAuthentication_AuthenticationWithFederation'
    ) {
      return event;
    }

    const attrs = (event.request && event.request.userAttributes) || {};
    const userId = attrs.sub;
    if (!userId || !TABLE) return event;

    const now = new Date();
    const eventId = randomUUID();
    const eventTime = now.toISOString();
    const eventDate = eventTime.slice(0, 10);
    const ttl = Math.floor(now.getTime() / 1000) + RETENTION_DAYS * 86400;

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          eventId,
          eventType: 'signin',
          eventTime,
          eventDate,
          eventTimeId: `${eventTime}#${eventId}`,
          userId,
          email: attrs.email || null,
          identityProvider: triggerSource === 'PostAuthentication_AuthenticationWithFederation'
            ? 'federated'
            : 'cognito',
          appClientId: event.callerContext && event.callerContext.clientId,
          ttl,
        },
      })
    );
  } catch (err) {
    console.error('auth-track: failed to write signin event', err && err.name, err && err.message);
  }
  return event;
};
