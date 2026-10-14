import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/subject_icons.dart';
import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../grades/domain/grade_item.dart';
import '../../../grades/presentation/providers/grade_providers.dart';
import '../../../subjects/domain/subject.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';
import '../../data/semester_repository.dart';
import '../../domain/semester.dart';
import '../providers/semester_providers.dart';
import 'semester_detail_screen.dart';

/// Pro gate + navigation for the wrap-up flow. Returns true when a semester
/// was actually wrapped up (only meaningful with [returnWhenDone]).
Future<bool> startSemesterWrapUp(BuildContext context, WidgetRef ref,
    {bool returnWhenDone = false}) async {
  if (!await requirePro(context, ref, UpgradeReason.semesters)) return false;
  if (!context.mounted) return false;
  final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      settings: const RouteSettings(name: 'Wrap Up Semester'),
      builder: (_) => WrapUpSemesterScreen(returnWhenDone: returnWhenDone)));
  return done == true;
}

/// Archives the current semester's subjects with their grades and exams into
/// a named past semester, so the student starts the next one fresh.
class WrapUpSemesterScreen extends ConsumerStatefulWidget {
  /// When true (opened from timetable import) the screen pops `true` after
  /// wrapping up instead of opening the new semester's page.
  final bool returnWhenDone;
  const WrapUpSemesterScreen({super.key, this.returnWhenDone = false});

  @override
  ConsumerState<WrapUpSemesterScreen> createState() =>
      _WrapUpSemesterScreenState();
}

class _WrapUpSemesterScreenState extends ConsumerState<WrapUpSemesterScreen> {
  final _name = TextEditingController();
  final _sgpa = TextEditingController();
  Set<String>? _selected;
  bool _includeUnlinked = true;
  bool _nameTouched = false;
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _sgpa.dispose();
    super.dispose();
  }

  void _initFrom(List<Subject> subjects) {
    _selected ??= {for (final s in subjects) s.id};
    if (_start == null) {
      final starts = subjects
          .map((s) => s.startDate ?? s.createdAt)
          .whereType<DateTime>()
          .toList()
        ..sort();
      _start = starts.isEmpty ? null : starts.first;
    }
    _end ??= DateTime.now();
    if (!_nameTouched) {
      final past = ref.watch(semestersStreamProvider).valueOrNull ?? const [];
      final suggestion = suggestSemesterName(
        profileSemester: ref.watch(userProfileProvider).valueOrNull?.semester,
        existingNames: [for (final s in past) s.name],
      );
      // Never write a controller during build (its TextField would rebuild
      // mid-frame); fill it in right after this frame instead.
      if (_name.text != suggestion) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_nameTouched) _name.text = suggestion;
        });
      }
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = (start ? _start : _end) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => start ? _start = picked : _end = picked);
  }

  WrapUpPlan _plan(List<Subject> subjects, List<GradeItem> grades) {
    return WrapUpPlan.build(
      selectedSubjectIds: _selected ?? const {},
      grades: grades,
      exams: ref.watch(examsStreamProvider).valueOrNull ?? const [],
      includeUnlinked: _includeUnlinked,
      currentSubjectIds: {for (final s in subjects) s.id},
    );
  }

  Future<void> _confirm(WrapUpPlan plan) async {
    final name = _name.text.trim().isEmpty ? 'Semester' : _name.text.trim();
    final sgpaText = _sgpa.text.trim();
    final sgpa = sgpaText.isEmpty ? null : double.tryParse(sgpaText);
    final max = maxSgpaFor(ref.read(gpaScaleProvider) == GpaScaleType.ten);
    if (sgpaText.isNotEmpty && !isValidSgpa(sgpa, max)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Enter an SGPA between 0 and ${max.toStringAsFixed(0)}, or leave it empty.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Wrap up $name?'),
        content: Text(
            '${_count(plan.subjectIds.length, 'subject')}, '
            '${_count(plan.gradeIds.length, 'grade')} and '
            '${_count(plan.examIds.length, 'exam')} move to Past semesters. '
            'Their classes leave your timetable and their reminders stop.\n\n'
            'Nothing is deleted. You can edit marks later or restore the '
            'semester any time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Wrap up')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final id = await ref.read(semesterControllerProvider).wrapUp(
            name: name,
            startDate: _start,
            endDate: _end,
            officialSgpa: sgpa,
            plan: plan,
          );
      if (!mounted || id == null) return;
      HapticFeedback.mediumImpact();
      if (widget.returnWhenDone) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$name saved to Past semesters. Starting fresh!')));
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            settings: const RouteSettings(name: 'Semester Detail'),
            builder: (_) =>
                SemesterDetailScreen(semesterId: id, justWrapped: true)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not wrap up: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _count(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjectsAsync = ref.watch(subjectsStreamProvider);
    final grades = ref.watch(gradesStreamProvider).valueOrNull ?? const [];
    final df = DateFormat('d MMM yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Wrap up semester')),
      body: subjectsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(subjectsStreamProvider)),
        data: (subjects) {
          if (subjects.isEmpty && grades.isEmpty) {
            return const EmptyState(
              icon: Icons.inventory_2_rounded,
              title: 'Nothing to wrap up',
              message: 'Your current semester has no subjects or grades yet.',
            );
          }
          _initFrom(subjects);
          final plan = _plan(subjects, grades);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                'Save this semester\'s subjects, marks, exams and attendance, '
                'then start the next one fresh.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.textTheme.bodySmall?.color),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => _nameTouched = true,
                decoration: const InputDecoration(labelText: 'Semester name'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _dateTile(theme, 'Started',
                      _start == null ? 'Pick' : df.format(_start!),
                      () => _pickDate(start: true)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateTile(theme, 'Ended',
                      _end == null ? 'Pick' : df.format(_end!),
                      () => _pickDate(start: false)),
                ),
              ]),
              const SizedBox(height: 22),
              Text('Subjects to wrap up', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Untick a subject that continues next semester.',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 10),
              Container(
                decoration: softCard(context, radius: 20),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(children: [
                    for (final s in subjects) _subjectTile(theme, s),
                    if (subjects.isEmpty)
                      const ListTile(title: Text('No subjects')),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeUnlinked,
                onChanged: (v) => setState(() => _includeUnlinked = v),
                title: const Text('Include grades and past exams with no subject'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sgpa,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Official SGPA (optional)',
                  helperText:
                      'From your result. You can add it or final marks later.',
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  const Icon(Icons.inventory_2_rounded,
                      color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Will save ${_count(plan.subjectIds.length, 'subject')}, '
                      '${_count(plan.gradeIds.length, 'grade')} and '
                      '${_count(plan.examIds.length, 'exam')}.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving || plan.isEmpty ? null : () => _confirm(plan),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded),
                label: Text(_saving ? 'Saving…' : 'Wrap up semester'),
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dateTile(
      ThemeData theme, String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(value),
      ),
    );
  }

  Widget _subjectTile(ThemeData theme, Subject s) {
    final selected = _selected!.contains(s.id);
    final grades = ref.watch(gradesForSubjectProvider(s.id)).length;
    final color = Color(s.colorHex);
    final att = s.held == 0 ? 'No attendance yet' : '${s.percent.round()}% attendance';
    return CheckboxListTile(
      value: selected,
      onChanged: (v) => setState(() {
        v == true ? _selected!.add(s.id) : _selected!.remove(s.id);
      }),
      secondary: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(SubjectIcons.resolve(s.iconKey), color: color, size: 20),
      ),
      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$att · ${_count(grades, 'grade')}'),
    );
  }
}
