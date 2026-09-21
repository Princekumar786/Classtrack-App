import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classtrack/core/theme/app_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/providers/notification_prefs_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/character_avatar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/screens/edit_profile_screen.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../insights/presentation/screens/daily_agenda_screen.dart';
import '../../../insights/presentation/screens/insights_screen.dart';
import '../../../planner/presentation/screens/weekly_planner_screen.dart';
import '../../../moments/presentation/screens/moments_screen.dart';
import '../../../referral/presentation/screens/referral_screen.dart';
import '../../../schedule/presentation/providers/schedule_providers.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../tasks/presentation/providers/task_providers.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/calendar_auto_sync.dart';
import '../../../import/presentation/screens/import_entry.dart';
import '../../../subscription/domain/pro_constants.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../subscription/presentation/screens/paywall_screen.dart';
import '../../../subscription/presentation/screens/pro_status_screen.dart';
import '../../../tips/presentation/screens/tips_screen.dart';
import 'privacy_policy_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final isPro = ref.watch(isProProvider);
    final target =
        profile?.targetAttendancePercent ?? AppConstants.defaultTargetAttendance;
    final lead = ref.watch(reminderLeadProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _profileHeaderTappable(context, theme, profile?.uid,
              profile?.displayName, profile?.email, profile?.avatarCharacter,
              isPro),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'ClassTrack Pro'),
          _proCard(context, ref, theme),
          const SizedBox(height: 8),
          _card(
            theme,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  const Icon(Icons.insights_rounded, color: AppColors.primary),
              title: const Text('Insights & predictions'),
              subtitle: const Text(
                  'Attendance forecasts, spending & grade trends'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                if (ref.read(isProProvider)) {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const InsightsScreen()));
                } else {
                  await showPaywall(context);
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Study planner'),
          _card(
            theme,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.primary),
              title: const Text('AI weekly planner'),
              subtitle: const Text(
                  'Turn your exams, deadlines & free time into a study plan'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const WeeklyPlannerScreen())),
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Daily agenda'),
          _card(
            theme,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.primary),
              title: const Text('AI daily summary'),
              subtitle: const Text(
                  'A smart briefing of your day — read it & download as PDF'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                if (ref.read(isProProvider)) {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const DailyAgendaScreen()));
                } else {
                  await showPaywall(context);
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Attendance'),
          _card(
            theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Default attendance target'),
                    const Spacer(),
                    Text('${target.toStringAsFixed(0)}%',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: AppColors.primary)),
                  ],
                ),
                Text('Used for every subject unless you set a custom target on it.',
                    style: theme.textTheme.bodySmall),
                Slider(
                  value: target.clamp(50, 100),
                  min: 50,
                  max: 100,
                  divisions: 50,
                  label: '${target.toStringAsFixed(0)}%',
                  onChanged: (v) {
                    final uid = ref.read(currentUidProvider);
                    if (uid != null) {
                      ref
                          .read(authRepositoryProvider)
                          .updateTargetAttendance(uid, v);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Grades'),
          _card(
            theme,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('GPA scale'),
                      Text(
                        ref.watch(gpaScaleProvider) == GpaScaleType.ten
                            ? '10-point (CGPA)'
                            : '4.0 scale',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                ...[
                  (GpaScaleType.four, '4.0'),
                  (GpaScaleType.ten, '10'),
                ].map((e) {
                  final selected = ref.watch(gpaScaleProvider) == e.$1;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(e.$2),
                      selected: selected,
                      onSelected: (_) =>
                          ref.read(gpaScaleProvider.notifier).set(e.$1),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Appearance'),
          _appearanceCard(context, ref, theme),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Notifications'),
          _card(
            theme,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(PhosphorIcons.bell(), color: AppColors.primary),
                  title: const Text('Enable reminders'),
                  subtitle: const Text(
                      'For classes, tasks, exams, courses & videos'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _enableNotifications(context, ref),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Remind me before',
                            style: theme.textTheme.bodyMedium),
                      ),
                      ...[10, 30].map((m) {
                        final selected = lead == m;
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text('$m min'),
                            selected: selected,
                            onSelected: (_) async {
                              await ref
                                  .read(reminderLeadProvider.notifier)
                                  .set(m);
                              if (!context.mounted) return;
                              await _enableNotifications(context, ref,
                                  silent: true);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Reminders set to $m minutes before.')),
                                );
                              }
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _notificationPrefsCard(context, ref, theme),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Google Calendar'),
          _googleAutoSyncCard(context, ref, theme),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Grow ClassTrack'),
          _card(
            theme,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.card_giftcard_rounded,
                      color: AppColors.primary),
                  title: const Text('Invite friends & earn Pro'),
                  subtitle: const Text(
                      'You both get ${AppConstants.referralRewardDays} days of Pro free'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ReferralScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.auto_awesome_motion_rounded,
                      color: AppColors.coral),
                  title: const Text('Shareable moments'),
                  subtitle: const Text('Turn your wins into share-worthy cards'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MomentsScreen())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Support & feedback'),
          _supportCard(context, ref, theme),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'About & legal'),
          _card(
            theme,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(PhosphorIcons.shieldCheck(),
                      color: AppColors.primary),
                  title: const Text('Privacy policy'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined,
                      color: AppColors.primary),
                  title: const Text('Terms of service'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () => _openUrl(AppConstants.termsUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.help_outline_rounded,
                      color: AppColors.primary),
                  title: const Text('Help & support'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () => _openUrl(AppConstants.supportUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tour_rounded,
                      color: AppColors.primary),
                  title: const Text('Show app tour'),
                  subtitle: const Text('Replay the quick home walkthrough'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    // Re-arm the tour, then return to the Home shell so it can
                    // play over the real nav bar and quick-add button.
                    final tour = ref.read(homeTourDoneProvider.notifier);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    tour.reset();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tips_and_updates_rounded,
                      color: AppColors.primary),
                  title: const Text('Tips & Tricks'),
                  subtitle:
                      const Text('See which features you haven’t tried yet'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TipsScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(PhosphorIcons.info(), color: AppColors.primary),
                  title: const Text('Version'),
                  trailing: const Text(AppConstants.appVersion),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Account'),
          _card(
            theme,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(PhosphorIcons.signOut()),
                  title: const Text('Sign out'),
                  onTap: () => ref.read(authRepositoryProvider).signOut(),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_forever_rounded,
                      color: AppColors.danger),
                  title: const Text('Delete account',
                      style: TextStyle(color: AppColors.danger)),
                  subtitle: const Text('Permanently remove your data'),
                  onTap: () => _deleteAccount(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enableNotifications(BuildContext context, WidgetRef ref,
      {bool silent = false}) async {
    final service = ref.read(notificationServiceProvider);
    final granted = await service.requestPermissions();
    if (!context.mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Notification permission denied.')));
      return;
    }
    final lead = ref.read(reminderLeadProvider);
    // Reschedule reminders for every subject's sessions.
    final subjects = ref.read(subjectsStreamProvider).valueOrNull ?? const [];
    await service.cancelAll();
    for (final s in subjects) {
      final sessions =
          ref.read(sessionsForSubjectProvider(s.id)).valueOrNull ?? const [];
      await service.scheduleForSubject(s, sessions, minutesBefore: lead);
    }
    // Reminders for tasks / courses / videos with a due date.
    final tasks = ref.read(tasksStreamProvider).valueOrNull ?? const [];
    await service.scheduleForTasks(tasks, minutesBefore: lead);
    // Exam reminders (evening-before + before the exam).
    final exams = ref.read(examsStreamProvider).valueOrNull ?? const [];
    await service.scheduleForExams(exams, minutesBefore: 30);
    // Remember that reminders are on so they auto-refresh as data changes.
    await ref.read(remindersEnabledProvider.notifier).set(true);
    if (context.mounted && !silent) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Reminders scheduled — classes & tasks $lead min before, exams too.')));
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your profile, subjects, schedule and attendance history. This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await ref.read(authControllerProvider.notifier).deleteAccount();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Please sign out and sign in again, then retry deleting your account.'),
      ));
    }
  }

  Widget _profileHeaderTappable(BuildContext context, ThemeData theme,
      String? uid, String? name, String? email, String? avatarCharacter,
      bool isPro) {
    return Semantics(
      button: true,
      label: 'Edit profile',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EditProfileScreen()),
        ),
        child: _profileHeader(theme, uid, name, email, avatarCharacter, isPro),
      ),
    );
  }

  Widget _profileHeader(ThemeData theme, String? uid, String? name,
      String? email, String? avatarCharacter, bool isPro) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          CharacterAvatar(
            uid: uid ?? '',
            character: avatarCharacter,
            fallbackText: name,
            size: 60,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name ?? 'Student',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: Colors.white)),
                    ),
                    if (isPro) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.workspace_premium_rounded,
                                color: Colors.white, size: 13),
                            const SizedBox(width: 3),
                            Text('PRO',
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (email != null)
                  Text(email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _proCard(BuildContext context, WidgetRef ref, ThemeData theme) {
    final isPro = ref.watch(isProProvider);
    if (isPro) {
      return _card(
        theme,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.workspace_premium_rounded,
              color: AppColors.primary),
          title: const Text('Pro active'),
          subtitle: const Text('View your subscription, renewal & restore'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ProStatusScreen())),
        ),
      );
    }
    return _card(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.workspace_premium_rounded,
                color: AppColors.primary),
            title: const Text('Upgrade to Pro'),
            subtitle: Text(
              ProConstants.enabled
                  ? 'Unlimited AI, photo import, exports and more.'
                  : 'Unlimited AI, photo import, exports and more (coming soon).',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showPaywall(context),
          ),
        ],
      ),
    );
  }

  // ── Appearance: theme mode + accent (Pro) ──────────────────────────────
  Widget _appearanceCard(BuildContext context, WidgetRef ref, ThemeData theme) {
    final mode = ref.watch(themeModeProvider);
    final selected = ref.watch(accentColorProvider);
    final isPro = ref.watch(isProProvider);
    final activeAccent = selected ?? AppColors.primary;

    const palette = <Color>[
      AppColors.primary, // default purple
      Color(0xFF0EA5E9), // sky
      Color(0xFF22C55E), // emerald
      Color(0xFFF59E0B), // amber
      Color(0xFFEF4444), // red
      Color(0xFFEC4899), // pink
      Color(0xFF14B8A6), // teal
      Color(0xFFF97316), // orange
      Color(0xFF6366F1), // indigo
    ];

    Future<void> pick(Color c) async {
      if (!isPro) {
        await showPaywall(context);
        return;
      }
      // Tapping the default purple clears the custom accent.
      await ref
          .read(accentColorProvider.notifier)
          .set(c == AppColors.primary ? null : c);
    }

    bool isSelectedSwatch(Color c) =>
        (selected == null && c == AppColors.primary) ||
        selected?.toARGB32() == c.toARGB32();

    return _card(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.palette_outlined,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('Theme', style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          Row(
            children: [
              for (final m in ThemeMode.values) ...[
                Expanded(
                  child: _ThemeModeTile(
                    mode: m,
                    selected: mode == m,
                    accent: activeAccent,
                    onTap: () => ref.read(themeModeProvider.notifier).set(m),
                  ),
                ),
                if (m != ThemeMode.dark) const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.color_lens_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Accent color', style: theme.textTheme.titleSmall),
              const SizedBox(width: 8),
              if (!isPro) _proChip(theme),
              const Spacer(),
              Container(
                width: 18,
                height: 18,
                decoration:
                    BoxDecoration(color: activeAccent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(selected == null ? 'Default' : 'Custom',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final c in palette)
                _AccentSwatch(
                  color: c,
                  selected: isSelectedSwatch(c),
                  onTap: () => pick(c),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              isPro
                  ? 'Personalise ClassTrack with your favourite accent.'
                  : 'Unlock custom accent colors with ClassTrack Pro.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }

  // ── Google Calendar daily auto-sync ─────────────────────────────────────
  Widget _googleAutoSyncCard(
      BuildContext context, WidgetRef ref, ThemeData theme) {
    final enabled = ref.watch(googleAutoSyncEnabledProvider);
    final connected = ref.watch(googleAutoSyncConnectedProvider);
    final isPro = ref.watch(isProProvider);
    return _card(
      theme,
      child: Column(
        children: [
          // Daily auto-import (Pro).
          _proSwitchTile(
            context,
            theme,
            title: 'Daily auto-sync',
            subtitle: connected
                ? 'Auto-imports your Google Calendar events & Tasks every day '
                    'at 7 PM (last 7 days only, no duplicates)'
                : 'Connect Google below, then it imports automatically every '
                    'day at 7 PM (last 7 days only, no duplicates)',
            value: enabled && isPro,
            isPro: isPro,
            onChanged: (v) async {
              if (!isPro) {
                await showPaywall(context);
                return;
              }
              await ref.read(googleAutoSyncEnabledProvider.notifier).set(v);
            },
          ),
          const Divider(height: 1),
          // Two-way write-back push — coming soon.
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: false,
            title: Row(
              children: [
                const Flexible(child: Text('Push to Google Calendar')),
                const SizedBox(width: 8),
                _comingSoonChip(theme),
              ],
            ),
            subtitle: Text(
              'Also add your classes, exams & deadlines into Google Calendar '
              'on each daily sync',
              style: theme.textTheme.bodySmall,
            ),
            trailing: const Switch(value: false, onChanged: null),
          ),
          const Divider(height: 1),
          // Manual "push now" — coming soon.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_rounded, color: AppColors.primary),
            title: Row(
              children: [
                const Flexible(child: Text('Push to Calendar now')),
                const SizedBox(width: 8),
                _comingSoonChip(theme),
              ],
            ),
            subtitle: Text(
              'Send your classes, exams & task deadlines to Google Calendar',
              style: theme.textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content:
                      Text('Push to Google Calendar is coming soon.')));
            },
          ),
          const Divider(height: 1),
          // Connect / import (free).
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              connected
                  ? Icons.check_circle_rounded
                  : Icons.event_available_rounded,
              color: connected ? Colors.green : AppColors.primary,
            ),
            title: Text(connected ? 'Import now' : 'Connect Google Calendar'),
            subtitle: Text(
              connected
                  ? 'Import the latest events & tasks right away'
                  : 'Grant read-only access — free one-tap import',
              style: theme.textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => runGoogleCalendarImport(context, ref),
          ),
        ],
      ),
    );
  }

  // ── Notification preferences ────────────────────────────────────────────
  Widget _notificationPrefsCard(
      BuildContext context, WidgetRef ref, ThemeData theme) {
    final prefs = ref.watch(notificationPrefsProvider);
    final ctrl = ref.read(notificationPrefsProvider.notifier);
    final isPro = ref.watch(isProProvider);
    return _card(
      theme,
      child: Column(
        children: [
          _switchTile(theme, 'Class reminders', prefs.classes,
              (v) => ctrl.setCategory(classes: v)),
          const Divider(height: 1),
          _switchTile(
            theme,
            'Attendance check-ins',
            prefs.attendanceCheckIns,
            (v) => ctrl.setCategory(attendanceCheckIns: v),
            subtitle: 'After each class, tap Present/Absent to mark it',
          ),
          const Divider(height: 1),
          _switchTile(theme, 'Task & deadline reminders', prefs.tasks,
              (v) => ctrl.setCategory(tasks: v)),
          const Divider(height: 1),
          _switchTile(theme, 'Exam reminders', prefs.exams,
              (v) => ctrl.setCategory(exams: v)),
          const Divider(height: 1),
          _switchTile(theme, 'Habit reminders', prefs.habits,
              (v) => ctrl.setCategory(habits: v)),
          const Divider(height: 1),
          _proSwitchTile(
            context,
            theme,
            title: 'Daily agenda summary',
            subtitle: (prefs.dailySummary && isPro)
                ? 'Every day at ${prefs.summaryTime.format(context)} · tap to change'
                : 'A morning digest of your classes, tasks & exams',
            value: prefs.dailySummary && isPro,
            isPro: isPro,
            onChanged: (v) => ctrl.setDailySummary(v),
            onTap: (prefs.dailySummary && isPro)
                ? () async {
                    final t = await showTimePicker(
                        context: context, initialTime: prefs.summaryTime);
                    if (t != null) ctrl.setDailySummary(true, at: t);
                  }
                : null,
          ),
          const Divider(height: 1),
          _proSwitchTile(
            context,
            theme,
            title: 'Quiet hours',
            subtitle: (prefs.quietHours && isPro)
                ? '${prefs.quietStartHour}:00 – ${prefs.quietEndHour}:00 · tap to change'
                : 'Silence reminders during a set window',
            value: prefs.quietHours && isPro,
            isPro: isPro,
            onChanged: (v) => ctrl.setQuietHours(v),
            onTap: (prefs.quietHours && isPro)
                ? () => _editQuietHours(context, ref)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _switchTile(
      ThemeData theme, String title, bool value, ValueChanged<bool> onChanged,
      {String? subtitle}) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _proSwitchTile(
    BuildContext context,
    ThemeData theme, {
    required String title,
    required String subtitle,
    required bool value,
    required bool isPro,
    required ValueChanged<bool> onChanged,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Flexible(child: Text(title)),
          const SizedBox(width: 8),
          _proChip(theme),
        ],
      ),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: Switch(
        value: value,
        onChanged: (v) async {
          if (!isPro) {
            await showPaywall(context);
            return;
          }
          onChanged(v);
        },
      ),
      onTap: onTap,
    );
  }

  Widget _proChip(ThemeData theme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text('PRO',
            style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.primary, fontWeight: FontWeight.w700)),
      );

  Widget _comingSoonChip(ThemeData theme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: theme.hintColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text('COMING SOON',
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor, fontWeight: FontWeight.w700)),
      );

  Future<void> _editQuietHours(BuildContext context, WidgetRef ref) async {
    final prefs = ref.read(notificationPrefsProvider);
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: prefs.quietStartHour, minute: 0),
      helpText: 'Quiet hours START',
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: prefs.quietEndHour, minute: 0),
      helpText: 'Quiet hours END',
    );
    if (end == null) return;
    await ref
        .read(notificationPrefsProvider.notifier)
        .setQuietHours(true, startHour: start.hour, endHour: end.hour);
  }

  // ── Support & feedback ──────────────────────────────────────────────────
  Widget _supportCard(BuildContext context, WidgetRef ref, ThemeData theme) {
    return _card(
      theme,
      child: Column(
        children: [
          _actionTile(theme, Icons.star_rounded, 'Rate ClassTrack',
              () => _rate(context)),
          const Divider(height: 1),
          _actionTile(theme, Icons.ios_share_rounded, 'Share with friends',
              () => _shareApp()),
          const Divider(height: 1),
          _actionTile(theme, Icons.feedback_rounded, 'Send feedback',
              () => _sendFeedback()),
          const Divider(height: 1),
          _actionTile(theme, Icons.card_membership_rounded,
              'Manage subscription', () => _manageSubscription()),
          const Divider(height: 1),
          _actionTile(theme, Icons.restore_rounded, 'Restore purchases',
              () => _restorePurchases(context, ref)),
        ],
      ),
    );
  }

  Widget _actionTile(
      ThemeData theme, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  Future<void> _rate(BuildContext context) async {
    final market = Uri.parse(AppConstants.playStoreMarketUrl);
    if (!await launchUrl(market, mode: LaunchMode.externalApplication)) {
      await launchUrl(Uri.parse(AppConstants.playStoreUrl),
          mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareApp() async {
    await Share.share(
      'Check out ClassTrack — track your attendance, timetable, tasks, '
      'grades and expenses, with an AI study assistant:\n'
      '${AppConstants.playStoreUrl}',
      subject: 'ClassTrack',
    );
  }

  Future<void> _sendFeedback() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConstants.supportEmail,
      query: 'subject=${Uri.encodeComponent('ClassTrack feedback')}',
    );
    await launchUrl(uri);
  }

  Future<void> _manageSubscription() async {
    await launchUrl(Uri.parse(AppConstants.manageSubscriptionsUrl),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _restorePurchases(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(subscriptionServiceProvider).restore();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.message),
    ));
  }

  Widget _sectionLabel(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
        child: Text(text.toUpperCase(),
            style: theme.textTheme.labelMedium
                ?.copyWith(letterSpacing: 1.0, color: theme.hintColor)),
      );

  Widget _card(ThemeData theme, {required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: theme.brightness == Brightness.light
              ? AppColors.softShadow(opacity: 0.05, blur: 18)
              : null,
        ),
        child: child,
      );
}

/// A tappable theme-mode option showing a little live mock of the theme, with
/// a selected ring in the current accent color.
class _ThemeModeTile extends StatelessWidget {
  final ThemeMode mode;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _ThemeModeTile({
    required this.mode,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? accent.withValues(alpha: 0.06)
              : Colors.transparent,
          border: Border.all(
            color: selected ? accent : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            _preview(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  Icon(Icons.check_circle_rounded, size: 14, color: accent),
                  const SizedBox(width: 4),
                ],
                Text(label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? accent : null,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    const lightBg = Color(0xFFF4F3FB);
    const lightCard = Colors.white;
    const darkBg = Color(0xFF10131C);
    const darkCard = Color(0xFF1B2030);
    switch (mode) {
      case ThemeMode.light:
        return _mock(bg: lightBg, card: lightCard, line: Colors.black12);
      case ThemeMode.dark:
        return _mock(bg: darkBg, card: darkCard, line: Colors.white24);
      case ThemeMode.system:
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              Expanded(
                child: _mock(
                    bg: lightBg,
                    card: lightCard,
                    line: Colors.black12,
                    radius: 0),
              ),
              Expanded(
                child: _mock(
                    bg: darkBg,
                    card: darkCard,
                    line: Colors.white24,
                    radius: 0),
              ),
            ],
          ),
        );
    }
  }

  Widget _mock({
    required Color bg,
    required Color card,
    required Color line,
    double radius = 10,
  }) {
    return Container(
      height: 58,
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 4,
            decoration: BoxDecoration(
                color: accent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                  color: card, borderRadius: BorderRadius.circular(5)),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
                color: line, borderRadius: BorderRadius.circular(2)),
          ),
        ],
      ),
    );
  }
}

/// A single accent-color swatch with an animated selected ring + check.
class _AccentSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? theme.colorScheme.onSurface : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: selected ? 0.45 : 0.25),
              blurRadius: selected ? 10 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}
