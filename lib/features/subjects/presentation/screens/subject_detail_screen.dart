import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classtrack/core/theme/app_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/url_launcher_util.dart';
import '../../../../shared/widgets/progress_ring.dart';
import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../attendance/domain/attendance_record.dart';
import '../../../attendance/presentation/providers/attendance_providers.dart';
import '../../../attendance/presentation/widgets/bunk_calculator.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../schedule/presentation/providers/schedule_providers.dart';
import '../../domain/subject.dart';
import '../providers/subject_providers.dart';
import 'edit_subject_screen.dart';

class SubjectDetailScreen extends ConsumerWidget {
  final String subjectId;
  const SubjectDetailScreen({super.key, required this.subjectId});

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Subject subject) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete subject?'),
        content: Text(
            'This permanently removes "${subject.name}", its schedule and attendance.'),
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
    if (ok == true) {
      try {
        await ref.read(subjectRepositoryProvider)?.delete(subject.id);
        if (context.mounted) Navigator.of(context).pop();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectAsync = ref.watch(subjectProvider(subjectId));
    return subjectAsync.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(
          body: ErrorView(
              error: e,
              onRetry: () => ref.invalidate(subjectProvider(subjectId)))),
      data: (subject) {
        if (subject == null) {
          return const Scaffold(body: Center(child: Text('Subject not found')));
        }
        return _content(context, ref, subject);
      },
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, Subject subject) {
    final theme = Theme.of(context);
    final color = Color(subject.colorHex);
    final stats =
        AttendanceStats(present: subject.attended, absent: subject.missed);
    final target =
        subject.effectiveTarget(
            ref.watch(userProfileProvider).valueOrNull?.targetAttendancePercent ??
                AppConstants.defaultTargetAttendance);
    final sessions =
        ref.watch(sessionsForSubjectProvider(subject.id)).valueOrNull ?? const [];
    // Hide identical duplicate sessions (e.g. a class accidentally added twice)
    // so the weekly schedule shows each slot only once.
    final seenSig = <String>{};
    final uniqueSessions =
        sessions.where((s) => seenSig.add(s.signature)).toList();
    final controller = ref.read(attendanceControllerProvider);
    final records =
        ref.watch(attendanceForSubjectProvider(subject.id)).valueOrNull ??
            const [];

    // Mark "today" per session: target the next unmarked class occurrence for
    // today so a subject that meets twice today can be marked twice, and
    // re-marking (or marking from Home) never double-counts.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayId = DateUtilsX.dateId(today);
    // Returns false when the class was already in this state (nothing written),
    // so the caller can skip the confirmation toast.
    bool markToday(AttendanceStatus status) {
      final slots = uniqueSessions
          .where((s) => s.occursOn(today))
          .map((s) => s.startTime)
          .toList()
        ..sort();
      // Union the dated records with marks already issued from this client, so
      // a quick second tap advances to the next class instead of re-targeting
      // the first one before the records stream has caught up.
      final markedSlots = <String>{
        for (final r in records)
          if (r.dateId == todayId) r.slot,
        ...controller.pendingSlots(subject.id, today),
      };
      final slot = nextAttendanceSlot(slots, markedSlots);
      return controller.markOccurrence(subject.id, now, slot, status);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(subject.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EditSubjectScreen(subject: subject),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _confirmDelete(context, ref, subject),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _heroCard(context, subject, stats, color, target),
          const SizedBox(height: 16),
          // Attended / Missed / Cancelled / Total counters
          Row(
            children: [
              _countTile(theme, 'Attended', subject.attended, AppColors.present),
              const SizedBox(width: 10),
              _countTile(theme, 'Missed', subject.missed, AppColors.absent),
              const SizedBox(width: 10),
              _countTile(theme, 'Cancelled', subject.cancelled,
                  AppColors.cancelled),
              const SizedBox(width: 10),
              _countTile(theme, 'Total', subject.held, AppColors.primary),
            ],
          ),
          const SizedBox(height: 20),
          _historyStrip(context, ref, subject, records),
          _sectionTitle(theme, 'Mark today'),
          // Big, interactive mark buttons with haptic + toast feedback.
          Row(
            children: [
              Expanded(
                child: _detailMark(
                    context,
                    'Present',
                    Icons.check_rounded,
                    AppColors.success,
                    () => markToday(AttendanceStatus.present),
                    'Marked present in ${subject.name}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _detailMark(
                    context,
                    'Absent',
                    Icons.close_rounded,
                    AppColors.danger,
                    () => markToday(AttendanceStatus.absent),
                    'Marked absent in ${subject.name}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _detailMark(
                    context,
                    'Cancelled',
                    Icons.event_busy_rounded,
                    AppColors.cancelled,
                    () => markToday(AttendanceStatus.cancelled),
                    '${subject.name} class cancelled'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Fine adjust steppers
          _adjustRow(context, ref, subject),
          const SizedBox(height: 18),
          BunkCalculator(stats: stats, target: target),
          const SizedBox(height: 24),
          _sectionTitle(theme, 'Weekly schedule'),
          if (uniqueSessions.isEmpty)
            _emptyHint(theme, 'No classes scheduled yet.')
          else
            ...uniqueSessions.map((s) => _sessionTile(context, theme, s, color)),
          const SizedBox(height: 20),
          _sectionTitle(theme, 'Quick links'),
          if (subject.classLink != null && subject.classLink!.isNotEmpty)
            _linkTile(context,
                icon: Icons.videocam_rounded,
                label: 'Join class',
                subtitle: subject.classLink!,
                color: AppColors.primary,
                onShare: () => Share.share(subject.classLink!),
                url: subject.classLink!),
          ...subject.resourceLinks.map((l) => _linkTile(context,
              icon: Icons.link_rounded,
              label: l.title,
              subtitle: l.url,
              color: AppColors.info,
              onShare: () => Share.share('${l.title}: ${l.url}'),
              url: l.url)),
          if ((subject.classLink == null || subject.classLink!.isEmpty) &&
              subject.resourceLinks.isEmpty)
            _emptyHint(theme, 'No links added yet.'),
        ],
      ),
    );
  }

  /// Gradient hero: the attendance ring beside the subject's key status.
  Widget _heroCard(BuildContext context, Subject subject, AttendanceStats stats,
      Color color, double target) {
    final theme = Theme.of(context);
    final hasData = subject.held > 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.20),
            color.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          AnimatedProgressRing(
            percent: stats.percent,
            size: 112,
            strokeWidth: 9,
            color: color,
            subLabel: hasData ? 'attendance' : 'no data',
            centerLabel: hasData ? null : '—',
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject.name,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (subject.professor != null &&
                    subject.professor!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subject.professor!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 12),
                _statusChip(theme, stats, target),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(ThemeData theme, AttendanceStats stats, double target) {
    if (stats.held == 0) {
      return _pill(Icons.info_outline_rounded, 'Mark a class to start',
          theme.hintColor);
    }
    final onTrack = stats.percent >= target;
    if (onTrack) {
      final skip = stats.bunkableClasses(target);
      return _pill(
          Icons.verified_rounded,
          skip > 0 ? 'On track · can skip $skip' : 'On track',
          AppColors.success);
    }
    final need = stats.classesToRecover(target);
    return _pill(
        Icons.trending_up_rounded,
        need > 0
            ? 'Attend $need to reach ${target.toStringAsFixed(0)}%'
            : 'Below target',
        AppColors.danger);
  }

  Widget _pill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: theme.textTheme.bodySmall),
      );

  /// Interactive recent-attendance strip: the last marked days as colored dots.
  /// Tapping a dot lets the student correct or clear that day's attendance.
  Widget _historyStrip(BuildContext context, WidgetRef ref, Subject subject,
      List<AttendanceRecord> records) {
    if (records.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    // Collapse duplicate / superseded records so a single class occurrence is
    // shown only once (fixes e.g. 3 dots for 2 marked classes).
    final deduped = dedupeAttendanceRecords(records);
    final sorted = [...deduped]..sort((a, b) => a.date.compareTo(b.date));
    final recent =
        sorted.length > 16 ? sorted.sublist(sorted.length - 16) : sorted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, 'Recent attendance'),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: recent.map((r) {
              final c = r.status.color;
              return Tooltip(
                message:
                    '${DateUtilsX.prettyDate(r.date)} · ${r.status.label} · tap to edit',
                child: InkWell(
                  onTap: () => _editRecord(context, ref, subject, r),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(r.status.icon, size: 14, color: c),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a day to change or clear it',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet to correct a single past attendance day/occurrence. Reuses the
  /// idempotent, counter-syncing write path, so changing or clearing a day keeps
  /// the aggregate Attended/Missed/Cancelled totals correct.
  Future<void> _editRecord(BuildContext context, WidgetRef ref,
      Subject subject, AttendanceRecord r) async {
    final controller = ref.read(attendanceControllerProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        Widget option(
            String label, IconData icon, Color color, AttendanceStatus status) {
          final selected = r.status == status;
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            title: Text(label),
            trailing:
                selected ? Icon(Icons.check_rounded, color: color) : null,
            onTap: () {
              Navigator.pop(ctx);
              controller.setForOccurrence(subject.id, r.date, r.slot, status);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
                child: Text(DateUtilsX.prettyFullDate(r.date),
                    style: theme.textTheme.titleMedium),
              ),
              if (r.slot.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Class at ${DateUtilsX.displayTime(ctx, r.slot)}',
                      style: theme.textTheme.bodySmall),
                ),
              option('Present', Icons.check_rounded, AppColors.success,
                  AttendanceStatus.present),
              option('Absent', Icons.close_rounded, AppColors.danger,
                  AttendanceStatus.absent),
              option('Cancelled', Icons.event_busy_rounded,
                  AppColors.cancelled, AttendanceStatus.cancelled),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Clear this day'),
                onTap: () {
                  Navigator.pop(ctx);
                  controller.setForOccurrence(
                      subject.id, r.date, r.slot, AttendanceStatus.unmarked);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _detailMark(BuildContext context, String label, IconData icon,
      Color color, bool Function() onTap, String toast) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Skip the haptic + toast when the class was already in this state:
          // re-showing an identical confirmation made the bar flash while the
          // counters stayed put, which read as a glitch.
          if (!onTap()) return;
          HapticFeedback.lightImpact();
          showQuickFeedback(context, toast,
              background: color,
              duration: const Duration(milliseconds: 1100));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    shape: BoxShape.circle),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countTile(ThemeData theme, String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text('$value',
                style: theme.textTheme.headlineSmall?.copyWith(color: color)),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _adjustRow(BuildContext context, WidgetRef ref, Subject subject) {
    final theme = Theme.of(context);
    final controller = ref.read(attendanceControllerProvider);
    Widget stepper(String label, int value, VoidCallback dec, VoidCallback inc) {
      return Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
              onPressed: dec,
            ),
            Column(
              children: [
                Text('$value', style: theme.textTheme.titleMedium),
                Text(label, style: theme.textTheme.bodySmall),
              ],
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              onPressed: inc,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          stepper(
            'Present',
            subject.attended,
            () => controller.adjustAttended(subject.id, -1),
            () => controller.adjustAttended(subject.id, 1),
          ),
          Container(width: 1, height: 40, color: theme.dividerColor),
          stepper(
            'Absent',
            subject.absent,
            () => controller.adjustAbsent(subject.id, -1),
            () => controller.adjustAbsent(subject.id, 1),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text, style: theme.textTheme.titleMedium),
      );

  Widget _sessionTile(
      BuildContext context, ThemeData theme, session, Color color) {
    final dayLabel = session.recurring && session.dayOfWeek != null
        ? Weekdays.full[session.dayOfWeek as int]
        : (session.specificDate != null
            ? DateUtilsX.prettyDate(session.specificDate)
            : 'One-off');
    final time =
        '${DateUtilsX.displayTime(context, session.startTime)} – ${DateUtilsX.displayTime(context, session.endTime)}';
    final hasRoom =
        session.room != null && (session.room as String).isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(PhosphorIcons.clock(), size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dayLabel,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(time, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (hasRoom)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.place_outlined,
                      size: 13, color: theme.hintColor),
                  const SizedBox(width: 4),
                  Text(session.room as String,
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _linkTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onShare,
    required String url,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openUrl(context, url),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.titleMedium),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                  onPressed: onShare,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
