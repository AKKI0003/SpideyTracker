/**
 * Vercel serverless function for Backblaze B2 photo storage — the
 * presign step described in the pin-photos feature guide, implemented
 * as a second endpoint on the same notify-server project (so there's
 * still no Cloud Functions / Blaze plan involved at all).
 *
 * B2's application key (B2_KEY_ID / B2_APPLICATION_KEY) never reaches
 * the Flutter app. The client asks this endpoint for permission, this
 * endpoint checks the caller is signed in AND a member of the party
 * the pin belongs to (same isMember() rule as firestore.rules), then
 * hands back a short-lived signed URL the client uploads straight to.
 *
 * The bucket is PRIVATE (per the setup guide), so this also returns a
 * signed *download* URL at upload time, valid 7 days, stored directly
 * on the PinPhoto. A "refresh" action re-signs a GET URL for an
 * existing objectKey — the client calls it proactively before a
 * photo's link gets close to expiring (see SelfHealingPinImage), so
 * photos stay viewable indefinitely instead of turning into a broken-
 * image icon after a week.
 *
 * Deploy: vercel --prod   (same project as notify.js — see README.md)
 *
 * Uses firebase-admin's MODULAR API (getApps/initializeApp/cert from
 * 'firebase-admin/app', getAuth from 'firebase-admin/auth', getFirestore
 * from 'firebase-admin/firestore') rather than the older
 * `admin.auth()`/`admin.firestore()` namespaced style — the currently
 * installed firebase-admin version's top-level require('firebase-admin')
 * only exposes app-management functions (initializeApp, getApps, cert,
 * etc.), not the auth/firestore namespaces, so the old style silently
 * failed with "Cannot read properties of undefined" the moment it tried
 * admin.apps.length or admin.credential.cert() — this is what every
 * upload failure so far actually was.
 *
 * Extra env vars required on top of the notify.js ones:
 *   B2_ENDPOINT            - e.g. s3.us-west-004.backblazeb2.com
 *                              (from the B2 bucket's "Endpoint" field)
 *   B2_REGION               - e.g. us-west-004 (the middle segment of
 *                              the endpoint above)
 *   B2_BUCKET               - your bucket name
 *   B2_KEY_ID                - the Application Key's keyID
 *   B2_APPLICATION_KEY       - the Application Key's secret
 *   FIREBASE_SERVICE_ACCOUNT_BASE64  - same var notify.js uses
 *
 * Request:
 *   POST /api/b2
 *   Headers: Content-Type: application/json,
 *            Authorization: Bearer <firebase ID token>
 *
 *   Upload:
 *     Body: { "action": "upload", "partyId": "...", "pinId": "...",
 *              "fileName": "photo.jpg", "contentType": "image/jpeg" }
 *     Response: { "uploadUrl": "...", "downloadUrl": "...",
 *                  "objectKey": "parties/.../pins/.../<uuid>.jpg" }
 *
 *   Delete:
 *     Body: { "action": "delete", "partyId": "...", "pinId": "...",
 *              "objectKey": "parties/.../pins/.../<uuid>.jpg" }
 *     Response: { "ok": true }
 *
 *   Refresh (re-signs a GET url for a photo whose 7-day link is about
 *   to expire or already has — this is the "future step" mentioned
 *   above, now implemented since photos were going broken after a
 *   week):
 *     Body: { "action": "refresh", "partyId": "...", "pinId": "...",
 *              "objectKey": "parties/.../pins/.../<uuid>.jpg" }
 *     Response: { "downloadUrl": "..." }
 */
const { initializeApp, cert, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { S3Client, PutObjectCommand, DeleteObjectCommand, GetObjectCommand, HeadObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const crypto = require('crypto');

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
  console.error('b2.js: firebase-admin initialization failed:', e && e.stack ? e.stack : e);
}

const s3 = initError
  ? null
  : new S3Client({
      endpoint: `https://${process.env.B2_ENDPOINT}`,
      region: process.env.B2_REGION,
      credentials: {
        accessKeyId: process.env.B2_KEY_ID,
        secretAccessKey: process.env.B2_APPLICATION_KEY,
      },
      forcePathStyle: true,
    });

const MAX_PHOTOS_PER_PIN = 5;
const SEVEN_DAYS_SECONDS = 7 * 24 * 60 * 60;

async function requireUid(req) {
  const authHeader = req.headers['authorization'] || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!token) throw { status: 401, message: 'Missing Authorization bearer token' };
  try {
    const decoded = await getAuth().verifyIdToken(token);
    return decoded.uid;
  } catch {
    throw { status: 401, message: 'Invalid or expired token' };
  }
}

async function requireMember(partyId, uid) {
  const partyDoc = await getFirestore().collection('parties').doc(partyId).get();
  if (!partyDoc.exists) throw { status: 404, message: 'Party not found' };
  const memberUids = partyDoc.data().memberUids || [];
  if (!memberUids.includes(uid)) throw { status: 403, message: 'Not a member of this party' };
}

function extensionFor(contentType, fileName) {
  const fromType = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/heic': 'heic' }[contentType];
  if (fromType) return fromType;
  const match = /\.([a-zA-Z0-9]+)$/.exec(fileName || '');
  return match ? match[1].toLowerCase() : 'jpg';
}

async function handleUpload(req, uid) {
  const { partyId, pinId, fileName, contentType } = req.body || {};
  if (!partyId || !pinId || !contentType) {
    throw { status: 400, message: 'partyId, pinId and contentType are required' };
  }
  await requireMember(partyId, uid);

  const pinRef = getFirestore()
    .collection('parties').doc(partyId)
    .collection('pins').doc(pinId);
  const pinDoc = await pinRef.get();
  const existingPhotos = pinDoc.exists ? (pinDoc.data().photos || []) : [];
  if (existingPhotos.length >= MAX_PHOTOS_PER_PIN) {
    throw { status: 400, message: `A pin can only have ${MAX_PHOTOS_PER_PIN} photos` };
  }

  const ext = extensionFor(contentType, fileName);
  const objectKey = `parties/${partyId}/pins/${pinId}/${crypto.randomUUID()}.${ext}`;

  const uploadUrl = await getSignedUrl(
    s3,
    new PutObjectCommand({
      Bucket: process.env.B2_BUCKET,
      Key: objectKey,
      // Deliberately NOT setting ContentType here — when it's part of
      // the signed command, the client's PUT request must send back a
      // byte-identical Content-Type header or B2 rejects the upload
      // with a 403 SignatureDoesNotMatch. Dropping it removes that
      // whole failure class; the client also sends no Content-Type
      // header on the PUT to match (see b2_upload_service.dart).
    }),
    { expiresIn: 600 } // 10 minutes to actually do the PUT
  );

  const downloadUrl = await getSignedUrl(
    s3,
    new GetObjectCommand({
      Bucket: process.env.B2_BUCKET,
      Key: objectKey,
    }),
    { expiresIn: SEVEN_DAYS_SECONDS }
  );

  return { uploadUrl, downloadUrl, objectKey };
}

async function handleDelete(req, uid) {
  const { partyId, pinId, objectKey } = req.body || {};
  if (!partyId || !pinId || !objectKey) {
    throw { status: 400, message: 'partyId, pinId and objectKey are required' };
  }
  if (!objectKey.startsWith(`parties/${partyId}/pins/${pinId}/`)) {
    throw { status: 400, message: 'objectKey does not match partyId/pinId' };
  }
  await requireMember(partyId, uid);

  const pinRef = getFirestore()
    .collection('parties').doc(partyId)
    .collection('pins').doc(pinId);
  const pinDoc = await pinRef.get();
  if (!pinDoc.exists) throw { status: 404, message: 'Pin not found' };
  if (pinDoc.data().ownerUid !== uid) {
    throw { status: 403, message: 'Only the pin owner can delete its photos' };
  }

  // A plain DeleteObjectCommand on a versioned B2 bucket only hides the
  // current version — the actual bytes stick around, billed against
  // the bucket, until B2's lifecycle job purges hidden versions on its
  // own schedule (can be up to 24h even with "keep only last version"
  // selected). Fetching the exact VersionId and deleting that specific
  // version instead removes it immediately, no lifecycle delay.
  try {
    const head = await s3.send(new HeadObjectCommand({ Bucket: process.env.B2_BUCKET, Key: objectKey }));
    await s3.send(new DeleteObjectCommand({
      Bucket: process.env.B2_BUCKET,
      Key: objectKey,
      VersionId: head.VersionId,
    }));
  } catch (e) {
    // Object already gone / already purged — nothing left to delete,
    // not a real failure.
    if (e.name !== 'NotFound' && e.$metadata?.httpStatusCode !== 404) {
      throw e;
    }
  }

  return { ok: true };
}

async function handleRefresh(req, uid) {
  const { partyId, pinId, objectKey } = req.body || {};
  if (!partyId || !pinId || !objectKey) {
    throw { status: 400, message: 'partyId, pinId and objectKey are required' };
  }
  if (!objectKey.startsWith(`parties/${partyId}/pins/${pinId}/`)) {
    throw { status: 400, message: 'objectKey does not match partyId/pinId' };
  }
  await requireMember(partyId, uid);

  const downloadUrl = await getSignedUrl(
    s3,
    new GetObjectCommand({
      Bucket: process.env.B2_BUCKET,
      Key: objectKey,
    }),
    { expiresIn: SEVEN_DAYS_SECONDS }
  );

  return { downloadUrl };
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

  try {
    const uid = await requireUid(req);
    const { action } = req.body || {};

    if (action === 'upload') {
      res.status(200).json(await handleUpload(req, uid));
    } else if (action === 'delete') {
      res.status(200).json(await handleDelete(req, uid));
    } else if (action === 'refresh') {
      res.status(200).json(await handleRefresh(req, uid));
    } else {
      res.status(400).json({ error: 'action must be "upload", "delete" or "refresh"' });
    }
  } catch (err) {
    const status = err.status || 500;
    if (status === 500) console.error('b2 endpoint failed:', err && err.stack ? err.stack : err);
    res.status(status).json({ error: err.message || 'Internal error' });
  }
};