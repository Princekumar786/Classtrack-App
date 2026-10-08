# ClassTrack — How It Works (Simple Version)

A short, plain-English guide to this project. No deep code knowledge needed.

## What the app is
A student app (Android, iOS and web) for tracking attendance, class timetables, exams, grades, notes, habits and expenses, plus an AI assistant. Version: 1.0.53.

## The 3 big pieces
| Piece | What it is | Where |
|---|---|---|
| App (what users see) | Flutter (Dart) | `lib/` |
| Backend (runs on Google's servers) | Firebase Cloud Functions (JavaScript) | `functions/` |
| Database and files | Firebase Firestore + Storage, with access rules | `firestore.rules`, `storage.rules` |

## App folders (`lib/`)
- `features/`: one folder per screen or feature (attendance, chat, exams, grades, notes, subscription, and so on)
- `services/`: helpers that talk to the outside world (notifications, Google Calendar, AI)
- `core/` and `shared/`: common settings, colours and reusable buttons/widgets

## Backend functions (`functions/index.js`)
- AI: `parseSchedule` (reads a timetable photo, PDF or text) and `chat` (the AI assistant). Both use Google Gemini.
- Payments: `revenueCatWebhook` and `reconcileEntitlement*` turn "Pro" on or off after a purchase.
- Users: `deleteAccount`, referrals, user roles.
- Admin/CMS: publishing opportunities, notifications, link checks, analytics.

## How the AI works
1. The app sends the message or timetable to our backend, never straight to Google. This keeps the Gemini API key secret.
2. The backend tries several Gemini models in order. If one fails, it tries the next.
3. Free users get a limited number of AI uses. Pro users get many more.

## Safety notes
- `functions/serviceAccount.json` is a secret key. It is in `.gitignore`. Never commit it.
- `node_modules/` (downloaded libraries) is also ignored.

## Where the code lives
- `origin`: github.com/killersbEE08/Classtrack-App (the default for `git push`)
- `playstore`: github.com/killersbEE08/classtrack-play-store (push with `git push playstore main`)

---

## Change log (newest first)

### 2026-10-08 — Pushed full codebase to classtrack-play-store
- **What:** Pushed the whole project to github.com/killersbEE08/classtrack-play-store (remote name `playstore`).
- **Why:** You wanted a separate copy of the repo for the Play Store work.
- **Action needed:** The old `origin` repo doesn't have these 2 commits yet. Run `git push` if you want them there too.

### 2026-10-08 — Readable guide added
- **What:** Created this file and set a rule that it gets updated after every change.

### 2026-10-08 — Repo prep for the new GitHub account
- **What:** Saved all pending work as one commit (`33326bd`), added `node_modules/` to `.gitignore`, and connected the new `playstore` repo.
- **Why:** So the whole project can be pushed to the Princekumar786 account.
- **Status:** Later changed to push to the killersbEE08 account instead (see above).

### 2026-10-08 — Gemini AI settings update
- **What:** In `functions/index.js`, each Gemini model now gets the right "thinking" setting. Older 2.5 models get `thinkingBudget`; newer models get `thinkingLevel`.
- **Why:** Google said new models will reject the old setting with an error. Without this fix, the AI chat and timetable import could break.
- **Action needed:** Deploy with `cd functions; npm run deploy`.
- **Not affected:** The Firebase Hosting and Cloud Storage emails need no action for this project.
