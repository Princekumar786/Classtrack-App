import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../domain/learning_plan.dart';
import '../../domain/learning_plan_generator.dart';
import '../../domain/plan_builder_math.dart';
import '../providers/learning_planner_providers.dart';
import '../widgets/planner_widgets.dart';
import 'plan_preview_screen.dart';

/// One editable topic in the builder.
class _TopicDraft {
  static int _seq = 0;
  final int id = _seq++;
  final TextEditingController title;
  final FocusNode focus = FocusNode();
  int minutes;
  final List<TextEditingController> subtopics = [];
  bool expanded = false;

  /// Set when the student adds a subtopic so the new field takes focus.
  bool focusNewSubtopic = false;
  final List<TextEditingController> links = [];
  bool linksOpen = false;

  _TopicDraft({String text = '', this.minutes = 30})
    : title = TextEditingController(text: text);

  bool get isFilled => title.text.trim().isNotEmpty;

  List<String> get subtopicTexts =>
      subtopics.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();

  /// Valid, normalised links (invalid entries are skipped, deduped).
  List<String> get linkUrls => links
      .map((c) => normalizeStudyLink(c.text))
      .whereType<String>()
      .toSet()
      .toList();

  void dispose() {
    title.dispose();
    focus.dispose();
    for (final s in subtopics) {
      s.dispose();
    }
    for (final l in links) {
      l.dispose();
    }
  }
}

/// "Build your own plan" — the student lists their own topics and time; we lay
/// them out day by day. Designed around three questions, top to bottom:
///  1. What are you studying?   (subject, with one-tap picks from My Subjects)
///  2. What's in it?            (topics: type, paste a whole syllabus, reorder,
///                               set time per topic, optional subtopics)
///  3. When?                    (daily time, study days, finish-by — incl.
///                               "before my exam")
/// A live "Will it fit?" card checks the maths as they type and offers
/// one-tap fixes, so the plan they create is one they can actually finish.
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
  final List<_TopicDraft> _topics = [_TopicDraft(), _TopicDraft()];
  int _dailyMinutes = 60;
  final Set<int> _studyDays = {1, 2, 3, 4, 5};
  DateTime _targetDate = _today().add(const Duration(days: 14));
  String? _deadlineChip = '2w';
  bool _creating = false;

  static const _dailyOptions = [15, 30, 45, 60, 90, 120];
  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _noteCtrl.dispose();
    for (final t in _topics) {
      t.dispose();
    }
    super.dispose();
  }

  // ── Derived state ──────────────────────────────────────────────────────

  List<_TopicDraft> get _filled => _topics.where((t) => t.isFilled).toList();
  int get _totalMinutes => _filled.fold(0, (s, t) => s + t.minutes);
  PlanFit get _fit => PlanFit(
    _totalMinutes,
    studyDaysBetween(DateTime.now(), _targetDate, _studyDays),
    _dailyMinutes,
  );

  String? get _blocker {
    if (_subjectCtrl.text.trim().isEmpty) return 'Add what you are studying';
    if (_filled.isEmpty) return 'Add at least one topic';
    if (_studyDays.isEmpty) return 'Pick at least one study day';
    return null;
  }

  // ── Topic actions ──────────────────────────────────────────────────────

  void _addTopic({bool focus = true}) {
    final d = _TopicDraft();
    setState(() => _topics.add(d));
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? d.focus.requestFocus() : null,
      );
    }
  }

  void _removeTopic(_TopicDraft d) {
    HapticFeedback.lightImpact();
    final index = _topics.indexOf(d);
    final removedText = d.title.text;
    final removedMinutes = d.minutes;
    // Keep subtopics + links so Undo restores the whole topic, not just its title.
    final removedSubtopics = d.subtopics.map((c) => c.text).toList();
    final removedLinks = d.links.map((c) => c.text).toList();
    setState(() {
      _topics.remove(d);
      if (_topics.isEmpty) _topics.add(_TopicDraft());
    });
    d.dispose();
    if (removedText.trim().isEmpty) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed "${removedText.trim()}"'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (!mounted) return;
              setState(
                () => _topics.insert(
                  index.clamp(0, _topics.length),
                  _TopicDraft(text: removedText, minutes: removedMinutes)
                    ..subtopics.addAll(removedSubtopics
                        .map((t) => TextEditingController(text: t)))
                    ..expanded = removedSubtopics.isNotEmpty
                    ..links.addAll(
                        removedLinks.map((t) => TextEditingController(text: t)))
                    ..linksOpen = removedLinks.isNotEmpty,
                ),
              );
            },
          ),
        ),
      );
  }

  Future<void> _pasteList() async {
    final parsed = await showModalBottomSheet<List<ParsedTopic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).cardColor,
      builder: (_) => const _PasteSheet(),
    );
    if (parsed == null || parsed.isEmpty || !mounted) return;
    setState(() {
      for (final t in _topics.where((t) => !t.isFilled).toList()) {
        _topics.remove(t);
        t.dispose();
      }
      for (final p in parsed) {
        final d = _TopicDraft(text: p.title, minutes: p.minutes ?? 30);
        for (final s in p.subtopics) {
          d.subtopics.add(TextEditingController(text: s));
        }
        _topics.add(d);
      }
    });
    final subs = parsed.fold<int>(0, (n, p) => n + p.subtopics.length);
    showQuickFeedback(
      context,
      'Added ${parsed.length} topic${parsed.length == 1 ? '' : 's'}'
      '${subs > 0 ? ' · $subs subtopic${subs == 1 ? '' : 's'}' : ''}',
    );
  }

  // ── Schedule actions ───────────────────────────────────────────────────

  void _setDeadline(DateTime d, String? chip) {
    HapticFeedback.selectionClick();
    setState(() {
      _targetDate = d.isBefore(_today()) ? _today() : d;
      _deadlineChip = chip;
    });
  }

  Future<void> _pickDate() async {
    final now = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate.isBefore(now) ? now : _targetDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
      helpText: 'Finish by',
    );
    if (picked != null) _setDeadline(picked, null);
  }

  void _toggleDay(int weekday) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_studyDays.remove(weekday)) _studyDays.add(weekday);
    });
  }

  void _setDays(Set<int> days) {
    HapticFeedback.selectionClick();
    setState(
      () => _studyDays
        ..clear()
        ..addAll(days),
    );
  }

  // ── Create ─────────────────────────────────────────────────────────────

  Future<void> _create() async {
    if (_blocker != null || _creating) return;
    setState(() => _creating = true);
    final country = ref.read(effectiveCountryProvider);
    final gen = ref.read(learningPlanGeneratorProvider);
    final filled = _filled;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final core = [
      for (var i = 0; i < filled.length; i++)
        LearningTopic(
          id: 'u_${stamp}_$i',
          title: filled[i].title.text.trim(),
          estMinutes: filled[i].minutes,
          objectives: filled[i].subtopicTexts,
          // Exactly the subtopics the student typed become the checklist —
          // no auto-added "self-check" lines on a hand-built plan.
          sections: [
            TopicSection(
              title: 'Subtopics',
              minutes: filled[i].minutes,
              points: filled[i].subtopicTexts,
            ),
          ],
          completionCriteria: const ['Finish every subtopic'],
          links: filled[i].linkUrls,
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
        studyDays: {..._studyDays},
        targetDate: _targetDate,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        region: StudyRegionX.fromCountryName(country),
      ),
      core,
      addReviews: false, // respect the student's exact topic list
    );
    await ref.read(learningPlansProvider.notifier).addPlan(plan);
    ref
        .read(analyticsProvider)
        .plannerPlanCreated(
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

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fit = _fit;
    final blocker = _blocker;

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
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Build your own plan',
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                behavior: HitTestBehavior.translucent,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Text(
                      'Your topics, your pace. We turn them into a '
                      'day-by-day plan you can tick off.',
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                    const SizedBox(height: 22),
                    _StepLabel(
                      number: 1,
                      title: 'What are you studying?',
                      done: _subjectCtrl.text.trim().isNotEmpty,
                    ),
                    const SizedBox(height: 10),
                    _subjectField(theme),
                    const SizedBox(height: 28),
                    _StepLabel(
                      number: 2,
                      title: 'Topics to cover',
                      done: _filled.isNotEmpty,
                      trailing: _filled.isEmpty
                          ? null
                          : '${_filled.length} · ~${formatEstMinutes(_totalMinutes)}',
                    ),
                    const SizedBox(height: 10),
                    _topicsSection(theme),
                    const SizedBox(height: 28),
                    _StepLabel(
                      number: 3,
                      title: 'When will you study?',
                      done: _studyDays.isNotEmpty,
                    ),
                    const SizedBox(height: 12),
                    _scheduleSection(theme),
                    const SizedBox(height: 20),
                    _FitCard(
                      fit: fit,
                      targetDate: _targetDate,
                      onUseDaily: (m) {
                        HapticFeedback.selectionClick();
                        setState(() => _dailyMinutes = m);
                      },
                      suggestedDaily: suggestDailyMinutes(
                        fit.neededPerDay,
                        _dailyOptions,
                      ),
                      suggestedFinish: earliestFinish(
                        DateTime.now(),
                        fit.daysNeeded,
                        _studyDays,
                      ),
                      onUseFinish: (d) => _setDeadline(d, null),
                    ),
                    const SizedBox(height: 16),
                    _noteTile(theme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: PlannerBottomBar(
        label: _creating ? 'Creating…' : 'Create my plan',
        trailingIcon: Icons.check_rounded,
        onTap: blocker == null && !_creating ? _create : null,
        secondary: Semantics(
          liveRegion: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                blocker != null
                    ? Icons.info_outline_rounded
                    : Icons.event_available_rounded,
                size: 16,
                color: blocker != null
                    ? theme.textTheme.bodySmall?.color
                    : AppColors.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  blocker ??
                      '${_filled.length} topic${_filled.length == 1 ? '' : 's'} · '
                          '~${formatEstMinutes(_totalMinutes)} · '
                          'by ${DateFormat('d MMM').format(_targetDate)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 1: subject ────────────────────────────────────────────────────

  Widget _subjectField(ThemeData theme) {
    final subjects = (ref.watch(subjectsStreamProvider).valueOrNull ?? const [])
        .map((s) => s.name.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .take(8)
        .toList();
    final current = _subjectCtrl.text.trim().toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: softCard(context, radius: 16),
          child: TextField(
            controller: _subjectCtrl,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            maxLength: 80,
            style: theme.textTheme.titleMedium,
            decoration: InputDecoration(
              hintText: 'e.g. Physics mid-sem revision',
              counterText: '',
              prefixIcon: const Icon(Icons.menu_book_rounded),
              suffixIcon: _subjectCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(_subjectCtrl.clear),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
        if (subjects.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: subjects.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => FilterPill(
                label: subjects[i],
                icon: Icons.class_outlined,
                selected: current == subjects[i].toLowerCase(),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _subjectCtrl.text = subjects[i]);
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 2: topics ─────────────────────────────────────────────────────

  Widget _topicsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PasteBanner(onTap: _pasteList),
        const SizedBox(height: 12),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _topics.length,
          onReorderItem: (oldIndex, newIndex) {
            HapticFeedback.selectionClick();
            setState(
              () => _topics.insert(newIndex, _topics.removeAt(oldIndex)),
            );
          },
          proxyDecorator: (child, _, __) => Material(
            color: Colors.transparent,
            elevation: 6,
            shadowColor: AppColors.primary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(18),
            child: child,
          ),
          itemBuilder: (_, i) {
            final d = _topics[i];
            return Padding(
              key: ValueKey(d.id),
              padding: const EdgeInsets.only(bottom: 10),
              child: _TopicCard(
                index: i,
                draft: d,
                canDelete: _topics.length > 1 || d.isFilled,
                onChanged: () => setState(() {}),
                onDelete: () => _removeTopic(d),
                onSubmitted: () {
                  if (i == _topics.length - 1 && d.isFilled) _addTopic();
                },
              ),
            );
          },
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: AppColors.primary,
            side: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.4),
              width: 1.3,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: _addTopic,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add topic'),
        ),
      ],
    );
  }

  // ── Step 3: schedule ───────────────────────────────────────────────────

  Widget _scheduleSection(ThemeData theme) {
    final today = _today();
    final exams = ref.watch(upcomingExamsProvider).take(3).toList();
    final subjectsById = ref.watch(subjectsByIdProvider);
    final df = DateFormat('EEE, d MMM yyyy');
    final weekdays = {1, 2, 3, 4, 5};
    final everyDay = {1, 2, 3, 4, 5, 6, 7};
    bool sameSet(Set<int> a) =>
        a.length == _studyDays.length && a.containsAll(_studyDays);

    final quick = <(String, String, DateTime)>[
      ('1w', '1 week', today.add(const Duration(days: 7))),
      ('2w', '2 weeks', today.add(const Duration(days: 14))),
      ('1m', '1 month', DateTime(today.year, today.month + 1, today.day)),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: softCard(context, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel(
            icon: Icons.timer_outlined,
            text: 'Time per study day',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _dailyOptions)
                FilterPill(
                  label: formatEstMinutes(m),
                  selected: _dailyMinutes == m,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _dailyMinutes = m);
                  },
                ),
            ],
          ),
          const _Divider(),
          Row(
            children: [
              const Expanded(
                child: _FieldLabel(
                  icon: Icons.calendar_view_week_rounded,
                  text: 'Study days',
                ),
              ),
              _MiniToggle(
                label: 'Weekdays',
                selected: sameSet(weekdays),
                onTap: () => _setDays(weekdays),
              ),
              const SizedBox(width: 6),
              _MiniToggle(
                label: 'Every day',
                selected: sameSet(everyDay),
                onTap: () => _setDays(everyDay),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _DayToggle(
                    letter: _dayLetters[i],
                    name: _dayNames[i],
                    selected: _studyDays.contains(i + 1),
                    onTap: () => _toggleDay(i + 1),
                  ),
                ),
              ],
            ],
          ),
          const _Divider(),
          const _FieldLabel(icon: Icons.flag_outlined, text: 'Finish by'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in quick)
                FilterPill(
                  label: q.$2,
                  selected: _deadlineChip == q.$1,
                  onTap: () => _setDeadline(q.$3, q.$1),
                ),
              for (final e in exams)
                FilterPill(
                  label: 'Before ${e.title}',
                  icon: Icons.school_outlined,
                  accent: AppColors.coral,
                  selected: _deadlineChip == 'exam:${e.id}',
                  onTap: () {
                    final day = DateTime(
                      e.date.year,
                      e.date.month,
                      e.date.day,
                    ).subtract(const Duration(days: 1));
                    _setDeadline(day, 'exam:${e.id}');
                    if (_subjectCtrl.text.trim().isEmpty) {
                      final s = subjectsById[e.subjectId]?.name;
                      setState(
                        () => _subjectCtrl.text =
                            (s != null && s.trim().isNotEmpty) ? s : e.title,
                      );
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Material(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        df.format(_targetDate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      'Change',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteTile(ThemeData theme) {
    return Container(
      decoration: softCard(context, radius: 18),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(),
          leading: const Icon(
            Icons.sticky_note_2_outlined,
            color: AppColors.primary,
          ),
          title: Text('Add a note', style: theme.textTheme.titleSmall),
          subtitle: Text(
            'Optional — goals, resources, reminders',
            style: theme.textTheme.bodySmall,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            TextField(
              controller: _noteCtrl,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'e.g. Use the class notes + last year’s papers',
                filled: true,
                fillColor: AppColors.primary.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────

class _StepLabel extends StatelessWidget {
  final int number;
  final String title;
  final bool done;
  final String? trailing;
  const _StepLabel({
    required this.number,
    required this.title,
    required this.done,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      label: 'Step $number: $title${done ? ', done' : ''}',
      excludeSemantics: true,
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? AppColors.success
                  : AppColors.primary.withValues(alpha: 0.12),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text(
                    '$number',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: AppColors.primary,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FieldLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 17, color: theme.textTheme.bodySmall?.color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Divider(
      height: 1,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
    ),
  );
}

class _PasteBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _PasteBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              const Icon(
                Icons.content_paste_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paste your syllabus',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'One topic per line — we add them all at once',
                      maxLines: 2,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  final int index;
  final _TopicDraft draft;
  final bool canDelete;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final VoidCallback onSubmitted;

  const _TopicCard({
    required this.index,
    required this.draft,
    required this.canDelete,
    required this.onChanged,
    required this.onDelete,
    required this.onSubmitted,
  });

  static const _step = 15;
  static const _min = 15;
  static const _max = 240;

  void _bump(int delta) {
    HapticFeedback.selectionClick();
    draft.minutes = (draft.minutes + delta).clamp(_min, _max);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = draft.isFilled;
    final subCount = draft.subtopicTexts.length;
    final linkCount = draft.linkUrls.length;

    return Container(
      decoration: softCard(context, radius: 18).copyWith(
        border: Border.all(
          color: draft.focus.hasFocus
              ? AppColors.primary.withValues(alpha: 0.5)
              : Colors.transparent,
          width: 1.3,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 6, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Tooltip(
                  message: 'Drag to reorder',
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 20,
                      color: theme.textTheme.bodySmall?.color?.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: filled
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: filled ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Focus(
                  onFocusChange: (_) => onChanged(),
                  child: TextField(
                    controller: draft.title,
                    focusNode: draft.focus,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => onSubmitted(),
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 120,
                    style: theme.textTheme.titleSmall,
                    decoration: InputDecoration(
                      hintText: 'Topic ${index + 1}',
                      counterText: '',
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove topic',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 19),
                color: theme.textTheme.bodySmall?.color,
                onPressed: canDelete ? onDelete : null,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _DurationStepper(
                  minutes: draft.minutes,
                  onMinus: draft.minutes > _min ? () => _bump(-_step) : null,
                  onPlus: draft.minutes < _max ? () => _bump(_step) : null,
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    draft.expanded = !draft.expanded;
                    if (draft.expanded && draft.subtopics.isEmpty) {
                      draft.subtopics.add(TextEditingController());
                    }
                    onChanged();
                  },
                  icon: Icon(
                    draft.expanded
                        ? Icons.expand_less_rounded
                        : Icons.subdirectory_arrow_right_rounded,
                    size: 17,
                  ),
                  label: Text(
                    subCount == 0
                        ? 'Subtopics'
                        : '$subCount subtopic${subCount == 1 ? '' : 's'}',
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    draft.linksOpen = !draft.linksOpen;
                    if (draft.linksOpen && draft.links.isEmpty) {
                      draft.links.add(TextEditingController());
                    }
                    onChanged();
                  },
                  icon: Icon(
                    draft.linksOpen
                        ? Icons.expand_less_rounded
                        : Icons.link_rounded,
                    size: 17,
                  ),
                  label: Text(
                    linkCount == 0
                        ? 'Links'
                        : '$linkCount link${linkCount == 1 ? '' : 's'}',
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !draft.expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(46, 8, 4, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var j = 0; j < draft.subtopics.length; j++)
                          Padding(
                            // Breathing room between the filled fields.
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(right: 10),
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: draft.subtopics[j],
                                    // A freshly added subtopic gets the cursor.
                                    autofocus: draft.focusNewSubtopic &&
                                        j == draft.subtopics.length - 1,
                                    onChanged: (_) => onChanged(),
                                    // Enter → next subtopic, for fast typing.
                                    textInputAction: TextInputAction.next,
                                    onSubmitted: (v) {
                                      if (v.trim().isEmpty) return;
                                      if (j == draft.subtopics.length - 1 &&
                                          draft.subtopics.length < 30) {
                                        draft.focusNewSubtopic = true;
                                        draft.subtopics
                                            .add(TextEditingController());
                                        onChanged();
                                      }
                                    },
                                    maxLength: 120,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    style: theme.textTheme.bodyMedium,
                                    decoration: InputDecoration(
                                      hintText: 'Subtopic ${j + 1}',
                                      counterText: '',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove subtopic',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                    size: 18,
                                  ),
                                  color: theme.textTheme.bodySmall?.color,
                                  onPressed: () {
                                    draft.subtopics.removeAt(j).dispose();
                                    onChanged();
                                  },
                                ),
                              ],
                            ),
                          ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: draft.subtopics.length >= 30
                              ? null
                              : () {
                                  draft.focusNewSubtopic = true;
                                  draft.subtopics.add(TextEditingController());
                                  onChanged();
                                },
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add subtopic'),
                        ),
                      ],
                    ),
                  ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !draft.linksOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(46, 8, 4, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var j = 0; j < draft.links.length; j++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _LinkField(
                              controller: draft.links[j],
                              onChanged: onChanged,
                              onRemove: () {
                                draft.links.removeAt(j).dispose();
                                onChanged();
                              },
                            ),
                          ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: draft.links.length >= 10
                              ? null
                              : () {
                                  draft.links.add(TextEditingController());
                                  onChanged();
                                },
                          icon: const Icon(Icons.add_link_rounded, size: 17),
                          label: const Text('Add link'),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A URL field with live validation: shows the site name when valid and a
/// gentle error when not (only invalid links block nothing — they're skipped).
class _LinkField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  const _LinkField({
    required this.controller,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = controller.text.trim();
    final normalized = normalizeStudyLink(text);
    final host = normalized == null
        ? null
        : Uri.parse(normalized).host.replaceFirst('www.', '');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, right: 8),
          child: Icon(Icons.link_rounded,
              size: 18,
              color: text.isEmpty || normalized != null
                  ? AppColors.primary
                  : AppColors.danger),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            keyboardType: TextInputType.url,
            autocorrect: false,
            maxLength: 2000,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Paste a link (YouTube, article, notes)',
              counterText: '',
              isDense: true,
              helperText: host,
              errorText: text.isNotEmpty && normalized == null
                  ? 'Not a valid web link'
                  : null,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Remove link',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
          color: theme.textTheme.bodySmall?.color,
          onPressed: onRemove,
        ),
      ],
    );
  }
}

class _DurationStepper extends StatelessWidget {
  final int minutes;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const _DurationStepper({
    required this.minutes,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget btn(IconData icon, String label, VoidCallback? onTap) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 16,
            color: onTap == null ? theme.disabledColor : AppColors.primary,
          ),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove_rounded, 'Less time', onMinus),
          Semantics(
            label: 'About ${formatEstMinutes(minutes)}',
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 52),
              child: Text(
                '~${formatEstMinutes(minutes)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          btn(Icons.add_rounded, 'More time', onPlus),
        ],
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  final String letter;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  const _DayToggle({
    required this.letter,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      toggled: selected,
      label: name,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : theme.dividerColor,
            ),
          ),
          child: Text(
            letter,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              color: selected
                  ? Colors.white
                  : theme.textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MiniToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected
                  ? AppColors.primary
                  : theme.textTheme.bodySmall?.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Live "Will it fit?" check with one-tap fixes.
class _FitCard extends StatelessWidget {
  final PlanFit fit;
  final DateTime targetDate;
  final int? suggestedDaily;
  final DateTime? suggestedFinish;
  final ValueChanged<int> onUseDaily;
  final ValueChanged<DateTime> onUseFinish;

  const _FitCard({
    required this.fit,
    required this.targetDate,
    required this.suggestedDaily,
    required this.suggestedFinish,
    required this.onUseDaily,
    required this.onUseFinish,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = fit.status;
    final (color, icon, title) = switch (status) {
      FitStatus.empty => (
        AppColors.primary,
        Icons.auto_graph_rounded,
        'Add topics to see your plan',
      ),
      FitStatus.fits => (
        AppColors.success,
        Icons.check_circle_rounded,
        'Fits comfortably',
      ),
      FitStatus.tight => (
        AppColors.warning,
        Icons.speed_rounded,
        'Tight, but doable',
      ),
      FitStatus.overflow => (
        AppColors.danger,
        Icons.warning_amber_rounded,
        "Won't fit by ${DateFormat('d MMM').format(targetDate)}",
      ),
    };

    final detail = switch (status) {
      FitStatus.empty => 'We check your topics against your time as you type.',
      FitStatus.overflow when fit.studyDays == 0 =>
        'No study days before the deadline. Pick a later date or more days.',
      FitStatus.overflow =>
        'You need about ${formatEstMinutes(fit.neededPerDay)} a day, '
            'or ${fit.daysNeeded} study days.',
      _ =>
        '~${formatEstMinutes(fit.totalMinutes)} over ${fit.studyDays} '
            'study day${fit.studyDays == 1 ? '' : 's'} '
            '(${formatEstMinutes(fit.capacity)} available).',
    };

    final fixes = <Widget>[
      if (status == FitStatus.overflow &&
          suggestedDaily != null &&
          suggestedDaily != fit.dailyMinutes &&
          fit.studyDays > 0)
        _FixChip(
          label: 'Study ${formatEstMinutes(suggestedDaily!)}/day',
          onTap: () => onUseDaily(suggestedDaily!),
        ),
      if (status == FitStatus.overflow && suggestedFinish != null)
        _FixChip(
          label: 'Finish ${DateFormat('d MMM').format(suggestedFinish!)}',
          onTap: () => onUseFinish(suggestedFinish!),
        ),
    ];

    return Semantics(
      liveRegion: true,
      container: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
            if (status != FitStatus.empty) ...[
              const SizedBox(height: 12),
              ThinProgressBar(
                value: fit.load.clamp(0, 1).toDouble(),
                height: 6,
                color: color,
              ),
            ],
            if (fixes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: fixes),
            ],
          ],
        ),
      ),
    );
  }
}

class _FixChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FixChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(
        Icons.auto_fix_high_rounded,
        size: 16,
        color: AppColors.primary,
      ),
      label: Text(label),
      labelStyle: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: AppColors.primary),
      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onPressed: onTap,
    );
  }
}

/// Bottom sheet: paste a syllabus / list and preview the parsed topics.
class _PasteSheet extends StatefulWidget {
  const _PasteSheet();

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  final _ctrl = TextEditingController();

  static int _subCount(List<ParsedTopic> p) =>
      p.fold(0, (n, t) => n + t.subtopics.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _fromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() => _ctrl.text = text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = parseTopicList(_ctrl.text);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Paste your topics', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'One per line. Bullets and numbers are removed. Add a time '
                'like "– 45 min" or "(1h)" and we use it. Indent a line '
                '(or start it with ◦) to make it a subtopic of the topic '
                'above.',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                autofocus: true,
                minLines: 6,
                maxLines: 10,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText:
                      '1. Kinematics – 45 min\n    - Displacement\n'
                      '    - Velocity\n2. Laws of motion (1h)',
                  filled: true,
                  fillColor: AppColors.primary.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _fromClipboard,
                    icon: const Icon(Icons.content_paste_go_rounded, size: 18),
                    label: const Text('Paste from clipboard'),
                  ),
                  const Spacer(),
                  Text(
                    parsed.isEmpty
                        ? 'No topics yet'
                        : '${parsed.length} topic${parsed.length == 1 ? '' : 's'}'
                            '${_subCount(parsed) > 0 ? ' · ${_subCount(parsed)} subtopics' : ''} found',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: parsed.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(parsed),
                  child: Text(
                    parsed.isEmpty
                        ? 'Add topics'
                        : 'Add ${parsed.length} topic${parsed.length == 1 ? '' : 's'}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
