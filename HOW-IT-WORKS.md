# ClassTrack - How It Works (Simple Version)

A short, plain-English guide to this project. No deep code knowledge needed.

## What the app is
A student app (Android, iOS and web) for tracking attendance, class timetables, exams, grades, notes, habits and expenses, plus an AI assistant. Version: 1.0.59.

## The 3 big pieces
| Piece | What it is | Where |
|---|---|---|
| App (what users see) | Flutter (Dart) | `lib/` |
| Backend (runs on Google's servers) | Firebase Cloud Functions (JavaScript) | `functions/` |
| Database and files | Firebase Firestore + Storage, with access rules | `firestore.rules`, `storage.rules` |

## App folders (`lib/`)
- `features/`: one folder per screen or feature (attendance, chat, exams, grades, notes, subscription, and so on). `semesters/` holds the semester wrap-up and Past semesters screens.
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
   - If Gemini is overloaded (too many students at once), it waits a short random time before the next try, gives up after about 45 seconds and says "busy". The app then tries again by itself up to 2 times (after 3–8 s, then 6–16 s). Code: `functions/aiGenerate.js`, `functions/aiResilience.js`.
   - `parseSchedule` can run up to ~1,200 imports at the same time (150 servers × 8 each; capped by Google's us-central1 CPU quota). The real limit is the Gemini quota of the Google project.
3. Free users get a limited number of AI uses. Pro users get many more.

## Safety notes
- `functions/serviceAccount.json` is a secret key. It is in `.gitignore`. Never commit it.
- `node_modules/` (downloaded libraries) is also ignored.

## Where the code lives
- `origin`: github.com/killersbEE08/Classtrack-App (the default for `git push`)
- `playstore`: github.com/killersbEE08/classtrack-play-store (push with `git push playstore main`)

---

## Change log (newest first)

### 2026-10-20 - Pushed all pending work to GitHub
- **What:** Committed all saved-but-not-sent changes (app, backend, store text, tests, new Notes/Tasks files) and pushed them to `origin` (github.com/killersbEE08/Classtrack-App) on the `main` branch.
- **Why:** Keep GitHub up to date so the latest code is backed up and shareable.
- **Action needed:** None.

### 2026-10-17 - v1.0.61 release build; Assignments tile removed; shorter billing text
- **What:** (1) Removed the separate "Assignments" quick tool. Assignments are still a tab on the Tasks page (Home → Quick tools → Tasks → Assignments). (2) The billing text under the pricing page's Purchase button is now short: "Charged to your Google Play account. Auto-renews until you cancel in Play Store › Subscriptions." Price, period and trial terms are already shown on each plan card, so this still covers what Google Play requires. iOS keeps Apple's "24 h before" wording. (3) Built `build/app/outputs/bundle/release/app-release.aab` (77 MB): version 1.0.61, build 63, with the RevenueCat key. Includes the Tasks, Assignments, Notes and Home changes from today. Crashlytics symbols were uploaded.
- **Action needed:** Upload this .aab to Play Console. Deploy the backend (`cd functions; npm run deploy`) so Kiro knows about assignments.

### 2026-10-17 - Redesigned Notes
- **What:** The Notes list now has a 2-column card grid (or a single list, toggle saved on the phone). Cards are tinted with their note or subject colour, and previews show clean text with no raw `#` or `[link](…)` symbols. New: a "Study all flashcards" card, filter chips (All / Pinned / Flashcards / Files / each subject), sort options (recent, oldest, A–Z), search that also covers subjects and flashcards, a "New note" button, and long-press for Pin / Study / Delete. The editor got a formatting bar above the keyboard (heading, lists, checklist, quote, divider, link, image, PDF, flashcard) and a word count.
- **Where:** `notes_screen.dart` (list). The editor moved to `note_editor_screen.dart`. The preview text cleaner is `notePlainPreview` in `notes/domain/note_formatting.dart`. Tests: `test/notes_redesign_test.dart`.
- **Note:** In Chrome the console shows PostHog "capture" errors. These come from PostHog being turned off on web (see 2026-10-10), not from this change.

### 2026-10-17 - Home shows "Tasks due", new Assignments tool, redesigned Tasks page
- **What:** (1) On Home, the Attendance % card is now **Tasks due**: the number of pending tasks, with "N overdue" (red), "N due today" or "N this week" under it. Attendance % is still in Quick tools → Attendance. (2) New task kind **Assignment** and a new **Assignments** quick tool (opens the Tasks page on the Assignments tab, with a subject filter). (3) The Tasks page was redesigned: a progress card with Overdue / Today / Next 7 days counts (tap to filter), tabs (All / Assignments / To-dos / Events / Videos), a quick-add bar (type and press enter), a list grouped by date, and a fold-out Completed section. Sort, priority filter and "Clear completed" are under the tune icon.
- **Where:** `tasks/domain/task_buckets.dart` (date groups + counts), `tasks_screen.dart` (new page), the editor moved to `tasks/widgets/task_editor_sheet.dart`. AI guide in `functions/index.js` knows about assignments. Tests: `test/tasks_assignments_test.dart`.
- **Action needed:** Ship the app and deploy the backend (`cd functions; npm run deploy`). Older app versions show assignments as normal tasks (nothing breaks). Users with a saved Quick tools order get Assignments added at the end.

### 2026-10-17 - v1.0.60 release build
- **What:** Built `build/app/outputs/bundle/release/app-release.aab` (77 MB): version 1.0.60, build 62, with the RevenueCat key and the upload signing key. Includes the missing-profile fix and the PostHog chat-event fix below. Crashlytics symbols were uploaded.
- **Note:** The first Gradle try failed with an R8 "file not found" error (left over from a cancelled build). Flutter retried by itself and the second try worked.
- **Action needed:** Upload this .aab to Play Console instead of the 1.0.59 one. Deploy the backend too (`cd functions; npm run deploy`) if you haven't yet.

### 2026-10-17 - Fixed: some users had no profile in Firestore
- **What:** If a phone couldn't reach Firestore right after Google sign-in, the account was created in Auth but the `users/{uid}` profile never was. Now sign-in retries the profile write, and the app re-checks on every start (`profileSelfHealProvider`) and creates any missing profile. It never overwrites a real one.
- **Also:** The PostHog `ai_message` event is now sent only after the AI replies. Failed sends are logged as `ai_message_failed` with a `reason`. If the chat counter can't be read, the chat still goes to the server instead of silently stopping. Tests: `test/profile_self_heal_test.dart`.
- **Action needed:** Ship the app. 4 accounts from the last 4 days (including `BOfLsVOM…`) have no profile. They are fixed the next time those users open the new version. In PostHog, `ai_message` counts from before this release include failed sends.

### 2026-10-17 - v1.0.59 release build
- **What:** Built `build/app/outputs/bundle/release/app-release.aab` (77 MB): version 1.0.59, build 61, with the RevenueCat key, signed with the upload key ("Prince Kumar"). Includes today's changes: new onboarding, light pricing page, rating prompt and in-app updates. Crashlytics symbols were uploaded.
- **Action needed:** Upload the .aab in Play Console. Deploy the backend too (`cd functions; npm run deploy`), so Kiro's new feature guide goes live.

### 2026-10-17 - AI assistant (Kiro) can now explain every feature
- **What:** Added a "Feature glossary" to the AI's instructions (`CHAT_SYSTEM` in `functions/index.js`). It covers each feature: what it is, where to find it, and free vs Pro. Kiro now answers "what is wrap-up?", "what is Pro?", "what can this app do?" and "who are you?" in plain words. I checked every fact against the app code.
- **Why:** You wanted the AI to explain the app's features to students.
- **Action needed:** Deploy the backend (`cd functions; npm run deploy`). Found while checking: the Focus timer, Export and Subjects-list screens exist in code but no button opens them. Export is still sold as a Pro perk. Until a button is added, Kiro tells students these screens don't exist.

### 2026-10-17 - Rating prompt and in-app updates
- **What:** (1) The Play Store rating sheet now pops up right after a win: a timetable import, a finished focus session, 80%+ on a flashcard deck, or sharing a Semester Wrapped card. Only if the app was installed 3+ days ago, opened on 3+ days, and this is the 2nd+ win. At most once every 120 days, 3 times ever. Code: `lib/services/rating_prompt_service.dart`. (2) On Android, the app checks Google Play for a new version (at most every 12 hours). Normal updates download in the background, then a "RESTART" bar appears. Updates you mark priority 4–5, or ones ignored for 14+ days, show a full-screen "must update" screen. Code: `lib/services/app_update_service.dart`.
- **Why:** More ratings help the store listing, and users get fixes faster.
- **Action needed:** To force an update for a release, set its "in-app update priority" to 4 or 5 when uploading (Play Developer API or Fastlane `in_app_update_priority`, since Play Console has no button for it). You can only test both features on a build installed from Play (internal testing track works). Debug builds skip them.

### 2026-10-17 - Pricing page now has a light mode
- **What:** The Pro pricing page used to be always dark. It now follows the app theme: soft lavender and white cards with a purple "Purchase" button in light mode, and the same dark look as before in dark mode. Colours live in one `_Palette` (light + dark) in `paywall_screen.dart`.
- **Why:** You asked for the pricing page in light mode too.

### 2026-10-17 - Onboarding no longer mentions attendance; new "When do you study best?" step
- **What:** Removed the 75% attendance-target step, the "Attendance" focus card, the 92% card on the welcome screen and the attendance goal on the final preview. In its place: a "When do you study best?" step (Early bird / Daytime / Night owl) with a little animated sky (sun rises, clouds drift, moon and stars at night). The pick shows as a badge on the student card, a "peak hours" bar on the final preview, and is saved to the profile as `studyRhythm`. Added an "Exams" focus card.
- **Why:** You wanted onboarding to feel fun and smooth, without attendance talk.
- **Note:** The attendance target still starts at 75% and can be changed in Settings. Tests check no "attendance" or "%" text appears in onboarding.

### 2026-10-15 - Play Store listing now sells ClassTrack as a full study app
- **What:** New title `ClassTrack: Study & Attendance`, new short description starting with "Study planner", and a rewritten full description (3,500 of 4,000 characters) that leads with study planning, exam countdowns and homework, then attendance.
- **Why:** Impressions fell 32% in 28 days. All top competitors use "Study Planner" in the title, so that is where searches are. Attendance and bunk calculator stay as our unique hook.
- **Action needed:** Paste the files from `play-store-listing/` into Play Console. Wait 28 days before changing the title again.

### 2026-10-14 - All of today's work saved to GitHub
- **What:** Committed everything as `d780b7d` ("v1.0.58: …") and pushed it to both `origin` (Classtrack-App) and `playstore` (classtrack-play-store). Before committing I checked that no secret files or keys were included. `.crashlytics/` (a downloaded tool) is now in `.gitignore`.
- **Note:** GitHub says `origin` has moved to github.com/Princekumar786/Classtrack-App. Pushes still work through the redirect. To point at the new address: `git remote set-url origin https://github.com/Princekumar786/Classtrack-App.git`.

### 2026-10-14 - Backend package security updates
- **What:** Ran `npm audit fix` in `functions/`. Security problems in downloaded libraries went from 8 to 2 (fixed: 1 critical, 2 high, 3 moderate, in libraries like `proxy-addr`, `qs`, `@grpc/grpc-js`, `@fastify/busboy`). Only `package-lock.json` changed. All 64 backend tests pass.
- **Left:** 2 "high" warnings come from `node-forge` inside `firebase-admin` 13. Fixing them needs `firebase-admin` 14 plus `firebase-functions` 7, which have breaking changes. Our code doesn't use the affected part (checking RSA signatures from outside), so the real risk is low. Plan this upgrade as its own task.
- **Action needed:** Deploy the backend again (`cd functions; npm run deploy`) so the patched libraries go live.

### 2026-10-14 - Deploy fix: import server size + Node 22
- **What:** `parseSchedule` max servers lowered from 250 to 150, so ~1,200 imports at once instead of ~2,000. Google's limit for one service in us-central1 is 200 CPUs / 400 GiB, and 250 servers × 1 CPU went over it, so the deploy was refused. Cloud Functions now run on Node.js 22 (in `functions/package.json` and `firebase.json`).
- **Why:** Deploy failed with "Max instances must be set to 200 or fewer". Node 20 is switched off by Google on 2026-10-30, after which deploys stop working.
- **Action needed:** Run `npm run deploy` again in `functions/`. For more than ~1,200 imports at the same moment, ask Google for a higher Cloud Run CPU quota in us-central1 first.

### 2026-10-14 - v1.0.58 release build
- **What:** Built `build/app/outputs/bundle/release/app-release.aab`: version 1.0.58, build 60, with the RevenueCat key and the upload signing key. It contains every fix logged above from today. Crashlytics symbols were uploaded, so crash reports are readable. `tool/build_release.ps1` now uses Android Studio's Java for that upload when Java isn't installed.
- **Action needed:** Deploy the backend FIRST (`cd functions; npm run deploy`), then upload the `.aab` to Play Console. Rebuild + deploy the CMS for the banner "Show to Pro users" switch. Keep `build/debug-info` for this release.

### 2026-10-14 - Task reminders no longer fire for finished or deleted tasks
- **What:** Each reminder sync now cancels the reminder of any task that is done, has no due date, is past, falls in quiet hours, or was deleted (for example on another device or by the AI chat). Before, only ticking or deleting a task on the Tasks screen cancelled it.
- **Why:** Students could get "Task due" for something already finished.
- **Action needed:** Ships with the next app release.

### 2026-10-14 - Fixed: Back needed 5–6 presses after tapping the attendance notification
- **What:** Tapping the notification opened several Attendance pages on top of each other, so Back seemed stuck. Now only one Attendance page can open from a notification. The tap that started the app is handled once, even if Android reports it again. The push service and the reminder service now share one tap handler, so the Present/Absent buttons always mark the class.
- **Why:** The same tap was delivered several times: the start-up tap was re-read on every reminder setup, a plain tap had no "already open" guard, and the push service's own handler ignored the Present/Absent buttons.
- **Action needed:** Ship the app. Test: `test/notification_tap_once_test.dart`.

### 2026-10-14 - Timetable import ready for heavy load (10,000+ users); planner fixes
- **What (import under load):**
  - The import server now handles many requests per server and can grow to 250 servers. Before, only about 100 imports could run at once in the whole app; the 101st failed with "Import failed".
  - When Gemini says "too many requests", the server waits a short random time before retrying, instead of firing up to 16 calls at once. That stopped making the overload worse. In a test with 2,000 imports at once against a fake Gemini that allows only 100 per second: 0 crashes, ~97% succeeded on the first go, the rest got a clean "busy" (app retries), ~5 calls per import (was up to 16).
  - Every AI call has a time limit, so the server always answers before its own 3-minute timeout.
  - The app retries "busy" by itself (twice, random wait) and shows "Lots of students are importing right now" instead of "Import failed". A failed scan still never uses up a free scan.
  - A Pro user who hits the daily safety cap no longer sees the "Upgrade" screen.
- **What (planner):** "Reschedule this day" is now "Reschedule remaining plan" and asks first, because it re-plans all unfinished topics. Un-marking a completed day now asks whether to un-tick its topics too.
- **Action needed:** Deploy the backend (`cd functions; npm run deploy`) and ship the app. Check your Gemini quota (Google AI Studio → your project → Usage / Rate limits). Free tier is far too small for 10,000 users. Move to a paid tier and request a higher limit if needed. Run backend tests with `npm test` in `functions/`.

### 2026-10-14 - Every error now reaches Crashlytics AND PostHog; audit fixes
- **What (error reporting):**
  - New `lib/services/error_reporter.dart` sends every error to both Firebase Crashlytics and PostHog → Error tracking, with the same tags.
  - Each report has `error_kind` (`defect` = a bug, `transient` = no internet / server busy / timeout), `reason` (where it happened), `screen` (last screen opened), and the user id.
  - Crashlytics issues also carry `is_pro`, `country` and `app_version`. The Crashlytics "Logs" tab shows the screens visited and attendance marks.
  - Network/offline errors now go to PostHog too (before they were hidden there), but as non-fatal, so they never count as crashes.
  - Also newly reported: failed Riverpod providers/streams (e.g. a Firestore listener refused), attendance marks that failed to save, broken Firestore documents, reminder scheduling errors.
  - `tool/build_release.ps1` now uploads the Dart symbol files to Crashlytics, so crash stack traces are readable (not obfuscated). This needs the Firebase CLI and `firebase login`.
- **What (bug fixes):**
  - Editing a subject (or renaming it from the AI chat, or a re-import adding a class link) could undo attendance marks made while the edit screen was open. Edits no longer write the attendance counts.
  - The Present/Absent − buttons on a subject can't go below the days already marked in the calendar, so the % and the calendar always agree.
  - SGPA boxes now respect a 4.0 grading scale (before, anything up to 10 was accepted). Invalid SGPA shows an error instead of a dead Save button.
  - "Undo" after deleting a topic in "Build your own plan" now brings back its subtopics and links too.
  - The study reminder had a notification id inside the check-in range. It now has its own range; reminders are re-created once on update.
  - A broken class (session) document can no longer blank the timetable or crash the subject page.
- **Security:** The FCM push token is no longer written to the phone log in release builds. `_flog.txt` (a local log) is removed from git and ignored. A full audit of rules, Cloud Functions, secrets and Android found no critical, high or medium issues.
- **Action needed:** Ship the app. In PostHog → Error tracking, filter `error_kind = defect` to see real bugs. Install Firebase CLI on the build PC for the symbol upload.

### 2026-10-14 - CMS banners: "Show to Pro users" on/off
- **What:** The banner editor has a new **Show to Pro users** switch (saved as `showToPro`). Off = only free users see the banner; the banner list shows "· free users only". Banners that open the pricing page (`app://paywall`) are always hidden from Pro users, so the switch is locked for them.
- **Why:** You wanted to choose per banner whether paying users see it (e.g. ads or offers meant for free users).
- **Notes:** Old banners have no `showToPro` value, so they count as "on" and keep showing to everyone. No rules or backend change. Rule lives in `filterBannersForPro` (`core/utils/destination_handler.dart`); tests in `test/destination_handler_test.dart`.
- **Action needed:** Rebuild + deploy the CMS (`flutter build web -t lib/features/cms/main_cms.dart`, then `firebase deploy --only hosting`) and ship the app. Older app versions ignore the switch and show the banner to Pro users too.

### 2026-10-14 - Fixed: app could freeze for 1–2 minutes after marking attendance
- **What:** Every attendance tap updates the subject, and that used to re-schedule *all* reminders (classes, check-ins, tasks, exams, habits) each time, with many runs overlapping. Now reminders re-schedule only when the timetable/tasks/exams/habits/settings really change, one run at a time, after a short pause (`lib/services/reminder_sync_runner.dart`). The home-screen widget also skips updates when nothing changed.
- **Why:** On Android these calls run on the phone's main thread. A burst of marks (or offline marks syncing all at once) queued hundreds of them, so taps, screen changes and attendance looked stuck. Errors from these calls escaped as "uncaught" exceptions, which PostHog showed. They are now logged to Crashlytics as non-fatal.
- **Action needed:** Ship the next app update. Test: `test/reminder_sync_runner_test.dart`.

### 2026-10-14 - Wrap-up moved to the Pro section, AI knows the new features, PostHog shows names + every screen
- **What:**
  - **Settings → ClassTrack Pro** now holds "Semester wrap-up & past semesters", next to Insights. It moved out of the Grades section.
  - **AI assistant:**
    - Its app guide (`functions/index.js`) now covers semester wrap-up / past semesters / SGPA / CGPA, the subtopic ticks in the planner, saving an unfinished import, the "7 days of Pro per 5 friends" referral, auto-detected country, and the full Free vs Pro list.
    - It lists the removed features so it never suggests them.
    - It has strict rules: never invent buttons, features, limits or prices. It never quotes Pro prices (they come from the store). If something isn't in the guide, it says it isn't sure.
    - The app now also sends the AI the student's **past semesters** (SGPA, attendance, subjects, CGPA), so "what was my SGPA last semester?" is answered from real numbers.
  - **PostHog:**
    - Each person now shows their **name**, email, country, college, semester and Pro status. These come from the ClassTrack profile, because email sign-ups have no name in Firebase Auth.
    - Every event carries `is_pro` and `app_version`.
    - **Every screen now has a readable name** (e.g. "Grades", "Semester Detail", "Edit Class"). Before, about 75 screens had no name, so PostHog never logged them. A test now fails if a new screen is added without a name.
    - Switching tabs now also logs a screen view (Home / Schedule / Explore / Planner).
  - Fixed the app version constant: it said 1.0.52, it is now 1.0.57.
- **Why "delayed":** The app already sends each event immediately. PostHog's main Activity list can lag by a minute or more while it processes events. Use **Activity → Live** to watch in real time. Debug builds send nothing (opted out on purpose), so test with a release build.
- **Action needed:** Deploy the backend (`cd functions; npm run deploy`) for the AI changes, and ship the app. In PostHog → Project settings → "Person display name", put `name` first, then `email`.

### 2026-10-14 - Smoother onboarding; removed moments, app tour, AI weekly planner, Calendar tool
- **What:**
  - **Onboarding is smoother.** Cards and pages now slide and fade from a saved image of themselves, instead of being redrawn (shadows, text, pictures) on every frame. The bouncy 60% → 100% "spring" pop is now a soft 90% → 100% one. Cards start just after the page slide, so the two don't compete. The welcome attendance ring no longer animates inside its floating card. The student ID card's shine no longer re-draws its big shadow, and no longer rebuilds the card at the start and end of each shine.
  - **Removed from Settings:** Shareable moments, Show app tour, and the AI weekly planner. The weekly planner is removed from the app completely: its screens, its Pro gate, its pricing-table row and its "What's in Pro" entry. The first-time home tour for new users still plays.
  - **Removed Calendar from Home → Quick tools.** The calendar tab in the bottom bar is unchanged. People who had saved a custom Quick tools layout simply lose the Calendar tile.
  - The AI assistant's app guide (`functions/index.js`) no longer mentions any of these.
- **Why:** You asked for smoother onboarding cards and for these items to be removed.
- **Action needed:** Ship the app update. Deploy the backend (`npm run deploy`) so the AI assistant stops pointing people to the removed items. The Shareable moments screen code is still in the project (the semester "Wrapped" card shares its share helper) but nothing opens it.

### 2026-10-14 - Planner: no more weeks, tick each subtopic, cleaner plan page
- **What:**
  - **Weeks removed.** Planner home no longer has the "This week" strip or the "This week" stat. It now shows **Today** (with the stats Today / Left today / Topics done) and a **Coming up** list of the next study days. A plan page is one continuous list of days with no "WEEK 1 — FOUNDATIONS" headers.
  - **Subtopics can be ticked on their own:** on the plan page (tap a topic to open its subtopics), on the Day page (opened by default) and on Topic detail. Ticking the last subtopic completes the topic. Marking a whole topic done ticks all its subtopics. The progress ring, day bars and Today stats move with every tick. Ticks are saved with the plan (`doneSubtopics`).
  - **Plan page:** no duplicate title. It shows "X of Y topics done · N subtopics ticked". Self-built plans show "Your own plan" instead of AI labels and "Why this order?".
  - **Build your own plan:** the subtopics you type become exactly the checklist (no auto "self-check" lines). Press Enter in a subtopic to start the next one. In "Paste your topics", indented lines (or ◦ lines) under a topic become its subtopics.
- **Why:** You asked to drop weeks, tick subtopics separately, and make the planner easier to use.
- **Where:** `learning_planner/domain/learning_plan.dart` (subtopic rules), `widgets/topic_checklist.dart`, `planner_home_screen.dart`, `plan_overview_screen.dart`, `day_view_screen.dart`, `topic_detail_screen.dart`, `plan_builder_math.dart`. Tests: `test/planner_subtopics_test.dart`, `test/planner_ui_test.dart`, `test/plan_builder_math_test.dart`.
- **Action needed:** Ships with the next app release. No backend change. Old plans keep working: existing ticks start empty, and completed topics count as fully ticked.

### 2026-10-14 - Country is now detected automatically (opportunities + CMS pushes)
- **What:** The app now works out the student's country from the phone: SIM country first, then mobile network, then the phone's region setting. No permission and no GPS. It saves this as `detectedCountry` on the profile. The country used for targeting is the one the student picked in Edit profile, **or** the detected one if they didn't pick (or picked "Other"). This one rule now drives opportunities, discounts, banners, campaigns, AI chat context, and the push group the phone joins (`country_india` etc.). CMS pushes sent to "India" therefore reach detected Indian users too. Edit profile shows "Auto · India" when the country was detected.
- **Why:** Before, a student in India who never set a country only saw global items and never got India pushes.
- **Server:** The CMS "estimated recipients" counts and the analytics reach-by-country now use the same rule (`effectiveCountry` in `functions/notifications.js`, matching `AppUser.effectiveCountry`).
- **Action needed:** Deploy the backend (`cd functions; npm run deploy`) and ship the app. Phones only get country pushes after updating and opening the app once. Also update the Play Data safety form / privacy policy to say the app collects an approximate country (not precise location). The new Android code in `MainActivity.kt` was not compiled locally (no Java on this PC); the next `flutter build appbundle` will compile it.

### 2026-10-13 - New pricing page + referral is now "7 days per 5 friends"
- **What:** The Pro pricing page was redesigned to a dark, store-style layout: a big CLASSTRACK PRO logo, plan cards (Monthly, Quarterly, Annual) with the longer plans showing a struck-out "what it would cost monthly" price, a MOST POPULAR tag on Annual (pre-selected), a bold "WHY PRO?" Free-vs-Pro table with an icon on every row, RESTORE PURCHASES, a "See everything in Pro" sheet, a white PURCHASE button, and the required store billing text. The table now lists every current feature, including the new semester wrap-up and CGPA.
- **Referral change:** The reward is now **7 days of Pro for every 5 friends** who join with your code (it stacks: 10 friends = 14 days). A friend who joins with a code still gets **3 days** free as a welcome. The invite screen shows a 5-slot progress bar to the next reward.
- **Why:** You asked for the pricing page to match the reference design, cover the features we built, and switch referrals to 7 days per 5 friends.
- **Where:** `subscription/presentation/screens/paywall_screen.dart`, `subscription/domain/{upgrade_reason,pro_features,paywall_pricing}.dart`; backend `functions/referral.js` (+ `getReferralInfo`/`redeemReferral` in `index.js`); `referral/` screens and `AppConstants`. Tests: `test/paywall_screen_test.dart`, `test/paywall_pricing_test.dart`, `functions/referral.test.js`.
- **Action needed:** Deploy the backend (`cd functions; npm run deploy`) and ship the app update together — the new reward rule needs both. Rewards already earned under the old "3 days per invite" rule are kept; the new milestone days are tracked separately so nobody is double-counted or loses days.

### 2026-10-13 - Unsaved timetable imports are no longer lost
- **What:** As soon as an AI scan finishes, the result is saved on the phone as a draft, and every edit on the Review screen updates it. When the app goes to the background, the latest edits are saved immediately. If the app is then killed or swiped away, Home and the Import screen show "Finish your timetable import", with Review & save or Discard. Pressing back on Review asks whether to keep it for later or discard it. Tapping "Add to ClassTrack" saves the timetable to the account as before, and deletes the draft.
- **Why:** The scan was only kept in memory, so closing the app lost it. Free users also lost one of their 2 free scans.
- **Notes:** The draft stays on that phone only (one per account, deleted after 7 days). The saved timetable still syncs to all devices. Code: `import/data/import_draft_store.dart`, `widgets/import_draft_banner.dart`. Tests: `test/import_draft_test.dart`.
- **Action needed:** Ship in the next app release. No backend change.

### 2026-10-13 - Semester wrap-up (Pro) + fix for grades lost on subject delete
- **What:** A new "Wrap up semester" screen moves the current subjects, their grades and their exams into "Past semesters". The current screens then start fresh. Each past semester shows its SGPA, attendance and subjects. Students can add marks, a final grade, credits or the official SGPA later. Past semesters also show an overall CGPA, can be put back with "Restore", and have a shareable "Semester Wrapped" card. If a new timetable import looks like a new semester, the app offers to wrap up the old one first. You can open it from Grades, from Settings → Grades, or after a timetable import. It's Pro-only. A student whose Pro ends can still see the list and restore it.
- **Free fix:** Deleting a subject used to hide its grades for good. Now its grades and exams are kept under "No subject", and grades hidden by older deletes show up again.
- **How it's stored:** Nothing is copied. Archived items just get a `semesterId` tag, and current screens only show items without one. Semester names and dates are in `users/{uid}/semesters`. The code is in `lib/features/semesters/`, with tests in `test/semester_wrap_up_test.dart` and `test/semester_wrap_up_screen_test.dart`.
- **Action needed:** Ship in the next app release. No change to rules or the backend (the existing per-user rule already covers the new `semesters` list).

### 2026-10-11 - v1.0.57: study links, roomier subtopics, faster PostHog
- **What:** Topics now have **Links** (YouTube, articles, notes). Add them in "Build your own plan" or on any topic's page (works for AI plans too). Only real web links are saved. Subtopic boxes have space between them. PostHog events go out right away, are not held up by Firebase, and anything still queued is pushed when the app is minimised.
- **Why:** You asked for links, spacing and real-time PostHog.
- **Action needed:** Upload `build/app/outputs/bundle/release/app-release.aab` (1.0.57, build 59, with the RevenueCat key) to Play Console. Also deploy the backend and CMS (see the analytics entry below).

### 2026-10-11 - Redesigned "Build your own plan"
- **What:** The page now has 3 clear steps (what, topics, when). You can paste a whole syllabus (one topic per line, "– 45 min" is read as the time), drag topics to reorder, set time with − / + buttons, undo a delete, pick a subject from My Subjects, and choose "Before <exam>" as the deadline. A live "Will it fit?" card warns when topics don't fit the time and offers one-tap fixes.
- **Why:** You asked for a best-in-class manual plan builder.
- **Where:** `custom_plan_builder_screen.dart`. The maths and paste parsing are in `learning_planner/domain/plan_builder_math.dart` (tested by `test/plan_builder_math_test.dart`). Long pill labels app-wide now cut off with "…" instead of overflowing.
- **Action needed:** Ships with the next app release.

### 2026-10-11 - Sponsor-ready analytics in the CMS
- **What:** The app now also counts **impressions** (a card or banner was shown, once per student per session) and **banner taps**. The backend adds unique **reach / viewers / clickers**, reach by **country** and **per-day** numbers for each item. CMS Analytics shows Impressions and Feed CTR, a "By sponsor" table, a "Sponsored items" table and a "Banners" table. Each row (and each campaign) has a **Report** page with a date range (or the campaign's own dates), a daily chart, countries and a **Download CSV** to send to the sponsor.
- **Why:** Sponsors expect impressions, reach, CTR, clicks, audience by country and a date-ranged report.
- **Where:** `functions/index.js` (`aggregateEvent`), `functions/analytics_agg.js`, `firestore.rules` (events can carry a `bannerId`; new `bannerMetrics` + `daily` readable by CMS roles), `lib/services/metrics_service.dart`, `cms_sponsor_report_screen.dart`.
- **Action needed:** Deploy `firebase deploy --only functions,firestore:rules`, rebuild the CMS website (`flutter build web -t lib/features/cms/main_cms.dart` then `firebase deploy --only hosting`), and ship the app update. Numbers only start from then; old data has no impressions or reach. The new rules were not tested in the emulator (Java isn't installed here).

### 2026-10-11 - "Check your spam" on email sign-up
- **What:** The "Verify your email" screen shows a yellow tip: check Spam / Junk / Promotions and mark it "Not spam". The resend, "not verified yet" and password-reset messages say the same. The screen now scrolls on small phones.
- **Why:** Verification emails often land in spam, so people get stuck.
- **Action needed:** Ships with the next app release.

### 2026-10-11 - Redesigned the Planner tab
- **What:** The Planner page now opens with a "Today's focus" card that shows what to study right now (it turns red with "Catch up" if you missed days). You can tick topics off or start a session from the card. Under it: 3 quick stats, a week strip you can tap, and a day agenda that shows study sessions, tasks due and exams together. After that come upcoming exam countdowns, and plan cards that say On track / Behind / Paused / Completed. New users see a short "How it works" guide.
- **Why:** You asked for a best-in-class planner that answers "what do I study now, and am I on track?"
- **Where:** `learning_planner/presentation/screens/planner_home_screen.dart`. The on-track maths is in `learning_planner/domain/planner_insights.dart`, tested by `test/planner_insights_test.dart`.
- **Action needed:** Ship it in the next app release, together with the Pro paywall fix. No database or server changes.

### 2026-10-11 - Fixed: Pro users were seeing the "Upgrade" banner and pricing page
- **What:** Banners whose Destination is `app://paywall` (or `pricing`, `pro`…) are now hidden for Pro users, so the next banner shows instead. If a Pro user still lands on that link (e.g. from a push), they see their "Pro active" subscription page, not the pricing page.
- **Why:** The `app://paywall` link opened the pricing page for everyone without checking if the user already paid.
- **Action needed:** Build and upload a new app version. Old versions keep the bug until users update.

### 2026-10-11 - Fixed: free users could reach locked perks by searching
- **What:** On the Perks screen, the top "Featured perks" row was built from search results without the free limit, so a free user could search any perk's name and open/redeem it. Now search results and category filters only ever show the 5 free perks; locked matches stay behind the Premium card.
- **Why:** Free users are only meant to see the latest 5 perks and 5 opportunities.
- **Not affected:** Opportunities search was already limited correctly. Perks/opportunities you mark as "Featured" in the CMS are still shown to everyone on purpose, as a teaser.
- **Action needed:** Upload the 1.0.56 `.aab` (built with this fix). Don't upload the older 1.0.55 build — it doesn't include it.

### 2026-10-10 - v1.0.55: easier-to-read Opportunity & Perk pages
- **What:** The detail page now turns CMS text into a clean layout by itself: numbered lines ("1. …") show as a step-by-step timeline, emoji or "-" lines show as a tidy list, and each section (About, Benefits, How to apply/redeem) sits in its own card. Long "About" text folds behind "Read more". The cut-off title in the top bar is gone, and the brand name is hidden when it's the same as the title (no more "Wix / Wix").
- **Why:** The pages were long walls of text and hard to scan.
- **Action needed:** Upload the new 1.0.55 `.aab`. No CMS change needed: keep writing steps as "1. …" lines and benefits as "💰 …" or "- …" lines.
- **Note:** The website `classtrack-bffb2.web.app` is the CMS. Always build it with `flutter build web -t lib/features/cms/main_cms.dart` before `firebase deploy --only hosting`, otherwise the student app replaces the CMS.

### 2026-10-10 - Turned off PostHog analytics on the web app
- **What:** In `web/index.html` the PostHog start-up call (`posthog.init`) is commented out, so the website (classtrack-*.web.app) no longer sends anything to PostHog — no page views, clicks, "web vitals" or Flutter events.
- **Why:** The web sessions were cluttering the PostHog data; you only want analytics from the real mobile app.
- **Action needed:** Rebuild the website and redeploy it: `flutter build web` then `firebase deploy --only hosting`. Until you redeploy, the live site keeps sending data. Old web events already in PostHog stay there — hide or delete them from the PostHog dashboard if you want them gone.
- **Not affected:** Android/iOS analytics still work as before.

### 2026-10-10 - v1.0.54: pricing links, banner image upload, Google logo, redesigned detail page, analytics fix
- **What:** Several changes shipped together in version 1.0.54:
  - Banners and push notifications can now send users to the in-app Pro pricing page. Type `app://paywall` in a banner's "Destination" box (there's a "Use pricing page" button too), or in a push's `payload`. The same box also accepts `tab:explore`, `resource:<id>` and normal web links.
  - The CMS banner editor now has an "Upload image" button, so marketing can upload a picture instead of pasting an image URL. Images go to Firebase Storage and must be under 5 MB.
  - The "Continue with Google" button on login and sign-up now shows the real, official Google "G" logo (before it was a plain letter "G" that confused people).
  - The opportunity/discount detail page was redesigned: a cleaner header card, clearer sections and a nicer "Apply/Redeem" button. Nothing it does changed, only how it looks.
  - Fixed PostHog analytics losing events: it now sends each event right away instead of waiting for a batch, so data no longer "stops and starts".
- **Why:** You asked to route users to pricing from banners and notifications, make banner images easier to add, remove the confusing fake Google logo, make the detail page look professional, and fix the on-and-off analytics.
- **Action needed:** Build the app bundle and upload version 1.0.54 to Play Console. Users must update to the new version before any of this takes effect (these are in the app code, not server settings).

### 2026-10-10 - Improved Play Store listing copy
- **What:** Rewrote the Play Store text and screenshot captions around attendance tracking, bunk calculation and timetables.
- **Why:** The old text had broken symbols and did not lead with the clearest student benefit.
- **Action needed:** Paste the new listing into Play Console and measure it for 14 days before changing another asset.

### 2026-10-08 - Pushed full codebase to classtrack-play-store
- **What:** Pushed the whole project to github.com/killersbEE08/classtrack-play-store (remote name `playstore`).
- **Why:** You wanted a separate copy of the repo for the Play Store work.
- **Action needed:** The old `origin` repo doesn't have these 2 commits yet. Run `git push` if you want them there too.

### 2026-10-08 - Readable guide added
- **What:** Created this file and set a rule that it gets updated after every change.

### 2026-10-08 - Repo prep for the new GitHub account
- **What:** Saved all pending work as one commit (`33326bd`), added `node_modules/` to `.gitignore`, and connected the new `playstore` repo.
- **Why:** So the whole project can be pushed to the Princekumar786 account.
- **Status:** Later changed to push to the killersbEE08 account instead (see above).

### 2026-10-08 - Gemini AI settings update
- **What:** In `functions/index.js`, each Gemini model now gets the right "thinking" setting. Older 2.5 models get `thinkingBudget`; newer models get `thinkingLevel`.
- **Why:** Google said new models will reject the old setting with an error. Without this fix, the AI chat and timetable import could break.
- **Action needed:** Deploy with `cd functions; npm run deploy`.
- **Not affected:** The Firebase Hosting and Cloud Storage emails need no action for this project.
