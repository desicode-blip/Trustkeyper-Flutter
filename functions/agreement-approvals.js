import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { verifiedPhone } from './verified-phone.js';
import { reviewSnapshot } from './agreement-review.js';

export class ApprovalError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

const hash = value => createHash('sha256').update(value).digest('hex');
const safe = value => typeof value === 'string' && /^[\w-]{1,128}$/.test(value);
const lifetime = 7 * 86400000;
const categories = ['Rent or deposit', 'Dates', 'Names or details', 'Rules · lock-in, notice', 'Brokerage', 'Other'];
export const approvalRoundId = (agreementId, revision) => hash(JSON.stringify([agreementId, revision]));
export const approvalDigest = snapshot => hash(JSON.stringify(snapshot));
function requireValue(value, message, code = 'failed-precondition') {
  if (!value) throw new ApprovalError(code, message);
}
function matches(first, second) {
  return typeof first === 'string' && typeof second === 'string' && /^[a-f0-9]{64}$/.test(first) &&
    /^[a-f0-9]{64}$/.test(second) && timingSafeEqual(Buffer.from(first, 'hex'), Buffer.from(second, 'hex'));
}
function changedFields(previous, current) {
  if (!previous) return [];
  return Object.keys(current).filter(key => JSON.stringify(previous[key]) !== JSON.stringify(current[key]) &&
    !['templateVersion', 'signable'].includes(key));
}

export function createAgreementApprovalService({ store, auth, now = Date.now,
  nonce = () => randomBytes(32).toString('base64url'), eventId = randomUUID }) {
  async function current(transaction, agreementId, revision) {
    const agreement = await transaction.get(`agreements/${agreementId}`);
    requireValue(agreement?.revision === revision && ['draft', 'review_requested', 'under_review', 'reviewed', 'signed_copy_received'].includes(agreement.status),
      'This agreement changed or is unavailable. Ask the broker for a new link.');
    const broker = await transaction.get(`users/${agreement.brokerUid}`);
    requireValue(broker?.roles?.includes('broker') && broker.approvalStatus === 'approved' && broker.paused !== true,
      'The broker cannot share this agreement right now.', 'permission-denied');
    return { agreement, broker, snapshot: reviewSnapshot(agreement) };
  }
  function audit(transaction, agreementId, action, metadata = {}) {
    transaction.set(`agreements/${agreementId}/events/${eventId()}`, {
      action, actorUid: auth.uid, createdAtMs: now(), ...metadata,
    });
  }
  async function enabled(transaction) {
    requireValue(auth?.uid, 'Verify your phone first.', 'unauthenticated');
    const profile = await transaction.get(`users/${auth.uid}`);
    requireValue(profile?.paused !== true, 'This account is paused. Contact support.', 'permission-denied');
  }
  async function active(transaction, token) {
    requireValue(typeof token === 'string' && /^[a-f0-9]{64}\.[\w-]{43}$/.test(token),
      'This link is incomplete. Ask the broker for a new link.');
    const id = token.slice(0, 64);
    const invitation = await transaction.get(`agreementInvitations/${id}`);
    requireValue(invitation && matches(invitation.tokenHash, hash(token)) && invitation.expiresAtMs > now(),
      'This link expired or was replaced. Ask the broker for a new link.');
    const context = await current(transaction, invitation.agreementId, invitation.revision);
    requireValue(matches(invitation.digest, approvalDigest(context.snapshot)),
      'The agreement changed. Read and reply to the new version.');
    const round = await transaction.get(`agreementApprovalRounds/${invitation.roundId}`);
    requireValue(round && matches(round.digest, invitation.digest) && round.replies?.[invitation.partyId],
      'This approval version is unavailable. Ask the broker for a new link.');
    const party = [...context.snapshot.owners, ...context.snapshot.tenants].find(person => person.id === invitation.partyId);
    requireValue(party?.phone === invitation.phone, 'The contact changed. Ask the broker for a new link.');
    return { id, invitation, round, party, ...context };
  }
  function proof(invitation) {
    return Boolean(auth?.uid && verifiedPhone(auth) === invitation.phone);
  }
  function result(context, verified) {
    const { id, invitation, round, snapshot, broker, party } = context;
    const output = { invitationId: id, role: invitation.role, phoneMasked: `+91 ••••••${invitation.phone.slice(-4)}`,
      brokerName: broker.displayName?.trim() || 'Your broker', verified, expiresAtMs: invitation.expiresAtMs };
    if (!verified) return output;
    return { ...output, agreementId: invitation.agreementId, revision: invitation.revision, digest: invitation.digest,
      partyId: invitation.partyId, partyName: party.name, status: round.replies[invitation.partyId].status,
      snapshot, changedFields: round.changedFields, demoOnly: true, signable: false,
      ...(context.agreement.agreementCopy?.revision === invitation.revision
        ? { copyReady: true, copyMode: context.agreement.agreementCopy.mode } : {}),
      reply: round.replies[invitation.partyId],
      people: [...snapshot.owners.map(person => ({ ...person, role: 'owner' })),
        ...snapshot.tenants.map(person => ({ ...person, role: 'tenant' }))].map(person => ({
        id: person.id, name: person.name, role: person.role, status: round.replies[person.id].status,
      })), allAgreed: Object.values(round.replies).every(reply => reply.status === 'agreed') };
  }
  return {
    async prepare({ agreementId, revision, operationId, refreshPartyId }) {
      requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
      requireValue(safe(agreementId) && Number.isSafeInteger(revision) && revision > 0 && safe(operationId) &&
        (refreshPartyId == null || safe(refreshPartyId)), 'Open a saved agreement revision.', 'invalid-argument');
      return store.transaction(async transaction => {
        const context = await current(transaction, agreementId, revision);
        requireValue(context.agreement.brokerUid === auth.uid && context.agreement.status === 'draft',
          'Only the broker can share a saved editable draft.', 'permission-denied');
        const roundId = approvalRoundId(agreementId, revision);
        const roundPath = `agreementApprovalRounds/${roundId}`;
        const previous = await transaction.get(roundPath);
        const head = await transaction.get(`agreementApprovalHeads/${agreementId}`);
        const priorRound = head && head.revision < revision
          ? await transaction.get(`agreementApprovalRounds/${head.roundId}`) : null;
        const digest = approvalDigest(context.snapshot);
        requireValue(!previous || matches(previous.digest, digest), 'Save a new revision for changed terms.');
        const people = [...context.snapshot.owners.map(person => ({ ...person, role: 'owner' })),
          ...context.snapshot.tenants.map(person => ({ ...person, role: 'tenant' }))];
        requireValue(refreshPartyId == null || people.some(person => person.id === refreshPartyId),
          'Choose a person on this agreement.', 'invalid-argument');
        const records = [];
        for (const person of people) {
          const id = hash(JSON.stringify([agreementId, revision, person.id]));
          const invitation = await transaction.get(`agreementInvitations/${id}`);
          const secret = await transaction.get(`agreementInvitationSecrets/${id}`);
          records.push({ id, person, invitation, secret });
        }
        const round = previous ?? { agreementId, revision, brokerUid: auth.uid, digest, snapshot: context.snapshot,
          createdAtMs: now(), changedFields: changedFields(priorRound?.snapshot, context.snapshot),
          replies: Object.fromEntries(people.map(person => [person.id, { status: 'not_opened' }])) };
        const links = [];
        for (const record of records) {
          const { id, person, invitation, secret } = record;
          const refresh = refreshPartyId === person.id && invitation?.lastOperationId !== operationId;
          requireValue(!refresh || !invitation || (invitation.issuedAtMs ?? 0) + 60000 <= now(),
            'Wait one minute before replacing this link.', 'resource-exhausted');
          requireValue(!refresh || !['agreed', 'change_requested'].includes(round.replies[person.id].status),
            'This person already replied. Save revised terms before asking again.');
          const reuse = invitation && secret && !refresh;
          requireValue(!reuse || matches(invitation.tokenHash, hash(secret.token)), 'This link needs to be reissued.');
          const token = reuse ? secret.token : `${id}.${nonce()}`;
          const data = reuse ? invitation : { agreementId, revision, roundId, digest, brokerUid: auth.uid,
            partyId: person.id, partyName: person.name, role: person.role, phone: person.phone,
            status: round.replies[person.id].status, tokenHash: hash(token), expiresAtMs: now() + lifetime,
            issuedAtMs: now(), lastOperationId: operationId, linkVersion: (invitation?.linkVersion ?? 0) + 1 };
          if (!reuse) {
            transaction.set(`agreementInvitations/${id}`, data);
            transaction.set(`agreementInvitationSecrets/${id}`, { token, expiresAtMs: data.expiresAtMs });
          }
          links.push({ invitationId: id, partyId: person.id, partyName: person.name, phone: person.phone,
            role: person.role, status: round.replies[person.id].status, token, expiresAtMs: data.expiresAtMs });
        }
        if (!previous) {
          transaction.set(roundPath, round);
          transaction.set(`agreementApprovalHeads/${agreementId}`, { roundId, revision, digest });
          audit(transaction, agreementId, 'agreement.demo_approval_prepared', { revision, digest });
        } else if (refreshPartyId && records.find(record => record.person.id === refreshPartyId)?.invitation?.lastOperationId !== operationId) {
          audit(transaction, agreementId, 'agreement.approval_link_reissued', { revision, partyId: refreshPartyId });
        }
        return { agreementId, revision, digest, demoOnly: true, signable: false, links };
      });
    },
    async read({ token }) {
      return store.transaction(async transaction => {
        const context = await active(transaction, token);
        const verified = proof(context.invitation);
        if (verified) {
          await enabled(transaction);
          if (context.round.replies[context.invitation.partyId].status === 'not_opened') {
            const reply = { status: 'seen', seenAtMs: now() };
            context.round.replies[context.invitation.partyId] = reply;
            transaction.update(`agreementApprovalRounds/${context.invitation.roundId}`, { replies: context.round.replies });
            transaction.update(`agreementInvitations/${context.id}`, { status: 'seen', seenAtMs: now() });
            audit(transaction, context.invitation.agreementId, 'agreement.approval_seen', {
              revision: context.invitation.revision, partyId: context.invitation.partyId });
          }
        }
        return result(context, verified);
      });
    },
    async reply({ token, revision, digest, decision, readAll, agreeTerms, category, note, operationId }) {
      requireValue(['agreed', 'change_requested'].includes(decision) && safe(operationId),
        'Choose an agreement reply.', 'invalid-argument');
      requireValue(decision !== 'agreed' || readAll === true && agreeTerms === true,
        'Read the full demo and check both confirmations.', 'invalid-argument');
      requireValue(decision !== 'change_requested' || categories.includes(category) && typeof note === 'string' &&
        note.trim().length >= 5 && note.length <= 1000, 'Choose what is wrong and add a note (5–1000 characters).', 'invalid-argument');
      return store.transaction(async transaction => {
        const context = await active(transaction, token);
        requireValue(proof(context.invitation), 'Verify the phone on this agreement.', 'permission-denied');
        await enabled(transaction);
        requireValue(context.agreement.status !== 'signed_copy_received',
          'A signed copy is available. Contact the team about changes to the executed agreement.');
        requireValue(revision === context.invitation.revision && matches(digest, context.invitation.digest),
          'This is not the version you read. Open the agreement again.', 'aborted');
        const oldReply = context.round.replies[context.invitation.partyId];
        const payload = approvalDigest({ decision, ...(decision === 'agreed' ? { readAll, agreeTerms } : { category, note: note.trim() }) });
        if (oldReply.operationId === operationId) {
          requireValue(oldReply.payload === payload, 'Retry the same reply, or reopen the agreement.', 'aborted');
          return result(context, true);
        }
        requireValue(!['agreed', 'change_requested'].includes(oldReply.status) || oldReply.status === 'agreed' && decision === 'change_requested',
          'Your reply is already recorded. Ask the broker to send a revised agreement.');
        const reply = { status: decision, actorUid: auth.uid, atMs: now(), operationId, payload,
          digest, revision, evidenceVersion: 'demo-reply-v1', demoOnly: true, signable: false,
          ...(decision === 'agreed' ? { readAll: true, agreeTerms: true } : { category, note: note.trim() }) };
        context.round.replies[context.invitation.partyId] = reply;
        transaction.update(`agreementApprovalRounds/${context.invitation.roundId}`, { replies: context.round.replies });
        transaction.update(`agreementInvitations/${context.id}`, { status: decision, reply });
        if (decision === 'change_requested' && context.agreement.status !== 'draft') {
          transaction.update(`agreements/${context.invitation.agreementId}`, { status: 'draft',
            reviewReturnReason: 'A participant requested a change. Save and send a new revision to everyone.', updatedAtMs: now() });
        }
        audit(transaction, context.invitation.agreementId, `agreement.demo_${decision}`, {
          revision, digest, partyId: context.invitation.partyId,
          ...(decision === 'change_requested' ? { category, note: note.trim() } : {}) });
        return result(context, true);
      });
    },
  };
}
