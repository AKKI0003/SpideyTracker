/**
 * Deploy with: firebase deploy --only functions
 * Requires: cd functions && npm install firebase-admin firebase-functions
 *
 * These two triggers are the "send a push to everyone else in the
 * party" half of Feature 3/notifications — sending FCM pushes requires
 * the Admin SDK's server-side credentials, which is why this can't run
 * purely on-device.
 *
 * IMPORTANT (privacy): the chat trigger deliberately does NOT read or
 * include the message text in the notification body — messages are
 * end-to-end encrypted client-side (see lib/core/chat/), and this
 * function only ever sees ciphertext anyway. The push just says
 * "New message from X" and lets the app show the real content once
 * decrypted on-device.
 */
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

admin.initializeApp();

async function getMemberTokens(partyId, excludeUid) {
  const partyDoc = await admin.firestore().collection('parties').doc(partyId).get();
  if (!partyDoc.exists) return { tokens: [], senderName: 'Someone' };

  const memberUids = (partyDoc.data().memberUids || []).filter((uid) => uid !== excludeUid);

  const tokens = [];
  let senderName = 'Someone';
  const userDocs = await Promise.all(
    memberUids.map((uid) => admin.firestore().collection('users').doc(uid).get())
  );
  for (const doc of userDocs) {
    const data = doc.data();
    if (data && Array.isArray(data.fcmTokens)) {
      tokens.push(...data.fcmTokens);
    }
  }

  if (excludeUid) {
    const senderDoc = await admin.firestore().collection('users').doc(excludeUid).get();
    senderName = senderDoc.data()?.displayName || 'Someone';
  }

  return { tokens, senderName, partyName: partyDoc.data().name || 'Your party' };
}

async function sendToTokens(tokens, notification) {
  if (tokens.length === 0) return;
  const response = await admin.messaging().sendEachForMulticast({
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
    const usersSnap = await admin.firestore().collection('users')
      .where('fcmTokens', 'array-contains-any', invalidTokens.slice(0, 10))
      .get();
    for (const doc of usersSnap.docs) {
      await doc.ref.update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
      });
    }
  }
}

exports.notifyOnNewPin = onDocumentCreated('parties/{partyId}/pins/{pinId}', async (event) => {
  const pin = event.data.data();
  const { partyId } = event.params;

  const { tokens, senderName, partyName } = await getMemberTokens(partyId, pin.ownerUid);

  await sendToTokens(tokens, {
    title: `${senderName} dropped a pin`,
    body: `New sighting in ${partyName}`,
  });
});

exports.notifyOnNewMessage = onDocumentCreated('parties/{partyId}/messages/{messageId}', async (event) => {
  const message = event.data.data();
  const { partyId } = event.params;

  const { tokens, senderName, partyName } = await getMemberTokens(partyId, message.senderUid);

  await sendToTokens(tokens, {
    title: partyName,
    body: `${senderName} sent a message`, // never the decrypted text — see file header
  });
});
