# spidertrack-notify-server

Replaces the two Firestore-triggered Cloud Functions
(`notifyOnNewPin`, `notifyOnNewMessage`) with a single free HTTP
endpoint on Vercel, since Cloud Functions requires the Blaze plan.
Same logic, just called from the app instead of auto-triggered.

This is a standalone project — it does **not** touch your existing
`functions/` folder. You can leave that folder as-is (unused) or
delete it later; nothing here depends on it.

## 1. Get your Firebase service account key

Firebase Console → Project settings (gear icon) → Service accounts →
**Generate new private key**. This downloads a `.json` file — keep it
private, never commit it or put it in the Flutter app.

## 2. Deploy to Vercel

```powershell
cd notify-server
npm install -g vercel      # if you don't have the CLI yet
vercel login
npm install
vercel
```

`vercel` (no flags) does a preview deploy and will ask a few setup
questions the first time — accept the defaults (link to a new
project, keep the folder name, no build command needed).

## 3. Set the two environment variables

```powershell
vercel env add FIREBASE_SERVICE_ACCOUNT production
```
When prompted, paste the **entire contents** of the service account
JSON file as one line (open the `.json` file, copy everything, paste
it in). Repeat for `preview` and `development` if you want those
environments to work too.

```powershell
vercel env add NOTIFY_SECRET production
```
Paste any random string when prompted — this is a shared secret so
random people can't hit your endpoint and spam your users. Generate
one with:
```powershell
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

## 4. Deploy to production

```powershell
vercel --prod
```

This prints your live URL, e.g. `https://spidertrack-notify-server.vercel.app`.
Your notify endpoint is:

```
https://spidertrack-notify-server.vercel.app/api/notify
```

Keep that URL — you'll paste it into the Flutter app (see
`NOTIFY_ENDPOINT` in `notify_trigger.dart`, provided separately).

## Test it manually

```powershell
curl -X POST https://spidertrack-notify-server.vercel.app/api/notify `
  -H "Content-Type: application/json" `
  -H "x-notify-secret: <your NOTIFY_SECRET value>" `
  -d '{\"type\":\"pin\",\"partyId\":\"<a real partyId>\",\"actorUid\":\"<a real uid>\"}'
```
You should get `{"ok":true,"notified":N}` back and a push should land
on every other party member's device (not the `actorUid` one, by
design — that matches the old Cloud Functions behavior of excluding
the sender).

## Redeploying after code changes

```powershell
vercel --prod
```
That's it — env vars persist across deploys, you only set them once.
