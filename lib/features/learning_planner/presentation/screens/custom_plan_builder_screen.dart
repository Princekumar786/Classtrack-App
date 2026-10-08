import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/learning_plan.dart';
import '../../domain/learning_plan_generator.dart';
import '../providers/learning_planner_providers.dart';
import '../widgets/planner_widgets.dart';
import 'plan_preview_screen.dart';

/// A single editable topic row in the manual builder.
class _TopicDraft {
  final TextEditingController title;
  int minutes;
  final List<TextEditingController> subtopics;
  _TopicDraft({String text = ''})
      : title = TextEditingController(text: text),
        minutes = 30,
        subtopics = [];

  List<String> get subtopicTexts => subtopics
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  void dispose() {
    title.dispose();
    for (final s in subtopics) {
      s.dispose();
    }
  }
}

/// "Build your own plan" — a template the student fills in themselves: subject,
/// their own topics with time estimates, and a schedule. ClassTrack lays it out
/// into days so they can follow it, without AI choosing the topics.
class CustomPlanBuilderScreen extends ConsumerStatefulWidget {
  const CustomPlanBuilderScreen({super.key});

  @override
  ConsumerState<CustomPlanBuilderScreen> createState() =>
      _CustomPlanBuilderScreenState();
}

class _CustomPlanBuilderScreenState
    extends ConsumerState<CustomPlanBuilderScreen> {
  final _subjectCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final List<_TopicDraft> _topics = [
    _TopicDraft(),
    _TopicDraft(),
    _TopicDraft(),
  ];
  int _dailyMinutes = 60;
  final Set<int> _studyDays = {1, 2, 3, 4, 5};
  DateTime _targetDate = DateTime.now().add(const Duration(days: 14));

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _minuteOptions = [15, 20, 30, 45, 60, 90];

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _noteCtrl.dispose();
    for (final t in _topics) {
      t.dispose();
    }
    super.dispose();
  }

  List<_TopicDraft> get _filled =>
      _topics.where((t) => t.title.text.trim().isNotEmpty).toList();

  bool get _canCreate =>
      _subjectCtrl.text.trim().isNotEmpty &&
      _filled.isNotEmpty &&
      _studyDays.isNotEmpty;

  int get _totalMinutes => _filled.fold(0, (s, t) => s + t.minutes);

  void _addRow() => setState(() => _topics.add(_TopicDraft()));

  void _removeRow(int i) {
    setState(() {
      _topics[i].dispose();
      _topics.removeAt(i);
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    final country = ref.read(userProfileProvider).valueOrNull?.country;
    final gen = ref.read(learningPlanGeneratorProvider);
    final core = [
      for (final t in _filled)
        LearningTopic(
          id: 'u_${DateTime.now().microsecondsSinceEpoch}_${_filled.indexOf(t)}',
          title: t.title.text.trim(),
          estMinutes: t.minutes,
          objectives: t.subtopicTexts,
          unit: 'My topics',
        ),
    ];
    final plan = gen.assembleFromCore(
      PlanRequest(
        subject: _subjectCtrl.text.trim(),
        specificTopic: false,
        level: KnowledgeLevel.basics,
        goal: LearningGoal.syllabus,
        dailyMinutes: _dailyMinutes,
        studyDays: _studyDays,
        targetDate: _targetDate,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        region: StudyRegionX.fromCountryName(country),
      ),
      core,
      addReviews: false, // respect the student's exact topic list
    );
    await ref.read(learningPlansProvider.notifier).addPlan(plan);
    ref.read(analyticsProvider).plannerPlanCreated(
          source: 'manual',
          subject: plan.subject,
          level: plan.level.name,
          goal: plan.goal.name,
          program: plan.program.name,
          region: plan.region.name,
          topics: plan.totalTopics,
          estMinutes: plan.totalMinutes,
          hasSyllabus: plan.hasSyllabus,
        );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'Planner: Preview'),
        builder: (_) => PlanPreviewScreen(planId: plan.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('d MMM yyyy');
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 4),
              child: Row(
                children: [
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    semanticLabel: 'Back',
                    background: theme.cardColor,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Build your own plan',
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  Text('Fill in what you want to cover',
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                      "Add your own topics and time — we'll turn them into a "
                      'day-by-day plan you can follow and track.',
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
                  const SizedBox(height: 22),

                  // Subject
                  Text('Subject or goal', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Container(
                    decoration: softCard(context, radius: 16),
                    child: TextField(
                      controller: _subjectCtrl,
                      onChanged: (_) => setState(() {}),
                      style: theme.textTheme.titleMedium,
                      decoration: InputDecoration(
                        hintText: 'e.g. My Physics revision',
                        prefixIcon: const Icon(Icons.menu_book_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Topics
                  Row(
                    children: [
                      Text('Your topics', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      if (_filled.isNotEmpty)
                        Text(
                            '${_filled.length} topics · ~${formatEstMinutes(_totalMinutes)}',
                            style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: softCard(context, radius: 18),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 6),
                    child: Column(
                      children: [
                        for (var i = 0; i < _topics.length; i++)
                          Column(
                            children: [
                              if (i > 0)
                                Divider(
                                    height: 1,
                                    color: theme.dividerColor,
                                    indent: 12,
                                    endIndent: 12),
                              _topicRow(i, theme),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _addRow,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add topic'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Schedule
                  Text('How much time per day?',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final m in const [30, 60, 120])
                        FilterPill(
                          label: m >= 60 ? '${m ~/ 60}h' : '$m min',
                          selected: _dailyMinutes == m,
                          onTap: () => setState(() => _dailyMinutes = m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text('Which days will you study?',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < 7; i++)
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              final d = i + 1;
                              if (_studyDays.contains(d)) {
                                _studyDays.remove(d);
                              } else {
                                _studyDays.add(d);
                              }
                            });
                          },
                          child: Container(
                            width: 40,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _studyDays.contains(i + 1)
                                  ? AppColors.primary
                                  : theme.cardColor,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                  color: _studyDays.contains(i + 1)
                                      ? AppColors.primary
                                      : theme.dividerColor),
                            ),
                            child: Text(_dayLabels[i],
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _studyDays.contains(i + 1)
                                        ? Colors.white
                                        : theme.textTheme.bodyMedium?.color)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text('Finish by', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: softCard(context, radius: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.event_rounded,
                              color: AppColors.primary),
                          const SizedBox(width: 12),
                          Text(df.format(_targetDate),
                              style: theme.textTheme.titleMedium),
                          const Spacer(),
                          Icon(Icons.edit_calendar_rounded,
                              size: 19,
                              color: theme.textTheme.bodySmall?.color),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: PlannerBottomBar(
        label: 'Create my plan',
        trailingIcon: Icons.check_rounded,
        onTap: _canCreate ? _create : null,
      ),
    );
  }

  Widget _topicRow(int i, ThemeData theme) {
    final t = _topics[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: t.title,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Topic ${i + 1}',
                    isDense: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
              DropdownButton<int>(
                value: t.minutes,
                underline: const SizedBox.shrink(),
                isDense: true,
                borderRadius: BorderRadius.circular(14),
                items: [
                  for (final m in _minuteOptions)
                    DropdownMenuItem(
                      value: m,
                      child: Text('~${m}m', style: theme.textTheme.bodySmall),
                    ),
                ],
                onChanged: (v) => setState(() => t.minutes = v ?? t.minutes),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: theme.textTheme.bodySmall?.color,
                onPressed: _topics.length > 1 ? () => _removeRow(i) : null,
              ),
            ],
          ),
          // Subtopics
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < t.subtopics.length; j++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 10),
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: t.subtopics[j],
                            onChanged: (_) => setState(() {}),
                            style: theme.textTheme.bodyMedium,
                            decoration: const InputDecoration(
                              hintText: 'Subtopic',
                              isDense: true,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            t.subtopics[j].dispose();
                            t.subtopics.removeAt(j);
                          }),
                          child: Icon(Icons.remove_circle_outline_rounded,
                              size: 16, color: theme.textTheme.bodySmall?.color),
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => setState(
                      () => t.subtopics.add(TextEditingController())),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add subtopic'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
