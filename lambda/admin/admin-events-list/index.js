'use strict';

// GET-style POST /admin/events/list
// Admin-group only. Queries the by-day GSI on xomware-events.
//
// Body:
//   { date?: 'YYYY-MM-DD' (default: today UTC),
//     eventType?: 'signin'|'signup'|'pageview'|'outbound'|'error'
//                  (omit for every type that day),
//     limit?: number (default 50, max 200),
//     cursor?: string  (opaque pagination token from a prior response) }

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const region = process.env.AWS_REGION || 'us-east-1';
const TABLE = process.env.EVENTS_TABLE_NAME;
const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({ region }), {
  marshallOptions: { removeUndefinedValues: true },
});

const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
};
const json = (statusCode, body) => ({ statusCode, headers, body: JSON.stringify(body) });

// signin/signup are written by the Cognito trigger; the rest by events-track.
const ALLOWED_TYPES = new Set(['signin', 'signup', 'pageview', 'outbound', 'error']);

function isAdmin(event) {
  const claim = event.requestContext?.authorizer?.claims?.['cognito:groups'] || '';
  if (typeof claim === 'string') {
    return claim.replace(/^\[|\]$/g, '').split(/,\s*/).includes('admin');
  }
  return Array.isArray(claim) && claim.includes('admin');
}

exports.handler = async (event) => {
  if (!isAdmin(event)) return json(403, { error: 'admin group required' });
  try {
    const body = JSON.parse(event.body || '{}');
    const date = typeof body.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(body.date)
      ? body.date
      : new Date().toISOString().slice(0, 10);
    const limit = Math.min(Math.max(Number(body.limit) || 50, 1), 200);
    const cursor = typeof body.cursor === 'string' && body.cursor
      ? JSON.parse(Buffer.from(body.cursor, 'base64').toString('utf8'))
      : undefined;
    const eventType = ALLOWED_TYPES.has(body.eventType) ? body.eventType : undefined;

    // Unfiltered reads walk the day. Filtered reads use the by-type index
    // instead of a FilterExpression: eventTimeId is `${ISO-8601}#${uuid}` and
    // ISO timestamps sort lexicographically, so begins_with on a YYYY-MM-DD
    // prefix is an exact single-day range on that index. That distinction
    // stops mattering academically and starts mattering practically the
    // moment pageviews outnumber signins — a FilterExpression would read
    // (and bill for) the whole day to return a handful of rows.
    const query = eventType
      ? {
          IndexName: 'by-type',
          KeyConditionExpression: 'eventType = :t AND begins_with(eventTimeId, :d)',
          ExpressionAttributeValues: { ':t': eventType, ':d': date },
        }
      : {
          IndexName: 'by-day',
          KeyConditionExpression: 'eventDate = :d',
          ExpressionAttributeValues: { ':d': date },
        };

    const { Items = [], LastEvaluatedKey } = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        ...query,
        ScanIndexForward: false,
        Limit: limit,
        ExclusiveStartKey: cursor,
      })
    );

    const nextCursor = LastEvaluatedKey
      ? Buffer.from(JSON.stringify(LastEvaluatedKey)).toString('base64')
      : null;

    return json(200, { date, eventType: eventType || null, items: Items, nextCursor });
  } catch (err) {
    console.error('admin-events-list error:', err);
    return json(500, { error: err.message });
  }
};
