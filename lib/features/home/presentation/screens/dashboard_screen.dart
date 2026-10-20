import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/url_launcher_util.dart';
import '../../../../services/reminder_scheduler.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../../shared/widgets/ai_mascot.dart';
import '../../../../shared/widgets/character_avatar.dart';
import '../../../../shared/widgets/placement_slot.dart';
import '../../../../shared/widgets/placement_banner.dart';
import '../../../../shared/widgets/placement_campaign.dart';
import '../../../cms/domain/marketing.dart';
import '../../../attendance/domain/attendance_record.dart';
import '../../../attendance/presentation/providers/attendance_providers.dart';
import '../../../attendance/presentation/screens/attendance_screen.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/screens/edit_profile_screen.dart';
import '../../../chat/presentation/screens/chat_screen.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../exams/presentation/screens/exams_screen.dart';
import '../../../expenses/presentation/screens/expenses_screen.dart';
import '../../../grades/presentation/providers/grade_providers.dart';
import '../../../grades/presentation/screens/grades_screen.dart';
import '../../../habits/presentation/screens/habits_screen.dart';
import '../../../import/presentation/screens/import_screen.dart';
import '../../../import/presentation/widgets/import_draft_banner.dart';
import '../../../notes/presentation/screens/notes_screen.dart';
import '../../../opportunities/domain/resource.dart';
import '../../../opportunities/presentation/providers/opportunities_providers.dart';
import '../../../opportunities/presentation/screens/discounts_screen.dart';
import '../../../opportunities/presentation/screens/opportunities_screen.dart';
import '../../../opportunities/presentation/screens/resource_detail_screen.dart';
import '../../../opportunities/presentation/widgets/resource_card.dart';
import '../../../schedule/presentation/providers/schedule_providers.dart';
import '../../../schedule/presentation/screens/schedule_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../subjects/presentation/screens/edit_subject_screen.dart';
import '../../../tasks/domain/task_buckets.dart';
import '../../../tasks/domain/task_item.dart';
import '../../../tasks/presentation/providers/task_providers.dart';
import '../../../tasks/presentation/screens/tasks_screen.dart';
import '../../../tasks/presentation/widgets/task_card.dart';
import '../widgets/home_banner.dart';
import '../providers/quick_tools_provider.dart';
import '../providers/notifications_seen_provider.dart';

/// Home dashboard. A calm, glanceable overview built around the question
/// "what matters to me today?":
///   • a friendly greeting header (AI + settings),
///   • a bold motivational headline,
///   • a 2×2 grid of the four headline metrics (today's classes, tasks due,
///     next exam, GPA),
///   • a "This week" momentum strip (attendance / focus / streak / tasks),
///   • today's class timeline with inline attendance marking,
///   • study tools, a recommended slot and lifecycle banners.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(
        settings: RouteSettings(name: _homeScreenName(screen)),
        builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final firstName = profile?.displayName?.split(' ').first ?? 'there';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            _Header(firstName: firstName).animate().fadeIn(duration: 350.ms),
            const SizedBox(height: 18),
            const _HomeHeadline()
                .animate()
                .fadeIn(duration: 350.ms)
                .slideY(begin: 0.06, curve: Curves.easeOut),
            const SizedBox(height: 18),
            // First-run guidance: only shown while the student has no subjects
            // yet, so a brand-new (empty) Home immediately points to value.
            const _GetStartedCard(),
            // Unsaved timetable import (app was closed mid-review).
            const ImportDraftBanner(padding: EdgeInsets.only(bottom: 18)),
            // Home — top ad/campaign slot (below the headline).
            const PlacementSlot(
                placement: Placements.homeTop,
                padding: EdgeInsets.only(bottom: 18)),
            const _StatGrid()
                .animate()
                .fadeIn(duration: 350.ms)
                .slideY(begin: 0.06, curve: Curves.easeOut),
            const SizedBox(height: 20),
            // Home — banner/campaign slot just above Quick tools.
            const PlacementSlot(
                placement: Placements.homeAboveQuickTools,
                padding: EdgeInsets.only(bottom: 18)),
            // Quick tools — moved up to replace the old "This week" strip.
            const _QuickTools()
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.06, curve: Curves.easeOut),
            // Home — below stats slot.
            const PlacementSlot(
                placement: Placements.homeBelowStats,
                padding: EdgeInsets.only(top: 18)),
            const SizedBox(height: 24),
            SectionHeader(
              title: "Today's timeline",
              actionLabel: 'View full day',
              onAction: () => _push(context, const ScheduleScreen()),
            ),
            const SizedBox(height: 12),
            const _TodayTimeline(),
            // Home — below timeline slot.
            const PlacementSlot(
                placement: Placements.homeBelowTimeline,
                padding: EdgeInsets.only(top: 6)),
            const SizedBox(height: 22),
            const _TasksSection(),
            // Home — below tasks slot.
            const PlacementSlot(
                placement: Placements.homeBelowTasks,
                padding: EdgeInsets.only(top: 16)),
            const SizedBox(height: 22),
            const _RecommendedForYou(),
            const SizedBox(height: 20),
            const RemindersBanner(),
            // Home — bottom sponsored campaign (banner rendered by HomeBanner).
            const PlacementCampaign(placement: Placements.home),
            const HomeBanner(),
          ],
        ),
      ),
    );
  }
}

/// First-run "aha" card. Appears ONLY when the student has zero subjects, so a
/// brand-new user lands on a Home that immediately guides them to value:
/// add their first subject, or import a whole timetable from a photo/PDF.
/// Collapses to nothing (SizedBox.shrink) the moment a subject exists — and
/// while the subjects stream is still loading — so it never flickers for
/// returning users.
class _GetStartedCard extends ConsumerWidget {
  const _GetStartedCard();

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(
        settings: RouteSettings(name: _homeScreenName(screen)),
        builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull;
    // Hide until we know for sure there are no subjects (avoids a flash for
    // returning users while the stream warms up).
    if (subjects == null || subjects.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.softShadow(opacity: 0.22, blur: 20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rocket_launch_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Let\u2019s get you set up',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Add your subjects to start tracking attendance, or import your '
            'whole timetable from a photo in seconds.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.35),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      _push(context, const EditSubjectScreen()),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add subject'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _push(context, const ImportScreen(freeAccess: true)),
                  icon: const Icon(Icons.auto_awesome_rounded,
                      size: 18, color: Colors.white),
                  label: const Text('Import timetable'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Greeting header: avatar + two-line greeting on the left, an AI assistant
/// button and a settings button on the right.
class _Header extends ConsumerWidget {
  final String firstName;
  const _Header({required this.firstName});

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(
          settings: RouteSettings(name: _homeScreenName(screen)),
          builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final alertCount = ref.watch(homeAlertsProvider).length;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Open settings',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _push(context, const SettingsScreen()),
              child: Row(
                children: [
                  CharacterAvatar(
                    uid: profile?.uid ?? '',
                    character: profile?.avatarCharacter,
                    fallbackText: firstName,
                    size: 46,
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryLight, AppColors.primary],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Hey, $firstName 👋',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(_timeGreeting(),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.hintColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Notifications',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              RoundIconButton(
                icon: alertCount > 0
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: 46,
                semanticLabel: alertCount > 0
                    ? 'Notifications, $alertCount new'
                    : 'Notifications',
                onTap: () => _openNotifications(context, ref),
              ),
              if (alertCount > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.scaffoldBackgroundColor,
                          width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text('$alertCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            height: 1)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Ask Kiro',
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _push(context, const ChatScreen()),
              child: const SizedBox(
                width: 46,
                height: 46,
                child: Center(child: AiMascot(size: 46)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openNotifications(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _NotificationsSheet(),
    );
    // Mark what was shown as seen once the sheet closes — clears the "new
    // match" nudges and unread announcements (standing items like overdue
    // tasks remain until actually resolved).
    final ids = (ref
                .read(placementBannersProvider(Placements.announcement))
                .valueOrNull ??
            const [])
        .map((b) => b.id)
        .toList();
    ref.read(notificationsSeenProvider.notifier).markSeen(ids);
  }
}

/// What the bell surfaces: the things that actually need the student's
/// attention right now, derived live from their data.
enum _AlertTarget { tasks, exams, attendance, opportunities, perks, announcement }

class _HomeAlert {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final _AlertTarget target;

  /// For announcement alerts: an optional external URL / in-app route to open.
  final String? url;
  const _HomeAlert({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.target,
    this.url,
  });
}

/// Live "needs attention" alerts: overdue tasks, tasks due today, exams within
/// three days, and unmarked classes today. Powers the bell badge + sheet.
final homeAlertsProvider = Provider<List<_HomeAlert>>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final alerts = <_HomeAlert>[];

  final pending = ref.watch(pendingTasksProvider);
  final overdue = pending.where((t) => t.isOverdue).toList();
  if (overdue.isNotEmpty) {
    alerts.add(_HomeAlert(
      icon: Icons.error_outline_rounded,
      color: AppColors.danger,
      title: '${overdue.length} overdue ${overdue.length == 1 ? 'task' : 'tasks'}',
      subtitle: overdue.first.title,
      target: _AlertTarget.tasks,
    ));
  }
  final dueToday = pending
      .where((t) =>
          !t.isOverdue &&
          t.dueDate != null &&
          DateUtilsX.isSameDay(t.dueDate!, now))
      .toList();
  if (dueToday.isNotEmpty) {
    alerts.add(_HomeAlert(
      icon: Icons.today_rounded,
      color: AppColors.warning,
      title: '${dueToday.length} ${dueToday.length == 1 ? 'task' : 'tasks'} due today',
      subtitle: dueToday.first.title,
      target: _AlertTarget.tasks,
    ));
  }
  final exams =
      ref.watch(upcomingExamsProvider).where((e) => e.daysUntil <= 3).toList();
  if (exams.isNotEmpty) {
    final e = exams.first;
    alerts.add(_HomeAlert(
      icon: Icons.event_note_rounded,
      color: AppColors.primary,
      title: 'Exam ${e.countdownLabel.toLowerCase()}',
      subtitle: e.title,
      target: _AlertTarget.exams,
    ));
  }
  final classes = ref.watch(classesForDayProvider(today));
  final marked = ref.watch(todayStatusProvider);
  final unmarked = classes
      .where((c) => !marked.containsKey(
          attendanceOccurrenceKey(c.subject.id, c.session.startTime)))
      .length;
  if (unmarked > 0) {
    alerts.add(_HomeAlert(
      icon: Icons.fact_check_rounded,
      color: AppColors.success,
      title: 'Mark today\'s attendance',
      subtitle: '$unmarked ${unmarked == 1 ? 'class' : 'classes'} to mark',
      target: _AlertTarget.attendance,
    ));
  }

  // Option A — personalized "new for you" opportunity/perk nudges. New =
  // published after the bell was last opened; matched = featured or a strong
  // personalized score (perks always qualify). Excludes hidden/saved items.
  final seen = ref.watch(notificationsSeenProvider);
  final country = ref.watch(effectiveCountryProvider);
  final hidden = ref.watch(hiddenResourceIdsProvider).valueOrNull ?? const {};
  final saved = ref.watch(savedResourceIdsProvider).valueOrNull ?? const {};
  final resources =
      ref.watch(visibleResourcesProvider).valueOrNull ?? const [];
  var newOpps = 0;
  var newPerks = 0;
  Resource? firstOpp;
  Resource? firstPerk;
  for (final r in resources) {
    final pub = r.publishedAt ?? r.createdAt;
    if (pub == null || !pub.isAfter(seen.seenAt)) continue;
    if (!r.isInActiveFeed || !r.targetsCountry(country)) continue;
    if (hidden.contains(r.id) || saved.contains(r.id)) continue;
    if (r.type.isDiscount) {
      newPerks++;
      firstPerk ??= r;
    } else {
      final score = ref.watch(resourceScoreProvider(r));
      final matched =
          r.featured || (score.personalized && score.score >= 60);
      if (matched) {
        newOpps++;
        firstOpp ??= r;
      }
    }
  }
  if (newOpps > 0) {
    alerts.add(_HomeAlert(
      icon: Icons.auto_awesome_rounded,
      color: AppColors.primary,
      title: '$newOpps new ${newOpps == 1 ? 'opportunity' : 'opportunities'} for you',
      subtitle: firstOpp?.title ?? 'Matched to your profile',
      target: _AlertTarget.opportunities,
    ));
  }
  if (newPerks > 0) {
    alerts.add(_HomeAlert(
      icon: Icons.redeem_rounded,
      color: AppColors.coral,
      title: '$newPerks new ${newPerks == 1 ? 'perk' : 'perks'} available',
      subtitle: firstPerk?.brandName ?? 'Fresh student deals',
      target: _AlertTarget.perks,
    ));
  }

  // Option B1 — unread in-app announcements (CMS banners on the "announcement"
  // placement). Device-local read state via [notificationsSeenProvider].
  final announcements =
      ref.watch(placementBannersProvider(Placements.announcement)).valueOrNull ??
          const [];
  for (final b in announcements) {
    if (seen.seenAnnouncementIds.contains(b.id)) continue;
    alerts.add(_HomeAlert(
      icon: Icons.campaign_rounded,
      color: AppColors.info,
      title: b.title,
      subtitle: b.ctaLabel?.isNotEmpty == true ? b.ctaLabel! : 'Announcement',
      target: _AlertTarget.announcement,
      url: b.destination,
    ));
  }

  return alerts;
});

/// The bell's notification center — a live, tappable digest of what needs
/// attention. Each row deep-links to the relevant screen.
class _NotificationsSheet extends ConsumerWidget {
  const _NotificationsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final alerts = ref.watch(homeAlertsProvider);

    void go(_HomeAlert a) {
      Navigator.pop(context);
      switch (a.target) {
        case _AlertTarget.tasks:
          Navigator.of(context).push(
              MaterialPageRoute(settings: const RouteSettings(name: 'Tasks'), builder: (_) => const TasksScreen()));
        case _AlertTarget.exams:
          Navigator.of(context).push(
              MaterialPageRoute(settings: const RouteSettings(name: 'Exams'), builder: (_) => const ExamsScreen()));
        case _AlertTarget.attendance:
          Navigator.of(context).push(
              MaterialPageRoute(settings: const RouteSettings(name: 'Attendance'), builder: (_) => const AttendanceScreen()));
        case _AlertTarget.opportunities:
          Navigator.of(context).push(
              MaterialPageRoute(settings: const RouteSettings(name: 'Opportunities'), builder: (_) => const OpportunitiesScreen()));
        case _AlertTarget.perks:
          Navigator.of(context).push(
              MaterialPageRoute(settings: const RouteSettings(name: 'Discounts'), builder: (_) => const DiscountsScreen()));
        case _AlertTarget.announcement:
          if (a.url != null && a.url!.isNotEmpty) openUrl(context, a.url);
      }
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Row(
              children: [
                Text('Notifications', style: theme.textTheme.titleLarge),
                const Spacer(),
                if (alerts.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${alerts.length} new',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "You're all caught up — no overdue tasks, exams or "
                        'classes needing attention right now.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.hintColor),
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final a in alerts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: theme.brightness == Brightness.dark
                        ? AppColors.darkSurfaceAlt
                        : AppColors.lavenderSoft,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => go(a),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: a.color.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(a.icon, color: a.color, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.title,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14.5)),
                                  const SizedBox(height: 1),
                                  Text(a.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: theme.hintColor)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: theme.hintColor),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Time-of-day greeting shown under the user's name.
String _timeGreeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning ☀️';
  if (h < 17) return 'Good afternoon 👋';
  if (h < 21) return 'Good evening 🌆';
  return 'Good night 🌙';
}

/// A bold, two-line motivational headline with an emphasised first word.
/// The message rotates daily so Home feels fresh and users resonate with it.
class _HomeHeadline extends StatelessWidget {
  const _HomeHeadline();

  // (emphasised head, remainder) — the head is tinted primary.
  static const _messages = <(String, String)>[
    ('Small steps,', ' big wins today.'),
    ('Make today', ' really count.'),
    ('Progress,', ' not perfection.'),
    ('Own', ' your day.'),
    ('One task', ' at a time.'),
    ('Keep', ' showing up.'),
    ('Dream big,', ' start now.'),
    ('Focus', ' on what matters.'),
    ('You’ve', ' got this.'),
    ('Show up', ' for future you.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = (theme.textTheme.displaySmall ??
            const TextStyle(fontSize: 32, fontWeight: FontWeight.w700))
        .copyWith(fontWeight: FontWeight.w800, height: 1.08, letterSpacing: -0.5);
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    final (head, tail) = _messages[dayOfYear % _messages.length];
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: head, style: base.copyWith(color: AppColors.primary)),
        TextSpan(
            text: tail,
            style: base.copyWith(color: theme.textTheme.displaySmall?.color)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Headline metrics grid
// ─────────────────────────────────────────────────────────────────────────

/// 2×2 grid of the four headline metrics, alternating lavender / peach tints
/// like the reference design. Each card is a one-tap shortcut into its
/// feature, wired to live providers.
class _StatGrid extends ConsumerWidget {
  const _StatGrid();

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(
          settings: RouteSettings(name: _homeScreenName(screen)),
          builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final classes = ref.watch(classesForDayProvider(today));
    final tasks = ref.watch(taskSummaryProvider);
    final nextExam = ref.watch(nextExamProvider);
    final gpa = ref.watch(gpaSummaryProvider);

    // Tasks due — the number of pending (not done) tasks. The sub-line points
    // at what matters most: overdue (red) → due today (amber) → this week.
    final tasksValue = '${tasks.pending}';
    final String tasksSub;
    final Color? tasksColor;
    if (tasks.overdue > 0) {
      tasksSub = '${tasks.overdue} overdue';
      tasksColor = AppColors.danger;
    } else if (tasks.dueToday > 0) {
      tasksSub = '${tasks.dueToday} due today';
      tasksColor = null; // amber on peach is too low-contrast; keep ink
    } else if (tasks.pending == 0) {
      tasksSub = 'All caught up';
      tasksColor = tasks.completed > 0 ? AppColors.success : null;
    } else if (tasks.dueThisWeek > 0) {
      tasksSub = '${tasks.dueThisWeek} this week';
      tasksColor = null;
    } else {
      tasksSub = tasks.pending == 1 ? 'Pending task' : 'Pending tasks';
      tasksColor = null;
    }

    // Next exam
    final String examValue;
    final String examSub;
    if (nextExam == null) {
      examValue = '—';
      examSub = 'None scheduled';
    } else if (nextExam.daysUntil <= 0) {
      examValue = 'Today';
      examSub = nextExam.title;
    } else {
      examValue = '${nextExam.daysUntil}';
      examSub = 'days left';
    }

    // GPA
    final hasGpa = gpa.gradedSubjects > 0;
    final gpaValue = hasGpa ? gpa.gpa.toStringAsFixed(2) : '—';
    final gpaSub =
        hasGpa ? 'of ${gpa.maxPoints.toStringAsFixed(0)}' : 'No grades yet';

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.calendar_today_rounded,
                  label: 'Today',
                  value: '${classes.length}',
                  sub: classes.length == 1 ? 'Class' : 'Classes',
                  background: AppColors.lavender,
                  onTap: () => _push(context, const ScheduleScreen()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.task_alt_rounded,
                  label: 'Tasks due',
                  value: tasksValue,
                  sub: tasksSub,
                  background: AppColors.peachSoft,
                  valueColor: tasksColor,
                  onTap: () => _push(context, const TasksScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.event_note_rounded,
                  label: 'Next exam',
                  value: examValue,
                  sub: examSub,
                  background: AppColors.lavender,
                  onTap: () => _push(context, const ExamsScreen()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.school_rounded,
                  label: 'GPA',
                  value: gpaValue,
                  sub: gpaSub,
                  background: AppColors.peachSoft,
                  onTap: () => _push(context, const GradesScreen()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color background;
  final Color? valueColor;
  final VoidCallback onTap;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.background,
    required this.onTap,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The tinted cards read as "light" surfaces, so ink text stays legible in
    // both light and dark themes.
    const ink = AppColors.ink;
    return Semantics(
      button: true,
      label: '$label, $value $sub',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: ink, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                    color: valueColor ?? ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 1),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: ink.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's timeline — a vertical rail of colour-coded class cards. The class in
/// progress fills with its subject colour and shows a live progress bar; other
/// classes use a soft tint, and unmarked ones offer one-tap attendance marking.
class _TodayTimeline extends ConsumerStatefulWidget {
  const _TodayTimeline();

  @override
  ConsumerState<_TodayTimeline> createState() => _TodayTimelineState();
}

class _TodayTimelineState extends ConsumerState<_TodayTimeline> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The timeline decides "Upcoming" vs "Tap to mark" purely from the current
    // wall-clock time. Rebuild every 30s so a class tile flips to its marking
    // state exactly when the class starts — without needing an app restart.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final classes = ref.watch(classesForDayProvider(today));
    final markedToday = ref.watch(todayStatusProvider);

    if (classes.isEmpty) {
      return _EmptyTile(
        icon: Icons.free_breakfast_rounded,
        text: markedToday.isEmpty
            ? 'No classes today. Enjoy your day!'
            : "You're all set — today's classes are marked ✓",
      );
    }

    final nowMinutes = now.hour * 60 + now.minute;
    return Column(
      children: [
        for (int i = 0; i < classes.length; i++)
          _ClassTimelineTile(
            scheduled: classes[i],
            isFirst: i == 0,
            isLast: i == classes.length - 1,
            nowMinutes: nowMinutes,
            status: markedToday[attendanceOccurrenceKey(
                classes[i].subject.id, classes[i].session.startTime)],
          ),
      ],
    );
  }
}

class _ClassTimelineTile extends ConsumerWidget {
  final ScheduledClass scheduled;
  final bool isFirst;
  final bool isLast;
  final int nowMinutes;
  final AttendanceStatus? status;
  const _ClassTimelineTile({
    required this.scheduled,
    required this.isFirst,
    required this.isLast,
    required this.nowMinutes,
    required this.status,
  });

  static int _min(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  void _mark(BuildContext context, WidgetRef ref, AttendanceStatus s) {
    final c = scheduled;
    // Only confirm (and only buzz) when the tap actually changed something.
    // Re-tapping an already-marked class is a no-op, so firing a snackbar for
    // it just made the bar flash without the numbers moving.
    final changed = ref.read(attendanceControllerProvider).markOccurrence(
        c.subject.id, DateTime.now(), c.session.startTime, s);
    if (!changed) return;
    HapticFeedback.selectionClick();
    showQuickFeedback(context, '${s.label} · ${c.subject.name}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = scheduled;
    final color = Color(c.subject.colorHex);
    final start = _min(c.session.startTime);
    final end = _min(c.session.endTime);
    final isNow = nowMinutes >= start && nowMinutes < end;
    final isPast = nowMinutes >= end;
    // Attendance marking only becomes available once the class has started.
    final started = nowMinutes >= start;
    final room = (c.session.room != null && c.session.room!.isNotEmpty)
        ? c.session.room
        : c.subject.room;
    final hasRoom = room != null && room.isNotEmpty;
    final progress = (isNow && end > start)
        ? ((nowMinutes - start) / (end - start)).clamp(0.0, 1.0)
        : 0.0;
    final minsLeft = isNow ? (end - nowMinutes) : 0;
    final startText = DateUtilsX.displayTime(context, c.session.startTime);
    final lineColor = AppColors.primary.withValues(alpha: 0.25);
    final cardColor = isNow ? color : color.withValues(alpha: 0.12);
    final onCard = isNow ? Colors.white : theme.textTheme.titleLarge?.color;
    final subColor =
        isNow ? Colors.white.withValues(alpha: 0.85) : theme.hintColor;

    // Description/meta line shown when the class isn't live. Room now shows on
    // the right, directly beneath the time.
    final String meta;
    if (status != null) {
      meta = status!.label;
    } else if (started) {
      meta = 'Tap to mark your attendance';
    } else {
      meta = 'Upcoming';
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left rail: connector line + subject-coloured node.
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                    width: 2,
                    height: 22,
                    color: isFirst ? Colors.transparent : lineColor),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isNow ? color : theme.cardColor,
                    border: Border.all(color: color, width: 3),
                    boxShadow: isNow
                        ? [
                            BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 1)
                          ]
                        : null,
                  ),
                ),
                Expanded(
                  child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : lineColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Colour-tinted class card.
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(18),
                boxShadow: (isNow && theme.brightness == Brightness.light)
                    ? [
                        BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 8))
                      ]
                    : null,
              ),
              child: Opacity(
                opacity: (isPast && status == null) ? 0.7 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(c.subject.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700, color: onCard),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(startText,
                                style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700, color: onCard)),
                            if (hasRoom) ...[
                              const SizedBox(height: 3),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.meeting_room_outlined,
                                      size: 12, color: subColor),
                                  const SizedBox(width: 3),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 90),
                                    child: Text(room,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: subColor,
                                                fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    if (isNow) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: Colors.white.withValues(alpha: 0.3),
                          valueColor:
                              const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('In progress · ${minsLeft}m left',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ] else ...[
                      const SizedBox(height: 5),
                      Text(meta,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: subColor)),
                    ],
                    if (status == null && started) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _markButton(context, ref, Icons.check_rounded,
                              AppColors.success, 'Present',
                              AttendanceStatus.present, isNow),
                          const SizedBox(width: 8),
                          _markButton(context, ref, Icons.close_rounded,
                              AppColors.danger, 'Absent',
                              AttendanceStatus.absent, isNow),
                          const SizedBox(width: 8),
                          _markButton(context, ref, Icons.event_busy_rounded,
                              AppColors.cancelled, 'Cancel',
                              AttendanceStatus.cancelled, isNow),
                        ],
                      ),
                    ],
                    if (c.subject.classLink != null &&
                        c.subject.classLink!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              openUrl(context, c.subject.classLink),
                          icon: const Icon(Icons.videocam_rounded, size: 18),
                          label: const Text('Join class'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                            foregroundColor:
                                isNow ? Colors.white : AppColors.info,
                            side: BorderSide(
                                color: isNow ? Colors.white : AppColors.info),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _markButton(BuildContext context, WidgetRef ref, IconData icon,
      Color color, String label, AttendanceStatus s, bool solid) {
    final bg =
        solid ? Colors.white.withValues(alpha: 0.22) : color.withValues(alpha: 0.14);
    final fg = solid ? Colors.white : color;
    return Expanded(
      child: Semantics(
        button: true,
        label: 'Mark $label',
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _mark(context, ref, s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 5),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(label,
                          style: TextStyle(
                              color: fg,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A "Tasks" list under the timeline. Following proven to-do patterns
/// (Todoist / Things), tasks are grouped Overdue → Today → Upcoming with light
/// section headers, a satisfying circular check to complete, priority colour
/// cues and a due badge — a clean vertical list, not a carousel.
class _TasksSection extends ConsumerWidget {
  const _TasksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingTasksProvider);

    // Order by the soonest due date (overdue first, no-date last), breaking
    // ties by priority (High → Low) so the 3 most pressing tasks surface.
    final ordered = [...pending]..sort(compareByDueThenPriority);
    final top = ordered.take(3).toList();

    void openEditor(TaskItem t) => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => TaskEditorSheet(task: t),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Tasks',
          actionLabel: pending.isEmpty ? null : 'View all',
          onAction: () => Navigator.of(context)
              .push(MaterialPageRoute(settings: const RouteSettings(name: 'Tasks'), builder: (_) => const TasksScreen())),
        ),
        const SizedBox(height: 12),
        if (top.isEmpty)
          GestureDetector(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(settings: const RouteSettings(name: 'Tasks'), builder: (_) => const TasksScreen())),
            child: const _EmptyTile(
              icon: Icons.task_alt_rounded,
              text: "No tasks — you're all caught up. Tap to add one.",
            ),
          )
        else
          for (final t in top)
            TaskCard(task: t, onOpen: () => openEditor(t)),
      ],
    );
  }
}

/// Personalised opportunities slot. Shows the top matched resource when the
/// feed has one, otherwise nudges the student to complete their profile /
/// explore the Opportunities tab.
class _RecommendedForYou extends ConsumerWidget {
  const _RecommendedForYou();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final hasDetails = profile?.hasAnyProfileDetails ?? false;
    final feed = ref.watch(opportunitiesFeedProvider);
    final top = feed.isNotEmpty ? feed.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Recommended for you',
          actionLabel: 'View all',
          onAction: () => Navigator.of(context).push(
              MaterialPageRoute(settings: const RouteSettings(name: 'Opportunities'), builder: (_) => const OpportunitiesScreen())),
        ),
        const SizedBox(height: 12),
        if (top != null)
          ResourceCard(
            resource: top,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                settings: const RouteSettings(name: 'Resource Detail'),
                builder: (_) => ResourceDetailScreen(resource: top))),
          )
        else
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                settings: RouteSettings(
                    name: hasDetails ? 'Opportunities' : 'Edit Profile'),
                builder: (_) => hasDetails
                    ? const OpportunitiesScreen()
                    : const EditProfileScreen())),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: softCard(context),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                        hasDetails
                            ? Icons.workspace_premium_rounded
                            : Icons.person_add_alt_1_rounded,
                        color: AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            hasDetails
                                ? 'Personalised opportunities'
                                : 'Get matched opportunities',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 3),
                        Text(
                          hasDetails
                              ? 'Scholarships, internships & deals picked for you — coming soon.'
                              : 'Add your country, degree & interests to unlock personalised matches.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A tool the user can launch from the Home "Quick tools" grid.
class _QuickTool {
  final String label;
  final IconData icon;
  final Color color;
  final Widget Function() screen;
  const _QuickTool(this.label, this.icon, this.color, this.screen);
}

/// Visual registry for every Quick-tool key. Keys match
/// [kDefaultQuickToolOrder]; ordering/visibility is user-controlled via
/// [quickToolsProvider].
Map<String, _QuickTool> _quickToolRegistry() => {
      'tasks': _QuickTool('Tasks', Icons.check_circle_outline_rounded,
          AppColors.primary, () => const TasksScreen()),
      'perks': _QuickTool('Perks', Icons.redeem_rounded, AppColors.coral,
          () => const DiscountsScreen()),
      'grades': _QuickTool('Grades', Icons.school_rounded, AppColors.primary,
          () => const GradesScreen()),
      'exams': _QuickTool('Exams', Icons.event_note_rounded, AppColors.danger,
          () => const ExamsScreen()),
      'notes': _QuickTool('Notes', Icons.sticky_note_2_rounded, AppColors.info,
          () => const NotesScreen()),
      'habits': _QuickTool('Habits', Icons.local_fire_department_rounded,
          AppColors.coral, () => const HabitsScreen()),
      'expenses': _QuickTool('Expenses', Icons.account_balance_wallet_rounded,
          AppColors.success, () => const ExpensesScreen()),
      'attendance': _QuickTool('Attendance', Icons.pie_chart_rounded,
          AppColors.info, () => const AttendanceScreen()),
    };

/// Home "Quick tools" — a clean, airy, user-managed grid of one-tap shortcuts.
/// Replaces the old dense horizontal "Study tools" strip; users can reorder and
/// show/hide tools via the Manage sheet.
class _QuickTools extends ConsumerWidget {
  const _QuickTools();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final registry = _quickToolRegistry();
    final visible = ref.watch(quickToolsProvider).visible;
    final tools = [
      for (final k in visible)
        if (registry[k] != null) MapEntry(k, registry[k]!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Quick tools', style: theme.textTheme.titleLarge),
            const Spacer(),
            _ManagePill(onTap: () => _openManage(context)),
          ],
        ),
        const SizedBox(height: 16),
        if (tools.isEmpty)
          _AddToolsHint(onTap: () => _openManage(context))
        else
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              itemCount: tools.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final e = tools[i];
                return _QuickToolTile(
                  tool: e.value,
                  onTap: () {
                    ref.read(analyticsProvider).openFeature(e.value.label);
                    Navigator.of(context).push(MaterialPageRoute(
                        settings: RouteSettings(name: e.value.label),
                        builder: (_) => e.value.screen()));
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  void _openManage(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _ManageQuickToolsSheet(),
    );
  }
}

class _QuickToolTile extends StatelessWidget {
  final _QuickTool tool;
  final VoidCallback onTap;
  const _QuickToolTile({required this.tool, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: tool.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Icon(tool.icon, color: tool.color, size: 25),
            ),
            const SizedBox(height: 7),
            Text(tool.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _ManagePill extends StatelessWidget {
  final VoidCallback onTap;
  const _ManagePill({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune_rounded,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 5),
              Text('Manage',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddToolsHint extends StatelessWidget {
  final VoidCallback onTap;
  const _AddToolsHint({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: softCard(context),
        child: Row(
          children: [
            const Icon(Icons.add_circle_outline_rounded,
                color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text('All tools are hidden. Tap Manage to add some back.',
                  style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet to reorder (drag) and show/hide Quick tools.
class _ManageQuickToolsSheet extends ConsumerWidget {
  const _ManageQuickToolsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final registry = _quickToolRegistry();
    final config = ref.watch(quickToolsProvider);
    final controller = ref.read(quickToolsProvider.notifier);
    final order = config.order;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(4)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Manage quick tools',
                          style: theme.textTheme.titleLarge),
                      Text('Drag to reorder · toggle to show or hide',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: controller.reset,
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              itemCount: order.length,
              // ignore: deprecated_member_use
              onReorder: controller.reorder,
              itemBuilder: (context, i) {
                final key = order[i];
                final tool = registry[key];
                if (tool == null) {
                  return SizedBox.shrink(key: ValueKey('missing_$key'));
                }
                final hidden = config.hidden.contains(key);
                return Padding(
                  key: ValueKey(key),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: softCard(context, radius: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: tool.color
                                .withValues(alpha: hidden ? 0.06 : 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Icon(tool.icon,
                              size: 20,
                              color: hidden ? theme.hintColor : tool.color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(tool.label,
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: hidden ? theme.hintColor : null)),
                        ),
                        Switch(
                          value: !hidden,
                          activeThumbColor: AppColors.primary,
                          onChanged: (v) => controller.setHidden(key, !v),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Icon(Icons.drag_handle_rounded,
                              color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Small informational tile used when there is nothing to show.
class _EmptyTile extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyTile({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: softCard(context),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}


/// Readable PostHog/Firebase screen name for a screen pushed from Home
/// (class names are obfuscated in release builds, so map them explicitly).
String _homeScreenName(Widget screen) => switch (screen) {
      AttendanceScreen() => 'Attendance',
      ChatScreen() => 'AI Chat',
      EditSubjectScreen() => 'Edit Subject',
      ExamsScreen() => 'Exams',
      GradesScreen() => 'Grades',
      ImportScreen() => 'Import',
      ScheduleScreen() => 'Schedule',
      SettingsScreen() => 'Settings',
      TasksScreen() => 'Tasks',
      _ => 'Home Shortcut',
    };
