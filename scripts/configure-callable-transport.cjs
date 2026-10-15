const path = require('node:path');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  if (!process.argv.includes('--project=trustkeyper')) throw new Error('Explicit production project is required.');
  const apply = process.argv.includes('--apply');
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business deployment account is not signed in.');
  const token = await auth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform']);
  async function request(url, body, method = body ? 'POST' : 'GET') {
    const response = await fetch(url, { method,
      headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(20000) });
    const result = await response.json();
    if (!response.ok) throw new Error(`Callable transport configuration failed: ${response.status} ${result.error?.status}: ${result.error?.message}`);
    return result;
  }
  const allowed = ['requestAgreementReview', 'recordAgreementReview', 'createDocumentRequest', 'readDocumentRequest',
    'recordDocumentRequest', 'beginDocumentUpload', 'completeDocumentUpload', 'beginRepairReport', 'submitRepairReport', 'readRepairPhoto',
    'prepareAgreementApproval', 'readAgreementApproval', 'replyToAgreementApproval',
    'beginAgreementCopyUpload', 'completeAgreementCopyUpload', 'readAgreementCopy',
    'quoteRentPayment', 'beginRentPayment', 'confirmRentPayment', 'reconcileRentPayment', 'razorpayTestWebhook',
    'readRepair', 'createInspectionRepair', 'recordRepairQuote', 'approveRepairQuote', 'scheduleRepairVisit', 'beginRepairCompletion',
    'completeRepair', 'confirmRepairOutcome', 'readRepairEvidence', 'readAccountRoles', 'selectAccountRole', 'addAccountRole',
    'listPropertyInspections', 'beginPropertyInspection', 'submitPropertyInspection', 'readPropertyInspectionPhoto', 'reviewPropertyInspection',
    'readTenancy', 'recordTenancyAction', 'issueKeyConfirmationCode', 'createAgreementRenewal',
    'readMoveOut', 'recordMoveOutAction', 'issueKeyReturnCode',
    'readManagerCallback', 'listManagerCallbacks', 'recordManagerCallback',
    'requestEmailOtp', 'verifyEmailOtp', 'requestProfileEmailOtp', 'verifyProfileEmailOtp',
    'requestAccountEmailOtp', 'verifyAccountEmailOtp',
    'readTenantSetup', 'recordTenantSetup', 'listTenantSetupRequests', 'resolveTenantSetupRequest',
    'readAccountProfile', 'saveAccountProfile', 'readAccountClosure', 'closeAccount',
    'listAccountClosures', 'restoreClosedAccount', 'finishAccountClosure'];
  const selected = process.argv.find(argument => argument.startsWith('--functions='))?.slice(12).split(',') ?? allowed;
  if (selected.length === 0 || selected.some(name => !allowed.includes(name)) || new Set(selected).size !== selected.length) {
    throw new Error('Callable transport targets must be unique known function names.');
  }
  for (const name of selected) {
    const metadata = await request(`https://cloudfunctions.googleapis.com/v2/projects/trustkeyper/locations/asia-south1/functions/${name}`);
    const service = metadata.serviceConfig?.service;
    if (metadata.state !== 'ACTIVE' || service !== `projects/trustkeyper/locations/asia-south1/services/${name.toLowerCase()}`) {
      throw new Error('The active callable service did not match the expected function.');
    }
    const url = `https://run.googleapis.com/v2/${service}`;
    const current = await request(url);
    const changed = current.invokerIamDisabled !== true;
    if (apply && changed) {
      let operation = await request(`${url}?updateMask=invokerIamDisabled,template.revision`, {
        name: service, etag: current.etag, invokerIamDisabled: true, template: { revision: '' },
      }, 'PATCH');
      for (let attempt = 0; !operation.done && attempt < 60; attempt++) {
        await new Promise(resolve => setTimeout(resolve, 2000));
        operation = await request(`https://run.googleapis.com/v2/${operation.name}`);
      }
      if (!operation.done || operation.error) throw new Error(`Callable configuration did not complete: ${operation.error?.message ?? 'timeout'}`);
    }
    process.stdout.write(`${JSON.stringify({ name, state: changed ? (apply ? 'callable transport enabled' : 'would enable callable transport') : 'already configured' })}\n`);
  }
}
main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
