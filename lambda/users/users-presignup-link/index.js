'use strict';

// Cognito PreSignUp trigger.
//
// Fires before a new user is created. We only act on
// `PreSignUp_ExternalProvider` (federated sign-up via Google etc.).
// If a CONFIRMED native Cognito user already exists with the same
// email, we link the federated identity to that existing user so
// they end up as a single account with two providers — instead of
// two separate Cognito users sharing an email.
//
// Other trigger sources (PreSignUp_SignUp, PreSignUp_AdminCreateUser)
// pass through untouched.
//
// Env:
//   USER_POOL_ID_SSM_PARAM — required, SSM param name holding the pool id.
//     We read SSM (not TF env) to avoid a TF dependency cycle: the pool's
//     lambda_config references this Lambda's ARN, so the Lambda can't
//     reference the pool's id back through env without cycling.

const {
  CognitoIdentityProviderClient,
  ListUsersCommand,
  AdminLinkProviderForUserCommand,
} = require('@aws-sdk/client-cognito-identity-provider');
const { SSMClient, GetParameterCommand } = require('@aws-sdk/client-ssm');

const region = process.env.AWS_REGION || 'us-east-1';
const POOL_ID_SSM_PARAM = process.env.USER_POOL_ID_SSM_PARAM;

const cognito = new CognitoIdentityProviderClient({ region });
const ssm = new SSMClient({ region });

let cachedPoolId = null;

async function getUserPoolId() {
  if (cachedPoolId) return cachedPoolId;
  if (!POOL_ID_SSM_PARAM) {
    throw new Error('USER_POOL_ID_SSM_PARAM env var is not set');
  }
  const res = await ssm.send(
    new GetParameterCommand({ Name: POOL_ID_SSM_PARAM, WithDecryption: false }),
  );
  cachedPoolId = res.Parameter && res.Parameter.Value;
  if (!cachedPoolId) throw new Error(`SSM param ${POOL_ID_SSM_PARAM} has no value`);
  return cachedPoolId;
}

exports.handler = async (event) => {
  const triggerSource = event && event.triggerSource;

  // Only handle external-provider sign-ups. Native sign-ups don't
  // need linking (PostConfirmation handles the DDB row).
  if (triggerSource !== 'PreSignUp_ExternalProvider') {
    return event;
  }

  try {
    const userPoolId = await getUserPoolId();

    const attrs = (event.request && event.request.userAttributes) || {};
    const email = attrs.email;
    if (!email) {
      console.warn('users-presignup-link: federated user has no email; skipping');
      return event;
    }

    // event.userName for ExternalProvider looks like `Google_<sub>`.
    // Split into provider name + provider attribute value (the Google sub).
    const incomingUserName = event.userName || '';
    const sepIdx = incomingUserName.indexOf('_');
    if (sepIdx <= 0) {
      console.warn(
        'users-presignup-link: unexpected userName shape, skipping',
        incomingUserName,
      );
      return event;
    }
    const providerName = incomingUserName.substring(0, sepIdx); // "Google"
    const providerUserId = incomingUserName.substring(sepIdx + 1); // Google sub

    // Look up any existing user(s) with this email.
    const list = await cognito.send(
      new ListUsersCommand({
        UserPoolId: userPoolId,
        Filter: `email = "${email}"`,
        Limit: 5,
      }),
    );

    const candidates = list.Users || [];

    // Find a native (non-federated) CONFIRMED user. Federated users have
    // a userName prefixed with the provider name (e.g. "Google_..."); skip
    // those — they're already federated identities, not the native account
    // we want to link to.
    const native = candidates.find((u) => {
      if (u.UserStatus !== 'CONFIRMED') return false;
      const uname = u.Username || '';
      return !uname.startsWith('Google_') && !uname.startsWith('Facebook_');
    });

    if (!native) {
      // No native user to link to. Let signup proceed as a brand-new
      // federated account; PostConfirmation will create the DDB row.
      console.log('users-presignup-link: no native user for', email, '— passing through');
      return event;
    }

    await cognito.send(
      new AdminLinkProviderForUserCommand({
        UserPoolId: userPoolId,
        DestinationUser: {
          ProviderName: 'Cognito',
          ProviderAttributeValue: native.Username,
        },
        SourceUser: {
          ProviderName: providerName,
          ProviderAttributeName: 'Cognito_Subject',
          ProviderAttributeValue: providerUserId,
        },
      }),
    );

    console.log(
      'users-presignup-link: linked',
      providerName,
      'identity to native user',
      native.Username,
      'for',
      email,
    );
  } catch (err) {
    // Never throw — throwing fails the sign-up entirely. Log and let the
    // user proceed; worst case they end up with two accounts and we can
    // reconcile manually.
    console.error('users-presignup-link: error', err);
  }

  return event;
};
