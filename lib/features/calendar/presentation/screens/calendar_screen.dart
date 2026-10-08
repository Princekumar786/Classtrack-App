import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/subject_icons.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../services/reminder_scheduler.dart';
import '../../../../shared/widgets/feature_tip_banner.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../exams/domain/exam.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../exams/presentation/screens/exams_screen.dart';
import '../../../import/presentation/screens/import_entry.dart';
import '../../../schedule/presentation/providers/schedule_providers.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../tasks/domain/task_item.dart';
import '../../../tasks/presentation/providers/task_providers.dart';
import '../../../tasks/presentation/screens/tasks_screen.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = ref.watch(tasksStreamProvider).valueOrNull ?? const [];
    final exams = ref.watch(examsStreamProvider).valueOrNull ?? const [];
    // Watch sessions so the month markers refresh when the timetable changes.
    ref.watch(allSessionsProvider);

    // Build a marker map (date-only -> has events) from dated tasks + exams.
    final markers = <DateTime, List<Object>>{};
    void addMarker(DateTime d, Object item) {
      final key = DateTime(d.year, d.month, d.day);
      markers.putIfAbsent(key, () => []).add(item);
    }

    for (final t in tasks) {
      if (t.dueDate != null) addMarker(t.dueDate!, t);
    }
    for (final e in exams) {
      addMarker(e.date, e);
    }

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
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Calendar',
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                RoundIconButton(
                  icon: Icons.file_download_outlined,
                  onTap: () => showImportOptions(context, ref),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _focused = DateTime.now();
                    _selected = DateTime.now();
                  }),
                  child: const Text('Today'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const FeatureTipBanner(
              prefsKey: AppConstants.prefsTipCalendar,
              message: 'Import your Google Calendar in one tap.',
              padding: EdgeInsets.only(bottom: 8),
            ),
            const RemindersBanner(),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: softCard(context),
              child: TableCalendar<Object>(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focused,
                calendarFormat: _format,
                availableCalendarFormats: const {
                  CalendarFormat.month: 'Month',
                  CalendarFormat.twoWeeks: '2 weeks',
                  CalendarFormat.week: 'Week',
                },
                selectedDayPredicate: (d) => isSameDay(d, _selected),
                eventLoader: (day) {
                  final key = DateTime(day.year, day.month, day.day);
                  final classes = ref.read(classesForDayProvider(day));
                  return [
                    ...?markers[key],
                    ...classes,
                  ];
                },
                onDaySelected: (sel, foc) => setState(() {
                  _selected = sel;
                  _focused = foc;
                }),
                onFormatChanged: (f) => setState(() => _format = f),
                onPageChanged: (foc) => _focused = foc,
                startingDayOfWeek: StartingDayOfWeek.monday,
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  markerDecoration: const BoxDecoration(
                    color: AppColors.coral,
                    shape: BoxShape.circle,
                  ),
                  markersMaxCount: 3,
                  outsideDaysVisible: false,
                ),
                headerStyle: HeaderStyle(
                  formatButtonDecoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  formatButtonTextStyle:
                      const TextStyle(color: AppColors.primary),
                  titleCentered: true,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateUtilsX.isSameDay(_selected, DateTime.now())
                        ? 'Today · ${DateUtilsX.prettyDate(_selected)}'
                        : DateUtilsX.prettyFullDate(_selected),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Add on this day',
                  onSelected: (v) {
                    if (v == 'task') {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) =>
                            TaskEditorSheet(initialDue: _selected),
                      );
                    } else {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) =>
                            ExamEditorSheet(initialDate: _selected),
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'task',
                      child: Row(children: [
                        Icon(Icons.check_circle_outline_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Add task'),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'exam',
                      child: Row(children: [
                        Icon(Icons.event_note_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Add exam'),
                      ]),
                    ),
                  ],
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.add_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _agenda(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _agenda(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final classes = ref.watch(classesForDayProvider(_selected));
    final tasks = ref.watch(tasksForDayProvider(_selected));
    final allExams = ref.watch(examsStreamProvider).valueOrNull ?? const [];
    final exams = allExams
        .where((e) => DateUtilsX.isSameDay(e.date, _selected))
        .toList();
    final byId = ref.watch(subjectsByIdProvider);

    if (classes.isEmpty && tasks.isEmpty && exams.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: softCard(context),
        child: Row(
          children: [
            const Icon(Icons.event_available_rounded,
                color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Nothing scheduled for this day.',
                  style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (exams.isNotEmpty) ...[
          _sectionLabel(theme, 'Exams', AppColors.danger),
          for (final e in exams) _examTile(context, e, byId),
          const SizedBox(height: 6),
        ],
        if (classes.isNotEmpty) ...[
          _sectionLabel(theme, 'Classes', AppColors.info),
          for (final c in classes) _classTile(context, c),
          const SizedBox(height: 6),
        ],
        if (tasks.isNotEmpty) ...[
          _sectionLabel(theme, 'Tasks', AppColors.primary),
          for (final t in tasks) _taskTile(context, ref, t, byId),
        ],
      ],
    );
  }

  Widget _sectionLabel(ThemeData theme, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(text,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _tileCard({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: softCard(context),
        child: child,
      );

  Widget _classTile(BuildContext context, ScheduledClass c) {
    final theme = Theme.of(context);
    final color = Color(c.subject.colorHex);
    return _tileCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(SubjectIcons.resolve(c.subject.iconKey),
                color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.subject.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${DateUtilsX.displayTime(context, c.session.startTime)} – ${DateUtilsX.displayTime(context, c.session.endTime)}'
                  '${(c.session.room?.isNotEmpty ?? false) ? ' · ${c.session.room}' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _examTile(BuildContext context, Exam e, Map byId) {
    final theme = Theme.of(context);
    final subject = e.subjectId != null ? byId[e.subjectId] : null;
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => ExamEditorSheet(initial: e),
      ),
      borderRadius: BorderRadius.circular(20),
      child: _tileCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.event_note_rounded,
                  color: AppColors.danger, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${TimeOfDay.fromDateTime(e.date).format(context)}'
                    '${subject != null ? ' · ${subject.name}' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            PillTag(
                label: e.countdownLabel,
                background: AppColors.danger,
                foreground: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _taskTile(
      BuildContext context, WidgetRef ref, TaskItem t, Map byId) {
    final theme = Theme.of(context);
    return _tileCard(
      child: Row(
        children: [
          GestureDetector(
            onTap: () => ref.read(taskControllerProvider).toggle(t),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: t.done ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                    color: t.done ? AppColors.primary : theme.dividerColor,
                    width: 2),
              ),
              child: t.done
                  ? const Icon(Icons.check_rounded,
                      size: 15, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => TaskEditorSheet(task: t),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        decoration:
                            t.done ? TextDecoration.lineThrough : null,
                        color: t.done ? theme.hintColor : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      Icon(t.type.icon, size: 12, color: t.type.color),
                      const SizedBox(width: 5),
                      Text(t.type.label, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
                color: t.priority.color,
                borderRadius: BorderRadius.circular(4)),
          ),
        ],
      ),
    );
  }
}
