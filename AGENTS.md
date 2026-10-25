# AGENTS.md: ClassTrack project map for AI assistants

Read this first. It tells you where things live and the rules that are easy to break,
so you don't have to scan the whole codebase. For the plain-English history of changes,
see `HOW-IT-WORKS.md` (newest first). **Keep this file up to date when you move or add
big pieces.**

## 1. What this is
ClassTrack is a student app for Android, iOS and web: attendance, timetable, tasks and
assignments, exams, grades/CGPA, notes and flashcards, habits, expenses, a learning
planner, opportunities and perks, and an AI assistant ("Kiro" in the UI).
- App: Flutter/Dart in `lib/`. Package name `classtrack`, app id `com.classtracks.app`.
  The version is in `pubspec.yaml` as `x.y.z+build`, and the build number must go up for every Play upload.
- Backend: Firebase Cloud Functions (Node 22, ES modules) in `functions/`. Firebase
  project `classtrack-bffb2`, region us-central1.
- Data: Firestore (`firestore.rules`, `firestore.indexes.json`) and Storage (`storage.rules`).
- Admin CMS: a separate Flutter web app inside the same repo. Its entry point is
  `lib/features/cms/main_cms.dart`, and it is hosted on Firebase Hosting from `build/web`.
- State: Riverpod 2 (`flutter_riverpod`). Routing: go_router (top-level stages only).
  Animations: `flutter_animate` plus built-in implicit animations. Payments: RevenueCat
  (`purchases_flutter`). Analytics: PostHog plus Firebase Analytics. Crashes: Crashlytics.

## 2. Commands (PowerShell on Windows, run from the project root)
| Task | Command |
|---|---|
| Static checks | `dart analyze lib test` (or `flutter analyze`) |
| All app tests | `flutter test` (about 650 tests, about 4–5 min) |
| One test file | `flutter test test/<name>_test.dart` |
| Run in Chrome | `flutter run -d chrome` |
| Backend tests | `cd functions; npm test` |
| Deploy backend | `cd functions; npm run deploy` (set `$env:FUNCTIONS_DISCOVERY_TIMEOUT='120'` if discovery times out) |
| Deploy rules | `firebase deploy --only firestore:rules` |
| Release .aab | `./tool/build_release.ps1`. It needs the user env var `REVENUECAT_ANDROID_KEY` (`goog_…`), obfuscates the build, and uploads Crashlytics Dart symbols. Output: `build/app/outputs/bundle/release/app-release.aab` |
| CMS web build | `flutter build web -t lib/features/cms/main_cms.dart` then `firebase deploy --only hosting` |
| Store screenshots | `flutter test tool/store_capture/capture_test.dart --update-goldens` |

Build speed: a release build is slow (20–45 min) when the PC is low on RAM. Close
Chrome, `flutter run` and emulators first. Idle Gradle daemons can hold GBs, so stop
them with `cd android; ./gradlew --stop`. Lint on release builds is off on purpose.

## 3. Folder map (`lib/`)
- `main.dart`: boot (Firebase, PostHog, Crashlytics, services created and injected as
  provider overrides, `notifications.init()` / `pushMessaging.init()` run unawaited).
- `app.dart`: `MaterialApp.router`.
- `core/`
  - `router/app_router.dart`: GoRouter redirects splash → onboarding → login/signup →
    verify-email → home. All six routes use `_stage()` (fade + slight zoom page).
  - `providers/app_settings_provider.dart`: `sharedPrefsProvider`, **`ScopedPrefs`**
    (per-signed-in-user prefs), onboarding done, home tour, reminders enabled, and more.
  - `constants/app_constants.dart`: every prefs key and collection name.
  - `theme/`: `app_colors.dart` (AppColors, `softShadow`), `app_typography.dart`
    (Poppins headings, Inter body), `app_theme.dart` (uses FadeUpwards page transitions;
    ZoomPageTransitions is avoided on purpose), `app_icons.dart`.
  - `utils/`: `validators.dart`, `url_launcher_util.dart` (`safeLaunchUri`, never crashes),
    `destination_handler.dart` (in-app deep links), `date_utils.dart`, `ics_exporter.dart`.
- `shared/widgets/`: `ui_kit.dart`, `buttons.dart`, `states.dart`, `skeleton.dart`,
  `sweep_shimmer.dart` (cheap shimmer), `progress_ring.dart`, `character_avatar.dart`,
  `ai_mascot.dart`, `placement_*` (CMS banners/campaigns), `confetti_overlay.dart`.
- `services/`
  - `notification_service.dart`: local notifications (class reminders, check-ins, daily
    agenda, risk alerts). `hasPermission()`, and `requestPermissions()` asks the OS only if not
    already allowed. The exact-alarm page is offered once per device.
  - `push_messaging_service.dart`: FCM. Asks permission only once per device
    (`push_permission_asked`). Exposes `permissionGranted`. Subscribes to topic `all` and
    `country_<slug>` (`pushCountryTopicSyncProvider`).
  - `reminder_scheduler.dart`: `reminderSyncProvider` (schedules everything when reminders
    are on), `autoEnableRemindersProvider` (Allow → reminders on), `RemindersBanner`.
  - `analytics_service.dart`: PostHog/Firebase events (`importOpened`, `log`, …).
  - `error_reporter.dart`: Crashlytics + PostHog exceptions (noise filters).
  - `country_detector.dart`: SIM/network/region country → `detectedCountry`.
  - `gemini_service.dart`: client wrapper. AI always goes through backend functions.
  - Others: `calendar_auto_sync.dart`, `google_calendar_service.dart`, `home_widget_service.dart`,
    `rating_prompt_service.dart`, `app_update_service.dart`, `push_deep_link.dart`.
- `features/<name>/` uses `data/` (repositories, Firestore), `domain/` (pure models and logic,
  unit-tested), and `presentation/` (`providers/`, `screens/`, `widgets/`).

| Feature | What / key files |
|---|---|
| `auth` | Sign-in/up, profile, **first-run onboarding**: `screens/onboarding_screen.dart` (enum `_Step` welcome→name→focus→rhythm→avatar→**perks**→building→plan), `widgets/onboarding_visuals.dart` (motion helpers `enter/pop/float`, `motionOn`, Mascot, PerksHero, StudentIdCard), `domain/onboarding_profile.dart`, `auth_providers.dart` (`userProfileProvider`, `effectiveCountryProvider`, `currentUidProvider`) |
| `home` | `home_shell.dart` (IndexedStack tabs Home/Schedule/Explore/Planner, quick-add FAB, app-wide sync providers watched here), `dashboard_screen.dart` (header, **bell sheet** `_NotificationsSheet`, `homeAlertsProvider`, `notificationResourcesProvider`), `notifications_seen_provider.dart` (`seenAt`, `listSince`), `home_tour.dart` |
| `attendance` | Marking, calendar, bunk calculator |
| `schedule` / `subjects` | Timetable sessions and subjects |
| `import` | AI timetable import: `import_screen.dart` (photo/PDF/text → `parseSchedule`), `review_screen.dart`, draft store, Google Calendar/Tasks import (`import_entry.dart`) |
| `chat` | AI assistant, chat actions (create/delete items via confirm cards), usage counters |
| `tasks` | Tasks + assignments, `task_buckets.dart` (date groups), editor sheet |
| `notes` | Notes grid, editor (`note_editor_screen.dart`), flashcards, `note_formatting.dart` |
| `exams`, `grades`, `habits`, `expenses`, `focus` | Standard CRUD features |
| `learning_planner` | AI and custom study plans (`kFreeLearningPlanLimit = 2`) |
| `opportunities` | Resources = opportunities + perks (discounts). `resource.dart` (`targetsCountry`, `isInActiveFeed`, `publishedAt`), `resource_type.dart`, `opportunities_providers.dart` (`visibleResourcesProvider`, feeds, `freeAllowedIds` free gate = 5 newest), `discounts_screen.dart` (titled "Perks") |
| `subscription` | Pro: `isProProvider` (server flag `_entitlements/{uid}`), RevenueCat service, `paywall_screen.dart`, `upgrade_prompt.dart` (`showUpgradePrompt`, `requirePro`), `upgrade_reason.dart` (copy and limits), `pro_features.dart` |
| `cms` | Admin web app: resources editor, banners, campaigns, notifications composer, media, reports, analytics, audit logs, roles |
| `insights`, `semesters`, `moments`, `referral`, `tips`, `settings`, `calendar`, `export` | As named |

## 4. Backend (`functions/`)
`index.js` exports these Cloud Functions:
- **AI:** `parseSchedule` (timetable from image/PDF/text), `chat`, `draftResource` (CMS AI drafts).
- **Payments:** `revenueCatWebhook`, `reconcileEntitlement`, `reconcileFlaggedEntitlements`. These write `_entitlements/{uid}`.
- **Users:** `deleteAccount`, `lookupUserByEmail`, `setUserRole`, `getReferralInfo`, `redeemReferral`.
- **CMS:** `sendQueuedNotification` (sends the FCM push when the CMS creates `notifications/{id}`), `runResourceSchedule` (scheduled publish/unpublish every 15 min), `auditResourceWrite` / `auditBannerWrite` / `auditCampaignWrite`, `checkResourceUrls` and `scheduledUrlHealthScan`.
- **Analytics:** `aggregateEvent`, `maintainAudienceCounts`.

Helper modules, each with a `*.test.js` file:
- `aiGenerate.js` and `aiResilience.js`: Gemini model fallback and retries.
- `chatGuard.js`: blocks code in AI replies.
- `freeQuota.js`: free allowance keyed by an email hash.
- `entitlement.js`, `notifications.js` (topic slugs), `scheduleParse.js`, `lifecycle.js`, `roles.js`, `referral.js`, `url_health.js`, `analytics_agg.js`.

The `*.mjs` files are one-off admin scripts (seed/publish/backfill/grantPro).

The AI system prompt is `CHAT_SYSTEM` in `index.js`. Update it when app features change, because it is the AI's guide to the app.

## 5. Firestore (main collections)
- `users/{uid}` (profile: `country`, `detectedCountry`, …) plus per-user subcollections for
  subjects, sessions, attendance, tasks, notes, plans, and so on.
- `resources` (opportunities + perks, written only by the CMS), `banners`, `campaigns`,
  `notifications` (CMS push queue), `categories`, `mediaAssets`, `config`, `reports`,
  `events`, `metricsDaily`, `resourceMetrics`, `bannerMetrics`, `audienceCounts`, `auditLogs`.
- Server-only: `_entitlements/{uid}` (Pro flag; the user can read it but never write it),
  `_aiUsage/{uid}` and `_freeQuota/{emailHash}` (usage counters).

## 6. Free vs Pro limits (the SERVER is the source of truth)
| Thing | Free | Pro | Enforced in |
|---|---|---|---|
| AI timetable scans | **2 total (lifetime)**, refunded if a scan fails or finds nothing | 100/day safety cap | `parseSchedule` → `enforceFreeAllowance` |
| AI chat | 10 / month | 300/day cap | `chat` |
| Learning plans | 2 | unlimited | app (`kFreeLearningPlanLimit`) |
| Opportunities / perks browsing | 5 newest per feed | all | app (`freeAllowedIds`) |
Free AI also needs a **verified email**. Error `resource-exhausted` with
`details.reason = free_limit` means show the upgrade prompt. `rate_limit` means the daily cap
was hit, so don't show the paywall.

## 7. Rules that are easy to break
- **Don't gate server-limited features on the client.** For example, don't call `requirePro` before
  `parseSchedule`. That bug hid the 2 free scans. Let the server answer and map its error.
- **Onboarding copy must not contain "attendance" or "%"**. `test/onboarding_screen_test.dart`
  checks this. Adding a `_Step` means updating `_accent`, the `switch` in `build`, `_back()`
  (plan → perks skips "building"), and the tests' tap sequence.
- **Every animation must respect reduce motion**: use `motionOn(context)` and make it a no-op when
  that is false. Widget tests run with reduce motion on and call `pumpAndSettle`, so a
  looping animation that ignores it hangs the tests. Wrap moving things in `RepaintBoundary`.
  No blur filters. No continuously animating full-screen backgrounds (they caused jank).
- **Per-user settings use `ScopedPrefs`** (`scopedPrefsProvider`), not raw SharedPreferences,
  so a second account on the same phone starts clean. Device-wide flags
  (`push_permission_asked`, `exact_alarm_asked`, `onboarding_done`) use raw prefs.
- **Never use `ref` after an `await`** without checking `mounted` / `context.mounted`. This caused a past
  crash: "Cannot use ref after the widget was disposed".
- **Notification permission:** check `hasPermission()` before asking. Don't re-prompt. Allow
  turns reminders on (`autoEnableRemindersProvider`).
- **Bell (Notifications sheet):** lists only perks/opportunities published after
  `listSince` (when the account started on this device), for `effectiveCountryProvider`
  (profile country, else the detected one). "New" means published after `seenAt`. Publishing in the
  CMS does **not** send a push by itself. Pushes only come from CMS → Notifications.
- **Links:** always use `safeLaunchUri` / `openUrl` from `url_launcher_util.dart`.
- **Home tabs** use `IndexedStack`, not AnimatedSwitcher, to avoid a deactivation-order crash.
- **Secrets:** `functions/serviceAccount.json` is gitignored and must never be committed. The Gemini key is a Functions
  secret. The RevenueCat **public** key comes in through `--dart-define` (`pro_constants.dart`).
  Without it, the paywall is off.
- **Editing `pubspec.yaml` from PowerShell:** write UTF-8 *without* a BOM and keep the "—"
  characters intact. `Set-Content -Encoding utf8` adds a BOM and garbles them.
- **Tests:** don't add new tests unless asked. Do update existing ones you break.
  `test/country_targeting_test.dart` is timing-sensitive (it waits 500 ms).

## 8. Project rule for every change
After changing anything, add an entry at the top of the "Change log" in
`HOW-IT-WORKS.md`, in simple English:
```
### YYYY-MM-DD - Short title
- **What:** … (file names in backticks)
- **Why:** …
- **Action needed:** None / what to do (deploy, upload .aab, …)
```
Also update its overview sections if folders, functions, the AI flow or the safety notes change.

## 9. Git
- **Remotes:** `origin` = github.com/Princekumar786/Classtrack-App (the default). `playstore` =
  github.com/killersbEE08/classtrack-play-store (push with `git push playstore main`).
- **Commit messages:** short, describing the user-visible change. Never force-push.
