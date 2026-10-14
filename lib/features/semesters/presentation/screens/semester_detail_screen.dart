import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/subject_icons.dart';
import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../exams/domain/exam.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../grades/domain/grade_item.dart';
import '../../../grades/presentation/providers/grade_providers.dart';
import '../../../grades/presentation/screens/grades_screen.dart';
import '../../../subjects/domain/subject.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../domain/semester.dart';
import '../providers/semester_providers.dart';
import 'semester_wrapped_screen.dart';

/// One past semester: SGPA, attendance, every subject with its marks and
/// final result, and its exams. Marks stay editable after wrap-up.
class SemesterDetailScreen extends ConsumerWidget {
  final String semesterId;

  /// Shows the "share your Semester Wrapped" banner right after wrap-up.
  final bool justWrapped;

  const SemesterDetailScreen(
      {super.key, required this.semesterId, this.justWrapped = false});

  static String fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semester = ref.watch(semesterByIdProvider(semesterId));
    final loading = ref.watch(semestersStreamProvider).isLoading;
    if (semester == null) {
      return Scaffold(
        appBar: AppBar(),
        body: loading
            ? const LoadingView()
            : const EmptyState(
                icon: Icons.inventory_2_rounded,
                title: 'Semester not found',
                message: 'It may have been restored to the current semester.',
              ),
      );
    }
    final stats = ref.watch(semesterStatsProvider(semesterId));
    final tenPoint = ref.watch(gpaScaleProvider) == GpaScaleType.ten;
    final subjects = [for (final r in stats.subjects) r.subject];
    final exams = (ref.watch(allExamsStreamProvider).valueOrNull ?? const [])
        .where((e) => e.semesterId == semesterId)
        .toList();
    final subjectIds = {for (final s in subjects) s.id};
    final otherGrades =
        (ref.watch(allGradesStreamProvider).valueOrNull ?? const [])
            .where((g) =>
                g.semesterId == semesterId &&
                (g.subjectId == null || !subjectIds.contains(g.subjectId)))
            .toList();
    final df = DateFormat('d MMM yyyy');
    final dates = [semester.startDate, semester.endDate]
        .whereType<DateTime>()
        .map(df.format)
        .join(' – ');

    return Scaffold(
      appBar: AppBar(
        title: Text(semester.name),
        actions: [
          IconButton(
            tooltip: 'Share Semester Wrapped',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => _openWrapped(context),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'rename') _rename(context, ref, semester);
              if (v == 'restore') _restore(context, ref, semester);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(
                  value: 'restore', child: Text('Restore to current semester')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          if (dates.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(dates, style: theme.textTheme.bodySmall),
            ),
          if (justWrapped) ...[
            _wrappedBanner(context, theme),
            const SizedBox(height: 14),
          ],
          _statsCard(context, ref, theme, semester, stats, tenPoint),
          const SizedBox(height: 22),
          Text('Subjects', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Tap a subject to add its final grade and credits.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          if (stats.subjects.isEmpty)
            _note(context, 'No subjects in this semester.'),
          for (final r in stats.subjects)
            _SubjectResultCard(
                result: r,
                semesterId: semesterId,
                semesterSubjects: subjects,
                tenPoint: tenPoint),
          if (otherGrades.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Other grades', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: softCard(context, radius: 18),
              child: Column(children: [
                for (final g in otherGrades)
                  _gradeRow(context, g, subjects, semesterId),
              ]),
            ),
          ],
          const SizedBox(height: 22),
          Text('Exams', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (exams.isEmpty) _note(context, 'No exams saved for this semester.'),
          if (exams.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: softCard(context, radius: 18),
              child: Column(children: [
                for (final e in exams) _examRow(context, ref, e),
              ]),
            ),
        ],
      ),
    );
  }

  void _openWrapped(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'Semester Wrapped'),
        builder: (_) => SemesterWrappedScreen(semesterId: semesterId)));
  }

  Widget _wrappedBanner(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFFEC4899)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        const Text('🎉', style: TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Semester wrapped!',
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              Text('Your timetable is clear for the next one.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white70)),
            ],
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              // The theme makes buttons full-width; inside a Row that is
              // infinite, so give this one an intrinsic size.
              minimumSize: const Size(0, 40),
              backgroundColor: Colors.white, foregroundColor: AppColors.primary),
          onPressed: () => _openWrapped(context),
          child: const Text('Share'),
        ),
      ]),
    );
  }

  Widget _statsCard(BuildContext context, WidgetRef ref, ThemeData theme,
      Semester semester, SemesterStats stats, bool tenPoint) {
    final sgpa = stats.sgpa;
    final att = stats.attendancePercent;
    Widget stat(String value, String label) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w800)),
            Text(label,
                style:
                    theme.textTheme.labelSmall?.copyWith(color: Colors.white70)),
          ],
        );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('SGPA',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: Colors.white70)),
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: stats.officialSgpa != null
                    ? _pill('Official')
                    : sgpa != null
                        ? _pill('Estimated')
                        : const SizedBox.shrink(),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: () => _editSgpa(context, ref, semester),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: Text(stats.officialSgpa == null ? 'Add official' : 'Edit'),
            ),
          ]),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(sgpa == null ? '—' : sgpa.toStringAsFixed(2),
                  style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 34)),
              const SizedBox(width: 6),
              Text(tenPoint ? '/ 10' : '/ 4.0',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: stat(att == null ? '—' : '${att.round()}%', 'Attendance')),
            Expanded(child: stat('${stats.attended}/${stats.held}', 'Classes')),
            Expanded(child: stat('${stats.subjects.length}', 'Subjects')),
            Expanded(child: stat('${stats.examCount}', 'Exams')),
          ]),
        ],
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _note(BuildContext context, String text) => Container(
        padding: const EdgeInsets.all(16),
        decoration: softCard(context, radius: 18),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );

  Widget _examRow(BuildContext context, WidgetRef ref, Exam e) {
    final theme = Theme.of(context);
    final subject = ref.watch(subjectsByIdProvider)[e.subjectId];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        const Icon(Icons.event_note_rounded, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (subject != null)
                Text(subject.name, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Text(DateFormat('d MMM').format(e.date),
            style: theme.textTheme.bodySmall),
      ]),
    );
  }

  Future<void> _editSgpa(
      BuildContext context, WidgetRef ref, Semester semester) async {
    final c = TextEditingController(
        text: semester.officialSgpa == null ? '' : fmt(semester.officialSgpa!));
    final max = maxSgpaFor(ref.read(gpaScaleProvider) == GpaScaleType.ten);
    String? error;
    final result = await showDialog<(bool, double?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Official SGPA'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          onChanged: (_) {
            if (error != null) setDialogState(() => error = null);
          },
          decoration: InputDecoration(
              helperText: 'From your result (0–${fmt(max)}). Leave empty to use your marks.',
              errorText: error),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final t = c.text.trim();
              final v = t.isEmpty ? null : double.tryParse(t);
              if (t.isNotEmpty && !isValidSgpa(v, max)) {
                setDialogState(
                    () => error = 'Enter a number from 0 to ${fmt(max)}');
                return;
              }
              Navigator.pop(ctx, (true, v));
            },
            child: const Text('Save'),
          ),
        ],
      ),
      ),
    );
    if (result == null) return;
    await ref
        .read(semesterControllerProvider)
        .setOfficialSgpa(semester.id, result.$2);
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, Semester semester) async {
    final c = TextEditingController(text: semester.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename semester'),
        content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(semesterControllerProvider).rename(semester.id, name);
  }

  Future<void> _restore(
      BuildContext context, WidgetRef ref, Semester semester) async {
    final ok = await confirmRestoreSemester(context, semester.name);
    if (!ok) return;
    await ref.read(semesterControllerProvider).restore(semester.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${semester.name} is back in your current semester.')));
      Navigator.of(context).pop();
    }
  }
}

/// Shared confirm dialog for "Restore to current semester".
Future<bool> confirmRestoreSemester(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Restore $name?'),
      content: const Text(
          'Its subjects, grades and exams move back to your current semester. '
          'Their classes return to your timetable.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore')),
      ],
    ),
  );
  return ok == true;
}

Widget _gradeRow(BuildContext context, GradeItem g, List<Subject> subjects,
    String semesterId) {
  final theme = Theme.of(context);
  return InkWell(
    onTap: () => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => GradeEditorSheet(
          initial: g, subjects: subjects, semesterId: semesterId),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Expanded(
          child: Text(g.title,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        Text(
            '${SemesterDetailScreen.fmt(g.score)}/'
            '${SemesterDetailScreen.fmt(g.maxScore)}',
            style: theme.textTheme.bodySmall),
        const SizedBox(width: 10),
        Text('${g.percent.toStringAsFixed(0)}%',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _SubjectResultCard extends ConsumerWidget {
  final SubjectResult result;
  final String semesterId;
  final List<Subject> semesterSubjects;
  final bool tenPoint;

  const _SubjectResultCard({
    required this.result,
    required this.semesterId,
    required this.semesterSubjects,
    required this.tenPoint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = result.subject;
    final color = Color(s.colorHex);
    final grades = (ref.watch(allGradesStreamProvider).valueOrNull ?? const [])
        .where((g) => g.subjectId == s.id)
        .toList();
    final letter = result.letter;
    final points = result.points;
    final course = result.computed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: softCard(context, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _editFinal(context, ref),
            borderRadius: BorderRadius.circular(12),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(SubjectIcons.resolve(s.iconKey),
                    color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      [
                        '${s.credits ?? 1} credit${(s.credits ?? 1) == 1 ? '' : 's'}',
                        if (s.held > 0) '${s.percent.round()}% attendance',
                        if (course.count > 0)
                          '${course.percent.toStringAsFixed(0)}% in marks',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(letter ?? '—',
                      style: theme.textTheme.titleLarge?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800)),
                  Text(
                      points == null
                          ? 'Add result'
                          : '${SemesterDetailScreen.fmt(points)} pts'
                              '${result.hasOfficial ? '' : ' (est.)'}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ]),
          ),
          if (grades.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final g in grades)
              _gradeRow(context, g, semesterSubjects, semesterId),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 0, children: [
            TextButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => GradeEditorSheet(
                  initialSubjectId: s.id,
                  subjects: semesterSubjects,
                  semesterId: semesterId,
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add marks'),
            ),
            TextButton.icon(
              onPressed: () => _editFinal(context, ref),
              icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              label: const Text('Final result'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _editFinal(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _FinalResultSheet(subject: result.subject, tenPoint: tenPoint),
    );
  }
}

/// Official final grade, grade points and credits for one archived subject.
class _FinalResultSheet extends ConsumerStatefulWidget {
  final Subject subject;
  final bool tenPoint;
  const _FinalResultSheet({required this.subject, required this.tenPoint});

  @override
  ConsumerState<_FinalResultSheet> createState() => _FinalResultSheetState();
}

class _FinalResultSheetState extends ConsumerState<_FinalResultSheet> {
  late final TextEditingController _grade;
  late final TextEditingController _points;
  late final TextEditingController _credits;

  @override
  void initState() {
    super.initState();
    final s = widget.subject;
    _grade = TextEditingController(text: s.finalGrade ?? '');
    _points = TextEditingController(
        text: s.finalGradePoints == null
            ? ''
            : SemesterDetailScreen.fmt(s.finalGradePoints!));
    _credits = TextEditingController(text: s.credits?.toString() ?? '');
  }

  @override
  void dispose() {
    _grade.dispose();
    _points.dispose();
    _credits.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final max = widget.tenPoint ? 10.0 : 4.0;
    final pText = _points.text.trim();
    final points = pText.isEmpty ? null : double.tryParse(pText);
    if (pText.isNotEmpty && (points == null || points < 0 || points > max)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Grade points must be between 0 and ${max.toInt()}.')));
      return;
    }
    final cText = _credits.text.trim();
    final credits = cText.isEmpty ? null : int.tryParse(cText);
    if (cText.isNotEmpty && (credits == null || credits < 0 || credits > 40)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter credits as a whole number.')));
      return;
    }
    await ref.read(semesterControllerProvider).setFinalResult(
          widget.subject.id,
          finalGrade: _grade.text,
          finalGradePoints: points,
          credits: credits,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = widget.tenPoint ? '10' : '4.0';
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Final result', style: theme.textTheme.titleLarge),
            Text(widget.subject.name, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _grade,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 4,
                  decoration: const InputDecoration(
                      labelText: 'Grade', hintText: 'e.g. A+, O', counterText: ''),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _points,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                  ],
                  decoration: InputDecoration(labelText: 'Grade points / $max'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _credits,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Credits',
                  helperText: 'Used to weight your SGPA and CGPA'),
            ),
            const SizedBox(height: 8),
            Text(
                'Grade points override the estimate from your marks. Leave '
                'them empty to keep using your marks.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
