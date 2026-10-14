import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../services/gemini_service.dart';
import '../../../services/google_calendar_service.dart';
import '../../schedule/data/session_repository.dart';
import '../../schedule/domain/class_session.dart';
import '../../subjects/data/subject_repository.dart';
import '../../subjects/domain/subject.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/domain/task_item.dart';
import '../domain/calendar_event_mapper.dart';
import '../domain/google_calendar_mapper.dart';
import '../domain/google_tasks_mapper.dart';
import '../domain/parsed_schedule.dart';

/// Result of committing an import: how many of each kind were newly created
/// (existing/duplicate items are skipped, so re-importing is safe).
class ImportResult {
  final int subjects;
  final int sessions;
  final int tasks;
  const ImportResult({this.subjects = 0, this.sessions = 0, this.tasks = 0});

  int get total => subjects + sessions + tasks;
}

/// Parses timetables via client-side Gemini and commits confirmed results.
class ImportRepository {
  final GeminiService _gemini;
  final GoogleCalendarService _calendar;
  final SubjectRepository _subjectRepo;
  final SessionRepository _sessionRepo;
  final TaskRepository _taskRepo;

  ImportRepository({
    required GeminiService gemini,
    required GoogleCalendarService calendar,
    required SubjectRepository subjectRepo,
    required SessionRepository sessionRepo,
    required TaskRepository taskRepo,
  })  : _gemini = gemini,
        _calendar = calendar,
        _subjectRepo = subjectRepo,
        _sessionRepo = sessionRepo,
        _taskRepo = taskRepo;

  bool get isConfigured => _gemini.isConfigured;

  Future<ParsedSchedule> parseText(String text) =>
      _gemini.parseSchedule(text: text);

  Future<ParsedSchedule> parseImage(Uint8List bytes) =>
      _gemini.parseSchedule(imageBytes: bytes);

  Future<ParsedSchedule> parsePdf(Uint8List bytes) =>
      _gemini.parseSchedule(pdfBytes: bytes);

  /// Signs the user into Google (read-only calendar scope) and turns their
  /// upcoming events into a reviewable schedule. No AI/Gemini needed.
  Future<ParsedSchedule> parseGoogleCalendar() async {
    final events = await _calendar.fetchUpcomingEvents();
    return googleCalendarToSchedule(events);
  }

  /// Signs the user into Google (read-only calendar scope) and turns EVERY
  /// upcoming calendar event into an `event`-type task item. This is what the
  /// "Google Calendar" import brings into the Tasks list.
  ///
  /// Pass [interactive] `false` for the background auto-sync so it reuses the
  /// existing session/scopes and never pops a sign-in dialog.
  Future<List<CalendarEventTask>> parseGoogleCalendarEvents({
    bool interactive = true,
  }) async {
    final events = await _calendar.fetchUpcomingEvents(interactive: interactive);
    return googleCalendarToEventTasks(events);
  }

  /// Fetches the user's Google **Tasks** (to-dos) and maps them into plain
  /// task items. Best-effort: returns an empty list if the Tasks scope/API
  /// isn't available, so calendar import is never blocked.
  Future<List<GoogleTaskItem>> parseGoogleTasks({bool interactive = true}) async {
    final tasks = await _calendar.fetchTasks(interactive: interactive);
    return googleTasksToItems(tasks);
  }

  /// Runs the daily background sync: silently (no dialogs) fetches the user's
  /// recent/upcoming calendar events and Google Tasks and commits the ones not
  /// already saved. De-duplication (by source id, then title + date/time) means
  /// running this every day never creates duplicates. Returns the number of
  /// newly-added items via [ImportResult]. A user who isn't currently signed in
  /// to Google (or hasn't granted the scopes) yields an empty result instead of
  /// an interactive prompt.
  Future<ImportResult> autoSyncGoogle() async {
    List<CalendarEventTask> events;
    try {
      events = await parseGoogleCalendarEvents(interactive: false);
    } on GoogleCalendarCancelled {
      // No silent session / scopes -> nothing to sync, no UI. Bail quietly.
      return const ImportResult();
    }
    final tasks = await parseGoogleTasks(interactive: false);
    if (events.isEmpty && tasks.isEmpty) return const ImportResult();
    return commitGoogleImport(events: events, tasks: tasks);
  }

  /// Imports both calendar events (as `event` tasks) and Google Tasks (as
  /// `task` items) in a single pass, de-duplicating against what's already
  /// saved — and against each other — so re-running never creates duplicates.
  Future<ImportResult> commitGoogleImport({
    required List<CalendarEventTask> events,
    required List<GoogleTaskItem> tasks,
  }) async {
    final existing = await _taskRepo.getAll();

    final freshEvents = filterNewEventTasks(events, existing);
    // De-dup tasks against existing items AND the events we're about to add,
    // so an event and a task describing the same thing don't both land.
    final withEvents = <TaskItem>[
      ...existing,
      for (final e in freshEvents)
        TaskItem(id: '', title: e.title, dueDate: e.due, sourceId: e.sourceId),
    ];
    final freshTasks = filterNewGoogleTasks(tasks, withEvents);

    for (final e in freshEvents) {
      final location = e.location?.trim();
      final link = e.link?.trim();
      await _taskRepo.add(TaskItem(
        id: '',
        title: e.title.trim(),
        note: (location == null || location.isEmpty) ? null : location,
        dueDate: e.due,
        type: TaskType.event,
        link: (link == null || link.isEmpty) ? null : link,
        sourceId: (e.sourceId == null || e.sourceId!.trim().isEmpty)
            ? null
            : e.sourceId!.trim(),
      ));
    }
    for (final t in freshTasks) {
      final note = t.note?.trim();
      final link = t.link?.trim();
      await _taskRepo.add(TaskItem(
        id: '',
        title: t.title.trim(),
        note: (note == null || note.isEmpty) ? null : note,
        dueDate: t.due,
        done: t.done,
        type: TaskType.task,
        link: (link == null || link.isEmpty) ? null : link,
        sourceId: (t.sourceId == null || t.sourceId!.trim().isEmpty)
            ? null
            : t.sourceId!.trim(),
      ));
    }

    return ImportResult(tasks: freshEvents.length + freshTasks.length);
  }

  /// Saves calendar events as `event`-type tasks, skipping any that were
  /// already imported. Re-running is safe: an event is matched first by its
  /// calendar source id, then (for items created by hand or by an older import
  /// that lacked a source id) by title + due date + time, so a second import
  /// never piles up duplicates.
  Future<ImportResult> commitEventTasks(List<CalendarEventTask> events) async {
    final existing = await _taskRepo.getAll();
    final fresh = filterNewEventTasks(events, existing);

    for (final e in fresh) {
      final location = e.location?.trim();
      final link = e.link?.trim();
      await _taskRepo.add(TaskItem(
        id: '',
        title: e.title.trim(),
        note: (location == null || location.isEmpty) ? null : location,
        dueDate: e.due,
        type: TaskType.event,
        link: (link == null || link.isEmpty) ? null : link,
        sourceId: (e.sourceId == null || e.sourceId!.trim().isEmpty)
            ? null
            : e.sourceId!.trim(),
      ));
    }

    return ImportResult(tasks: fresh.length);
  }

  /// Pure de-dup: returns the subset of [incoming] events that are NOT already
  /// represented in [existing]. An event is considered already-imported when
  /// its calendar source id matches an existing item's, or (for items created
  /// by hand / by an older import without a source id) when its title + due
  /// date + time-of-day matches. De-dups within [incoming] too, so a single
  /// call never returns two copies of the same event.
  static List<CalendarEventTask> filterNewEventTasks(
    List<CalendarEventTask> incoming,
    List<TaskItem> existing,
  ) {
    final sourceIds = <String>{
      for (final t in existing)
        if (t.sourceId != null && t.sourceId!.trim().isNotEmpty)
          t.sourceId!.trim(),
    };
    final keys = <String>{
      for (final t in existing) _eventKey(t.title, t.dueDate),
    };

    final fresh = <CalendarEventTask>[];
    for (final e in incoming) {
      final title = e.title.trim();
      if (title.isEmpty) continue;
      final sid = (e.sourceId ?? '').trim();
      final key = _eventKey(title, e.due);

      final isDuplicate =
          (sid.isNotEmpty && sourceIds.contains(sid)) || keys.contains(key);
      if (isDuplicate) continue;

      if (sid.isNotEmpty) sourceIds.add(sid);
      keys.add(key);
      fresh.add(e);
    }
    return fresh;
  }

  /// Pure de-dup for Google Tasks, mirroring [filterNewEventTasks]: skips a
  /// task already present by its Google Task id, or by title + due date.
  static List<GoogleTaskItem> filterNewGoogleTasks(
    List<GoogleTaskItem> incoming,
    List<TaskItem> existing,
  ) {
    final sourceIds = <String>{
      for (final t in existing)
        if (t.sourceId != null && t.sourceId!.trim().isNotEmpty)
          t.sourceId!.trim(),
    };
    final keys = <String>{
      for (final t in existing) _eventKey(t.title, t.dueDate),
    };

    final fresh = <GoogleTaskItem>[];
    for (final t in incoming) {
      final title = t.title.trim();
      if (title.isEmpty) continue;
      final sid = (t.sourceId ?? '').trim();
      final key = _eventKey(title, t.due);

      final isDuplicate =
          (sid.isNotEmpty && sourceIds.contains(sid)) || keys.contains(key);
      if (isDuplicate) continue;

      if (sid.isNotEmpty) sourceIds.add(sid);
      keys.add(key);
      fresh.add(t);
    }
    return fresh;
  }

  /// Commit the reviewed schedule: create subjects + their sessions, and route
  /// assignment-like items to the Tasks list.
  ///
  /// Idempotent: an existing subject (matched by name, case-insensitive) is
  /// reused rather than duplicated, identical sessions are skipped (by content
  /// signature), and a task with the same title + due date is not re-added.
  /// This makes re-running the import safe instead of piling up duplicates.
  Future<ImportResult> commit(ParsedSchedule schedule) async {
    // Snapshot existing data once so re-import de-duplicates.
    final existingSubjects = await _subjectRepo.getAll();
    final byName = <String, Subject>{
      for (final s in existingSubjects) s.name.trim().toLowerCase(): s,
    };
    final existingTasks = await _taskRepo.getAll();
    final taskKeys = <String>{
      for (final t in existingTasks) _taskKey(t.title, t.dueDate),
    };

    var createdSubjects = 0, createdSessions = 0, createdTasks = 0;
    var colorIndex = existingSubjects.length;

    for (final ps in schedule.subjects) {
      if (!ps.include) continue;
      final name = ps.name.trim().isEmpty ? 'Untitled' : ps.name.trim();
      final key = name.toLowerCase();

      String subjectId;
      final existing = byName[key];
      if (existing != null) {
        subjectId = existing.id;
        // Backfill a class link onto an existing subject that doesn't have one
        // yet, so a Meet/Zoom/resource URL from the calendar shows up in the
        // subject's "Quick links" instead of being dropped on re-import.
        final incomingLink = ps.classLink?.trim();
        if (incomingLink != null &&
            incomingLink.isNotEmpty &&
            (existing.classLink == null || existing.classLink!.trim().isEmpty)) {
          final updated = existing.copyWith(classLink: incomingLink);
          // Details-only merge: a full set() here would overwrite the
          // subject's live attendance counters and manual baselines.
          await _subjectRepo.update(updated);
          byName[key] = updated;
        }
      } else {
        final color = AppColors
            .subjectPalette[colorIndex % AppColors.subjectPalette.length];
        colorIndex++;
        subjectId = _subjectRepo.newId();
        final subject = Subject(
          id: subjectId,
          name: name,
          colorHex: color.toARGB32(),
          professor:
              ps.professor?.trim().isEmpty == true ? null : ps.professor,
          classLink: ps.classLink?.trim().isEmpty == true
              ? null
              : ps.classLink?.trim(),
          startDate: ps.startDate,
          endDate: ps.endDate,
        );
        await _subjectRepo.setWithId(subjectId, subject);
        byName[key] = subject;
        createdSubjects++;
      }

      // Skip identical sessions that already exist for this subject.
      final existingSessions = await _sessionRepo.getForSubject(subjectId);
      final seenSig = <String>{for (final s in existingSessions) s.signature};

      for (final sess in ps.sessions) {
        final id = const Uuid().v4();
        final session = ClassSession(
          id: id,
          subjectId: subjectId,
          recurring: sess.isRecurring,
          dayOfWeek: sess.isRecurring ? (sess.dayIndex ?? 0) : null,
          specificDate: sess.date,
          startTime: sess.start,
          endTime: sess.end,
          room: sess.room,
        );
        if (seenSig.contains(session.signature)) continue;
        await _sessionRepo.setWithId(subjectId, id, session);
        seenSig.add(session.signature);
        createdSessions++;
      }
    }

    // Route assignment-like one-off events to the Tasks list.
    for (final pt in schedule.tasks) {
      if (!pt.include) continue;
      final title = pt.title.trim();
      if (title.isEmpty) continue;
      final k = _taskKey(title, pt.due);
      if (taskKeys.contains(k)) continue;
      taskKeys.add(k);
      await _taskRepo.add(TaskItem(
        id: '',
        title: title,
        dueDate: pt.due,
        link: pt.link?.trim().isEmpty == true ? null : pt.link?.trim(),
      ));
      createdTasks++;
    }

    return ImportResult(
      subjects: createdSubjects,
      sessions: createdSessions,
      tasks: createdTasks,
    );
  }

  /// De-dup key for a task: title (case-insensitive) + due date (day only).
  static String _taskKey(String title, DateTime? due) {
    final d = due == null ? '' : DateUtilsX.dateId(due);
    return '${title.trim().toLowerCase()}|$d';
  }

  /// De-dup key for a calendar event task: title + due date + time-of-day.
  /// Includes the time so two same-named events on the same day at different
  /// times (e.g. a 10:00 lecture and a 14:00 lab) are kept as separate items,
  /// while a re-import of the exact same event is recognised as a duplicate.
  static String _eventKey(String title, DateTime? due) {
    if (due == null) return '${title.trim().toLowerCase()}|';
    final hasTime = !(due.hour == 0 && due.minute == 0);
    final t = hasTime
        ? '${due.hour.toString().padLeft(2, '0')}:'
            '${due.minute.toString().padLeft(2, '0')}'
        : '';
    return '${title.trim().toLowerCase()}|${DateUtilsX.dateId(due)}|$t';
  }
}
