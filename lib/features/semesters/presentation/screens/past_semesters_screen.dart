import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../grades/presentation/providers/grade_providers.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';
import '../../domain/semester.dart';
import '../providers/semester_providers.dart';
import 'semester_detail_screen.dart';
import 'wrap_up_semester_screen.dart';

/// Opens Past semesters. Free users without any archive see the Pro prompt
/// first; anyone who already has past semesters can always open the list
/// (so a lapsed Pro user can still restore their data).
Future<void> openPastSemesters(BuildContext context, WidgetRef ref) async {
  var hasArchive = false;
  if (!ref.read(isProProvider)) {
    try {
      hasArchive = (await ref
              .read(semestersStreamProvider.future)
              .timeout(const Duration(seconds: 3)))
          .isNotEmpty;
    } catch (_) {
      // Offline/slow: fall through to the Pro prompt.
    }
    if (!context.mounted) return;
  }
  if (!hasArchive &&
      !await requirePro(context, ref, UpgradeReason.semesters)) {
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
      MaterialPageRoute(settings: const RouteSettings(name: 'Past Semesters'), builder: (_) => const PastSemestersScreen()));
}

/// CGPA plus every wrapped-up semester, newest first.
class PastSemestersScreen extends ConsumerWidget {
  const PastSemestersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semestersAsync = ref.watch(semestersStreamProvider);
    final cgpa = ref.watch(cgpaProvider);
    final isPro = ref.watch(isProProvider);
    final tenPoint = ref.watch(gpaScaleProvider) == GpaScaleType.ten;
    final current = ref.watch(gpaSummaryProvider);
    final hasCurrent =
        (ref.watch(subjectsStreamProvider).valueOrNull ?? const []).isNotEmpty ||
            ref.watch(gradesStreamProvider).valueOrNull?.isNotEmpty == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Past semesters')),
      body: semestersAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(semestersStreamProvider)),
        data: (semesters) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _cgpaCard(theme, cgpa, semesters.length, tenPoint,
                current.gradedSubjects > 0 ? current.gpa : null, isPro),
            const SizedBox(height: 14),
            if (hasCurrent)
              OutlinedButton.icon(
                onPressed: () => startSemesterWrapUp(context, ref),
                icon: const Icon(Icons.inventory_2_rounded),
                label: const Text('Wrap up current semester'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
              ),
            const SizedBox(height: 20),
            if (semesters.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: EmptyState(
                  icon: Icons.history_edu_rounded,
                  title: 'No past semesters yet',
                  message: 'When your semester ends, wrap it up to save its '
                      'subjects, marks, exams and attendance here and start '
                      'the next one fresh.',
                ),
              ),
            for (var i = 0; i < semesters.length; i++)
              _SemesterCard(semester: semesters[i], locked: !isPro)
                  .listEntrance(i),
          ],
        ),
      ),
    );
  }

  Widget _cgpaCard(ThemeData theme, double? cgpa, int count, bool tenPoint,
      double? currentGpa, bool isPro) {
    final max = tenPoint ? '/ 10' : '/ 4.0';
    final shown = isPro ? cgpa : null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CGPA',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: Colors.white70)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                      !isPro && cgpa != null
                          ? '🔒'
                          : shown == null
                              ? '—'
                              : shown.toStringAsFixed(2),
                      style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 34)),
                  const SizedBox(width: 6),
                  Text(max,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white70)),
                ],
              ),
              Text(
                  'Across $count past semester${count == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white70)),
            ],
          ),
        ),
        if (currentGpa != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(currentGpa.toStringAsFixed(2),
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              Text('This semester',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: Colors.white70)),
            ],
          ),
      ]),
    );
  }
}

class _SemesterCard extends ConsumerWidget {
  final Semester semester;

  /// Non-Pro (e.g. lapsed) users see the list but must upgrade to open a
  /// semester. Restore always works so their data is never stuck.
  final bool locked;
  const _SemesterCard({required this.semester, required this.locked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(semesterStatsProvider(semester.id));
    final sgpa = stats.sgpa;
    final att = stats.attendancePercent;
    final df = DateFormat('MMM yyyy');
    final dates = [semester.startDate, semester.endDate]
        .whereType<DateTime>()
        .map(df.format)
        .toSet()
        .join(' – ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: softCard(context, radius: 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          if (locked &&
              !await requirePro(context, ref, UpgradeReason.semesters)) {
            return;
          }
          if (!context.mounted) return;
          Navigator.of(context).push(MaterialPageRoute(
              settings: const RouteSettings(name: 'Semester Detail'),
              builder: (_) => SemesterDetailScreen(semesterId: semester.id)));
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                  locked
                      ? '🔒'
                      : sgpa == null
                          ? '—'
                          : sgpa.toStringAsFixed(2),
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(semester.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    [
                      if (dates.isNotEmpty) dates,
                      '${stats.subjects.length} subject${stats.subjects.length == 1 ? '' : 's'}',
                      if (att != null) '${att.round()}% attendance',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v != 'restore') return;
                if (!await confirmRestoreSemester(context, semester.name)) {
                  return;
                }
                await ref.read(semesterControllerProvider).restore(semester.id);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'restore',
                    child: Text('Restore to current semester')),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
