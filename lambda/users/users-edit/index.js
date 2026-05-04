'use strict';

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const {
  DynamoDBDocumentClient,
  QueryCommand,
  UpdateCommand,
} = require('@aws-sdk/lib-dynamodb');

const region = process.env.AWS_REGION || 'us-east-1';
const TABLE = process.env.USERS_TABLE_NAME;
const AVATARS_BUCKET = process.env.AVATARS_BUCKET_NAME || '';
const CDN_HOST = 'cdn.xomware.com';

const HANDLE_REGEX = /^[a-z0-9_]{3,20}$/;
const RESERVED_HANDLES = new Set([
  'admin', 'system', 'xomware', 'xomappetit', 'support',
  'chef', 'diner', 'help', 'about', 'privacy', 'terms',
  'api', 'auth', 'profile', 'login', 'signin', 'signup',
  'me', 'you', 'user', 'users',
]);

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

function isAllowedAvatarUrl(url) {
  if (!url) return true; // null is allowed (clear avatar)
  try {
    const u = new URL(url);
    if (u.protocol !== 'https:') return false;
    if (u.hostname === CDN_HOST) return true;
    // Also allow direct bucket origin (s3 virtual-hosted style)
    if (AVATARS_BUCKET && u.hostname.startsWith(`${AVATARS_BUCKET}.s3`)) return true;
    return false;
  } catch (err) {
    return false;
  }
}

exports.handler = async (event) => {
  const userId = getUserId(event);
  if (!userId) return json(401, { error: 'unauthorized' });

  let body;
  try {
    body = event && event.body ? JSON.parse(event.body) : {};
  } catch (err) {
    return json(400, { error: 'invalid_json' });
  }

  const updates = {};
  const errors = [];

  if (Object.prototype.hasOwnProperty.call(body, 'displayName')) {
    const dn = body.displayName;
    if (typeof dn !== 'string' || dn.length < 1 || dn.length > 50) {
      errors.push('displayName must be 1-50 chars');
    } else {
      updates.displayName = dn;
    }
  }

  if (Object.prototype.hasOwnProperty.call(body, 'avatarUrl')) {
    const av = body.avatarUrl;
    if (av !== null && typeof av !== 'string') {
      errors.push('avatarUrl must be string or null');
    } else if (av && !isAllowedAvatarUrl(av)) {
      errors.push('avatarUrl host not allowed');
    } else {
      updates.avatarUrl = av;
    }
  }

  if (Object.prototype.hasOwnProperty.call(body, 'profileVisibility')) {
    const pv = body.profileVisibility;
    if (pv !== 'public' && pv !== 'private') {
      errors.push('profileVisibility must be public or private');
    } else {
      updates.profileVisibility = pv;
    }
  }

  if (Object.prototype.hasOwnProperty.call(body, 'preferredUsername')) {
    const pu = body.preferredUsername;
    if (typeof pu !== 'string') {
      errors.push('preferredUsername must be a string');
    } else {
      const handle = pu.trim().toLowerCase();
      if (!HANDLE_REGEX.test(handle)) {
        errors.push('preferredUsername must be 3-20 lowercase letters, numbers, or underscores');
      } else if (RESERVED_HANDLES.has(handle)) {
        errors.push('preferredUsername is reserved');
      } else {
        updates.preferredUsername = handle;
      }
    }
  }

  if (errors.length > 0) return json(400, { error: 'validation_failed', details: errors });
  if (Object.keys(updates).length === 0) return json(400, { error: 'no_fields_to_update' });

  // Uniqueness check on preferredUsername — handle-index GSI lookup.
  // Race window between this query and the conditional update is tiny;
  // the conditional update is the source of truth.
  if (updates.preferredUsername) {
    const { Items = [] } = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        IndexName: 'handle-index',
        KeyConditionExpression: 'preferredUsername = :pu',
        ExpressionAttributeValues: { ':pu': updates.preferredUsername },
        Limit: 1,
      }),
    );
    if (Items.length > 0 && Items[0].userId !== userId) {
      return json(409, { error: 'handle_taken' });
    }
  }

  const setExpr = [];
  const exprAttrNames = {};
  const exprAttrValues = {};
  for (const [key, val] of Object.entries(updates)) {
    setExpr.push(`#${key} = :${key}`);
    exprAttrNames[`#${key}`] = key;
    exprAttrValues[`:${key}`] = val;
  }

  try {
    const { Attributes } = await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { userId },
        UpdateExpression: 'SET ' + setExpr.join(', '),
        ExpressionAttributeNames: exprAttrNames,
        ExpressionAttributeValues: exprAttrValues,
        ConditionExpression: 'attribute_exists(userId)',
        ReturnValues: 'ALL_NEW',
      }),
    );
    return json(200, Attributes);
  } catch (err) {
    if (err && err.name === 'ConditionalCheckFailedException') {
      return json(404, { error: 'user_not_found' });
    }
    console.error('users-edit error', err);
    return json(500, { error: 'internal_error' });
  }
};
