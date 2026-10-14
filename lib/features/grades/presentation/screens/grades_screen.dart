import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/subject_icons.dart';
import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../../shared/widgets/placement_slot.dart';
import '../../../cms/domain/marketing.dart';
import '../../../semesters/presentation/providers/semester_providers.dart';
import '../../../semesters/presentation/screens/past_semesters_screen.dart';
import '../../../subjects/domain/subject.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../domain/grade_item.dart';
import '../providers/grade_providers.dart';

class GradesScreen extends ConsumerWidget {
  const GradesScreen({super.key});

  Color _gradeColor(double p) => p >= 75
      ? AppColors.success
      : p >= 50
          ? AppColors.warning
          : AppColors.danger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subjectsAsync = ref.watch(subjectsStreamProvider);
    final gpa = ref.watch(gpaSummaryProvider);
    final unassigned = ref.watch(unassignedGradesProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            Row(
              children: [
                RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                _AddButton(onTap: () => _openEditor(context)),
              ],
            ),
            const SizedBox(height: 14),
            Text('Grades & GPA', style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Track marks, see your GPA, plan your target',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.textTheme.bodySmall?.color)),
            const SizedBox(height: 18),
            _gpaCard(context, gpa).animate().fadeIn(duration: 350.ms).slideY(
                begin: 0.08, curve: Curves.easeOut),
            const SizedBox(height: 12),
            _scaleToggle(context, ref),
            const SizedBox(height: 12),
            _pastSemestersTile(context, ref),
            const SizedBox(height: 16),
            const PlacementSlot(placement: Placements.grades),
            const SizedBox(height: 8),
            Text('By subject', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            subjectsAsync.when(
              loading: () => const Padding(
                  padding: EdgeInsets.only(top: 30), child: LoadingView()),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(subjectsStreamProvider)),
              data: (subjects) {
                if (subjects.isEmpty) {
                  return _empty(context,
                      'Add subjects first to track their grades.');
                }
                return Column(
                  children: [
                    for (var i = 0; i < subjects.length; i++)
                      _SubjectGradeCard(subject: subjects[i])
                          .listEntrance(i, stepMs: 60, slide: 0.08),
                  ],
                );
              },
            ),
            if (unassigned.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Other grades', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: softCard(context),
                child: Column(
                  children: [
                    for (final g in unassigned)
                      _gradeRow(context, ref, g),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _gpaCard(BuildContext context, GpaSummary gpa) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('GPA · this semester',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: Colors.white70)),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    gpa.gradedSubjects == 0 ? '—' : gpa.gpa.toStringAsFixed(2),
                    style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 32,
                        height: 1),
                  ),
                  const SizedBox(width: 6),
                  Text(gpa.maxPoints >= 10 ? '/ 10' : '/ 4.0',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white70)),
                ],
              ),
            ],
          ),
            ),
          ),
          const SizedBox(width: 12),
          _gpaStat(
              theme,
              gpa.gradedSubjects == 0
                  ? '—'
                  : '${gpa.averagePercent.toStringAsFixed(0)}%',
              'Average'),
          const SizedBox(width: 20),
          _gpaStat(theme, '${gpa.gradedSubjects}', 'Graded'),
        ],
      ),
    );
  }

  Widget _gpaStat(ThemeData theme, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white, fontWeight: FontWeight.w800)),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70)),
      ],
    );
  }

  /// Visible 4.0 / 10-point scale switcher (also in Settings).
  Widget _scaleToggle(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scale = ref.watch(gpaScaleProvider);
    Widget seg(String label, GpaScaleType type) {
      final selected = scale == type;
      return GestureDetector(
        onTap: () => ref.read(gpaScaleProvider.notifier).set(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected
                      ? Colors.white
                      : theme.textTheme.bodyMedium?.color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: softCard(context),
      child: Row(
        children: [
          const Icon(Icons.straighten_rounded,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Grading scale',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                seg('4.0', GpaScaleType.four),
                seg('10-pt', GpaScaleType.ten),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Entry to Past semesters / wrap-up (Pro).
  Widget _pastSemestersTile(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isPro = ref.watch(isProProvider);
    final count = ref.watch(semestersStreamProvider).valueOrNull?.length ?? 0;
    final cgpa = ref.watch(cgpaProvider);
    final subtitle = count == 0
        ? 'Semester over? Wrap it up and start fresh'
        : isPro && cgpa != null
            ? 'CGPA ${cgpa.toStringAsFixed(2)} · $count past semester${count == 1 ? '' : 's'}'
            : '$count past semester${count == 1 ? '' : 's'}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => openPastSemesters(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: softCard(context),
          child: Row(children: [
            const Icon(Icons.history_edu_rounded,
                size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Past semesters & CGPA',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (!isPro)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.workspace_premium_rounded,
                    size: 18, color: AppColors.primary),
              ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }

  Widget _gradeRow(BuildContext context, WidgetRef ref, GradeItem g) {
    final theme = Theme.of(context);
    final c = _gradeColor(g.percent);
    return InkWell(
      onTap: () => _openEditor(context, grade: g),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${_num(g.score)} / ${_num(g.maxScore)}'
                    '${g.hasWeight ? '  ·  ${_num(g.weight!)}% weight' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${g.percent.toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: c, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: softCard(context),
      child: Row(
        children: [
          const Icon(Icons.school_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context,
      {GradeItem? grade, String? subjectId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          GradeEditorSheet(initial: grade, initialSubjectId: subjectId),
    );
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_rounded, size: 20, color: Colors.white),
              SizedBox(width: 6),
              Text('Add grade',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectGradeCard extends ConsumerWidget {
  final Subject subject;
  const _SubjectGradeCard({required this.subject});

  Color _gradeColor(double p) => p >= 75
      ? AppColors.success
      : p >= 50
          ? AppColors.warning
          : AppColors.danger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = ref.watch(gradesForSubjectProvider(subject.id));
    final course = ref.watch(courseGradeProvider(subject.id));
    final tenPoint = ref.watch(gpaScaleProvider) == GpaScaleType.ten;
    final coursePoints = GradeScale.pointsFor(course.percent, tenPoint);
    final color = Color(subject.colorHex);
    final pctColor = _gradeColor(course.percent);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: softCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(SubjectIcons.resolve(subject.iconKey),
                    color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      course.count == 0
                          ? 'No grades yet'
                          : '${course.count} assessment${course.count == 1 ? '' : 's'}'
                              '${course.usesWeights ? ' · ${course.gradedWeight.toStringAsFixed(0)}% weighted' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (course.count > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${course.percent.toStringAsFixed(0)}%',
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: pctColor, fontWeight: FontWeight.w800)),
                    Text('${course.letter} · ${coursePoints.toStringAsFixed(1)} GPA',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: pctColor)),
                  ],
                ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final g in items) _assessmentRow(context, ref, g, pctColor),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        GradeEditorSheet(initialSubjectId: subject.id),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ),
              if (course.usesWeights && course.gradedWeight < 100) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        _showTargetCalc(context, subject, course),
                    icon: const Icon(Icons.calculate_rounded, size: 18),
                    label: const Text('What do I need?'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _assessmentRow(
      BuildContext context, WidgetRef ref, GradeItem g, Color color) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => GradeEditorSheet(initial: g),
      ),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.chevron_right_rounded, size: 16),
            const SizedBox(width: 4),
            Expanded(
              child: Text(g.title,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Text(
              '${GradesScreen._num(g.score)}/${GradesScreen._num(g.maxScore)}'
              '${g.hasWeight ? ' · ${GradesScreen._num(g.weight!)}%' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 10),
            Text('${g.percent.toStringAsFixed(0)}%',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  void _showTargetCalc(
      BuildContext context, Subject subject, CourseGrade course) {
    final controller = TextEditingController(text: '75');
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          final target = double.tryParse(controller.text) ?? 0;
          final needed = course.neededOnRemaining(target);
          final remaining = 100 - course.gradedWeight;
          String result;
          Color color = AppColors.primary;
          if (needed == null) {
            result = 'Add weighted assessments to project your target.';
          } else if (needed <= 0) {
            result =
                "You've already secured $target% — anything on the remaining ${remaining.toStringAsFixed(0)}% keeps you there.";
            color = AppColors.success;
          } else if (needed > 100) {
            result =
                'Reaching $target% is not possible with the remaining ${remaining.toStringAsFixed(0)}% (would need ${needed.toStringAsFixed(0)}%).';
            color = AppColors.danger;
          } else {
            result =
                'You need to average ${needed.toStringAsFixed(1)}% on the remaining ${remaining.toStringAsFixed(0)}% of ${subject.name}.';
            color = needed >= 85 ? AppColors.warning : AppColors.success;
          }
          return AlertDialog(
            title: const Text('Target calculator'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current: ${course.percent.toStringAsFixed(1)}% over '
                    '${course.gradedWeight.toStringAsFixed(0)}% graded'),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Target final grade %',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(result,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close')),
            ],
          );
        });
      },
    );
  }
}

/// Bottom sheet to add / edit a grade.
class GradeEditorSheet extends ConsumerStatefulWidget {
  final GradeItem? initial;
  final String? initialSubjectId;

  /// Subjects offered in the picker. Defaults to the current semester's; the
  /// Past semesters screens pass that semester's (archived) subjects.
  final List<Subject>? subjects;

  /// Archived semester a NEW grade belongs to (null = current semester).
  final String? semesterId;

  const GradeEditorSheet({
    super.key,
    this.initial,
    this.initialSubjectId,
    this.subjects,
    this.semesterId,
  });

  @override
  ConsumerState<GradeEditorSheet> createState() => _GradeEditorSheetState();
}

class _GradeEditorSheetState extends ConsumerState<GradeEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _score;
  late final TextEditingController _max;
  late final TextEditingController _weight;
  String? _subjectId;

  @override
  void initState() {
    super.initState();
    final g = widget.initial;
    _title = TextEditingController(text: g?.title ?? '');
    _score = TextEditingController(
        text: g != null ? GradesScreen._num(g.score) : '');
    _max = TextEditingController(
        text: g != null ? GradesScreen._num(g.maxScore) : '100');
    _weight = TextEditingController(
        text: g?.hasWeight == true ? GradesScreen._num(g!.weight!) : '');
    _subjectId = g?.subjectId ?? widget.initialSubjectId;
  }

  @override
  void dispose() {
    _title.dispose();
    _score.dispose();
    _max.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final score = double.tryParse(_score.text.trim());
    final max = double.tryParse(_max.text.trim());
    if (title.isEmpty || score == null || max == null || max <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a title, score and a max score > 0.')));
      return;
    }
    final weight = double.tryParse(_weight.text.trim());
    final ctrl = ref.read(gradeControllerProvider);
    final existing = widget.initial;
    if (existing == null) {
      ctrl.add(GradeItem(
        id: 'new',
        subjectId: _subjectId,
        title: title,
        score: score,
        maxScore: max,
        weight: weight,
        date: DateTime.now(),
        semesterId: widget.semesterId,
      ));
    } else {
      ctrl.update(existing.copyWith(
        subjectId: _subjectId,
        title: title,
        score: score,
        maxScore: max,
        weight: weight,
        clearWeight: weight == null,
        clearSubject: _subjectId == null,
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjects = widget.subjects ??
        ref.watch(subjectsStreamProvider).valueOrNull ??
        const <Subject>[];
    // A grade can point at a subject that's gone (deleted earlier) — show it
    // as "No subject" instead of crashing the picker with an unknown value.
    final pickerValue =
        subjects.any((s) => s.id == _subjectId) ? _subjectId : null;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SingleChildScrollView(
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
            Text(widget.initial == null ? 'Add grade' : 'Edit grade',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Assessment name (e.g. Midterm)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _score,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(labelText: 'Score'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(labelText: 'Out of'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weight,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Weight % of final grade (optional)',
                helperText:
                    'Add weights to unlock the "what do I need?" calculator',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: pickerValue,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Subject'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('No subject')),
                for (final s in subjects)
                  DropdownMenuItem<String?>(
                      value: s.id,
                      child: Text(s.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _subjectId = v),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.initial != null)
                  IconButton(
                    onPressed: () {
                      ref
                          .read(gradeControllerProvider)
                          .delete(widget.initial!.id);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.danger),
                  ),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
