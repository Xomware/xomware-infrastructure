'use strict';

const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { randomUUID } = require('crypto');

const region = process.env.AWS_REGION || 'us-east-1';
const BUCKET = process.env.AVATARS_BUCKET_NAME;
const CDN_BASE = process.env.AVATARS_CDN_URL || 'https://cdn.xomware.com';
const KMS_KEY_ARN = process.env.AVATARS_KMS_KEY_ARN || '';
const URL_TTL_SECONDS = 5 * 60;

const s3 = new S3Client({ region });

const allowedTypes = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/webp': 'webp',
};

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

  let body;
  try {
    body = event && event.body ? JSON.parse(event.body) : {};
  } catch (err) {
    return json(400, { error: 'invalid_json' });
  }

  const contentType = body && body.contentType;
  if (!allowedTypes[contentType]) {
    return json(400, { error: 'unsupported_content_type', allowed: Object.keys(allowedTypes) });
  }

  const ext = allowedTypes[contentType];
  const key = `avatars/${userId}/${randomUUID()}.${ext}`;

  try {
    const putParams = {
      Bucket: BUCKET,
      Key: key,
      ContentType: contentType,
      ServerSideEncryption: 'aws:kms',
    };
    if (KMS_KEY_ARN) putParams.SSEKMSKeyId = KMS_KEY_ARN;

    const command = new PutObjectCommand(putParams);
    const uploadUrl = await getSignedUrl(s3, command, { expiresIn: URL_TTL_SECONDS });
    const finalUrl = `${CDN_BASE.replace(/\/$/, '')}/${key}`;

    return json(200, { uploadUrl, finalUrl, key, contentType, expiresIn: URL_TTL_SECONDS });
  } catch (err) {
    console.error('users-presign-avatar error', err);
    return json(500, { error: 'internal_error' });
  }
};
