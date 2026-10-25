import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/providers/notification_prefs_provider.dart';
import '../features/schedule/domain/class_session.dart';
import '../features/subjects/domain/subject.dart';
import '../features/tasks/domain/task_item.dart';
import '../features/exams/domain/exam.dart';
import '../features/habits/domain/habit.dart';

/// Wraps flutter_local_notifications: class-start reminders + attendance nudges.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Subject ids we currently have class reminders scheduled for. Used to
  /// cancel reminders for subjects that get deleted between syncs (otherwise
  /// their weekly reminders would keep firing forever).
  final Set<String> _scheduledClassSubjects = {};

  /// The concrete notification ids currently scheduled for each subject's class
  /// reminders, keyed by subject id. Because a subject can have several classes
  /// on the same weekday (e.g. a 09:00 and a 14:00 slot), reminders are keyed by
  /// subject + weekday + start-time, so we must remember exactly which ids we
  /// created in order to cancel them precisely on prune/delete/reschedule.
  final Map<String, Set<int>> _classReminderIds = {};

  /// Subject ids we currently have after-class attendance check-ins scheduled
  /// for, and the concrete notification ids per subject — mirrors the class
  /// reminder tracking so check-ins are pruned/cancelled precisely.
  final Set<String> _scheduledCheckSubjects = {};
  final Map<String, Set<int>> _checkInIds = {};

  /// Android delivery mode. Defaults to inexact (never throws, always allowed);
  /// upgraded to exact-while-idle once we confirm the OS permits exact alarms,
  /// so time-sensitive reminders (class start, 7:30 daily summary) fire on time
  /// instead of being batched/delayed by Doze. Falls back to inexact when the
  /// SCHEDULE_EXACT_ALARM permission isn't granted, so scheduling never fails.
  AndroidScheduleMode _scheduleMode =
      AndroidScheduleMode.inexactAllowWhileIdle;

  /// Payload of the notification the user last tapped (e.g. 'daily_agenda').
  /// The UI listens to this to deep-link to the right screen, then clears it.
  static final ValueNotifier<String?> selectedPayload =
      ValueNotifier<String?>(null);

  /// Payload used by the daily agenda summary notification.
  static const String dailyAgendaPayload = 'daily_agenda';

  /// Payload used by the daily learning-planner study reminder. Tapping it
  /// deep-links to the Planner tab.
  static const String studyReminderPayload = 'planner_study_reminder';

  /// Payload used by the attendance risk-alert notification.
  static const String attendanceRiskPayload = 'attendance_risk';

  /// Payload used by the per-class "starts soon" reminder. Tapping it should
  /// deep-link to the schedule/today view so the student can mark attendance —
  /// which is exactly what the notification body invites them to do.
  static const String classReminderPayload = 'class_reminder';

  /// Prefix for the after-class "mark attendance" nudge. The full payload is
  /// `attendance_checkin|<subjectId>|<slot>` where slot is the class start time
  /// (the occurrence key). A plain tap deep-links to the Attendance tab.
  static const String attendanceCheckInPrefix = 'attendance_checkin';

  /// Prefix set by [selectedPayload] when the user taps a Present/Absent action
  /// on the check-in notification: `attendance_mark|<present|absent>|<subjectId>|<slot>`.
  static const String attendanceMarkPrefix = 'attendance_mark';

  static const String _actionPresent = 'att_present';
  static const String _actionAbsent = 'att_absent';

  /// Parses an `attendance_mark|<status>|<subjectId>|<slot>` payload into its
  /// parts, or returns null if [payload] isn't a mark payload. Pure — unit
  /// tested. [slot] may be empty.
  static ({String status, String subjectId, String slot})? parseAttendanceMark(
      String payload) {
    if (!payload.startsWith('$attendanceMarkPrefix|')) return null;
    final parts = payload.split('|');
    // [prefix, status, subjectId, slot?]
    if (parts.length < 3) return null;
    final status = parts[1];
    if (status != 'present' && status != 'absent') return null;
    final subjectId = parts[2];
    if (subjectId.isEmpty) return null;
    final slot = parts.length >= 4 ? parts[3] : '';
    return (status: status, subjectId: subjectId, slot: slot);
  }

  static const _channelId = 'classtrack_reminders';
  static const _channelName = 'Class reminders';
  static const _channelDesc =
      'Reminders when a class is about to start and nudges to mark attendance.';

  // ---- Notification id partitioning ----------------------------------------
  // Each category gets its own disjoint band that is [_idBand] wide. The
  // per-entity component is a 20-bit hash (0.._idHashMask == 1,048,575), which
  // is always smaller than the band width, so a class reminder can NEVER share
  // an id with a task/exam/habit reminder. The previous scheme let class ids
  // grow to ~84M and overlap every other band, so a class and (say) an exam
  // could silently overwrite or cancel one another.
  static const int _idBand = 2000000;
  static const int _idHashMask = 0xFFFFF; // 1,048,575

  /// Stable 20-bit hash of [s], kept well under [_idBand].
  ///
  /// Uses FNV-1a over the string's UTF-16 code units so the id is byte-stable
  /// across app restarts and platforms. This is essential: the in-memory id
  /// tracking (`_classReminderIds`) is empty on a cold start, so the ONLY way a
  /// reschedule can cancel/overwrite the reminder scheduled by a previous run
  /// is if the same input always hashes to the same id. `String.hashCode` is
  /// not guaranteed by the Dart spec to be stable across executions (the VM may
  /// randomize its hash seed), which would silently orphan every previously
  /// scheduled reminder after a restart, so we compute the hash explicitly.
  static int _hash20(String s) {
    const int fnvOffsetBasis = 0x811c9dc5;
    const int fnvPrime = 0x01000193;
    var hash = fnvOffsetBasis;
    for (final unit in s.codeUnits) {
      hash = (hash ^ unit) * fnvPrime;
      hash &= 0xFFFFFFFF; // keep arithmetic within an unsigned 32-bit range
    }
    return hash & _idHashMask;
  }

  /// Notification-ID scheme version. Bump this whenever the id math below
  /// changes so [_migrateNotificationIdsIfNeeded] clears reminders scheduled
  /// under the old, now-uncancellable ids (otherwise old recurring reminders
  /// keep firing forever alongside the new ones).
  ///
  /// v3: class reminders now include the class start-time in their id hash, so
  /// two classes on the same weekday no longer collide. Old v2 ids (keyed by
  /// subject+weekday only) are cleared once on upgrade.
  /// v4: the per-entity hash switched from `String.hashCode` to an explicit
  /// FNV-1a hash for guaranteed cross-restart stability, which changes every
  /// numeric id once. Clear the v3 reminders so they can't linger un-cancelled.
  /// v5: the study reminder moved from band 8 to its own band 9; clear once so
  /// the old copy doesn't keep firing alongside the new one.
  static const int _idSchemeVersion = 5;
  static const String _idSchemeVersionKey = 'notif_id_scheme_version';

  /// In-flight initialisation, shared by concurrent callers so the plugin is
  /// initialised (and the id migration run) once, not once per caller.
  Future<void>? _initFuture;

  Future<void> init() {
    if (_ready) return Future.value();
    return _initFuture ??= _doInit().catchError((Object e, StackTrace st) {
      _initFuture = null; // allow a retry on the next call
      Error.throwWithStackTrace(e, st);
    });
  }

  Future<void> _doInit() async {
    tzdata.initializeTimeZones();
    // CRITICAL: without setting the local location, tz.local defaults to UTC,
    // so every zonedSchedule fires at the wrong wall-clock time (e.g. +5:30
    // off in India). Resolve the device's IANA zone and use it.
    try {
      final localZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localZone.identifier));
    } catch (_) {
      // Leave the default (UTC) if the platform can't report a zone; better
      // than crashing, and rare on real devices.
    }
    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_notify');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: handleResponse,
    );
    // Cold start: if the app was launched by tapping a notification, surface
    // its payload so the UI can deep-link once it's ready — ONCE. The plugin
    // keeps reporting the same launch tap for as long as the process lives
    // (and again if Android recreates the screen), which used to open the
    // Attendance page several times on top of itself.
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final resp = launch!.notificationResponse;
        if (resp != null && await _isNewLaunchTap(resp)) handleResponse(resp);
      }
    } catch (_) {/* launch details are best-effort */}
    await _refreshScheduleMode();
    await _migrateNotificationIdsIfNeeded();
    _ready = true;
  }

  static const String _launchSigKey = 'notif_launch_sig';
  static const String _launchAtKey = 'notif_launch_at';

  /// Re-delivered launch taps are ignored for this long. Every repeating
  /// notification fires at most once a day, so a genuinely NEW tap of the
  /// same notification can't land inside this window.
  static const Duration launchDedupeWindow = Duration(hours: 6);

  /// Pure rule behind [_isNewLaunchTap] — unit tested.
  @visibleForTesting
  static bool isNewLaunch({
    required String signature,
    required String? lastSignature,
    required DateTime? lastAt,
    required DateTime now,
  }) {
    if (lastSignature != signature || lastAt == null) return true;
    return now.difference(lastAt) >= launchDedupeWindow;
  }

  /// True the first time a given launch tap is seen (persisted, so it also
  /// survives the screen being recreated). Fails open: if storage is
  /// unavailable we handle the tap rather than drop it.
  Future<bool> _isNewLaunchTap(NotificationResponse resp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sig = '${resp.id}|${resp.actionId}|${resp.payload}';
      final atMs = prefs.getInt(_launchAtKey);
      final isNew = isNewLaunch(
        signature: sig,
        lastSignature: prefs.getString(_launchSigKey),
        lastAt: atMs == null ? null : DateTime.fromMillisecondsSinceEpoch(atMs),
        now: DateTime.now(),
      );
      if (isNew) {
        await prefs.setString(_launchSigKey, sig);
        await prefs.setInt(_launchAtKey, DateTime.now().millisecondsSinceEpoch);
      }
      return isNew;
    } catch (_) {
      return true;
    }
  }

  /// Turns a tapped notification (body OR an action button) into a
  /// [selectedPayload] the UI can act on. A Present/Absent action on the
  /// attendance check-in is rewritten to an `attendance_mark|…` payload so the
  /// app marks that class when it opens; every other tap forwards its payload.
  ///
  /// Static and shared: the push-messaging service initialises the SAME
  /// plugin, and whichever `initialize` ran last owned the tap callback. Its
  /// own callback ignored the Present/Absent buttons, so an action tap opened
  /// the page without marking. Both now route through this one handler.
  static void handleResponse(NotificationResponse resp) {
    final p = resp.payload;
    if (p == null || p.isEmpty) return;
    final action = resp.actionId;
    if (p.startsWith('$attendanceCheckInPrefix|') &&
        (action == _actionPresent || action == _actionAbsent)) {
      final status = action == _actionPresent ? 'present' : 'absent';
      // p == "attendance_checkin|<subjectId>|<slot>" → keep everything after
      // the prefix so the subjectId/slot are preserved.
      final rest = p.substring(attendanceCheckInPrefix.length + 1);
      selectedPayload.value = '$attendanceMarkPrefix|$status|$rest';
    } else {
      selectedPayload.value = p;
    }
  }

  /// One-time cleanup after an id-scheme change: cancel every locally scheduled
  /// notification once, so stale/duplicate reminders left under the previous
  /// (now-uncancellable) id scheme disappear. `reminderSyncProvider`
  /// reschedules everything under the new ids as soon as the home shell mounts.
  ///
  /// Device-global (notification ids are per-device, not per-account), so this
  /// intentionally uses an unscoped SharedPreferences key. Never throws — a
  /// failed run simply retries on the next launch.
  Future<void> _migrateNotificationIdsIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_idSchemeVersionKey) ?? 0;
      if (stored < _idSchemeVersion) {
        await _plugin.cancelAll();
        await prefs.setInt(_idSchemeVersionKey, _idSchemeVersion);
      }
    } catch (_) {/* best-effort; retried next launch */}
  }

  /// Checks whether the OS currently allows exact alarms and upgrades the
  /// delivery mode accordingly. Safe to call repeatedly; never throws.
  Future<void> _refreshScheduleMode() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return; // iOS: exact by nature.
      final canExact = await android.canScheduleExactNotifications() ?? false;
      _scheduleMode = canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      _scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  /// Whether the OS currently lets this app show notifications. Never throws.
  Future<bool> hasPermission() async {
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.areNotificationsEnabled() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return (await ios.checkPermissions())?.isEnabled ?? false;
    } catch (_) {/* treat as not granted */}
    return false;
  }

  /// Device-wide flag: the Android "Alarms & reminders" settings page has
  /// already been offered once.
  static const String _exactAlarmAskedKey = 'exact_alarm_asked';

  /// Offers the exact-alarm settings page at most ONCE per device, and only if
  /// exact alarms aren't already allowed. Opening it on every Enable tap made
  /// the app look like it was asking for permission again.
  Future<void> _askExactAlarmsOnce(
      AndroidFlutterLocalNotificationsPlugin? android) async {
    if (android == null) return;
    try {
      if (await android.canScheduleExactNotifications() ?? false) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_exactAlarmAskedKey) ?? false) return;
      await prefs.setBool(_exactAlarmAskedKey, true);
      await android.requestExactAlarmsPermission();
    } catch (_) {/* best-effort; unsupported on older OS versions */}
  }

  /// Ask the OS for permission (Android 13+ and iOS). If notifications are
  /// already allowed (e.g. the user tapped Allow on the launch prompt), the OS
  /// dialog is NOT shown again.
  Future<bool> requestPermissions() async {
    await init();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (await hasPermission()) {
      await _askExactAlarmsOnce(androidPlugin);
      await _refreshScheduleMode();
      return true;
    }
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final android = await androidPlugin?.requestNotificationsPermission();
    // Only the current platform's answer counts (the old `(ios ?? true) ||
    // (android ?? true)` was always true on Android, even after "Don't allow").
    final granted = ios ?? android ?? true;
    // Exact alarms make time-critical reminders fire on time. If declined we
    // keep the inexact fallback: scheduling still works, just less precisely.
    if (granted) await _askExactAlarmsOnce(androidPlugin);
    await _refreshScheduleMode();
    return granted;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          icon: 'ic_stat_notify',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Notification details for the after-class attendance check-in, with
  /// Present / Absent action buttons (Android). `showsUserInterface: true`
  /// launches the app when an action is tapped so the marking happens in the
  /// foreground isolate (where Firebase + the signed-in user are available);
  /// [_handleResponse] then records the class. iOS falls back to a plain tap.
  NotificationDetails get _checkInDetails => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          icon: 'ic_stat_notify',
          importance: Importance.high,
          priority: Priority.high,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(_actionPresent, '✔\uFE0F Present',
                icon: DrawableResourceAndroidBitmap('ic_action_present'),
                showsUserInterface: true),
            AndroidNotificationAction(_actionAbsent, '✖\uFE0F Absent',
                icon: DrawableResourceAndroidBitmap('ic_action_absent'),
                showsUserInterface: true),
          ],
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Deterministic notification id for a single recurring class reminder
  /// (class band = 1). Keyed by subject + weekday + start-time so a subject with
  /// two classes on the same weekday gets two distinct reminders instead of one
  /// silently overwriting the other. Stable across runs, so re-scheduling
  /// overwrites (rather than duplicates) the same reminder.
  @visibleForTesting
  static int classReminderId(String subjectId, int weekday0, String startTime) =>
      1 * _idBand + _hash20('$subjectId#$weekday0#$startTime');

  /// Schedule weekly reminders a few minutes before each recurring class.
  Future<void> scheduleForSubject(
    Subject subject,
    List<ClassSession> sessions, {
    int minutesBefore = 10,
    NotificationPrefs? prefs,
  }) async {
    await init();
    _scheduledClassSubjects.add(subject.id);

    // Cancel every reminder we previously scheduled for this subject before
    // re-scheduling. Sessions may have been edited (time/day changed) or
    // removed since the last sync; without this their old ids would linger and
    // keep firing, because the new ids no longer overwrite them.
    final previous = _classReminderIds[subject.id];
    if (previous != null) {
      for (final oldId in previous) {
        await _plugin.cancel(id: oldId);
      }
    }

    final scheduledIds = <int>{};
    for (final s in sessions) {
      if (!s.recurring || s.dayOfWeek == null) continue;
      final parts = s.startTime.split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]) ?? 9;
      final minute = int.tryParse(parts[1]) ?? 0;

      final when = _nextInstanceOfWeekdayTime(
        weekday0: s.dayOfWeek!,
        hour: hour,
        minute: minute,
        minutesBefore: minutesBefore,
      );

      // Keyed by subject + weekday + start-time so multiple classes on the same
      // weekday each get their own reminder instead of colliding on one id.
      final id = classReminderId(subject.id, s.dayOfWeek!, s.startTime);
      // Respect quiet hours: cancel any existing in-window reminder and skip.
      if (prefs != null && prefs.isQuietHour(when.hour)) {
        await _plugin.cancel(id: id);
        continue;
      }

      await _plugin.zonedSchedule(
        id: id,
        title: '${subject.name} starts soon',
        body: s.room != null && s.room!.isNotEmpty
            ? 'Starts at ${s.startTime} · Room ${s.room}. Tap to mark attendance.'
            : 'Starts at ${s.startTime}. Tap to mark attendance.',
        scheduledDate: when,
        notificationDetails: _details,
        androidScheduleMode: _scheduleMode,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: classReminderPayload,
      );
      scheduledIds.add(id);
    }
    _classReminderIds[subject.id] = scheduledIds;
  }

  /// After-class attendance check-in id (band 8). Keyed by subject + weekday +
  /// start + end time so every class slot gets its own nudge.
  @visibleForTesting
  static int attendanceCheckId(
          String subjectId, int weekday0, String startTime, String endTime) =>
      8 * _idBand + _hash20('$subjectId#$weekday0#$startTime#$endTime');

  /// After-class check-in id for a ONE-OFF (specific-date) class (band 8).
  /// Keyed by subject + ISO date + start/end time so each dated class gets a
  /// distinct nudge that never collides with the recurring (weekday-keyed) ids.
  @visibleForTesting
  static int attendanceCheckOnceId(
          String subjectId, String dateId, String startTime, String endTime) =>
      8 * _idBand + _hash20('$subjectId#once#$dateId#$startTime#$endTime');

  /// ISO "yyyy-MM-dd" for a date, without importing an intl formatter.
  static String _isoDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// Schedule a weekly "mark your attendance" nudge [minutesAfter] the end of
  /// each recurring class. The notification carries Present/Absent actions and,
  /// on a plain tap, deep-links to the Attendance tab. Idempotent: re-scheduling
  /// overwrites by id, and previously-scheduled ids for the subject are
  /// cancelled first so edited/removed sessions don't linger.
  Future<void> scheduleAttendanceCheckIns(
    Subject subject,
    List<ClassSession> sessions, {
    int minutesAfter = 5,
    NotificationPrefs? prefs,
  }) async {
    await init();
    _scheduledCheckSubjects.add(subject.id);

    final previous = _checkInIds[subject.id];
    if (previous != null) {
      for (final oldId in previous) {
        await _plugin.cancel(id: oldId);
      }
    }

    final scheduledIds = <int>{};
    for (final s in sessions) {
      final parts = s.endTime.split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]) ?? 9;
      final minute = int.tryParse(parts[1]) ?? 0;

      // Compute the fire time + a stable id for both recurring and one-off
      // classes. Recurring classes repeat weekly; one-off (specific-date)
      // classes fire once and are skipped once their time has passed.
      final int id;
      final tz.TZDateTime when;
      final bool repeatsWeekly;
      if (s.recurring && s.dayOfWeek != null) {
        // Fire minutesAfter the class END. Reuse the weekday-aligned helper with
        // a negative "before" so it adds the delay instead of subtracting it.
        when = _nextInstanceOfWeekdayTime(
          weekday0: s.dayOfWeek!,
          hour: hour,
          minute: minute,
          minutesBefore: -minutesAfter,
        );
        id = attendanceCheckId(
            subject.id, s.dayOfWeek!, s.startTime, s.endTime);
        repeatsWeekly = true;
      } else if (!s.recurring && s.specificDate != null) {
        final d = s.specificDate!;
        when = tz.TZDateTime(tz.local, d.year, d.month, d.day, hour, minute)
            .add(Duration(minutes: minutesAfter));
        // A one-off class whose check-in time is already past can never fire
        // again — don't schedule it in the past.
        if (when.isBefore(tz.TZDateTime.now(tz.local))) continue;
        id = attendanceCheckOnceId(
            subject.id, _isoDate(d), s.startTime, s.endTime);
        repeatsWeekly = false;
      } else {
        continue;
      }

      if (prefs != null && prefs.isQuietHour(when.hour)) {
        await _plugin.cancel(id: id);
        continue;
      }

      await _plugin.zonedSchedule(
        id: id,
        title: 'How was ${subject.name}?',
        body: 'Tap Present or Absent to mark your attendance.',
        scheduledDate: when,
        notificationDetails: _checkInDetails,
        androidScheduleMode: _scheduleMode,
        // Recurring classes repeat weekly at the same weekday+time; a one-off
        // fires exactly once (no repeat component).
        matchDateTimeComponents:
            repeatsWeekly ? DateTimeComponents.dayOfWeekAndTime : null,
        // slot = the class start time, matching the per-occurrence key used
        // everywhere else so marking from the notification never double-counts.
        payload: '$attendanceCheckInPrefix|${subject.id}|${s.startTime}',
      );
      scheduledIds.add(id);
    }
    _checkInIds[subject.id] = scheduledIds;
  }

  /// Cancel a subject's after-class check-ins (on delete or toggle-off).
  Future<void> cancelAttendanceCheckInsForSubject(String subjectId) async {
    await init();
    final ids = _checkInIds.remove(subjectId);
    if (ids != null) {
      for (final id in ids) {
        await _plugin.cancel(id: id);
      }
    }
    _scheduledCheckSubjects.remove(subjectId);
  }

  /// Reconcile scheduled check-ins against the subjects that still exist,
  /// cancelling any for deleted subjects. Pass an empty set to cancel all.
  Future<void> pruneAttendanceCheckIns(Set<String> currentSubjectIds) async {
    await init();
    final stale = _scheduledCheckSubjects.difference(currentSubjectIds);
    for (final subjectId in stale) {
      final ids = _checkInIds.remove(subjectId);
      if (ids != null) {
        for (final id in ids) {
          await _plugin.cancel(id: id);
        }
      }
    }
    _scheduledCheckSubjects
      ..clear()
      ..addAll(currentSubjectIds);
  }

  /// Task/course/video id band = 2.
  int _idForTask(String taskId) => 2 * _idBand + _hash20(taskId);

  /// Schedule a one-off reminder for each task that has a future due date.
  /// Fires [minutesBefore] before 9:00 AM on the due date.
  ///
  /// Also CANCELS the reminder of every task that no longer qualifies — done
  /// (e.g. ticked via the AI chat), due date removed or moved into the past or
  /// quiet hours, or deleted (on another device) — so a stale reminder can
  /// never fire for a task the student already dealt with.
  Future<void> scheduleForTasks(
    List<TaskItem> tasks, {
    int minutesBefore = 10,
    NotificationPrefs? prefs,
  }) async {
    await init();
    final now = tz.TZDateTime.now(tz.local);
    for (final t in tasks) {
      final id = _idForTask(t.id);
      if (t.done || t.dueDate == null) {
        await _plugin.cancel(id: id);
        continue;
      }
      final due = t.dueDate!;
      // Items with a specific time-of-day (events, timed deadlines) remind
      // [minutesBefore] their start. All-day items (stored at midnight) keep
      // the 9:00 AM morning nudge so they don't fire at 00:00.
      final hasTime = !(due.hour == 0 && due.minute == 0);
      final base = hasTime
          ? tz.TZDateTime(
              tz.local, due.year, due.month, due.day, due.hour, due.minute)
          : tz.TZDateTime(tz.local, due.year, due.month, due.day, 9, 0);
      var when = base.subtract(Duration(minutes: minutesBefore));
      if (when.isBefore(now) ||
          (prefs != null && prefs.isQuietHour(when.hour))) {
        await _plugin.cancel(id: id);
        continue;
      }
      final label = switch (t.type) {
        TaskType.event => 'Event',
        TaskType.video => 'Video planned',
        TaskType.task => 'Task due',
        TaskType.assignment => 'Assignment due',
      };
      await _plugin.zonedSchedule(
        id: id,
        title: '$label: ${t.title}',
        body: t.hasLink ? 'Tap to open the link and get started.' : 'Due today.',
        scheduledDate: when,
        notificationDetails: _details,
        androidScheduleMode: _scheduleMode,
      );
    }
    // Tasks that existed at the last sync but are gone now (deleted on
    // another device, cleared by the AI chat…): cancel their reminders.
    final current = {for (final t in tasks) t.id};
    for (final gone in _taskReminderIds.difference(current)) {
      await _plugin.cancel(id: _idForTask(gone));
    }
    _taskReminderIds
      ..clear()
      ..addAll(current);
  }

  /// Task ids seen at the last [scheduleForTasks] run.
  final Set<String> _taskReminderIds = {};

  /// Exam id bands: day-of = 3, eve-before = 4.
  int _idForExamDay(String examId) => 3 * _idBand + _hash20(examId);
  int _idForExamEve(String examId) => 4 * _idBand + _hash20(examId);

  /// Schedule two reminders per upcoming exam:
  ///  • a "starts soon" reminder [minutesBefore] the exam time, and
  ///  • an evening-before revision nudge at 18:00.
  Future<void> scheduleForExams(
    List<Exam> exams, {
    int minutesBefore = 30,
    NotificationPrefs? prefs,
  }) async {
    await init();
    final now = tz.TZDateTime.now(tz.local);
    for (final e in exams) {
      final timeLabel =
          '${e.date.hour.toString().padLeft(2, '0')}:${e.date.minute.toString().padLeft(2, '0')}';

      final soon = tz.TZDateTime(
        tz.local,
        e.date.year,
        e.date.month,
        e.date.day,
        e.date.hour,
        e.date.minute,
      ).subtract(Duration(minutes: minutesBefore));
      final quietSoon = prefs != null && prefs.isQuietHour(soon.hour);
      if (soon.isAfter(now) && !quietSoon) {
        await _plugin.zonedSchedule(
          id: _idForExamDay(e.id),
          title: 'Exam soon: ${e.title}',
          body: e.room != null && e.room!.isNotEmpty
              ? 'Starts at $timeLabel · Room ${e.room}. Good luck!'
              : 'Starts at $timeLabel. Good luck!',
          scheduledDate: soon,
          notificationDetails: _details,
          androidScheduleMode: _scheduleMode,
        );
      } else if (quietSoon) {
        await _plugin.cancel(id: _idForExamDay(e.id));
      }

      final eve = tz.TZDateTime(
        tz.local,
        e.date.year,
        e.date.month,
        e.date.day,
        18,
        0,
      ).subtract(const Duration(days: 1));
      final quietEve = prefs != null && prefs.isQuietHour(eve.hour);
      if (eve.isAfter(now) && !quietEve) {
        await _plugin.zonedSchedule(
          id: _idForExamEve(e.id),
          title: 'Exam tomorrow: ${e.title}',
          body: 'Your exam is tomorrow at $timeLabel. Time for a final revision!',
          scheduledDate: eve,
          notificationDetails: _details,
          androidScheduleMode: _scheduleMode,
        );
      } else if (quietEve) {
        await _plugin.cancel(id: _idForExamEve(e.id));
      }
    }
  }

  Future<void> cancelForSubject(String subjectId) async {
    await init();
    final ids = _classReminderIds.remove(subjectId);
    if (ids != null) {
      for (final id in ids) {
        await _plugin.cancel(id: id);
      }
    }
    _scheduledClassSubjects.remove(subjectId);
  }

  /// Reconcile scheduled class reminders against the set of subjects that still
  /// exist. Cancels reminders for any subject that has since been deleted (so
  /// its reminders stop firing), then records [currentSubjectIds] as the new
  /// baseline. Pass an empty set to cancel everything we've tracked.
  Future<void> pruneClassReminders(Set<String> currentSubjectIds) async {
    await init();
    final stale = _scheduledClassSubjects.difference(currentSubjectIds);
    for (final subjectId in stale) {
      final ids = _classReminderIds.remove(subjectId);
      if (ids != null) {
        for (final id in ids) {
          await _plugin.cancel(id: id);
        }
      }
    }
    _scheduledClassSubjects
      ..clear()
      ..addAll(currentSubjectIds);
  }

  /// Cancel a task's scheduled reminder (on delete or when marked done).
  Future<void> cancelTask(String taskId) async {
    await init();
    await _plugin.cancel(id: _idForTask(taskId));
  }

  /// Cancel an exam's scheduled reminders (both the day-of and eve-before).
  Future<void> cancelExam(String examId) async {
    await init();
    await _plugin.cancel(id: _idForExamDay(examId));
    await _plugin.cancel(id: _idForExamEve(examId));
  }

  /// Habit reminder id band = 5.
  int _idForHabit(String habitId) => 5 * _idBand + _hash20(habitId);

  /// Schedule a daily reminder for each habit that has a reminder time set;
  /// cancels reminders for habits that have theirs turned off.
  Future<void> scheduleForHabits(List<Habit> habits,
      {NotificationPrefs? prefs}) async {
    await init();
    final now = tz.TZDateTime.now(tz.local);
    for (final h in habits) {
      final id = _idForHabit(h.id);
      if (!h.hasReminder) {
        await _plugin.cancel(id: id);
        continue;
      }
      var when = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        h.reminderHour,
        h.reminderMinute,
      );
      if (when.isBefore(now)) when = when.add(const Duration(days: 1));
      if (prefs != null && prefs.isQuietHour(when.hour)) {
        await _plugin.cancel(id: id);
        continue;
      }
      await _plugin.zonedSchedule(
        id: id,
        title: 'Habit reminder: ${h.title}',
        body: "Keep your streak alive — don't forget today!",
        scheduledDate: when,
        notificationDetails: _details,
        androidScheduleMode: _scheduleMode,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> cancelHabit(String habitId) async {
    await init();
    await _plugin.cancel(id: _idForHabit(habitId));
  }

  /// Daily agenda summary id (single, repeating) — its own slot (band 6),
  /// above every hashed band.
  static const int _idDailySummary = 6 * _idBand;

  /// Schedules (or reschedules) the once-daily agenda summary at [hour]:[minute].
  /// Repeats every day via [DateTimeComponents.time].
  Future<void> scheduleDailySummary({
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    await init();
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: _idDailySummary,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: _details,
      androidScheduleMode: _scheduleMode,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: dailyAgendaPayload,
    );
  }

  Future<void> cancelDailySummary() async {
    await init();
    await _plugin.cancel(id: _idDailySummary);
  }

  /// Daily learning-planner study reminder id — its own band (9). It used to
  /// sit at 8 * _idBand, inside the attendance check-in band, so a check-in
  /// whose hash was 0 could overwrite or cancel it.
  static const int _idStudyReminder = 9 * _idBand;

  /// Schedules (or reschedules) a once-daily study reminder at [hour]:[minute]
  /// for the learning planner. Repeats daily via [DateTimeComponents.time].
  Future<void> scheduleStudyReminder({
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    await init();
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: _idStudyReminder,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: _details,
      androidScheduleMode: _scheduleMode,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: studyReminderPayload,
    );
  }

  Future<void> cancelStudyReminder() async {
    await init();
    await _plugin.cancel(id: _idStudyReminder);
  }

  /// Attendance risk-alert id (single, one-shot per reschedule) — band 7, above
  /// every hashed band and the daily summary slot.
  static const int _idAttendanceRisk = 7 * _idBand;

  /// Schedules a one-off attendance risk alert at [hour]:[minute] (today if
  /// still ahead, otherwise tomorrow). Unlike the daily summary this does NOT
  /// repeat — the reminder scheduler recomputes the risk and reschedules it
  /// whenever attendance or the timetable changes, so the body is always fresh.
  /// Suppressed (and any pending one cancelled) during quiet hours.
  Future<void> scheduleAttendanceRiskAlert({
    required int hour,
    required int minute,
    required String title,
    required String body,
    NotificationPrefs? prefs,
  }) async {
    await init();
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    if (prefs != null && prefs.isQuietHour(when.hour)) {
      await _plugin.cancel(id: _idAttendanceRisk);
      return;
    }
    await _plugin.zonedSchedule(
      id: _idAttendanceRisk,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: _details,
      androidScheduleMode: _scheduleMode,
      payload: attendanceRiskPayload,
    );
  }

  Future<void> cancelAttendanceRiskAlert() async {
    await init();
    await _plugin.cancel(id: _idAttendanceRisk);
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
    // Reset the in-memory baseline so a stale set from the previous account
    // can't suppress the next user's prune/reschedule on a shared device.
    _scheduledClassSubjects.clear();
    _classReminderIds.clear();
    _scheduledCheckSubjects.clear();
    _checkInIds.clear();
  }

  tz.TZDateTime _nextInstanceOfWeekdayTime({
    required int weekday0,
    required int hour,
    required int minute,
    required int minutesBefore,
  }) =>
      nextInstanceOfWeekdayTime(
        now: tz.TZDateTime.now(tz.local),
        weekday0: weekday0,
        hour: hour,
        minute: minute,
        minutesBefore: minutesBefore,
      );

  /// Returns the next reminder instant: [minutesBefore] before the next
  /// occurrence of a class on [weekday0] (0=Mon..6=Sun) at [hour]:[minute].
  ///
  /// The weekday is aligned to the *class start time* first, and only then is
  /// the lead subtracted. Doing it the other way round is wrong for classes
  /// near midnight: e.g. a 00:05 class with a 10-minute lead reminds at 23:55
  /// the previous day, so subtracting first shifts the timestamp onto the wrong
  /// weekday. Aligning the reminder's own weekday to the class weekday then
  /// lands it ~24h late and mis-anchors the weekly repeat
  /// ([DateTimeComponents.dayOfWeekAndTime] keys off this instant's weekday).
  @visibleForTesting
  static tz.TZDateTime nextInstanceOfWeekdayTime({
    required tz.TZDateTime now,
    required int weekday0,
    required int hour,
    required int minute,
    required int minutesBefore,
  }) {
    // Align to the class start on the correct weekday whose reminder is still
    // in the future (DateTime.weekday is 1..7, weekday0 is 0..6).
    var classStart =
        tz.TZDateTime(now.location, now.year, now.month, now.day, hour, minute);
    while ((classStart.weekday - 1) != weekday0 ||
        classStart.subtract(Duration(minutes: minutesBefore)).isBefore(now)) {
      classStart = classStart.add(const Duration(days: 1));
    }
    // Now subtract the lead — this may legitimately cross back over midnight
    // (and onto the previous weekday), which is exactly the desired reminder.
    return classStart.subtract(Duration(minutes: minutesBefore));
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
