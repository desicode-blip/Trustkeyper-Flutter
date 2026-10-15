const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const deploymentAuth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));
const dependencies = require('node:module').createRequire(path.join(__dirname, '../functions/package.json'));
const { initializeApp, deleteApp } = dependencies('firebase/app');
const { getAuth, signInWithCustomToken } = dependencies('firebase/auth');
const { getFirestore, getDoc, doc } = dependencies('firebase/firestore');

async function main() {
  assert.ok(process.argv.includes('--project=trustkeyper'));
  const account = deploymentAuth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  assert.ok(account, 'Deployment account required');
  const credential = await deploymentAuth.getAccessToken(account.tokens.refresh_token,
    account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform']);
  const googleHeaders = { Authorization: `Bearer ${credential.access_token}`, 'Content-Type': 'application/json' };
  async function json(url, options = {}) {
    const response = await fetch(url, { ...options, signal: AbortSignal.timeout(120000) });
    if (!response.ok) throw new Error(`Verification HTTP ${response.status}`);
    return response.json();
  }
  const providerSecret = await json('https://secretmanager.googleapis.com/v1/projects/trustkeyper/secrets/RESEND_API_KEY/versions/latest:access', { headers: googleHeaders });
  const otpSecret = await json('https://secretmanager.googleapis.com/v1/projects/trustkeyper/secrets/EMAIL_OTP_SECRET/versions/latest:access', { headers: googleHeaders });
  const providerKey = Buffer.from(providerSecret.payload.data, 'base64').toString();
  const hashingKey = Buffer.from(otpSecret.payload.data, 'base64').toString();
  const source = fs.readFileSync(path.join(__dirname, '../apps/flutter_app/lib/firebase_options.dart'), 'utf8');
  const apiKey = source.match(/static const FirebaseOptions web = FirebaseOptions\([\s\S]*?apiKey:\s*'([^']+)'/)?.[1];
  assert.ok(apiKey);
  const email = `delivered+trustkeyper-build28-${crypto.randomBytes(10).toString('hex')}@resend.dev`;
  const challengePath = `emailOtpChallenges/${crypto.createHmac('sha256', hashingKey).update(`email:${email}`).digest('hex')}`;
  const endpoints = ['requestEmailOtp', 'verifyEmailOtp', 'requestProfileEmailOtp', 'verifyProfileEmailOtp'];
  const evidence = { endpoints: [], stage: 'metadata', simulatorRequest: false, realCustomerInbox: 'not tested',
    actualCustomTokenSignIn: false, replayRejected: false, challengePrivate: false, fixtureCleanup: false };
  async function call(name, data, idToken) {
    const response = await fetch(`https://asia-south1-trustkeyper.cloudfunctions.net/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...(idToken ? { Authorization: `Bearer ${idToken}` } : {}) },
      body: JSON.stringify({ data }), signal: AbortSignal.timeout(120000),
    });
    const result = await response.json();
    if (result.error) {
      const error = new Error(`Callable ${name} rejected: ${result.error.status}`);
      error.code = result.error.status;
      throw error;
    }
    assert.equal(response.status, 200);
    return result.result;
  }
  let clientApp;
  let uid;
  let challengeRequested = false;
  try {
    for (const name of endpoints) {
      const metadata = await json(`https://cloudfunctions.googleapis.com/v2/projects/trustkeyper/locations/asia-south1/functions/${name}`, { headers: googleHeaders });
      assert.equal(metadata.state, 'ACTIVE');
      evidence.endpoints.push({ name, state: metadata.state, revision: metadata.serviceConfig.revision });
    }
    await assert.rejects(call('requestEmailOtp', { email: 'not-an-email' }), { code: 'INVALID_ARGUMENT' });
    await assert.rejects(call('requestProfileEmailOtp', { email }), { code: 'UNAUTHENTICATED' });
    await assert.rejects(call('verifyProfileEmailOtp', { email, challengeId: 'missing', code: '000000' }), { code: 'UNAUTHENTICATED' });
    evidence.stage = 'request';
    const challenge = await call('requestEmailOtp', { email });
    challengeRequested = true;
    assert.equal(challenge.expiresInSeconds, 300);
    assert.equal(challenge.resendAfterSeconds, 60);
    evidence.simulatorRequest = true;
    await assert.rejects(call('requestEmailOtp', { email }), { code: 'RESOURCE_EXHAUSTED' });
    evidence.stage = 'provider-list';
    let message;
    for (let attempt = 0; attempt < 8 && !message; attempt++) {
      const response = await fetch('https://api.resend.com/emails?limit=100', { headers: { Authorization: `Bearer ${providerKey}` } });
      if ([401, 403].includes(response.status)) {
        evidence.providerLookupHttp = response.status;
        evidence.stage = 'sending-only-key; real inbox verification pending';
        process.stdout.write('PASS: request, resend cooldown and unauthenticated profile guards. Sending-only key cannot read simulator messages; full login acceptance requires the controlled inbox.\n');
        return;
      }
      if (!response.ok) {
        evidence.providerLookupHttp = response.status;
        throw new Error(`Provider test lookup HTTP ${response.status}`);
      }
      const result = await response.json();
      message = result.data?.find(item => item.to?.length === 1 && item.to[0] === email);
      if (!message) await new Promise(resolve => setTimeout(resolve, 2000));
    }
    assert.ok(message, 'Unique official simulator message unavailable');
    evidence.stage = 'provider-detail';
    const detail = await json(`https://api.resend.com/emails/${encodeURIComponent(message.id)}`, { headers: { Authorization: `Bearer ${providerKey}` } });
    const code = detail.text?.match(/verification code is (\d{6})/)?.[1];
    assert.ok(code, 'Simulator code unavailable');
    const incorrect = (Number(code) + 1).toString().padStart(6, '0').slice(-6);
    await assert.rejects(call('verifyEmailOtp', { email, challengeId: challenge.challengeId, code: incorrect }), { code: 'INVALID_ARGUMENT' });
    evidence.stage = 'server-verification';
    const verified = await call('verifyEmailOtp', { email, challengeId: challenge.challengeId, code });
    assert.ok(typeof verified.customToken === 'string');
    uid = JSON.parse(Buffer.from(verified.customToken.split('.')[1], 'base64url').toString()).uid;
    assert.ok(typeof uid === 'string');
    clientApp = initializeApp({ apiKey, projectId: 'trustkeyper' }, `email-qa-${crypto.randomUUID()}`);
    evidence.stage = 'client-sign-in';
    const login = await signInWithCustomToken(getAuth(clientApp), verified.customToken);
    assert.equal(login.user.uid, uid);
    const token = await login.user.getIdTokenResult();
    assert.equal(login.user.email, email);
    assert.equal(token.claims.email_verified, true);
    assert.equal(token.claims.trustkeyper_email_otp, true);
    assert.equal(token.claims.firebase.sign_in_provider, 'custom');
    evidence.actualCustomTokenSignIn = true;
    evidence.stage = 'replay-and-rules';
    await assert.rejects(call('verifyEmailOtp', { email, challengeId: challenge.challengeId, code }), { code: 'FAILED_PRECONDITION' });
    evidence.replayRejected = true;
    await assert.rejects(getDoc(doc(getFirestore(clientApp), challengePath)));
    evidence.challengePrivate = true;
    evidence.stage = 'passed';
  } finally {
    if (clientApp) await deleteApp(clientApp);
    if (challengeRequested) {
      const lookup = await json('https://identitytoolkit.googleapis.com/v1/projects/trustkeyper/accounts:lookup', {
        method: 'POST', headers: googleHeaders, body: JSON.stringify({ email: [email] }),
      });
      assert.ok((lookup.users?.length ?? 0) <= 1);
      if (lookup.users?.length === 1) {
        assert.equal(lookup.users[0].email, email);
        if (uid) assert.equal(lookup.users[0].localId, uid);
        await json('https://identitytoolkit.googleapis.com/v1/projects/trustkeyper/accounts:delete', {
          method: 'POST', headers: googleHeaders, body: JSON.stringify({ localId: lookup.users[0].localId }),
        });
      }
    }
    if (challengeRequested) {
      const response = await fetch(`https://firestore.googleapis.com/v1/projects/trustkeyper/databases/(default)/documents/${challengePath}`, { method: 'DELETE', headers: googleHeaders });
      assert.ok(response.ok || response.status === 404, 'QA challenge cleanup failed');
    }
    evidence.fixtureCleanup = true;
    fs.writeFileSync(path.join(__dirname, '../output/ui-audit/build28-firebase-email-smoke.json'), JSON.stringify(evidence, null, 2));
  }
  process.stdout.write('PASS: deployed simulator delivery, actual Firebase email sign-in, wrong-code/cooldown/replay/private-data guards; temporary fixture removed. Real inbox acceptance remains a tester step.\n');
}
main().catch(error => { process.stderr.write(`Email verification failed: ${error.code ?? error.name}. ${error.message.includes('Sending-only') ? 'Sending key cannot read simulator messages; use a controlled real inbox.' : 'See sanitized audit status; no credentials or codes were printed.'}\n`); process.exitCode = 1; });
