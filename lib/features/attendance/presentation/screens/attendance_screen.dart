import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classtrack/core/theme/app_icons.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../../shared/widgets/progress_ring.dart';
import '../../../../shared/widgets/placement_slot.dart';
import '../../../cms/domain/marketing.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../import/presentation/screens/import_screen.dart';
import '../../../schedule/presentation/providers/schedule_providers.dart';
import '../../../subjects/domain/subject.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../subjects/presentation/screens/edit_subject_screen.dart';
import '../../../subjects/presentation/screens/subject_detail_screen.dart';
import '../../domain/attendance_record.dart';
import '../providers/attendance_providers.dart';
import '../widgets/attendance_calendar.dart';

/// Attendance overview: an overall hero ring plus a per-subject breakdown with
/// quick present/absent/cancelled marking and a manual counts editor.
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectsAsync = ref.watch(subjectsStreamProvider);
    final target =
        ref.watch(userProfileProvider).valueOrNull?.targetAttendancePercent ??
            AppConstants.defaultTargetAttendance;
    final overall = ref.watch(overallStatsProvider);
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Row(
                children: [
                  if (canPop) ...[
                    RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      semanticLabel: 'Back',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text('Attendance', style: theme.textTheme.displaySmall),
                  const Spacer(),
                  RoundIconButton(
                    icon: Icons.add_rounded,
                    background: AppColors.primary,
                    iconColor: Colors.white,
                    semanticLabel: 'Add subject',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const EditSubjectScreen()),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: subjectsAsync.when(
                loading: () => const SkeletonList(showTrailing: true),
                error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(subjectsStreamProvider)),
                data: (subjects) {
                  if (subjects.isEmpty) {
                    return const _NoSubjectsView();
                  }
                  return ListView(
                    // Extra bottom padding so the last subject's mark buttons
                    // clear the floating bottom nav bar + FAB (the shell uses
                    // extendBody: true, so content draws under the pill).
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    children: [
                      _OverallCard(overall: overall, target: target),
                      const SizedBox(height: 16),
                      const PlacementSlot(placement: Placements.attendance),
                      const SizedBox(height: 6),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: SectionHeader(title: 'By subject'),
                      ),
                      const SizedBox(height: 10),
                      ...subjects.map(
                        (s) => _SubjectAttendanceCard(subject: s, target: target),
                      ),
                      const SizedBox(height: 8),
                      const AttendanceCalendar(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The gradient hero showing overall attendance, a ring, and a mini-breakdown.
class _OverallCard extends StatelessWidget {
  final AttendanceStats overall;
  final double target;
  const _OverallCard({required this.overall, required this.target});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final has = overall.held > 0;
    final pct = overall.percent;
    final onTrack = has && pct >= target;

    final statusLine = !has
        ? 'Start marking classes to see your trend'
        : onTrack
            ? 'On track — you\'re at or above your ${target.toStringAsFixed(0)}% target'
            : 'Below your ${target.toStringAsFixed(0)}% target — attend the next few';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: AppColors.softShadow(opacity: 0.18, blur: 26),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overall attendance',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      has
                          ? '${overall.present} attended of ${overall.held}'
                          : 'No classes logged yet',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          onTrack
                              ? Icons.trending_up_rounded
                              : Icons.info_outline_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            statusLine,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              AnimatedProgressRing(
                percent: has ? pct : 0,
                size: 96,
                strokeWidth: 10,
                color: Colors.white,
                centerLabel: has ? null : '—',
                subLabel: 'overall',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _miniStat(theme, 'Attended', overall.present),
              const SizedBox(width: 10),
              _miniStat(theme, 'Missed', overall.absent),
              const SizedBox(width: 10),
              _miniStat(theme, 'Cancelled', overall.cancelled),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(ThemeData theme, String label, int value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectAttendanceCard extends ConsumerWidget {
  final Subject subject;
  final double target;
  const _SubjectAttendanceCard({required this.subject, required this.target});

  Color _ringColor(double pct, double target, ThemeData theme) {
    if (subject.held == 0) return theme.hintColor;
    if (pct >= target) return AppColors.success;
    if (pct >= target - 15) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = Color(subject.colorHex);
    final pct = subject.percent;
    final effTarget = subject.effectiveTarget(target);
    final ringColor = _ringColor(pct, effTarget, theme);
    final stats = AttendanceStats(present: subject.attended, absent: subject.missed);
    final onTrack = subject.held > 0 && pct >= effTarget;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: softCard(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SubjectDetailScreen(subjectId: subject.id),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.menu_book_rounded, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${subject.attended} attended · ${subject.missed} missed · ${subject.held} total',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (subject.room != null &&
                          subject.room!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.meeting_room_outlined,
                                size: 13, color: theme.hintColor),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(subject.room!,
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 56,
                  height: 56,
                  child: AnimatedProgressRing(
                    percent: subject.held == 0 ? 0 : pct,
                    size: 56,
                    strokeWidth: 6,
                    color: ringColor,
                    centerLabel: subject.held == 0 ? '—' : null,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: theme.hintColor),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ProgressBar(
            value: subject.held == 0 ? 0 : subject.attended / subject.held,
            targetFraction: (effTarget / 100).clamp(0.0, 1.0),
            color: ringColor,
          ),
          if (subject.held > 0) ...[
            const SizedBox(height: 12),
            _bunkHintPill(theme, stats, effTarget, onTrack),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _ActionButton(
                status: AttendanceStatus.present,
                onTap: () => _markNow(ref, AttendanceStatus.present),
              ),
              const SizedBox(width: 8),
              _ActionButton(
                status: AttendanceStatus.absent,
                onTap: () => _markNow(ref, AttendanceStatus.absent),
              ),
              const SizedBox(width: 8),
              _ActionButton(
                status: AttendanceStatus.cancelled,
                onTap: () => _markNow(ref, AttendanceStatus.cancelled),
              ),
              const SizedBox(width: 8),
              // Manual counts editor.
              Material(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => _openEditor(context, ref),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.tune_rounded,
                        size: 20, color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bunkHintPill(
      ThemeData theme, AttendanceStats stats, double target, bool onTrack) {
    final String text;
    if (stats.percent >= target) {
      final canSkip = stats.bunkableClasses(target);
      text = canSkip <= 0
          ? 'Right on your ${target.toStringAsFixed(0)}% target'
          : 'You can skip $canSkip more and stay ≥ ${target.toStringAsFixed(0)}%';
    } else {
      final need = stats.classesToRecover(target);
      text = need <= 0
          ? 'Below your ${target.toStringAsFixed(0)}% target'
          : 'Attend $need in a row to reach ${target.toStringAsFixed(0)}%';
    }
    final tint = onTrack ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            onTrack ? Icons.sentiment_satisfied_rounded : Icons.warning_amber_rounded,
            size: 16,
            color: tint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: tint, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Records a quick mark as a dated occurrence for *today*, keyed by the
  /// class's session start time — the SAME per-occurrence key the home timeline
  /// and subject screen use — so marking here also flips the matching timeline
  /// tile and never double-counts. When the subject has no class scheduled
  /// today (an ad-hoc extra class) we fall back to a unique per-tap time slot so
  /// repeated quick marks each still count. Bulk/historical edits use the manual
  /// counts editor (tune icon).
  void _markNow(WidgetRef ref, AttendanceStatus status) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayId = DateUtilsX.dateId(today);
    final controller = ref.read(attendanceControllerProvider);

    final todaySlots = ref
        .read(sessionsForSubjectProvider(subject.id))
        .valueOrNull
        ?.where((s) => s.occursOn(today))
        .map((s) => s.startTime)
        .toList()
      ?..sort();

    if (todaySlots == null || todaySlots.isEmpty) {
      // No scheduled class today — record an ad-hoc occurrence with a unique
      // per-tap slot so several quick marks in a row each count.
      String two(int n) => n.toString().padLeft(2, '0');
      final slot = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
      if (controller.markOccurrence(subject.id, now, slot, status)) {
        HapticFeedback.selectionClick();
      }
      return;
    }

    // Mark the next unmarked scheduled occurrence using its session start time.
    // The "already marked" set unions the records stream with the marks this
    // client has just issued — without the pending half, two quick taps on a
    // two-class day both saw an empty set and re-targeted the FIRST class.
    final records =
        ref.read(dedupedAttendanceForSubjectProvider(subject.id));
    final markedSlots = <String>{
      for (final r in records)
        if (r.dateId == todayId && r.slot.isNotEmpty) r.slot,
      ...controller.pendingSlots(subject.id, today),
    };
    final slot = nextAttendanceSlot(todaySlots, markedSlots);
    // Tactile confirmation for the core daily action — a crisp selection tick
    // makes marking feel registered and reinforces the habit loop. Only fired
    // when the mark actually changed state.
    if (controller.markOccurrence(subject.id, now, slot, status)) {
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<({int attended, int total})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _EditAttendanceSheet(subject: subject),
    );
    if (result != null) {
      // Count what the dated attendance records already contribute so the
      // manual total can never be set below the calendar (drift guard — see
      // SubjectRepository.setAttendance).
      final records = ref.read(dedupedAttendanceForSubjectProvider(subject.id));
      var dPresent = 0, dAbsent = 0;
      for (final r in records) {
        if (r.status == AttendanceStatus.present) {
          dPresent++;
        } else if (r.status == AttendanceStatus.absent) {
          dAbsent++;
        }
      }
      // setCounts expects (attended, ABSENT); convert the collected total.
      ref.read(attendanceControllerProvider).setCounts(
            subject.id,
            result.attended,
            result.total - result.attended,
            minAttended: dPresent,
            minAbsent: dAbsent,
          );
    }
  }
}

/// A rounded progress bar with a subtle target marker tick.
class _ProgressBar extends StatelessWidget {
  final double value; // 0..1
  final double targetFraction; // 0..1
  final Color color;
  const _ProgressBar({
    required this.value,
    required this.targetFraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tickColor = theme.brightness == Brightness.light
        ? AppColors.ink.withValues(alpha: 0.35)
        : Colors.white54;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 10,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: (width * targetFraction).clamp(0.0, width - 2),
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: tickColor),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A tinted, equal-width quick-mark button (present / absent / cancelled).
class _ActionButton extends StatelessWidget {
  final AttendanceStatus status;
  final VoidCallback onTap;
  const _ActionButton({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Expanded(
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Column(
              children: [
                Icon(status.icon, size: 20, color: color),
                const SizedBox(height: 3),
                Text(
                  status.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet editor for a subject's raw attendance counts, with a live
/// preview ring. Pops with the chosen (attended, total); the caller converts
/// total → absent and persists via the attendance controller.
class _EditAttendanceSheet extends StatefulWidget {
  final Subject subject;
  const _EditAttendanceSheet({required this.subject});

  @override
  State<_EditAttendanceSheet> createState() => _EditAttendanceSheetState();
}

class _EditAttendanceSheetState extends State<_EditAttendanceSheet> {
  late int _attended = widget.subject.attended;
  late int _total = widget.subject.held;

  double get _pct => _total == 0 ? 0 : _attended / _total * 100;

  void _setAttended(int v) => setState(() {
        _attended = v < 0 ? 0 : v;
        if (_attended > _total) _total = _attended;
      });

  void _setTotal(int v) => setState(() {
        _total = v < _attended ? _attended : v;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(widget.subject.colorHex);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.subject.name,
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Adjust your recorded classes',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 18),
          Center(
            child: AnimatedProgressRing(
              percent: _pct,
              size: 108,
              strokeWidth: 11,
              subLabel: '$_attended / $_total',
            ),
          ),
          const SizedBox(height: 22),
          _StepperCard(
            label: 'Attended',
            value: _attended,
            color: AppColors.success,
            onChanged: _setAttended,
          ),
          const SizedBox(height: 12),
          _StepperCard(
            label: 'Total classes',
            value: _total,
            color: AppColors.primary,
            onChanged: _setTotal,
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () =>
                Navigator.pop(context, (attended: _attended, total: _total)),
            child: const Text('Save'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// A labelled row with round -/+ steppers and the current value, in a soft card.
class _StepperCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;
  const _StepperCard({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardBg = theme.brightness == Brightness.dark
        ? AppColors.darkSurfaceAlt
        : AppColors.lavenderSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          _RoundStep(
            icon: Icons.remove_rounded,
            color: color,
            onTap: () => onChanged(value - 1),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          _RoundStep(
            icon: Icons.add_rounded,
            color: color,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _RoundStep extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _RoundStep({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}



/// Empty state shown to a brand-new user with no subjects yet. Puts a big,
/// centered add button front-and-centre that opens a chooser to create a
/// subject, import from Google Calendar, or scan a timetable photo.
class _NoSubjectsView extends ConsumerWidget {
  const _NoSubjectsView();

  void _showStartOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
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
            onTap: onTap,
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            title: Text(title, style: theme.textTheme.titleMedium),
            subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
            trailing: const Icon(Icons.chevron_right_rounded),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Add subjects', style: theme.textTheme.titleLarge),
              ),
              option(
                icon: Icons.menu_book_rounded,
                color: AppColors.primary,
                title: 'Create a subject',
                subtitle: 'Add one course and track its attendance',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const EditSubjectScreen()));
                },
              ),
              option(
                icon: Icons.document_scanner_rounded,
                color: AppColors.coral,
                title: 'Scan a timetable',
                subtitle: 'Free — read a photo or paste text with AI',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ImportScreen(freeAccess: true)),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(PhosphorIcons.chartPieSlice(),
                  size: 44, color: AppColors.accent),
            ),
            const SizedBox(height: 20),
            Text('No subjects yet',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Add subjects first, then track how many classes you attend '
              'for each.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.textTheme.bodySmall?.color),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            // Big, centered add button — the primary call-to-action for new
            // users. Opens a chooser (create / import / scan).
            Semantics(
              button: true,
              label: 'Add subjects',
              child: InkWell(
                borderRadius: BorderRadius.circular(40),
                onTap: () => _showStartOptions(context, ref),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryLight, AppColors.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.40),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 34),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Create subject · Import · Scan timetable',
                style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
