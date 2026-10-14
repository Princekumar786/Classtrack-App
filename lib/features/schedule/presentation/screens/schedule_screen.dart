import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classtrack/core/theme/app_icons.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../import/presentation/screens/import_entry.dart';
import '../../../attendance/domain/attendance_record.dart';
import '../../../attendance/presentation/providers/attendance_providers.dart';
import '../../../exams/domain/exam.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../exams/presentation/screens/exams_screen.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../tasks/presentation/providers/task_providers.dart';
import '../../../tasks/presentation/screens/tasks_screen.dart';
import '../../../tasks/presentation/widgets/task_timeline_tile.dart';
import '../providers/schedule_providers.dart';
import 'edit_session_screen.dart';

enum ScheduleView { day, week, month }

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  ScheduleView _view = ScheduleView.day;
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();

  void _openEditor() {
    Navigator.of(context).push(
      MaterialPageRoute(settings: const RouteSettings(name: 'Edit Session'), builder: (_) => const EditSessionScreen()),
    );
  }

  /// Current attendance status for one class occurrence (this subject, on
  /// [date], at the session's start-time slot). Returns [AttendanceStatus.unmarked]
  /// when nothing has been marked for that specific occurrence yet. Watched via
  /// [ref] so the sheet rebuilds the moment a mark is added/changed/cleared.
  AttendanceStatus _occurrenceStatus(
      WidgetRef ref, ScheduledClass c, DateTime date) {
    final dateId = DateUtilsX.dateId(date);
    final slot = c.session.startTime;
    final records = ref.watch(dedupedAttendanceForSubjectProvider(c.subject.id));
    for (final r in records) {
      if (r.dateId == dateId &&
          r.slot == slot &&
          r.status != AttendanceStatus.unmarked) {
        return r.status;
      }
    }
    return AttendanceStatus.unmarked;
  }

  void _showClassSheet(ScheduledClass c, DateTime date) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        // When an occurrence is already marked the sheet shows a compact
        // "marked" view (status + Edit + Delete). Tapping Edit flips [editing]
        // so the Present/Absent/Cancelled buttons reappear to change the mark.
        bool editing = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Consumer(
            builder: (ctx, sheetRef, _) {
              final theme = Theme.of(ctx);
              final color = Color(c.subject.colorHex);
              final status = _occurrenceStatus(sheetRef, c, date);
              final isMarked = status != AttendanceStatus.unmarked;
              final showMarkOptions = !isMarked || editing;

              // Write a status for this specific occurrence (idempotent, so it
              // matches Home/Progress and never double-counts). Passing
              // [AttendanceStatus.unmarked] clears the mark.
              void setStatus(AttendanceStatus s) {
                HapticFeedback.selectionClick();
                ref.read(attendanceControllerProvider).setForOccurrence(
                    c.subject.id, date, c.session.startTime, s);
                Navigator.pop(ctx);
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(c.subject.name,
                              style: theme.textTheme.titleLarge),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${DateUtilsX.displayTime(ctx, c.session.startTime)} – ${DateUtilsX.displayTime(ctx, c.session.endTime)}'
                      '${c.session.room?.isNotEmpty == true ? '  ·  ${c.session.room}' : ''}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                    if (isMarked && !editing) ...[
                      // Already marked: show what was marked + Edit/Delete of
                      // the mark (change it, or clear it).
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: status.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(status.icon, color: status.color),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Attendance',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: theme.hintColor)),
                                Text('Marked ${status.label}',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: status.color)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  setSheetState(() => editing = true),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Edit'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side:
                                    const BorderSide(color: AppColors.danger),
                              ),
                              onPressed: () =>
                                  setStatus(AttendanceStatus.unmarked),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 18),
                              label: const Text('Delete'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (showMarkOptions) ...[
                      Text(editing ? 'Change attendance' : 'Mark attendance',
                          style: theme.textTheme.labelLarge),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (final s in [
                            AttendanceStatus.present,
                            AttendanceStatus.absent,
                            AttendanceStatus.cancelled,
                          ]) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: s.color,
                                  side: BorderSide(color: s.color),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () => setStatus(s),
                                icon: Icon(s.icon, size: 18),
                                label: Text(s.label,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                      if (editing) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: () =>
                                setSheetState(() => editing = false),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                      // Class-level edit/delete stay available while the
                      // occurrence is still unmarked.
                      if (!isMarked) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _editClass(c);
                                },
                                icon:
                                    const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('Edit class'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                  side: const BorderSide(
                                      color: AppColors.danger),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _deleteClass(c);
                                },
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label: const Text('Delete class'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  if (canPop) ...[
                    RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text('Schedule',
                        style: theme.textTheme.displaySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  RoundIconButton(
                    icon: Icons.file_download_outlined,
                    onTap: () => showImportOptions(context, ref),
                  ),
                  const SizedBox(width: 10),
                  RoundIconButton(
                    icon: Icons.add_rounded,
                    background: AppColors.primary,
                    iconColor: Colors.white,
                    onTap: _openEditor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: ScheduleView.values.map((v) {
                  final selected = v == _view;
                  final label = switch (v) {
                    ScheduleView.day => 'Day',
                    ScheduleView.week => 'Week',
                    ScheduleView.month => 'Month',
                  };
                  return Flexible(
                    child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => setState(() => _view = v),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.ink : theme.cardColor,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: selected
                                ? Colors.white
                                : theme.textTheme.bodySmall?.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (_view) {
                ScheduleView.day => _dayView(),
                ScheduleView.week => _weekView(),
                ScheduleView.month => _monthView(),
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- DAY ----------------
  Widget _dayView() {
    final classes = ref.watch(classesForDayProvider(_selectedDay));
    final dueTasks = ref.watch(tasksForDayProvider(_selectedDay));
    final allExams = ref.watch(examsStreamProvider).valueOrNull ?? const [];
    final exams = allExams
        .where((e) => DateUtilsX.isSameDay(e.date, _selectedDay))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final isEmpty = classes.isEmpty && dueTasks.isEmpty && exams.isEmpty;

    return Column(
      children: [
        _dateStrip(),
        Expanded(
          child: isEmpty
              ? EmptyState(
                  icon: PhosphorIcons.coffee(),
                  title: 'Nothing scheduled',
                  message:
                      'No classes, tasks, or exams for ${DateUtilsX.prettyDate(_selectedDay)}. Enjoy the break!',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                  children: [
                    if (exams.isNotEmpty) ...[
                      _sectionLabel('Exams', AppColors.danger),
                      for (final e in exams) _examTile(e),
                      const SizedBox(height: 6),
                    ],
                    if (classes.isNotEmpty) ...[
                      _sectionLabel('Classes', AppColors.info),
                      for (var i = 0; i < classes.length; i++)
                        _dayClassTile(
                            classes[i], i, classes.length, _selectedDay),
                      const SizedBox(height: 6),
                    ],
                    if (dueTasks.isNotEmpty) ...[
                      _sectionLabel('Tasks', AppColors.primary),
                      for (var i = 0; i < dueTasks.length; i++)
                        TaskTimelineTile(
                          task: dueTasks[i],
                          isFirst: i == 0,
                          isLast: i == dueTasks.length - 1,
                          onTap: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) =>
                                TaskEditorSheet(task: dueTasks[i]),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _dateStrip() {
    final today = DateTime.now();
    // Grow with the OS text size so the weekday + date never overflow.
    final ts = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    return SizedBox(
      height: 84 + (ts - 1.0) * 30,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: 21,
        itemBuilder: (context, i) {
          final date = DateTime(today.year, today.month, today.day)
              .add(Duration(days: i - 3));
          final selected = DateUtilsX.isSameDay(date, _selectedDay);
          final theme = Theme.of(context);
          return GestureDetector(
            onTap: () => setState(() => _selectedDay = date),
            child: Container(
              width: 56,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? AppColors.primary : theme.dividerColor,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Fixed 56×60 chip: shrink text to fit at large font sizes.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      Weekdays.short[date.weekday - 1],
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected ? Colors.white70 : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${date.day}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: selected ? Colors.white : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------- WEEK ----------------
  Widget _weekView() {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final todayIdx = now.weekday - 1; // 0 = Monday
    // Anchor each row to the real calendar date in the *current* week so the
    // list honors each subject's course start/end dates (and one-off classes /
    // cancellations), staying consistent with the Day and Month views.
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: todayIdx));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
      itemCount: 7,
      itemBuilder: (context, day) {
        final date = monday.add(Duration(days: day));
        final classes = ref.watch(classesForDayProvider(date));
        final isToday = day == todayIdx;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: softCard(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(Weekdays.full[day], style: theme.textTheme.titleMedium),
                  if (isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Today',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    classes.isEmpty
                        ? 'Free'
                        : '${classes.length} ${classes.length == 1 ? 'class' : 'classes'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              if (classes.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('No classes — free day 🎉',
                      style: theme.textTheme.bodySmall),
                )
              else ...[
                const SizedBox(height: 12),
                ...classes.map((c) => _classTileStatic(c)),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---------------- MONTH ----------------
  Widget _monthView() {
    final theme = Theme.of(context);
    final classes = ref.watch(classesForDayProvider(_selectedDay));
    final tasks = ref.watch(tasksForDayProvider(_selectedDay));
    final allExams = ref.watch(examsStreamProvider).valueOrNull ?? const [];
    final exams = allExams
        .where((e) => DateUtilsX.isSameDay(e.date, _selectedDay))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    // Watch tasks/exams streams so markers refresh on change.
    ref.watch(tasksStreamProvider);

    List<Object> eventsFor(DateTime day) => [
          ...ref.read(classesForDayProvider(day)),
          ...ref.read(tasksForDayProvider(day)),
          ...(ref.read(examsStreamProvider).valueOrNull ?? const [])
              .where((e) => DateUtilsX.isSameDay(e.date, day)),
        ];

    final nothing = classes.isEmpty && tasks.isEmpty && exams.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(26),
            boxShadow: theme.brightness == Brightness.light
                ? AppColors.softShadow(opacity: 0.06, blur: 22)
                : null,
          ),
          child: TableCalendar<Object>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (d) => DateUtilsX.isSameDay(d, _selectedDay),
            calendarFormat: CalendarFormat.month,
            startingDayOfWeek: StartingDayOfWeek.sunday,
            eventLoader: eventsFor,
            onDaySelected: (selected, focused) => setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            }),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              leftChevronIcon: const Icon(Icons.chevron_left_rounded),
              rightChevronIcon: const Icon(Icons.chevron_right_rounded),
              titleTextStyle: theme.textTheme.titleLarge!,
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: theme.textTheme.bodySmall!,
              weekendStyle: theme.textTheme.bodySmall!,
            ),
            calendarStyle: CalendarStyle(
              isTodayHighlighted: true,
              markersMaxCount: 1,
              markerSize: 5,
              markerMargin: const EdgeInsets.only(top: 1),
              markerDecoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              defaultTextStyle: theme.textTheme.bodyMedium!,
              weekendTextStyle: theme.textTheme.bodyMedium!,
              outsideTextStyle: theme.textTheme.bodySmall!
                  .copyWith(color: theme.disabledColor),
              todayDecoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              todayTextStyle: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700),
              selectedDecoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(DateUtilsX.prettyFullDate(_selectedDay),
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (nothing)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(PhosphorIcons.coffee(), color: theme.hintColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Nothing scheduled this day',
                      style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          )
        else ...[
          if (exams.isNotEmpty) ...[
            _sectionLabel('Exams', AppColors.danger),
            for (final e in exams) _examTile(e),
            const SizedBox(height: 6),
          ],
          if (classes.isNotEmpty) ...[
            _sectionLabel('Classes', AppColors.info),
            for (var i = 0; i < classes.length; i++)
              _dayClassTile(classes[i], i, classes.length, _selectedDay),
            const SizedBox(height: 6),
          ],
          if (tasks.isNotEmpty) ...[
            _sectionLabel('Tasks', AppColors.primary),
            for (var i = 0; i < tasks.length; i++)
              TaskTimelineTile(
                task: tasks[i],
                isFirst: i == 0,
                isLast: i == tasks.length - 1,
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => TaskEditorSheet(task: tasks[i]),
                ),
              ),
          ],
        ],
      ],
    );
  }

  // ---------------- shared tiles ----------------
  /// Timeline day tile: a colour-coded rail node + a subject-tinted card
  /// (the class in progress fills solid with a live progress bar). Tapping
  /// opens the class sheet to mark attendance, edit or delete.
  Widget _dayClassTile(
      ScheduledClass c, int index, int total, DateTime date) {
    final theme = Theme.of(context);
    final color = Color(c.subject.colorHex);
    final isToday = DateUtilsX.isSameDay(date, DateTime.now());
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    final start = DateUtilsX.minutesOfDay(c.session.startTime);
    final end = DateUtilsX.minutesOfDay(c.session.endTime);
    final isNow = isToday && nowMin >= start && nowMin < end;
    final isPast = isToday && nowMin >= end;
    final room = (c.session.room != null && c.session.room!.isNotEmpty)
        ? c.session.room
        : c.subject.room;
    final hasRoom = room != null && room.isNotEmpty;
    final progress = (isNow && end > start)
        ? ((nowMin - start) / (end - start)).clamp(0.0, 1.0)
        : 0.0;
    final minsLeft = isNow ? (end - nowMin) : 0;
    final isFirst = index == 0;
    final isLast = index == total - 1;
    final lineColor = AppColors.primary.withValues(alpha: 0.25);
    final cardColor = isNow ? color : color.withValues(alpha: 0.12);
    final onCard = isNow ? Colors.white : theme.textTheme.titleLarge?.color;
    final subColor =
        isNow ? Colors.white.withValues(alpha: 0.85) : theme.hintColor;
    final startText = DateUtilsX.displayTime(context, c.session.startTime);
    final timeRange =
        '${DateUtilsX.displayTime(context, c.session.startTime)} – ${DateUtilsX.displayTime(context, c.session.endTime)}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left rail: connector line + subject-coloured node.
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                    width: 2,
                    height: 22,
                    color: isFirst ? Colors.transparent : lineColor),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isNow ? color : theme.cardColor,
                    border: Border.all(color: color, width: 3),
                    boxShadow: isNow
                        ? [
                            BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 1)
                          ]
                        : null,
                  ),
                ),
                Expanded(
                  child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : lineColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(18),
                boxShadow: (isNow && theme.brightness == Brightness.light)
                    ? [
                        BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 8))
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showClassSheet(c, date),
                  child: Opacity(
                    opacity: isPast ? 0.7 : 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(c.subject.name,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: onCard),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 8),
                              Text(startText,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: onCard)),
                            ],
                          ),
                          if (isNow) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.3),
                                valueColor: const AlwaysStoppedAnimation(
                                    Colors.white),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('In progress · ${minsLeft}m left',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ] else ...[
                            const SizedBox(height: 5),
                            Text(timeRange,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: subColor)),
                          ],
                          if (hasRoom) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Icon(Icons.meeting_room_outlined,
                                    size: 14, color: subColor),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(room,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: subColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the class editor to modify this class (and its room).
  void _editClass(ScheduledClass c) {
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: 'Edit Session'),
      builder: (_) =>
          EditSessionScreen(subjectId: c.subject.id, session: c.session),
    ));
  }

  /// Deletes a class from the timetable after confirmation.
  Future<void> _deleteClass(ScheduledClass c) async {
    final repo = ref.read(sessionRepositoryProvider);
    if (repo == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this class?'),
        content: Text(
            'Remove "${c.subject.name}" from your timetable? This cannot be '
            'undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.delete(c.subject.id, c.session.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Class deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  Widget _classTileStatic(ScheduledClass c) {
    final theme = Theme.of(context);
    final color = Color(c.subject.colorHex);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.subject.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${DateUtilsX.displayTime(context, c.session.startTime)} – ${DateUtilsX.displayTime(context, c.session.endTime)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- tasks & exams ----------------
  Widget _sectionLabel(String text, Color color) {
    final theme = Theme.of(context);
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

  Widget _examTile(Exam e) {
    final theme = Theme.of(context);
    final byId = ref.watch(subjectsByIdProvider);
    final subject = e.subjectId != null ? byId[e.subjectId] : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => ExamEditorSheet(initial: e),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.15),
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
        ),
      ),
    );
  }
}
