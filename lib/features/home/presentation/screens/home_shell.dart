import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/utils/shared_intake.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../../services/analytics_service.dart';
import '../../../../services/calendar_auto_sync.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/push_deep_link.dart';
import '../../../../services/push_messaging_service.dart';
import '../../../../services/reminder_scheduler.dart';
import '../../../../services/home_widget_service.dart';
import '../../../insights/presentation/screens/daily_agenda_screen.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../schedule/presentation/screens/schedule_screen.dart';
import '../../../schedule/presentation/screens/edit_session_screen.dart';
import '../../../import/presentation/screens/import_screen.dart';
import '../../../subjects/presentation/screens/edit_subject_screen.dart';
import '../../../tasks/presentation/screens/tasks_screen.dart';
import '../../../tasks/presentation/screens/share_link_handler.dart';
import '../../../opportunities/domain/resource.dart';
import '../../../opportunities/presentation/providers/opportunities_providers.dart';
import '../../../opportunities/presentation/screens/opportunities_screen.dart';
import '../../../opportunities/presentation/screens/resource_detail_screen.dart';
import '../../../attendance/presentation/screens/attendance_screen.dart';
import '../../../attendance/presentation/providers/attendance_providers.dart';
import '../../../learning_planner/presentation/screens/planner_home_screen.dart';
import '../../../learning_planner/presentation/providers/learning_planner_providers.dart';
import '../../../attendance/domain/attendance_record.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../exams/presentation/screens/exams_screen.dart';
import '../../../expenses/presentation/screens/expenses_screen.dart';
import '../../../grades/presentation/screens/grades_screen.dart';
import '../../../habits/presentation/screens/habits_screen.dart';
import '../../../notes/presentation/screens/notes_screen.dart';
import '../../../tips/presentation/providers/tips_providers.dart';
import '../../../tips/presentation/screens/tips_screen.dart';
import '../widgets/home_tour.dart';
import 'dashboard_screen.dart';

/// Opens the "quick add" menu triggered by the center FAB. Available app-wide.
enum _QuickAddAction {
  task,
  classSession,
  subject,
  importTimetable,
  exam,
  grade,
  note,
  habit,
  expense,
}

Future<void> showQuickAddSheet(BuildContext context) async {
  final action = await showModalBottomSheet<_QuickAddAction>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      Widget option({
        required IconData icon,
        required Color color,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
      }) {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          onTap: onTap,
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          title: Text(title, style: theme.textTheme.titleMedium),
          subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
          trailing: const Icon(Icons.chevron_right_rounded),
        );
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: theme.dividerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Text('Quick add', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
              option(
                icon: Icons.check_circle_outline_rounded,
                color: AppColors.primary,
                title: 'New task',
                subtitle: 'Assignment, deadline, event or video',
                onTap: () => Navigator.pop(ctx, _QuickAddAction.task),
              ),
              option(
                icon: Icons.calendar_today_rounded,
                color: AppColors.info,
                title: 'New class',
                subtitle: 'Add a session to your timetable',
                onTap: () => Navigator.pop(ctx, _QuickAddAction.classSession),
              ),
              option(
                icon: Icons.menu_book_rounded,
                color: AppColors.coral,
                title: 'New subject',
                subtitle: 'Track attendance for a course',
                onTap: () => Navigator.pop(ctx, _QuickAddAction.subject),
              ),
              option(
                icon: Icons.document_scanner_rounded,
                color: AppColors.info,
                title: 'Import timetable',
                subtitle: 'Scan a photo, PDF or paste text with AI',
                onTap: () => Navigator.pop(ctx, _QuickAddAction.importTimetable),
              ),
              option(
                icon: Icons.event_note_rounded,
                color: AppColors.danger,
                title: 'New exam',
                subtitle: 'Add a test with a live countdown',
                onTap: () => Navigator.pop(ctx, _QuickAddAction.exam),
              ),
              option(
                icon: Icons.school_rounded,
                color: AppColors.primary,
                title: 'Log grade',
                subtitle: 'Record a mark and update your GPA',
                onTap: () => Navigator.pop(ctx, _QuickAddAction.grade),
              ),
              option(
                icon: Icons.sticky_note_2_rounded,
                color: AppColors.info,
                title: 'New note',
                subtitle: 'Jot down a lecture note or idea',
                onTap: () => Navigator.pop(ctx, _QuickAddAction.note),
              ),
              option(
                icon: Icons.local_fire_department_rounded,
                color: AppColors.coral,
                title: 'New habit',
                subtitle: 'Build a streak you can keep',
                onTap: () => Navigator.pop(ctx, _QuickAddAction.habit),
              ),
              option(
                icon: Icons.account_balance_wallet_rounded,
                color: AppColors.success,
                title: 'Add expense',
                subtitle: 'Log spending and track your budget',
                onTap: () => Navigator.pop(ctx, _QuickAddAction.expense),
              ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  // Open the chosen editor only AFTER the quick-add sheet has fully closed, so
  // the two sheet animations never overlap (which felt laggy / janky before).
  if (action == null || !context.mounted) return;

  // Feature-usage analytics: which quick-add option was used.
  ProviderScope.containerOf(context, listen: false)
      .read(analyticsProvider)
      .quickAdd(action.name);

  Future<void> openSheet(Widget sheet) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => sheet,
      );

  Future<void> openScreen(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  switch (action) {
    case _QuickAddAction.task:
      await openSheet(const TaskEditorSheet());
      break;
    case _QuickAddAction.exam:
      await openSheet(const ExamEditorSheet());
      break;
    case _QuickAddAction.grade:
      await openSheet(const GradeEditorSheet());
      break;
    case _QuickAddAction.habit:
      await openSheet(const HabitEditorSheet());
      break;
    case _QuickAddAction.expense:
      await openSheet(const ExpenseEditorSheet());
      break;
    case _QuickAddAction.classSession:
      await openScreen(const EditSessionScreen());
      break;
    case _QuickAddAction.subject:
      await openScreen(const EditSubjectScreen());
      break;
    case _QuickAddAction.importTimetable:
      await openScreen(const ImportScreen());
      break;
    case _QuickAddAction.note:
      await openScreen(const NoteEditorScreen());
      break;
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;

  /// Targets highlighted by the first-run home tour.
  final GlobalKey _fabKey = GlobalKey();
  final GlobalKey _navKey = GlobalKey();

  /// Guards against showing the tour twice at once.
  bool _tourShowing = false;

  /// Live subscription to links/text shared into the app while it's running.
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  /// Periodic check that fires the daily 7 PM Google auto-sync while the app is
  /// open across the trigger time. Self-gated in [CalendarAutoSyncController] to
  /// run at most once per day.
  Timer? _autoSyncTimer;

  /// Guards against opening the share sheet twice for the same share (the
  /// initial-media and stream callbacks can otherwise overlap).
  bool _handlingShare = false;

  /// Signature + time of the last attendance mark applied from a notification
  /// action, used to ignore a re-delivered/replayed identical action so it
  /// can't double-count during the cold-start window.
  String? _lastMarkSig;
  DateTime? _lastMarkAt;

  /// True while the AttendanceScreen route opened from a Present/Absent
  /// notification action is still on the stack. Guards against pushing it
  /// again for a re-delivered/replayed action tap (Android can deliver the
  /// same action response several times), which otherwise stacked multiple
  /// identical routes so the user had to press back once per copy.
  bool _attendanceMarkRouteOpen = false;

  /// Signature of the last shared payload we actually handled, persisted so a
  /// stale cold-start re-delivery of the same link (see [SharedIntake]) is not
  /// processed again. `null` until loaded from disk.
  String? _lastHandledShare;

  /// SharedPreferences key backing [_lastHandledShare]. Device-global (share
  /// intake is not user-scoped) so it works signed-out too.
  static const String _lastSharePrefsKey = 'last_handled_share_sig';

  static const _screens = [
    DashboardScreen(),
    ScheduleScreen(),
    OpportunitiesScreen(),
    PlannerHomeScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deep-link when the user taps the daily-agenda notification (foreground
    // tap or cold-start launch handled in NotificationService).
    NotificationService.selectedPayload.addListener(_onNotificationPayload);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _onNotificationPayload());
    _initShareIntake();
    // Kick the daily Google auto-sync check on launch, then re-check every 15
    // minutes so it also fires if the app is left open across 7 PM. The
    // controller self-gates (once per day, on/after 7 PM, connected accounts).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoSync());
    _autoSyncTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _maybeAutoSync(),
    );
    // NOTE: The first-run coach-mark tour is NO LONGER auto-launched on
    // startup. On some devices/renderers (e.g. Impeller/Vulkan) the root
    // overlay could fail to lay out and leave a full-screen scrim that blocked
    // all input on Home. To guarantee the app is always usable on launch we
    // mark the tour as seen instead; users can still replay it on demand from
    // Settings → "Show app tour" (which flips the flag and starts it via the
    // listener in build()).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(homeTourDoneProvider)) {
        ref.read(homeTourDoneProvider.notifier).complete();
      }
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        if (ref.read(shouldShowTipsPromptProvider)) {
          _showTipsPrompt();
        }
      });
    });
  }

  /// Auto-opens the "✨ Tips & Tricks" page once, for returning users who have
  /// been using ClassTrack for 7+ days but still have features left to try.
  Future<void> _showTipsPrompt() async {
    if (!mounted) return;
    // Persist immediately so it can never fire twice, even if navigation is
    // interrupted.
    await ref.read(tipsPromptShownProvider.notifier).markShown();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TipsScreen()),
    );
  }

  /// Shows the home walkthrough as a safe, dismissible bottom sheet and marks
  /// it seen when closed.
  Future<void> _startTour() async {
    if (!mounted || _tourShowing) return;
    _tourShowing = true;
    await showHomeTour(
      context,
      steps: const [
        TourStep(
          title: 'Welcome to ClassTrack 👋',
          body:
              "Here's a quick tour of the essentials. You can skip anytime.",
          icon: Icons.waving_hand_rounded,
        ),
        TourStep(
          title: 'Move around',
          body:
              'Switch between Home, Schedule, Explore and Planner from '
              'the bar at the bottom — it stays with you everywhere.',
          icon: Icons.dashboard_rounded,
        ),
        TourStep(
          title: 'Add anything, fast',
          body:
              'Tap the + button to quickly add a task, class, event, exam, '
              'grade, note, habit or expense.',
          icon: Icons.add_circle_rounded,
        ),
      ],
      onFinish: () {
        _tourShowing = false;
        if (mounted) ref.read(homeTourDoneProvider.notifier).complete();
      },
    );
  }

  /// Listens for URLs/text shared into ClassTrack (Android/iOS share sheet) and
  /// opens the editable "New item" sheet. Mobile-only; guarded so web/desktop
  /// or a plugin hiccup can never crash the shell.
  void _initShareIntake() {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      // Load the last-handled signature first so the very first cold-start
      // delivery can be de-duplicated against it.
      SharedPreferences.getInstance().then((prefs) {
        _lastHandledShare = prefs.getString(_lastSharePrefsKey);
      }).catchError((_) {});

      // Live shares received while the app is running are always genuine.
      _shareSub = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen((files) => _onShared(files, isColdStart: false),
              onError: (_) {});
      // A share that cold-started the app. Some launchers re-attach the
      // original ACTION_SEND intent to the task, so this can also fire on a
      // plain relaunch — [_onShared] de-duplicates those.
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        if (files.isNotEmpty) {
          _onShared(files, isColdStart: true);
        }
        // Always clear the plugin's cached initial media so it can't be
        // re-emitted to a future engine attach within this process.
        ReceiveSharingIntent.instance.reset();
      }).catchError((_) {});
    } catch (_) {
      // Platform channel unavailable — ignore, sharing is a bonus path.
    }
  }

  /// Persists [signature] as the most recently handled share so an identical
  /// cold-start re-delivery is ignored next time.
  Future<void> _rememberHandledShare(String signature) async {
    _lastHandledShare = signature;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSharePrefsKey, signature);
    } catch (_) {/* best-effort */}
  }

  /// Opens the pre-filled "New item" sheet for the first text/URL item shared.
  void _onShared(List<SharedMediaFile> files, {required bool isColdStart}) {
    if (files.isEmpty || !mounted || _handlingShare) return;
    final shared = files.firstWhere(
      (f) => f.type == SharedMediaType.text || f.type == SharedMediaType.url,
      orElse: () => files.first,
    );
    final text = shared.path.trim();
    if (text.isEmpty) return;
    // Skip a stale cold-start re-delivery of a link we already handled.
    if (!SharedIntake.shouldHandle(
      text: text,
      isColdStart: isColdStart,
      lastHandled: _lastHandledShare,
    )) {
      return;
    }
    final signature = SharedIntake.signature(text);
    _handlingShare = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _handlingShare = false;
        return;
      }
      try {
        await openSharedLinkEditor(context, text);
        // Record only after the sheet was actually presented, so a delivery
        // that raced with a transient unmount (and never showed a sheet) can
        // still be retried — while a later cold-start re-delivery of this same
        // link is recognised as already-handled and ignored.
        await _rememberHandledShare(signature);
      } finally {
        _handlingShare = false;
      }
    });
  }

  /// Fires the daily Google Calendar/Tasks auto-sync if it's due. Safe to call
  /// often — the controller runs the actual sync at most once per day.
  void _maybeAutoSync() {
    if (!mounted) return;
    ref.read(calendarAutoSyncProvider).maybeSync();
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _autoSyncTimer?.cancel();
    NotificationService.selectedPayload.removeListener(_onNotificationPayload);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Deep-links in response to a tapped notification, then clears the pending
  /// payload so it only fires once.
  ///  • daily-agenda summary  → the Daily agenda screen.
  ///  • class "starts soon"   → the Schedule tab, where attendance is marked
  ///    (the reminder body invites the student to "mark attendance").
  ///  • attendance risk alert → the Schedule tab as well.
  void _onNotificationPayload() {
    final payload = NotificationService.selectedPayload.value;
    if (payload == null) return;

    // Attendance check-in: a Present/Absent action was tapped. Mark that class
    // occurrence (today) and confirm with a snackbar.
    final mark = NotificationService.parseAttendanceMark(payload);
    if (mark != null) {
      NotificationService.selectedPayload.value = null;
      final status = mark.status == 'present'
          ? AttendanceStatus.present
          : AttendanceStatus.absent;
      // De-duplicate re-delivered action taps. Android can deliver the same
      // notification-action response more than once (and the cold-start launch
      // path can replay it), which — before the records stream has loaded —
      // would each be treated as a fresh mark and over-count. Ignore an
      // identical mark seen within a short window; the write itself is also
      // idempotent once records are loaded, so this only guards the cold window.
      final now = DateTime.now();
      final sig = '${mark.subjectId}|${mark.slot}|${mark.status}';
      final isDuplicate = sig == _lastMarkSig &&
          _lastMarkAt != null &&
          now.difference(_lastMarkAt!) < const Duration(seconds: 5);
      _lastMarkSig = sig;
      _lastMarkAt = now;
      if (!isDuplicate) {
        ref.read(attendanceControllerProvider).setForOccurrence(
              mark.subjectId,
              now,
              mark.slot,
              status,
            );
      }
      // Only confirm + navigate for a genuine (non-replayed) action tap, and
      // never stack a second AttendanceScreen on top of one already opened
      // this way. Android re-delivers the same action response (and the
      // cold-start path replays it); without these guards each delivery
      // pushed another AttendanceScreen, so returning Home needed one back
      // press per duplicated route ("have to tap back 3-4 times").
      if (isDuplicate || _attendanceMarkRouteOpen) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final name = ref.read(subjectsByIdProvider)[mark.subjectId]?.name;
        final label = name != null && name.isNotEmpty ? ' for $name' : '';
        // De-duplicating feedback: Android can deliver the same action response
        // more than once, and re-showing an identical confirmation made the bar
        // visibly flash.
        showQuickFeedback(
            context,
            status == AttendanceStatus.present
                ? 'Marked present$label ✅'
                : 'Marked absent$label');
        setState(() => _index = 0);
        _attendanceMarkRouteOpen = true;
        Navigator.of(context)
            .push(
              MaterialPageRoute(builder: (_) => const AttendanceScreen()),
            )
            .whenComplete(() => _attendanceMarkRouteOpen = false);
      });
      return;
    }

    // Plain tap on the check-in notification → open the Attendance tab to mark.
    if (payload.startsWith('${NotificationService.attendanceCheckInPrefix}|')) {
      NotificationService.selectedPayload.value = null;
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AttendanceScreen()),
        );
      }
      return;
    }

    if (payload == NotificationService.dailyAgendaPayload) {
      NotificationService.selectedPayload.value = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DailyAgendaScreen()),
        );
      });
      return;
    }

    if (payload == NotificationService.classReminderPayload ||
        payload == NotificationService.attendanceRiskPayload) {
      NotificationService.selectedPayload.value = null;
      // Schedule tab (index 1) lists today's classes with their mark-attendance
      // controls.
      if (mounted) setState(() => _index = 1);
      return;
    }

    if (payload == NotificationService.studyReminderPayload) {
      NotificationService.selectedPayload.value = null;
      // Planner tab (index 3) — the Today card shows what's due.
      if (mounted) setState(() => _index = 3);
      return;
    }

    // CMS push deep links (`resource:<id>`, `tab:<name>`).
    final link = PushDeepLink.parse(payload);
    if (link != null) {
      NotificationService.selectedPayload.value = null;
      switch (link) {
        case TabDeepLink(:final index):
          if (mounted) setState(() => _index = index);
        case ResourceDeepLink(:final resourceId):
          _openResourceFromPush(resourceId);
      }
    }
  }

  /// Guards against Android re-delivering the same push tap and stacking two
  /// detail pages.
  String? _openingResourceId;

  /// Loads the pushed resource and opens its detail page on top of the
  /// Explore tab (so Back lands somewhere related). Falls back to the Explore
  /// feed with a message if it was removed / unpublished or can't be loaded.
  Future<void> _openResourceFromPush(String id) async {
    if (_openingResourceId == id) return;
    _openingResourceId = id;
    try {
      if (mounted) setState(() => _index = 2);
      Resource? r;
      try {
        r = await ref
            .read(resourceRepositoryProvider)
            .watchById(id)
            .first
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        r = null; // offline / timeout / permission — fall through.
      }
      if (!mounted) return;
      if (r == null || !r.isVisibleToStudents) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("That post isn't available anymore.")));
        return;
      }
      final resource = r;
      ref.read(analyticsProvider).log('push_opened', {
        'id': resource.id,
        'type': resource.type.key,
      });
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ResourceDetailScreen(resource: resource)));
    } finally {
      _openingResourceId = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user returns to the app, re-check the store entitlement with a
    // forced (cache-invalidating) fetch so an expired, cancelled or refunded
    // subscription stops showing Pro promptly instead of lingering.
    if (state == AppLifecycleState.resumed) {
      ref.read(subscriptionServiceProvider).refresh(invalidateCache: true);
      // Returning to the app is a good moment to run the daily Google sync if
      // it's now due (e.g. the app was backgrounded before 7 PM).
      _maybeAutoSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Replay support: when the tour is re-armed from Settings (flag flips back
    // to false), show it again.
    ref.listen<bool>(homeTourDoneProvider, (prev, next) {
      if (next == false && !_tourShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _startTour());
      }
    });
    // Keep task + exam reminders in sync with the latest data (no-op unless
    // the user has enabled reminders from Settings).
    ref.watch(reminderSyncProvider);
    // Schedule/cancel the daily learning-planner study reminder.
    ref.watch(plannerReminderSyncProvider);
    // Keep RevenueCat's identity tied to the signed-in Firebase user.
    ref.watch(subscriptionAuthLinkProvider);
    // Keep the device subscribed to its profile country's push topic.
    ref.watch(pushCountryTopicSyncProvider);
    // Keep the home-screen widget's "today" snapshot fresh.
    ref.watch(homeWidgetSyncProvider);
    return PopScope(
      // Never let the root route be popped into an empty Navigator (which shows
      // a blank/black screen). On non-Home tabs the back button returns to
      // Home; on Home it backgrounds/exits the app via the platform.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) {
          setState(() => _index = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        extendBody: true,
        // IndexedStack keeps every tab mounted and simply shows the selected
        // one. This avoids the InheritedWidget deactivation-order crash that a
        // page-swapping AnimatedSwitcher triggered when the outgoing Scaffold
        // (and its in-page flutter_animate entrance animations) tore down while
        // descendants still depended on its Theme/MediaQuery scopes. It also
        // preserves each tab's scroll position and state between switches.
        body: IndexedStack(
          index: _index,
          children: _screens,
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton:
            _CenterFab(key: _fabKey, onTap: () => showQuickAddSheet(context)),
        bottomNavigationBar: _FloatingNavBar(
          key: _navKey,
          index: _index,
          onSelect: (i) {
            if (i != _index) {
              const names = ['home', 'schedule', 'explore', 'planner'];
              ref.read(analyticsProvider).tab(names[i]);
            }
            setState(() => _index = i);
          },
        ),
      ),
    );
  }
}

class _CenterFab extends StatefulWidget {
  final VoidCallback onTap;
  const _CenterFab({super.key, required this.onTap});

  @override
  State<_CenterFab> createState() => _CenterFabState();
}

class _CenterFabState extends State<_CenterFab>
    with SingleTickerProviderStateMixin {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
      padding: const EdgeInsets.only(top: 26),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _scale = 0.88),
        onTapUp: (_) {
          setState(() => _scale = 1);
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        onTapCancel: () => setState(() => _scale = 1),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: RepaintBoundary(
            child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryLight, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
          )
              // A few gentle "breaths" after launch to draw the eye, then it
              // rests. (It used to breathe forever on every tab, repainting
              // its blurred shadow every frame for the app's whole session.)
              .animate(onPlay: (c) => c.repeat(reverse: true, count: 3))
              .scaleXY(
                begin: 1,
                end: 1.06,
                duration: 2200.ms,
                curve: Curves.easeInOut,
              )
              // Springy entrance the first time the shell mounts.
              .animate()
              .scale(
                begin: const Offset(0.6, 0.6),
                end: const Offset(1, 1),
                duration: 420.ms,
                curve: Curves.easeOutBack,
              )
              .fadeIn(duration: 280.ms),
        ),
      ),
    ),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _FloatingNavBar({super.key, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The Scaffold uses extendBody: true, so this floating bar is drawn all the
    // way to the physical screen bottom. Add the device's bottom safe-area
    // inset (large on phones with a 3-button nav bar, ~0 on gesture nav) so the
    // pill and its labels are never clipped by the system navigation bar.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomInset),
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            _NavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Home',
              selected: index == 0,
              onTap: () => onSelect(0),
            ),
            _NavItem(
              icon: Icons.calendar_month_outlined,
              activeIcon: Icons.calendar_month_rounded,
              label: 'Schedule',
              selected: index == 1,
              onTap: () => onSelect(1),
            ),
            const SizedBox(width: 58), // gap for the center FAB
            _NavItem(
              icon: Icons.explore_outlined,
              activeIcon: Icons.explore_rounded,
              label: 'Explore',
              selected: index == 2,
              onTap: () => onSelect(2),
            ),
            _NavItem(
              icon: Icons.auto_awesome_outlined,
              activeIcon: Icons.auto_awesome_rounded,
              label: 'Planner',
              selected: index == 3,
              onTap: () => onSelect(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon; // outlined (unselected)
  final IconData activeIcon; // filled (selected)
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selected;
    final unselectedColor = theme.textTheme.bodySmall?.color;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            if (!selected) HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: AnimatedScale(
            scale: _pressed ? 0.86 : 1.0,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Moving indicator bar that grows in under the active tab.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  height: 3,
                  width: selected ? 22 : 0,
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                // Icon: outlined→filled with a soft pop + colour + size shift.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    selected ? widget.activeIcon : widget.icon,
                    key: ValueKey(selected),
                    size: selected ? 30 : 27,
                    color: selected ? AppColors.primary : unselectedColor,
                  ),
                ),
                // Label reveal: only the active tab shows its name, and the
                // row animates its height so the swap feels alive.
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: selected
                      ? Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                              height: 1,
                            ),
                          ),
                        )
                      : const SizedBox(width: 0, height: 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
