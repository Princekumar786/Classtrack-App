import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/checklist_item.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/widgets/progress_ring.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../../shared/widgets/placement_slot.dart';
import '../../../cms/domain/marketing.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../domain/exam.dart';
import '../providers/exam_providers.dart';

enum _ExamView { upcoming, past }

class ExamsScreen extends ConsumerStatefulWidget {
  const ExamsScreen({super.key});

  @override
  ConsumerState<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends ConsumerState<ExamsScreen> {
  _ExamView _view = _ExamView.upcoming;

  static Color urgencyColor(int days, {bool past = false}) {
    if (past) return AppColors.cancelled;
    if (days <= 1) return AppColors.danger;
    if (days <= 3) return AppColors.warning;
    if (days <= 7) return AppColors.accent;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming = ref.watch(upcomingExamsProvider);
    final past = ref.watch(pastExamsProvider);
    final showList = _view == _ExamView.upcoming ? upcoming : past;

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
            Text('Exams',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Countdowns and prep, so nothing sneaks up on you',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.textTheme.bodySmall?.color)),
            const SizedBox(height: 18),
            const PlacementSlot(placement: Placements.exams),
            if (upcoming.isEmpty && past.isEmpty)
              _empty(context)
            else ...[
              // Hero: the very next exam.
              if (upcoming.isNotEmpty) ...[
                _nextExamHero(context, ref, upcoming.first)
                    .animate()
                    .fadeIn(duration: 340.ms)
                    .slideY(begin: 0.06, curve: Curves.easeOut),
                const SizedBox(height: 18),
              ],
              if (past.isNotEmpty) ...[
                _viewToggle(theme, upcoming.length, past.length),
                const SizedBox(height: 16),
              ],
              if (showList.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Center(
                    child: Text(
                        _view == _ExamView.upcoming
                            ? 'No upcoming exams'
                            : 'No past exams',
                        style: theme.textTheme.bodyMedium),
                  ),
                )
              else
                for (var i = 0; i < showList.length; i++)
                  _examCard(context, ref, showList[i],
                          past: _view == _ExamView.past)
                      .listEntrance(i, stepMs: 50, slide: 0.08),
            ],
          ],
        ),
      ),
    );
  }

  Widget _viewToggle(ThemeData theme, int upCount, int pastCount) {
    Widget seg(_ExamView v, String label, int count) {
      final selected = v == _view;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _view = v),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: Text('$label · $count',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? Colors.white
                      : theme.textTheme.bodySmall?.color,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          seg(_ExamView.upcoming, 'Upcoming', upCount),
          seg(_ExamView.past, 'Past', pastCount),
        ],
      ),
    );
  }

  /// Prominent countdown card for the soonest exam, with a readiness ring.
  Widget _nextExamHero(BuildContext context, WidgetRef ref, Exam e) {
    final theme = Theme.of(context);
    final byId = ref.watch(subjectsByIdProvider);
    final subject = e.subjectId != null ? byId[e.subjectId] : null;
    final accent = urgencyColor(e.daysUntil);
    final timeLabel = TimeOfDay.fromDateTime(e.date).format(context);
    final countdown =
        e.daysUntil == 0 ? 'Today' : (e.daysUntil == 1 ? 'Tomorrow' : '${e.daysUntil}');
    final showDaysUnit = e.daysUntil > 1;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openEditor(context, exam: e),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent, Color.lerp(accent, Colors.black, 0.28)!],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppColors.softShadow(opacity: 0.20, blur: 22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_note_rounded,
                      size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text('Next exam',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: Colors.white70)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(e.countdownLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Big countdown.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(countdown,
                          style: theme.textTheme.displaySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              fontSize: 30)),
                      if (showDaysUnit)
                        const Text('days to go',
                            style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const Spacer(),
                  // Readiness ring or prompt.
                  if (e.hasTopics)
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: AnimatedProgressRing(
                        percent: e.readiness * 100,
                        size: 52,
                        strokeWidth: 6,
                        color: Colors.white,
                        centerLabel: '${e.topicsDone}/${e.topics.length}',
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.checklist_rounded,
                              size: 15, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Add prep list',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(e.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _heroMeta(Icons.calendar_today_rounded,
                      '${DateUtilsX.prettyDate(e.date)} · $timeLabel'),
                  if (subject != null)
                    _heroMeta(Icons.menu_book_rounded, subject.name),
                  if (e.room?.isNotEmpty ?? false)
                    _heroMeta(Icons.meeting_room_rounded, e.room!),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroMeta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white70),
        const SizedBox(width: 5),
        Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 12.5)),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: softCard(context),
      child: Column(
        children: [
          const Icon(Icons.event_note_rounded,
              size: 42, color: AppColors.primary),
          const SizedBox(height: 12),
          Text('No exams yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
              'Add your tests to see live countdowns, track revision and stay prepared.',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add exam'),
          ),
        ],
      ),
    );
  }

  Widget _examCard(BuildContext context, WidgetRef ref, Exam e,
      {bool past = false}) {
    final theme = Theme.of(context);
    final byId = ref.watch(subjectsByIdProvider);
    final subject = e.subjectId != null ? byId[e.subjectId] : null;
    final accent = urgencyColor(e.daysUntil, past: past);
    final timeLabel = TimeOfDay.fromDateTime(e.date).format(context);

    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            SizedBox(width: 6),
            Text('Delete',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      onDismissed: (_) => _deleteWithUndo(context, ref, e),
      child: Opacity(
        opacity: past ? 0.75 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: softCard(context),
          child: InkWell(
            onTap: () => _openEditor(context, exam: e),
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            past
                                ? '✓'
                                : (e.daysUntil == 0
                                    ? 'Today'
                                    : '${e.daysUntil}'),
                            style: theme.textTheme.titleLarge?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w800,
                                height: 1),
                          ),
                          if (!past && e.daysUntil > 0)
                            Text(e.daysUntil == 1 ? 'day' : 'days',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: accent, fontSize: 10)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.calendar_today_rounded,
                                  size: 12, color: theme.hintColor),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  '${DateUtilsX.prettyDate(e.date)} · $timeLabel',
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (subject != null ||
                              (e.room?.isNotEmpty ?? false)) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                if (subject != null) ...[
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                        color: Color(subject.colorHex),
                                        shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(subject.name,
                                        style: theme.textTheme.bodySmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                                if (e.room?.isNotEmpty ?? false) ...[
                                  if (subject != null)
                                    const SizedBox(width: 8),
                                  Icon(Icons.meeting_room_rounded,
                                      size: 12, color: theme.hintColor),
                                  const SizedBox(width: 4),
                                  Text(e.room!,
                                      style: theme.textTheme.bodySmall),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                // Prep readiness bar.
                if (e.hasTopics && !past) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.checklist_rounded,
                          size: 14, color: accent),
                      const SizedBox(width: 6),
                      Text('Prep ${e.topicsDone}/${e.topics.length}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: e.readiness,
                            minHeight: 6,
                            backgroundColor: accent.withValues(alpha: 0.14),
                            valueColor: AlwaysStoppedAnimation(accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _deleteWithUndo(BuildContext context, WidgetRef ref, Exam e) {
    final ctrl = ref.read(examControllerProvider);
    ctrl.delete(e.id);
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Text('Deleted “${e.title}”'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => ctrl.add(Exam(
          id: 'new',
          title: e.title,
          subjectId: e.subjectId,
          date: e.date,
          room: e.room,
          note: e.note,
          topics: e.topics,
        )),
      ),
    ));
  }

  void _openEditor(BuildContext context, {Exam? exam}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExamEditorSheet(initial: exam),
    );
  }
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
              Text('Add exam',
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

class ExamEditorSheet extends ConsumerStatefulWidget {
  final Exam? initial;
  final DateTime? initialDate;
  const ExamEditorSheet({super.key, this.initial, this.initialDate});

  @override
  ConsumerState<ExamEditorSheet> createState() => _ExamEditorSheetState();
}

class _ExamEditorSheetState extends ConsumerState<ExamEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _room;
  late final TextEditingController _note;
  String? _subjectId;
  late DateTime _date;
  final List<_TopicField> _topics = [];

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _title = TextEditingController(text: e?.title ?? '');
    _room = TextEditingController(text: e?.room ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _subjectId = e?.subjectId;
    _topics.addAll((e?.topics ?? const [])
        .map((t) => _TopicField(text: t.text, done: t.done)));
    final initDate = widget.initialDate;
    _date = e?.date ??
        (initDate != null
            ? DateTime(initDate.year, initDate.month, initDate.day, 9, 0)
            : DateTime.now().add(const Duration(days: 1)).copyWith(
                hour: 9, minute: 0, second: 0, millisecond: 0, microsecond: 0));
  }

  @override
  void dispose() {
    _title.dispose();
    _room.dispose();
    _note.dispose();
    for (final t in _topics) {
      t.dispose();
    }
    super.dispose();
  }

  List<ChecklistItem> _buildTopics() => _topics
      .where((t) => t.controller.text.trim().isNotEmpty)
      .map((t) => ChecklistItem(text: t.controller.text.trim(), done: t.done))
      .toList();

  void _addTopic() => setState(() => _topics.add(_TopicField()));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() => _date = DateTime(
          picked.year, picked.month, picked.day, _date.hour, _date.minute));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (picked != null) {
      setState(() => _date = DateTime(
          _date.year, _date.month, _date.day, picked.hour, picked.minute));
    }
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give the exam a title.')));
      return;
    }
    final ctrl = ref.read(examControllerProvider);
    final room = _room.text.trim();
    final note = _note.text.trim();
    final topics = _buildTopics();
    if (widget.initial == null) {
      ctrl.add(Exam(
        id: 'new',
        title: title,
        subjectId: _subjectId,
        date: _date,
        room: room.isEmpty ? null : room,
        note: note.isEmpty ? null : note,
        topics: topics,
      ));
    } else {
      ctrl.update(widget.initial!.copyWith(
        title: title,
        subjectId: _subjectId,
        clearSubject: _subjectId == null,
        date: _date,
        room: room.isEmpty ? null : room,
        clearRoom: room.isEmpty,
        note: note.isEmpty ? null : note,
        clearNote: note.isEmpty,
        topics: topics,
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
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
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Text(widget.initial == null ? 'Add exam' : 'Edit exam',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Exam title'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _pickerTile(
                    icon: Icons.calendar_today_rounded,
                    label: DateUtilsX.prettyDate(_date),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _pickerTile(
                    icon: Icons.schedule_rounded,
                    label: TimeOfDay.fromDateTime(_date).format(context),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              // An exam can point at a deleted subject; show "No subject"
              // rather than crash the picker with an unknown value.
              initialValue:
                  subjects.any((s) => s.id == _subjectId) ? _subjectId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Subject'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('No subject')),
                for (final s in subjects)
                  DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text(s.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _subjectId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _room,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Room (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Topics / syllabus (optional)'),
            ),
            const SizedBox(height: 16),
            // Prep / revision checklist.
            Row(
              children: [
                Text('Revision checklist', style: theme.textTheme.labelLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addTopic,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add topic'),
                ),
              ],
            ),
            for (var i = 0; i < _topics.length; i++) _topicRow(i, _topics[i]),
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.initial != null)
                  IconButton(
                    onPressed: () {
                      ref
                          .read(examControllerProvider)
                          .delete(widget.initial!.id);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.danger),
                  ),
                Expanded(
                  child: FilledButton(
                      onPressed: _save, child: const Text('Save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _topicRow(int i, _TopicField t) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => t.done = !t.done),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: t.done ? AppColors.success : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                    color: t.done ? AppColors.success : theme.dividerColor,
                    width: 2),
              ),
              child: t.done
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: t.controller,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Topic to revise',
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: theme.hintColor),
            onPressed: () => setState(() {
              t.dispose();
              _topics.removeAt(i);
            }),
          ),
        ],
      ),
    );
  }

  Widget _pickerTile(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: theme.inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.hintColor),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

/// Editable revision-topic row backing (text field + done flag).
class _TopicField {
  final TextEditingController controller;
  bool done;
  _TopicField({String text = '', this.done = false})
      : controller = TextEditingController(text: text);
  void dispose() => controller.dispose();
}
