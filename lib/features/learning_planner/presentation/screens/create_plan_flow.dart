import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../domain/learning_plan.dart';
import '../../domain/learning_plan_generator.dart';
import '../providers/learning_planner_providers.dart';
import '../widgets/planner_widgets.dart';
import 'plan_preview_screen.dart';

/// Ordered wizard steps. [curriculum] only appears for jurisdiction-sensitive
/// subjects, so generic subjects stay a clean 5-step flow.
enum _WizStep { subject, curriculum, level, goal, syllabus, time }

/// Mutable draft collected across the wizard steps.
class _Draft {
  String subject = '';
  bool specificTopic = false;
  StudyProgram program = StudyProgram.general;
  StudyRegion region = StudyRegion.global;
  KnowledgeLevel? level;
  LearningGoal? goal;
  List<String> syllabusTopics = [];
  int dailyMinutes = 60;
  Set<int> studyDays = {1, 2, 3, 4, 5};
  DateTime targetDate = DateTime.now().add(const Duration(days: 14));
  String? note;
}

/// Screens 2–7 — the Create-a-Plan wizard. Five collection steps followed by a
/// calm "generating" screen, after which the finished plan opens.
class CreatePlanFlow extends ConsumerStatefulWidget {
  const CreatePlanFlow({super.key});

  @override
  ConsumerState<CreatePlanFlow> createState() => _CreatePlanFlowState();
}

class _CreatePlanFlowState extends ConsumerState<CreatePlanFlow> {
  final _Draft _d = _Draft();
  final _subjectCtrl = TextEditingController();

  int _index = 0; // position within [_steps]
  bool _showCurriculum = true;
  bool _generating = false;

  /// The active step sequence. The Course & country step is shown for every
  /// subject so the AI always has the course/level/location context it needs
  /// to build an accurate schedule.
  List<_WizStep> get _steps => [
        _WizStep.subject,
        if (_showCurriculum) _WizStep.curriculum,
        _WizStep.level,
        _WizStep.goal,
        _WizStep.syllabus,
        _WizStep.time,
      ];

  _WizStep get _current => _steps[_index];
  int get _total => _steps.length;

  @override
  void initState() {
    super.initState();
    // Prefill the region from the student's profile country (used for regional
    // offers already), so law/tax/governance plans are jurisdiction-correct by
    // default. They can still change it on the Course & country step.
    final country = ref.read(effectiveCountryProvider);
    _d.region = StudyRegionX.fromCountryName(country);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    super.dispose();
  }

  void _recomputeCurriculum() {
    // The Course & country step is always shown; kept as a hook in case we
    // ever want to hide it again.
    _showCurriculum = true;
  }

  bool get _canContinue {
    switch (_current) {
      case _WizStep.subject:
        return _d.subject.trim().isNotEmpty;
      case _WizStep.level:
        return _d.level != null;
      case _WizStep.goal:
        return _d.goal != null;
      case _WizStep.time:
        return _d.studyDays.isNotEmpty;
      case _WizStep.curriculum:
      case _WizStep.syllabus:
        return true;
    }
  }

  void _next() {
    if (_current == _WizStep.subject) _recomputeCurriculum();
    if (_index < _total - 1) {
      setState(() => _index++);
    } else {
      _startGenerating();
    }
  }

  void _back() {
    if (_index > 0) {
      setState(() => _index--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _startGenerating() async {
    setState(() => _generating = true);
  }

  Future<void> _finishGeneration() async {
    final generator = ref.read(learningPlanGeneratorProvider);
    final req = PlanRequest(
      subject: _d.subject,
      specificTopic: _d.specificTopic,
      level: _d.level ?? KnowledgeLevel.basics,
      goal: _d.goal ?? LearningGoal.fundamentals,
      syllabusTopics: _d.syllabusTopics,
      dailyMinutes: _d.dailyMinutes,
      studyDays: _d.studyDays,
      targetDate: _d.targetDate,
      note: _d.note,
      region: _d.region,
      program: _d.program,
    );

    LearningPlan? plan;
    var source = 'library';
    // Pro users get an AI-tailored roadmap (jurisdiction- and program-aware);
    // any failure/timeout silently falls back to the offline knowledge base so
    // the wizard always finishes with a usable plan.
    if (ref.read(isProProvider)) {
      try {
        final core = await ref.read(aiPlanServiceProvider).generateTopics(req);
        if (core != null && core.isNotEmpty) {
          plan = generator.assembleFromCore(req, core);
          source = 'ai';
        }
      } catch (_) {
        plan = null;
      }
    }
    plan ??= generator.generate(req);

    await ref.read(learningPlansProvider.notifier).addPlan(plan);
    ref.read(analyticsProvider).plannerPlanCreated(
          source: source,
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
    // Show the concise Plan Preview before the full overview.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'Planner: Preview'),
        builder: (_) => PlanPreviewScreen(planId: plan!.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_generating) {
      return _GeneratingScreen(onDone: _finishGeneration);
    }
    final isLast = _index == _total - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _wizardHeader(),
            Expanded(child: _stepBody()),
          ],
        ),
      ),
      bottomNavigationBar: PlannerBottomBar(
        label: isLast ? 'Generate my plan' : 'Continue',
        trailingIcon:
            isLast ? Icons.auto_awesome_rounded : Icons.arrow_forward_rounded,
        onTap: _canContinue ? _next : null,
      ),
    );
  }

  Widget _wizardHeader() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RoundIconButton(
                icon: Icons.arrow_back_rounded,
                semanticLabel: 'Back',
                background: theme.cardColor,
                onTap: _back,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Create a Plan', style: theme.textTheme.titleLarge),
                  Text('Step ${_index + 1} of $_total',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: StepProgressBar(step: _index + 1, total: _total),
          ),
        ],
      ),
    );
  }

  Widget _stepBody() {
    switch (_current) {
      case _WizStep.subject:
        return _SubjectStep(
          controller: _subjectCtrl,
          specificTopic: _d.specificTopic,
          onChanged: (v) => setState(() => _d.subject = v),
          onSpecificToggle: (v) => setState(() => _d.specificTopic = v),
          onPickChip: (v) {
            setState(() {
              _d.subject = v;
              _subjectCtrl.text = v;
              _subjectCtrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: v.length));
            });
          },
        );
      case _WizStep.curriculum:
        return _ContextStep(
          program: _d.program,
          region: _d.region,
          onProgram: (p) => setState(() => _d.program = p),
          onRegion: (r) => setState(() => _d.region = r),
        );
      case _WizStep.level:
        return _LevelStep(
          selected: _d.level,
          onSelect: (l) => setState(() => _d.level = l),
        );
      case _WizStep.goal:
        return _GoalStep(
          selected: _d.goal,
          onSelect: (g) => setState(() => _d.goal = g),
        );
      case _WizStep.syllabus:
        return _SyllabusStep(
          topics: _d.syllabusTopics,
          onTopics: (t) => setState(() => _d.syllabusTopics = t),
          onSkip: _next,
        );
      case _WizStep.time:
        return _TimeStep(
          draft: _d,
          onChanged: () => setState(() {}),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 1 — Subject
// ---------------------------------------------------------------------------

class _SubjectStep extends ConsumerWidget {
  final TextEditingController controller;
  final bool specificTopic;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onSpecificToggle;
  final ValueChanged<String> onPickChip;

  const _SubjectStep({
    required this.controller,
    required this.specificTopic,
    required this.onChanged,
    required this.onSpecificToggle,
    required this.onPickChip,
  });

  static const _popular = [
    'DBMS',
    'Operating Systems',
    'Financial Accounting',
    'Marketing Management',
    'Python',
    'Data Analytics',
    'Business Law',
    'Economics',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Personalise the chips with the student's own subjects — added manually or
    // parsed from an imported timetable. Dedupe by name (case-insensitive) and
    // keep their order. Fall back to the curated popular list only when they
    // don't have any subjects yet.
    final mySubjects =
        ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final seen = <String>{};
    final personalised = <String>[];
    for (final s in mySubjects) {
      final name = s.name.trim();
      if (name.isEmpty) continue;
      if (seen.add(name.toLowerCase())) personalised.add(name);
    }
    final hasOwn = personalised.isNotEmpty;
    final chips = hasOwn ? personalised : _popular;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      children: [
        Text('What do you want to learn?',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Enter a subject or a specific topic.',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        Container(
          decoration: softCard(context, radius: 18),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.done,
            style: theme.textTheme.titleMedium,
            decoration: InputDecoration(
              hintText: 'e.g. Financial Accounting',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SpecificTopicRow(
          value: specificTopic,
          onChanged: onSpecificToggle,
        ),
        const SizedBox(height: 24),
        Text(hasOwn ? 'Your subjects' : 'Popular subjects',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in chips)
              FilterPill(
                label: s,
                selected: controller.text.trim().toLowerCase() ==
                    s.toLowerCase(),
                onTap: () => onPickChip(s),
              ),
          ],
        ),
      ],
    );
  }
}

class _SpecificTopicRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SpecificTopicRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: value ? AppColors.lavenderSoft : theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value ? AppColors.primary : theme.dividerColor,
            width: value ? 1.6 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              value
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: value ? AppColors.primary : theme.dividerColor,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This is a specific topic',
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text('e.g. "Normalization in DBMS"',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — Course (program) & country (region)
// ---------------------------------------------------------------------------

class _ContextStep extends StatelessWidget {
  final StudyProgram program;
  final StudyRegion region;
  final ValueChanged<StudyProgram> onProgram;
  final ValueChanged<StudyRegion> onRegion;

  const _ContextStep({
    required this.program,
    required this.region,
    required this.onProgram,
    required this.onRegion,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      children: [
        Text('What are you studying for?',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'This helps AI pitch the right depth and examples — and, for subjects '
          'like law, tax or politics, use the correct curriculum for your country.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 22),
        Text('Your course', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final p in StudyProgram.values) ...[
          SelectableOptionCard(
            icon: p.icon,
            title: p.title,
            subtitle: p.subtitle,
            selected: program == p,
            onTap: () => onProgram(p),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        Text('Country / curriculum', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Prefilled from your profile — change it if needed.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final r in StudyRegion.values)
              FilterPill(
                label: r.label,
                icon: r == region
                    ? Icons.public_rounded
                    : Icons.public_outlined,
                selected: region == r,
                onTap: () => onRegion(r),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.lavenderSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tip: for a specific course, uploading your syllabus on the '
                  'next steps gives the most accurate plan.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — Level
// ---------------------------------------------------------------------------

class _LevelStep extends StatelessWidget {
  final KnowledgeLevel? selected;
  final ValueChanged<KnowledgeLevel> onSelect;
  const _LevelStep({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      children: [
        Text("What's your current level?",
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('This helps AI create the right starting point.',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        for (final l in KnowledgeLevel.values) ...[
          SelectableOptionCard(
            title: l.title,
            subtitle: l.subtitle,
            selected: selected == l,
            onTap: () => onSelect(l),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — Goal
// ---------------------------------------------------------------------------

class _GoalStep extends StatelessWidget {
  final LearningGoal? selected;
  final ValueChanged<LearningGoal> onSelect;
  const _GoalStep({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      children: [
        Text("What's your goal?", style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Your goal helps AI decide what to prioritize.',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        for (final g in LearningGoal.values) ...[
          SelectableOptionCard(
            icon: g.icon,
            title: g.title,
            subtitle: g.subtitle,
            selected: selected == g,
            onTap: () => onSelect(g),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4 — Optional syllabus
// ---------------------------------------------------------------------------

class _SyllabusStep extends StatefulWidget {
  final List<String> topics;
  final ValueChanged<List<String>> onTopics;
  final VoidCallback onSkip;

  const _SyllabusStep({
    required this.topics,
    required this.onTopics,
    required this.onSkip,
  });

  @override
  State<_SyllabusStep> createState() => _SyllabusStepState();
}

enum _SyllabusPhase { idle, reading, review }

class _SyllabusStepState extends State<_SyllabusStep> {
  late List<String> _topics = List.of(widget.topics);
  final _addCtrl = TextEditingController();
  _SyllabusPhase _phase = _SyllabusPhase.idle;

  @override
  void initState() {
    super.initState();
    if (_topics.isNotEmpty) _phase = _SyllabusPhase.review;
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  static List<String> _parse(String raw) => raw
      .split(RegExp(r'[\n;]'))
      .map((e) => e.replaceAll(RegExp(r'^[\s\-\d\.\)]+'), '').trim())
      .where((e) => e.length > 2)
      .toList();

  Future<void> _extract(List<String> parsed) async {
    setState(() => _phase = _SyllabusPhase.reading);
    // Brief, honest "reading" beat — no fake technical processing.
    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    setState(() {
      _topics = parsed;
      _phase = _SyllabusPhase.review;
    });
    widget.onTopics(_topics);
  }

  Future<void> _choose() async {
    List<String> parsed = const [];
    try {
      final res = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'txt', 'png', 'jpg', 'jpeg'],
      );
      final file = res?.files.single;
      if (file == null) return; // cancelled
      if (file.extension == 'txt' && file.bytes != null) {
        parsed = _parse(String.fromCharCodes(file.bytes!));
      }
    } catch (_) {
      // Picker unavailable — fall back to paste.
    }
    if (!mounted) return;
    if (parsed.isEmpty) {
      // We can't reliably OCR a PDF/image on-device, so confirm topics by paste.
      await _paste();
    } else {
      await _extract(parsed);
    }
  }

  Future<void> _paste() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final ctrl = TextEditingController(text: _topics.join('\n'));
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: theme.dividerColor,
                        borderRadius: BorderRadius.circular(4))),
              ),
              const SizedBox(height: 16),
              Text('Paste your syllabus', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('One topic per line.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                maxLines: 8,
                minLines: 5,
                decoration: InputDecoration(
                  hintText:
                      'Introduction to Accounting\nJournal Entries\nTrial Balance',
                  filled: true,
                  fillColor: theme.scaffoldBackgroundColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  onPressed: () => Navigator.pop(ctx, ctrl.text),
                  child: const Text('Use these topics',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (text == null) return;
    final parsed = _parse(text);
    if (parsed.isEmpty) return;
    await _extract(parsed);
  }

  void _removeAt(int i) {
    setState(() => _topics.removeAt(i));
    widget.onTopics(_topics);
  }

  void _add() {
    final v = _addCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _topics.add(v);
      _addCtrl.clear();
    });
    widget.onTopics(_topics);
  }

  void _clear() {
    setState(() {
      _topics = [];
      _phase = _SyllabusPhase.idle;
    });
    widget.onTopics(_topics);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text('Do you have a syllabus?',
                  style: theme.textTheme.headlineSmall),
            ),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.lavenderSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Optional',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text("Upload it and we'll use its topics to build a more accurate plan.",
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
        const SizedBox(height: 20),
        if (_phase == _SyllabusPhase.reading)
          _readingCard(theme)
        else if (_phase == _SyllabusPhase.review)
          _reviewList(theme)
        else
          _idle(theme),
      ],
    );
  }

  Widget _idle(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _choose,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: theme.dividerColor, width: 1.4),
            ),
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.upload_file_rounded,
                      size: 28, color: AppColors.primary),
                ),
                const SizedBox(height: 14),
                Text('Upload syllabus', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('PDF, image or text', style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _choose,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: const Text('Choose file'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton.icon(
            onPressed: _paste,
            icon: const Icon(Icons.notes_rounded, size: 18),
            label: const Text('Paste syllabus text'),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: Divider(color: theme.dividerColor)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: theme.textTheme.bodySmall),
            ),
            Expanded(child: Divider(color: theme.dividerColor)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: widget.onSkip,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Skip for now'),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text('You can add your syllabus later.',
              style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }

  Widget _readingCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor, width: 1.2),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text('Reading your syllabus…', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Pulling out the topics for your plan.',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _reviewList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'We found ${_topics.length} topics. Review and edit below.',
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
              ),
            ),
            TextButton(onPressed: _clear, child: const Text('Re-upload')),
          ],
        ),
        const SizedBox(height: 12),
        // Editable topic list — plain rows separated by dividers (no nested cards).
        Container(
          decoration: softCard(context, radius: 18),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < _topics.length; i++)
                Column(
                  children: [
                    if (i > 0)
                      Divider(height: 1, color: theme.dividerColor, indent: 14, endIndent: 14),
                    ListTile(
                      dense: true,
                      title: Text(_topics[i], style: theme.textTheme.bodyMedium),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: theme.textTheme.bodySmall?.color,
                        onPressed: () => _removeAt(i),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addCtrl,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: 'Add a topic',
                  isDense: true,
                  filled: true,
                  fillColor: theme.cardColor,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: _add,
              style: IconButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: Text("Not exact? Edit anything — you're in control.",
              style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 5 — Time & deadline
// ---------------------------------------------------------------------------

class _TimeStep extends StatelessWidget {
  final _Draft draft;
  final VoidCallback onChanged;
  const _TimeStep({required this.draft, required this.onChanged});

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.targetDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      draft.targetDate = picked;
      onChanged();
    }
  }

  Future<void> _pickCustomMinutes(BuildContext context) async {
    final ctrl = TextEditingController(text: draft.dailyMinutes.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Minutes per day'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'minutes'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text) ?? draft.dailyMinutes),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (result != null && result > 0) {
      draft.dailyMinutes = result;
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('d MMMM yyyy');
    final presets = {30: '30 minutes', 60: '1 hour', 120: '2 hours'};
    final isCustom = !presets.containsKey(draft.dailyMinutes);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      children: [
        Text('When do you want to complete it?',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text("We'll create your plan based on your available time.",
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),

        // Target date
        Text('Target date', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _pickDate(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: softCard(context, radius: 16),
            child: Row(
              children: [
                const Icon(Icons.event_rounded, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(df.format(draft.targetDate),
                    style: theme.textTheme.titleMedium),
                const Spacer(),
                Icon(Icons.edit_calendar_rounded,
                    size: 19, color: theme.textTheme.bodySmall?.color),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Minutes per day
        Text('How much time can you study per day?',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final e in presets.entries)
              FilterPill(
                label: e.value,
                selected: draft.dailyMinutes == e.key,
                onTap: () {
                  draft.dailyMinutes = e.key;
                  onChanged();
                },
              ),
            FilterPill(
              label: isCustom ? '${draft.dailyMinutes} min' : 'Custom',
              selected: isCustom,
              icon: Icons.tune_rounded,
              onTap: () => _pickCustomMinutes(context),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Study days
        Text('Which days will you study?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 7; i++)
              _DayToggle(
                label: _dayLabels[i],
                selected: draft.studyDays.contains(i + 1),
                onTap: () {
                  final day = i + 1;
                  if (draft.studyDays.contains(day)) {
                    draft.studyDays.remove(day);
                  } else {
                    draft.studyDays.add(day);
                  }
                  onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 24),

        // Note
        Text('Add a note', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Optional', style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        Container(
          decoration: softCard(context, radius: 16),
          child: TextField(
            onChanged: (v) => draft.note = v.trim().isEmpty ? null : v.trim(),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'e.g. I have less time on weekdays.',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Summary
        _SummaryCard(draft: draft),
      ],
    );
  }
}

class _DayToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayToggle(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 40,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : theme.cardColor,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? AppColors.primary : theme.dividerColor,
            width: 1.2,
          ),
        ),
        child: Text(
          label.substring(0, 1),
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? Colors.white : theme.textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final _Draft draft;
  const _SummaryCard({required this.draft});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('MMM d');
    final perDay = draft.dailyMinutes >= 60 && draft.dailyMinutes % 60 == 0
        ? '${draft.dailyMinutes ~/ 60}h/day'
        : '${draft.dailyMinutes} min/day';
    final rows = <String>[
      draft.subject.trim().isEmpty ? 'Your subject' : draft.subject.trim(),
      '${draft.program.title} · ${draft.region.label}',
      draft.level?.shortLabel ?? 'Level not set',
      draft.goal?.title ?? 'Goal not set',
      perDay,
      'Finish by ${df.format(draft.targetDate)}',
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.lavenderSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summarize_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Plan summary', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                      i == 0
                          ? Icons.menu_book_rounded
                          : Icons.check_rounded,
                      size: 16,
                      color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(rows[i],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 7 — AI generating
// ---------------------------------------------------------------------------

class _GeneratingScreen extends StatefulWidget {
  final Future<void> Function() onDone;
  const _GeneratingScreen({required this.onDone});

  @override
  State<_GeneratingScreen> createState() => _GeneratingScreenState();
}

class _GeneratingScreenState extends State<_GeneratingScreen>
    with SingleTickerProviderStateMixin {
  static const _steps = [
    'Understanding your subject',
    'Identifying key topics',
    'Mapping prerequisites',
    'Estimating topic time',
    'Building the learning sequence',
    'Fitting the plan to your schedule',
  ];
  int _done = 0;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _run();
  }

  Future<void> _run() async {
    for (var i = 0; i < _steps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      setState(() => _done = i + 1);
    }
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await widget.onDone();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              ScaleTransition(
                scale: Tween(begin: 0.92, end: 1.08).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryLight, AppColors.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 44),
                ),
              ),
              const SizedBox(height: 28),
              Text('Building your learning roadmap',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'AI is mapping the subject to your level, goal and deadline.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 34),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: softCard(context, radius: 20),
                child: Column(
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      _ChecklistRow(
                        label: _steps[i],
                        done: i < _done,
                        active: i == _done,
                        last: i == _steps.length - 1,
                      ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final String label;
  final bool done;
  final bool active;
  final bool last;
  const _ChecklistRow({
    required this.label,
    required this.done,
    required this.active,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? AppColors.primary : Colors.transparent,
              border: Border.all(
                color: done
                    ? AppColors.primary
                    : (active
                        ? AppColors.primary
                        : theme.dividerColor),
                width: 2,
              ),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : active
                    ? const Padding(
                        padding: EdgeInsets.all(5),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: done || active
                      ? theme.textTheme.bodyLarge?.color
                      : theme.textTheme.bodySmall?.color,
                  fontWeight: done || active ? FontWeight.w600 : FontWeight.w400,
                )),
          ),
        ],
      ),
    );
  }
}
