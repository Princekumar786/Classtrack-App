/// App-wide constants and Firestore collection/field keys.
class AppConstants {
  AppConstants._();

  static const String appName = 'ClassTrack';
  static const String bundleId = 'com.classtracks.app';

  /// User-facing app version shown in Settings. Keep this in sync with the
  /// `version:` field in pubspec.yaml (the part before the `+` build number).
  static const String appVersion = '1.0.58';

  // Google Sign-In: the OAuth 2.0 *Web* client ID (client_type 3 in
  // google-services.json). Passing this explicitly to GoogleSignIn makes the
  // native SDK request an ID token directly, instead of relying on the
  // auto-generated `default_web_client_id` string resource — which R8's
  // resource shrinker strips from release builds, causing idToken == null and
  // sign-in to fail only on Play Store / release builds.
  static const String googleServerClientId =
      '401205940629-8qbn7p6an2icehcp8lbortsom24ii7oa.apps.googleusercontent.com';

  /// OAuth scope requested when importing a timetable from Google Calendar.
  /// Read-only: ClassTrack only ever reads the user's events, never writes.
  static const String googleCalendarScope =
      'https://www.googleapis.com/auth/calendar.readonly';

  /// OAuth scope requested to import the user's Google Tasks (to-dos).
  /// Read-only: ClassTrack only ever reads tasks, never writes.
  static const String googleTasksScope =
      'https://www.googleapis.com/auth/tasks.readonly';

  /// OAuth scope requested for two-way sync (ClassTrack Pro): lets the app
  /// WRITE events into the user's Google Calendar (push classes, exams and
  /// task deadlines). Scoped to events only — it cannot read or change calendar
  /// sharing/settings.
  static const String googleCalendarWriteScope =
      'https://www.googleapis.com/auth/calendar.events';

  /// How many days into the PAST a Google Calendar/Tasks import may reach.
  /// Product rule: never pull items older than the last week, so a re-import
  /// (and the daily auto-sync) only ever brings in the current, relevant window
  /// instead of dredging up months of stale events.
  static const int googleImportBackDays = 7;

  /// How many days AHEAD a Google Calendar import looks (upcoming events).
  static const int googleImportForwardDays = 60;

  /// Local hour-of-day (24h) at which the once-daily background Google
  /// Calendar/Tasks auto-sync becomes eligible to run. 19 == 7 PM.
  static const int googleAutoSyncHour = 19;

  // Defaults
  static const double defaultTargetAttendance = 75.0;

  // Firestore collections
  static const String usersCollection = 'users';
  static const String subjectsCollection = 'subjects';
  static const String sessionsCollection = 'sessions';
  static const String attendanceCollection = 'attendance';
  static const String importJobsCollection = 'importJobs';

  // Opportunities / unified Resource platform (Phase 2+).
  // A single top-level collection backs scholarships, internships, discounts,
  // hackathons, etc. — the `type` field discriminates. Content is authored by
  // the CMS (Admin SDK / privileged roles); clients only ever read it.
  static const String resourcesCollection = 'resources';
  // Marketing banners shown on Home/Opportunities/Discounts (CMS-managed).
  static const String bannersCollection = 'banners';
  // Sponsored campaigns (CMS-managed).
  static const String campaignsCollection = 'campaigns';
  // Remotely-configurable app config (e.g. recommendation weights). Read-only
  // for clients; a single well-known doc per concern.
  static const String configCollection = 'config';
  static const String recommendationConfigDoc = 'recommendation';
  // Per-user saved/hidden opportunities: users/{uid}/savedResources/{id}.
  static const String savedResourcesCollection = 'savedResources';
  // CMS-composed targeted notification queue (processed by a Cloud Function).
  static const String notificationsCollection = 'notifications';
  // User-submitted content reports (moderation queue).
  static const String reportsCollection = 'reports';
  // Analytics: append-only engagement events + backend-aggregated counters.
  static const String eventsCollection = 'events';
  static const String resourceMetricsCollection = 'resourceMetrics';
  static const String metricsDailyCollection = 'metricsDaily';
  // Aggregate user-base counts for notification recipient estimates.
  static const String audienceCountsCollection = 'audienceCounts';
  // Managed content taxonomy (opportunity/discount categories).
  static const String categoriesCollection = 'categories';
  // Uploaded media library (index of Cloud Storage assets).
  static const String mediaAssetsCollection = 'mediaAssets';

  // Cloud Function
  static const String parseScheduleFunction = 'parseSchedule';
  static const String getReferralInfoFunction = 'getReferralInfo';
  static const String redeemReferralFunction = 'redeemReferral';

  /// Server-side self-heal: reconciles the caller's Pro entitlement against
  /// RevenueCat's source of truth (repairs a missed/denied webhook).
  static const String reconcileEntitlementFunction = 'reconcileEntitlement';

  // Referrals (server-enforced in functions/referral.js — keep in sync):
  //  • the inviter earns [referralMilestoneDays] of Pro for every
  //    [referralMilestoneSize] friends who join with their code;
  //  • a friend who joins with a code gets [referralWelcomeDays] once.
  static const int referralMilestoneSize = 5;
  static const int referralMilestoneDays = 7;
  static const int referralWelcomeDays = 3;
  // Number of successful invites that unlock the "ambassador" milestone.
  static const int referralAmbassadorGoal = 5;

  // SharedPreferences keys
  static const String prefsOnboardingDone = 'onboarding_done';
  static const String prefsHomeTourDone = 'home_tour_done';
  // Answers from the personalised onboarding (JSON). Device-global because it
  // is collected BEFORE sign-in; consumed + cleared on the first sign-in.
  static const String prefsOnboardingDraft = 'onboarding_profile_draft';
  // One-time feature-discovery tips (💡). Stored device-global, same as the
  // home tour: they teach the app's UI, so they surface once per install.
  static const String prefsTipNotes = 'tip_seen_notes';
  static const String prefsTipTasks = 'tip_seen_tasks';
  static const String prefsTipCalendar = 'tip_seen_calendar';
  // Tips & Tricks feature-discovery page. Device-global.
  //  • first-launch timestamp (millis since epoch) — drives the 7-day gate;
  //  • the set of flag-tracked features the user has tried (StringList);
  //  • whether the once-only "you're using X% of ClassTrack" prompt has shown.
  static const String prefsFirstLaunchAt = 'first_launch_at';
  static const String prefsFeaturesUsed = 'features_used';
  static const String prefsTipsPromptShown = 'tips_prompt_shown';
  static const String prefsThemeMode = 'theme_mode';
  // Clock style for every time in the app: 'system' (follow the phone),
  // '12h' or '24h'. Per user.
  static const String prefsTimeFormat = 'time_format';
  static const String prefsGeminiKey = 'gemini_api_key';
  static const String prefsReminderLead = 'reminder_lead_minutes';
  static const String prefsRemindersEnabled = 'reminders_enabled';
  // Google Calendar/Tasks daily auto-sync (per user):
  //  • whether the once-daily 7 PM background sync is enabled (default ON);
  //  • whether this account has connected Google at least once (set after the
  //    first successful manual import) — the silent sync only runs once this is
  //    true, so it can reuse the already-granted OAuth scopes without ever
  //    popping an interactive account/consent prompt;
  //  • the yyyy-MM-dd of the last successful auto-sync, so it runs at most once
  //    per calendar day.
  static const String prefsGoogleAutoSync = 'google_auto_sync_enabled';
  static const String prefsGoogleAutoSyncConnected = 'google_auto_sync_connected';
  static const String prefsGoogleAutoSyncLastDate = 'google_auto_sync_last_date';
  // Two-way sync (Pro): when enabled, the daily auto-sync ALSO pushes the
  // user's ClassTrack classes, exams and task deadlines back into their Google
  // Calendar. Opt-in (default off) so nothing is ever written without consent.
  static const String prefsGoogleAutoPush = 'google_auto_push_enabled';  static const String prefsGpaScale = 'gpa_scale'; // 'four' or 'ten'
  static const String prefsCurrency = 'currency_symbol';
  static const String prefsMonthlyBudget = 'monthly_budget';
  static const String prefsAccentColor = 'accent_color'; // ARGB int, 0 = default
  // Home "Quick tools" personalisation (per user):
  //  • ordered CSV of all tool keys in the user's chosen order;
  //  • CSV of hidden tool keys.
  static const String prefsQuickToolsOrder = 'quick_tools_order';
  static const String prefsQuickToolsHidden = 'quick_tools_hidden';
  // Home notification bell "seen" state (per user):
  //  • timestamp (millis) of when notifications were last viewed — anything
  //    published after it counts as a new match;
  //  • CSV of announcement (banner) ids the user has already seen.
  static const String prefsNotifSeenAt = 'notif_seen_at';
  static const String prefsAnnouncementsSeen = 'announcements_seen';

  // Notification preferences
  static const String prefsNotifyClasses = 'notify_classes';
  static const String prefsNotifyTasks = 'notify_tasks';
  static const String prefsNotifyExams = 'notify_exams';
  static const String prefsNotifyHabits = 'notify_habits';
  // After-class nudge to mark attendance (Present/Absent from the notification).
  static const String prefsNotifyAttendanceCheck = 'notify_attendance_check';
  static const String prefsDailySummary = 'notify_daily_summary';
  static const String prefsDailySummaryHour = 'notify_daily_summary_hour';
  static const String prefsDailySummaryMinute = 'notify_daily_summary_minute';
  static const String prefsQuietHours = 'notify_quiet_hours';
  static const String prefsQuietStartHour = 'notify_quiet_start_hour';
  static const String prefsQuietEndHour = 'notify_quiet_end_hour';

  // Gemini
  static const String geminiModel = 'gemini-2.0-flash';

  // ── PostHog (product analytics, EU cloud) ────────────────────────────────
  // The PROJECT API key is a public client token (it ships to every device,
  // like the Google client ID above) — safe to embed. A build can override it
  // with --dart-define=POSTHOG_KEY=... / --dart-define=POSTHOG_HOST=... .
  static const String posthogApiKey = String.fromEnvironment(
    'POSTHOG_KEY',
    defaultValue: 'phc_sCjBUKQ55dxzbzbedF964bFPhrDVeERHwLkRt7oru9d9',
  );
  static const String posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://eu.i.posthog.com',
  );

  // Website & legal (hosted pages)
  static const String websiteUrl = 'https://classtracks.app/';
  static const String privacyPolicyUrl = 'https://classtracks.app/privacy/';
  static const String termsUrl = 'https://classtracks.app/terms/';
  static const String supportUrl = 'https://classtracks.app/support/';

  // Contact
  static const String supportEmail = 'support@classtracks.app';
  static const String contactEmail = 'piyush@classtracks.app';

  // Store links
  static const String androidPackage = 'com.classtracks.app';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.classtracks.app';
  // Deep link that opens the Play Store app directly on the listing.
  static const String playStoreMarketUrl =
      'market://details?id=com.classtracks.app';
  // Where the store subscription-management screen lives.
  static const String manageSubscriptionsUrl =
      'https://play.google.com/store/account/subscriptions';
}

/// Days of the week, Monday-first, matching DateTime.weekday (1..7)
/// but stored 0..6 (Mon=0) in Firestore for compactness.
class Weekdays {
  Weekdays._();

  static const List<String> full = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> short = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Convert DateTime.weekday (Mon=1..Sun=7) to storage index (Mon=0..Sun=6).
  static int fromDateTime(DateTime date) => date.weekday - 1;

  /// Parse "Monday".."Sunday" (case-insensitive) to 0..6, or null.
  static int? parse(String value) {
    final idx = full.indexWhere(
      (d) => d.toLowerCase() == value.trim().toLowerCase(),
    );
    return idx == -1 ? null : idx;
  }
}
