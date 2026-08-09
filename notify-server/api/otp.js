/**
 * Vercel serverless function handling email OTP send/verify for
 * SpideyTracker's signup/login email-verification step.
 *
 * Uses firebase-admin's MODULAR API (initializeApp/cert/getApps from
 * 'firebase-admin/app', getFirestore from 'firebase-admin/firestore',
 * getAuth from 'firebase-admin/auth') — same fix as notify.js needed:
 * the installed firebase-admin version's top-level
 * require('firebase-admin') only exposes app-management functions
 * (initializeApp, getApps, cert, etc.), not the auth/firestore
 * namespaces some old code expects. Calling `admin.apps.length` (the
 * old namespaced style) on that object crashes with "Cannot read
 * properties of undefined (reading 'length')" because `.apps` simply
 * isn't there — that was this file's exact bug. The modular imports
 * below sidestep that entirely.
 *
 * Deploy: vercel --prod   (same project as notify.js — see README.md)
 *
 * Env vars required (already set for notify.js, reused here):
 *   FIREBASE_SERVICE_ACCOUNT_BASE64  - the service account JSON,
 *                                base64-encoded as one line (see
 *                                README.md for the exact command)
 *   GMAIL_USER                  - the Gmail address sending the OTP emails
 *   GMAIL_APP_PASSWORD          - a Gmail App Password for that account
 *                                (not the account's normal login password)
 *
 * Request:
 *   POST /api/otp
 *   Headers: Content-Type: application/json, Authorization: Bearer <Firebase ID token>
 *   Body: { "action": "send", "email": "..." }
 *      or { "action": "verify", "code": "123456" }
 */
const crypto = require('crypto');
const nodemailer = require('nodemailer');
const { initializeApp, cert, getApps } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');

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
  console.error('otp.js: firebase-admin initialization failed:', e && e.stack ? e.stack : e);
}

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.GMAIL_USER,
    pass: process.env.GMAIL_APP_PASSWORD,
  },
});

const OTP_TTL_MS = 10 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;

function hashCode(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

async function verifyRequestAuth(req) {
  const authHeader = req.headers.authorization || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!token) throw { status: 401, message: 'Missing auth token' };
  const decoded = await getAuth().verifyIdToken(token);
  return decoded.uid;
}

async function handleSend(req, res) {
  const uid = await verifyRequestAuth(req);
  const { email } = req.body || {};
  if (!email) {
    return res.status(400).json({ error: 'email is required' });
  }

  const db = getFirestore();
  const userRef = db.collection('users').doc(uid);
  const userDoc = await userRef.get();
  const data = userDoc.data() || {};

  const lastSent = data.emailOtpLastSentAt?.toMillis?.() ?? 0;
  if (Date.now() - lastSent < RESEND_COOLDOWN_MS) {
    return res.status(429).json({ error: 'Please wait before requesting another code' });
  }

  const code = String(Math.floor(100000 + Math.random() * 900000));

  await userRef.set(
    {
      emailOtpHash: hashCode(code),
      emailOtpExpiresAt: Timestamp.fromMillis(Date.now() + OTP_TTL_MS),
      emailOtpAttempts: 0,
      emailOtpLastSentAt: FieldValue.serverTimestamp(),
      emailOtpTarget: email,
    },
    { merge: true }
  );

  await transporter.sendMail({
    from: `SpideyTracker <${process.env.GMAIL_USER}>`,
    to: email,
    subject: 'Your SpideyTracker verification code',
    text: `Your verification code is ${code}. It expires in 10 minutes.`,
    html: `<p>Your verification code is:</p><h2 style="letter-spacing:4px">${code}</h2><p>It expires in 10 minutes. If you didn't request this, you can ignore this email.</p>`,
  });

  return res.status(200).json({ ok: true });
}

async function handleVerify(req, res) {
  const uid = await verifyRequestAuth(req);
  const { code } = req.body || {};
  if (!code) {
    return res.status(400).json({ error: 'code is required' });
  }

  const db = getFirestore();
  const userRef = db.collection('users').doc(uid);
  const userDoc = await userRef.get();
  const data = userDoc.data() || {};

  if (!data.emailOtpHash || !data.emailOtpExpiresAt) {
    return res.status(400).json({ error: 'No code was requested' });
  }

  const attempts = data.emailOtpAttempts || 0;
  if (attempts >= MAX_ATTEMPTS) {
    return res.status(429).json({ error: 'Too many attempts. Request a new code.' });
  }

  const expired = Date.now() > data.emailOtpExpiresAt.toMillis();
  if (expired) {
    return res.status(400).json({ error: 'Code expired. Request a new one.' });
  }

  const matches = hashCode(code) === data.emailOtpHash;

  if (!matches) {
    await userRef.update({ emailOtpAttempts: attempts + 1 });
    return res.status(400).json({ error: 'Incorrect code' });
  }

  await userRef.set(
    {
      emailVerified: true,
      emailOtpHash: FieldValue.delete(),
      emailOtpExpiresAt: FieldValue.delete(),
      emailOtpAttempts: FieldValue.delete(),
      emailOtpTarget: FieldValue.delete(),
    },
    { merge: true }
  );

  return res.status(200).json({ ok: true });
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  if (initError) {
    return res.status(500).json({ error: `Server init failed: ${initError.message}` });
  }
  try {
    const { action } = req.body || {};
    if (action === 'send') return await handleSend(req, res);
    if (action === 'verify') return await handleVerify(req, res);
    return res.status(400).json({ error: 'Unknown action' });
  } catch (e) {
    const status = e.status || 500;
    return res.status(status).json({ error: e.message || 'Internal error' });
  }
};