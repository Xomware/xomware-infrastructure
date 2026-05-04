'use strict';

// POST /admin/cost/summary
// Admin-group only. Pulls month-to-date AWS cost from Cost Explorer,
// grouped by service. Cost Explorer charges $0.01/request — cache the
// result for 1 hour in-process.
//
// Body: { startDate?: 'YYYY-MM-DD', endDate?: 'YYYY-MM-DD' }
// Defaults: 1st of current month → today (UTC).

const {
  CostExplorerClient,
  GetCostAndUsageCommand,
} = require('@aws-sdk/client-cost-explorer');

// Cost Explorer is a global service; SDK requires us-east-1 endpoint.
const ceClient = new CostExplorerClient({ region: 'us-east-1' });

const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
};
const json = (statusCode, body) => ({ statusCode, headers, body: JSON.stringify(body) });

function isAdmin(event) {
  const claim = event.requestContext?.authorizer?.claims?.['cognito:groups'] || '';
  if (typeof claim === 'string') {
    return claim.replace(/^\[|\]$/g, '').split(/,\s*/).includes('admin');
  }
  return Array.isArray(claim) && claim.includes('admin');
}

const cache = { key: null, value: null, expiresAt: 0 };

function defaultRange() {
  const now = new Date();
  const start = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}-01`;
  const end = now.toISOString().slice(0, 10);
  return { start, end };
}

exports.handler = async (event) => {
  if (!isAdmin(event)) return json(403, { error: 'admin group required' });
  try {
    const body = JSON.parse(event.body || '{}');
    const { start: defStart, end: defEnd } = defaultRange();
    const start = /^\d{4}-\d{2}-\d{2}$/.test(body.startDate) ? body.startDate : defStart;
    const end = /^\d{4}-\d{2}-\d{2}$/.test(body.endDate) ? body.endDate : defEnd;

    const cacheKey = `${start}~${end}`;
    if (cache.key === cacheKey && cache.expiresAt > Date.now()) {
      return json(200, { ...cache.value, cached: true });
    }

    const result = await ceClient.send(
      new GetCostAndUsageCommand({
        TimePeriod: { Start: start, End: end },
        Granularity: 'MONTHLY',
        Metrics: ['UnblendedCost'],
        GroupBy: [{ Type: 'DIMENSION', Key: 'SERVICE' }],
      })
    );

    const groups = (result.ResultsByTime?.[0]?.Groups || []).map((g) => ({
      service: g.Keys?.[0] || 'Unknown',
      amount: Number(g.Metrics?.UnblendedCost?.Amount || 0),
      unit: g.Metrics?.UnblendedCost?.Unit || 'USD',
    }));
    groups.sort((a, b) => b.amount - a.amount);
    const total = Number(groups.reduce((s, g) => s + g.amount, 0).toFixed(4));

    const value = { start, end, total, currency: groups[0]?.unit || 'USD', services: groups };
    cache.key = cacheKey;
    cache.value = value;
    cache.expiresAt = Date.now() + 60 * 60 * 1000;

    return json(200, { ...value, cached: false });
  } catch (err) {
    console.error('admin-cost-summary error:', err);
    return json(500, { error: err.message });
  }
};
