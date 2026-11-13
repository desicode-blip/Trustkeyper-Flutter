import { getApps, initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { createTk2FileFinalizer, createTk2Service, Tk2Error } from './tk2.js';

if (getApps().length === 0) initializeApp();

function tk2Store() {
  const database = getFirestore();
  return {
    transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      update: (path, data) => transaction.update(database.doc(path), { ...data, updatedAt: FieldValue.serverTimestamp() }),
    })),
  };
}
export const tk2ConfirmVisit = onCall({ region: 'asia-south1', invoker: 'public', maxInstances: 5, timeoutSeconds: 20 }, async request => {
  try {
    return await createTk2Service({ store: tk2Store() }).confirmVisit(request.auth, request.data);
  } catch (error) {
    if (error instanceof Tk2Error) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'The visit could not be confirmed. Try again.');
  }
});

export const tk2FinalizeFile = onCall({ region: 'asia-south1', invoker: 'public', maxInstances: 5, timeoutSeconds: 60 }, async request => {
  try {
    const database = getFirestore();
    const finalize = createTk2FileFinalizer({
      getRecord: async path => (await database.doc(path).get()).data(),
      bucket: getStorage().bucket(),
    });
    return await finalize(request.auth, request.data?.path);
  } catch (error) {
    if (error instanceof Tk2Error) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'The file could not be saved. Try again.');
  }
});
