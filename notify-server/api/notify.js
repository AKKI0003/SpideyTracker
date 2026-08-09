/**
 * Vercel serverless function that replaces functions/index.js's two
 * Firestore triggers (notifyOnNewPin / notifyOnNewMessage).
 *
 * Cloud Functions requires the Blaze plan (because it needs Cloud
 * Build) even for triggers you never expect to cost anything. FCM
 * pushes themselves are free — the restriction is specifically on
 * running your own trigger code in Cloud Functions. This endpoint runs
 * the exact same "look up party members, send a push" logic on
 * Vercel's free tier instead, and the Flutter app calls it directly
 * right after writing a pin or message, instead of Firestore
 * auto-triggering it.
 *
 * Deploy: vercel --prod   (see README.md)
 *
 * Uses firebase-admin's MODULAR API (getApps/initializeApp/cert from
 * 'firebase-admin/app', getFirestore from 'firebase-admin/firestore',
 * getMessaging from 'firebase-admin/messaging') rather than the older
 * `admin.firestore()`/`admin.messaging()` namespaced style — the
 * currently installed firebase-admin version's top-level
 * require('firebase-admin') only exposes app-management functions
 * (initializeApp, getApps, cert, etc.), not the auth/firestore/
 * messaging namespaces, so the old style silently fails with
 * "Cannot read properties of undefined" the moment it tries to call
 * admin.firestore() or admin.credential.cert().
 *
 * Env vars required (set in Vercel project settings, not committed):
 *   FIREBASE_SERVICE_ACCOUNT_BASE64  - the service account JSON,
 *                                base64-encoded as one line (see
 *                                README.md for the exact command)
 *   NOTIFY_SECRET               - any random string; the client must send
 *                                it back in the x-notify-secret header
 *                                so randoms can't spam your users' push
 *                                notifications by hitting this URL
 *
 * Request:
 *   POST /api/notify
 *   Headers: Content-Type: application/json, x-notify-secret: <secret>
 *   Body: { "type": "pin" | "message", "partyId": "...", "actorUid": "..." }
 *
 * IMPORTANT (privacy, same as before): this endpoint never receives or
 * sends actual message text — chat is end-to-end encrypted client-side,
 * and this function only ever gets a partyId + the sender's uid. The
 * push just says "X sent a message" / "X dropped a pin"; the real
 * content is decrypted on-device.
 */
const { initializeApp, cert, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

let initError = null;
try {
  if (!getApps().length) {
    const raw = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64;
    if (!raw) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT_BASE64 env var is not set (or not set for this environment)');
    }
    const decoded = Buffer.from(raw, 'base64').toString('utf8');
    let serviceAccount;
    try {
      serviceAccount = JSON.parse(decoded);
    } catch {
      throw new Error(`FIREBASE_SERVICE_ACCOUNT_BASE64 did not decode to valid JSON (first 40 chars: "${decoded.slice(0, 40)}")`);
    }
    if (!serviceAccount.private_key || !serviceAccount.client_email) {
      throw new Error('Decoded service account JSON is missing private_key or client_email — value is likely truncated or corrupted');
    }
    initializeApp({ credential: cert(serviceAccount) });
  }
} catch (e) {
  initError = e;
  console.error('notify.js: firebase-admin initialization failed:', e && e.stack ? e.stack : e);
}

async function getMemberTokens(partyId, excludeUid) {
  const db = getFirestore();
  const partyDoc = await db.collection('parties').doc(partyId).get();
  if (!partyDoc.exists) return { tokens: [], senderName: 'Someone', partyName: 'Your party' };

  const memberUids = (partyDoc.data().memberUids || []).filter((uid) => uid !== excludeUid);

  const tokens = [];
  let senderName = 'Someone';
  const userDocs = await Promise.all(
    memberUids.map((uid) => db.collection('users').doc(uid).get())
  );
  for (const doc of userDocs) {
    const data = doc.data();
    if (data && Array.isArray(data.fcmTokens)) {
      tokens.push(...data.fcmTokens);
    }
  }

  if (excludeUid) {
    const senderDoc = await db.collection('users').doc(excludeUid).get();
    senderName = senderDoc.data()?.displayName || 'Someone';
  }

  return { tokens, senderName, partyName: partyDoc.data().name || 'Your party' };
}

async function sendToTokens(tokens, notification) {
  if (tokens.length === 0) return;
  const db = getFirestore();
  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification,
  });

  // Clean up tokens that are no longer valid (uninstalled app, etc.)
  const invalidTokens = [];
  response.responses.forEach((res, i) => {
    if (!res.success && res.error?.code === 'messaging/registration-token-not-registered') {
      invalidTokens.push(tokens[i]);
    }
  });
  if (invalidTokens.length > 0) {
    const usersSnap = await db.collection('users')
      .where('fcmTokens', 'array-contains-any', invalidTokens.slice(0, 10))
      .get();
    for (const doc of usersSnap.docs) {
      await doc.ref.update({
        fcmTokens: FieldValue.arrayRemove(...invalidTokens),
      });
    }
  }
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  if (initError) {
    res.status(500).json({ error: `Server init failed: ${initError.message}` });
    return;
  }

  if (req.headers['x-notify-secret'] !== process.env.NOTIFY_SECRET) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  const { type, partyId, actorUid } = req.body || {};
  if (!type || !partyId || !actorUid) {
    res.status(400).json({ error: 'type, partyId and actorUid are required' });
    return;
  }
  if (type !== 'pin' && type !== 'message') {
    res.status(400).json({ error: 'type must be "pin" or "message"' });
    return;
  }

  try {
    const { tokens, senderName, partyName } = await getMemberTokens(partyId, actorUid);

    const notification = type === 'pin'
      ? { title: `${senderName} dropped a pin`, body: `New sighting in ${partyName}` }
      : { title: partyName, body: `${senderName} sent a message` }; // never the decrypted text

    await sendToTokens(tokens, notification);
    res.status(200).json({ ok: true, notified: tokens.length });
  } catch (err) {
    console.error('notify failed:', err && err.stack ? err.stack : err);
    res.status(500).json({ error: err.message || 'Internal error' });
  }
};