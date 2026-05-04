'use strict';

// Pull Cognito sub from API Gateway authorizer claims.
function getUserId(event) {
  const claims =
    (event && event.requestContext && event.requestContext.authorizer && event.requestContext.authorizer.claims) ||
    null;
  if (!claims || !claims.sub) return null;
  return claims.sub;
}

function getClaims(event) {
  return (
    (event && event.requestContext && event.requestContext.authorizer && event.requestContext.authorizer.claims) ||
    {}
  );
}

module.exports = { getUserId, getClaims };
