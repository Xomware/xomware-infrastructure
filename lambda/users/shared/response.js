'use strict';

// API Gateway REST API v1 response helper.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Credentials': 'true',
};

function ok(body) {
  return {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
    body: JSON.stringify(body),
  };
}

function notFound(message) {
  return {
    statusCode: 404,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
    body: JSON.stringify({ error: message || 'not_found' }),
  };
}

function badRequest(message) {
  return {
    statusCode: 400,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
    body: JSON.stringify({ error: message || 'bad_request' }),
  };
}

function unauthorized(message) {
  return {
    statusCode: 401,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
    body: JSON.stringify({ error: message || 'unauthorized' }),
  };
}

function serverError(message) {
  return {
    statusCode: 500,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
    body: JSON.stringify({ error: message || 'internal_error' }),
  };
}

module.exports = { ok, notFound, badRequest, unauthorized, serverError };
