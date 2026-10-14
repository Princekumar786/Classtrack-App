import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../services/error_reporter.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../data/attendance_repository.dart';
import '../../domain/attendance_record.dart';
import '../../domain/pending_marks.dart';

/// Aggregate stats for a single subject, derived from its attended/held counters.
final subjectStatsProvider =
    Provider.family<AttendanceStats, String>((ref, subjectId) {
  final subject = ref.watch(subjectsByIdProvider)[subjectId];
  if (subject == null) return const AttendanceStats();
  return AttendanceStats(
    present: subject.attended,
    absent: subject.missed,
    cancelled: subject.cancelled,
  );
});

/// Overall stats across all subjects.
final overallStatsProvider = Provider<AttendanceStats>((ref) {
  final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
  var total = const AttendanceStats();
  for (final s in subjects) {
    total = total +
        AttendanceStats(
            present: s.attended, absent: s.missed, cancelled: s.cancelled);
  }
  return total;
});

/// Per-date attendance repository bound to the current user (null signed out).
final attendanceRepositoryProvider = Provider<AttendanceRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return AttendanceRepository(db: ref.watch(firestoreProvider), uid: uid);
});

/// Live per-date attendance records for a single subject.
final attendanceForSubjectProvider =
    StreamProvider.family<List<AttendanceRecord>, String>((ref, subjectId) {
  final repo = ref.watch(attendanceRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchForSubject(subjectId);
});

/// Canonical key for one class occurrence on a day: subject + session slot.
String attendanceOccurrenceKey(String subjectId, String slot) =>
    '$subjectId#$slot';

/// Deduped per-date records for a subject, memoized so the (non-trivial)
/// [dedupeAttendanceRecords] pass runs at most ONCE per subject-stream emit and
/// is shared by every consumer (today/weekly/daily aggregators), instead of
/// each of them re-deduping the same records on every rebuild.
final dedupedAttendanceForSubjectProvider =
    Provider.family<List<AttendanceRecord>, String>((ref, subjectId) {
  final records =
      ref.watch(attendanceForSubjectProvider(subjectId)).valueOrNull ??
          const [];
  return dedupeAttendanceRecords(records);
});

/// Given today's session start-times and the slots already marked today,
/// returns the next slot to mark: the first unmarked session; if every session
/// is already marked, the last one (so a re-tap corrects it rather than adding);
/// or '' when nothing is scheduled (a single subject-level record).
String nextAttendanceSlot(List<String> todaySlots, Set<String> markedSlots) {
  for (final s in todaySlots) {
    if (!markedSlots.contains(s)) return s;
  }
  return todaySlots.isEmpty ? '' : todaySlots.last;
}

/// Map of occurrence-key -> the status marked for TODAY (only entries that have
/// a record for today are present). Keyed per session occurrence so a subject
/// that meets twice today can have each class tracked independently. Drives the
/// dashboard so a class marked today disappears from the "to mark" list and
/// stays gone, while a second same-subject class remains until it too is marked.
final todayStatusProvider = Provider<Map<String, AttendanceStatus>>((ref) {
  final todayId = DateUtilsX.dateId(DateTime.now());
  final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
  final map = <String, AttendanceStatus>{};
  for (final s in subjects) {
    final records = ref.watch(dedupedAttendanceForSubjectProvider(s.id));
    for (final r in records) {
      if (r.dateId == todayId && r.status != AttendanceStatus.unmarked) {
        map[attendanceOccurrenceKey(s.id, r.slot)] = r.status;
      }
    }
  }
  return map;
});

/// Attendance recorded over the last 7 days (from per-date records), for the
/// dashboard "This week" insights card.
final weeklyAttendanceProvider = Provider<AttendanceStats>((ref) {
  final now = DateTime.now();
  final weekStart =
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
  final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
  var present = 0, absent = 0, cancelled = 0;
  for (final s in subjects) {
    final records = ref.watch(dedupedAttendanceForSubjectProvider(s.id));
    for (final r in records) {
      if (r.date.isBefore(weekStart)) continue;
      switch (r.status) {
        case AttendanceStatus.present:
          present++;
          break;
        case AttendanceStatus.absent:
          absent++;
          break;
        case AttendanceStatus.cancelled:
          cancelled++;
          break;
        case AttendanceStatus.unmarked:
          break;
      }
    }
  }
  return AttendanceStats(
      present: present, absent: absent, cancelled: cancelled);
});

/// A single day's attendance tally aggregated across every subject.
typedef DayAttendance = ({int present, int absent, int cancelled});

/// Per-day attendance tallies keyed by [DateUtilsX.dateId] ("yyyy-MM-dd"),
/// aggregated across all subjects from their dated records. Powers the month
/// [AttendanceCalendar]. Cancelled classes are tracked separately so they can
/// render as "No class" without affecting the attended percentage.
final dailyAttendanceProvider = Provider<Map<String, DayAttendance>>((ref) {
  final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
  final map = <String, DayAttendance>{};
  for (final s in subjects) {
    final records = ref.watch(dedupedAttendanceForSubjectProvider(s.id));
    for (final r in records) {
      final cur = map[r.dateId] ?? (present: 0, absent: 0, cancelled: 0);
      map[r.dateId] = switch (r.status) {
        AttendanceStatus.present => (
            present: cur.present + 1,
            absent: cur.absent,
            cancelled: cur.cancelled
          ),
        AttendanceStatus.absent => (
            present: cur.present,
            absent: cur.absent + 1,
            cancelled: cur.cancelled
          ),
        AttendanceStatus.cancelled => (
            present: cur.present,
            absent: cur.absent,
            cancelled: cur.cancelled + 1
          ),
        AttendanceStatus.unmarked => cur,
      };
    }
  }
  return map;
});

/// Controller for adjusting attendance — both quick counters (Progress screen)
/// and per-date marking (dashboard / today's classes).
final attendanceControllerProvider = Provider<AttendanceController>((ref) {
  return AttendanceController(
    ref,
    ref.watch(subjectRepositoryProvider),
    ref.watch(attendanceRepositoryProvider),
  );
});

class AttendanceController {
  final Ref _ref;
  final dynamic _repo; // SubjectRepository (nullable)
  final AttendanceRepository? _attendance;
  AttendanceController(this._ref, this._repo, this._attendance);

  /// Marks this client has issued but which the records stream may not have
  /// echoed back yet. See [PendingMarks] for why this is required for the
  /// counter deltas to stay correct under rapid taps.
  final PendingMarks _pending = PendingMarks();

  /// Resolves the status of a specific occurrence from the live, already-loaded
  /// records (no network). Returns null when the records stream hasn't loaded
  /// yet (cold start), letting the repository fall back to a cache read.
  AttendanceStatus? _streamStatus(String subjectId, DateTime date, String slot) {
    final records =
        _ref.read(attendanceForSubjectProvider(subjectId)).valueOrNull;
    if (records == null) return null; // not loaded — repo resolves it
    final dateId = DateUtilsX.dateId(date);
    for (final r in dedupeAttendanceRecords(records)) {
      if (r.dateId == dateId && r.slot == slot) return r.status;
    }
    return AttendanceStatus.unmarked; // loaded, no record ⇒ genuinely unmarked
  }

  /// The occurrence's status accounting for marks issued but not yet confirmed.
  AttendanceStatus? effectiveStatus(
          String subjectId, DateTime date, String slot) =>
      _pending.effectiveStatus(
        subjectId: subjectId,
        dateId: DateUtilsX.dateId(date),
        slot: slot,
        streamStatus: _streamStatus(subjectId, date, slot),
      );

  /// Slots on [date] for [subjectId] already marked by this client but possibly
  /// not yet visible on the records stream. Callers union this into the set they
  /// pass to [nextAttendanceSlot] so consecutive taps advance through a day's
  /// classes instead of all re-targeting the first one.
  Set<String> pendingSlots(String subjectId, DateTime date) =>
      _pending.slotsFor(subjectId, DateUtilsX.dateId(date));

  // --- Quick counter adjustments (no specific date) ---------------------------

  Future<void> markPresent(String subjectId) async =>
      _repo?.adjust(subjectId, attendedDelta: 1);

  Future<void> markAbsent(String subjectId) async =>
      _repo?.adjust(subjectId, absentDelta: 1);

  /// A cancelled class is recorded separately and does not affect the
  /// attendance percentage.
  Future<void> markCancelled(String subjectId) async =>
      _repo?.adjust(subjectId, cancelledDelta: 1);

  Future<void> adjustAttended(String subjectId, int delta) async =>
      _repo?.adjust(subjectId, attendedDelta: delta);

  Future<void> adjustAbsent(String subjectId, int delta) async =>
      _repo?.adjust(subjectId, absentDelta: delta);

  Future<void> setCounts(String subjectId, int attended, int absent,
          {int? cancelled,
          int minAttended = 0,
          int minAbsent = 0,
          int minCancelled = 0}) async =>
      _repo?.setAttendance(subjectId, attended, absent,
          cancelled: cancelled,
          minAttended: minAttended,
          minAbsent: minAbsent,
          minCancelled: minCancelled);

  // --- Per-date marking (writes a dated record + reconciles counters) ---------

  /// Marks one class occurrence and reports SYNCHRONOUSLY whether it changed
  /// anything — `false` means the occurrence was already in [status] and
  /// nothing was written.
  ///
  /// The decision comes from [effectiveStatus] (local intent) rather than from
  /// the network, so it is both instant — callers can confirm without waiting
  /// for connectivity — and safe against repeat taps. The write itself is
  /// fire-and-forget: Firestore applies it to the local cache immediately and
  /// syncs when online.
  bool markOccurrence(
    String subjectId,
    DateTime date,
    String slot,
    AttendanceStatus status,
  ) {
    final attendance = _attendance;
    if (attendance == null) return false;
    final dateId = DateUtilsX.dateId(date);
    final decision = _pending.requestMark(
      subjectId: subjectId,
      dateId: dateId,
      slot: slot,
      streamStatus: _streamStatus(subjectId, date, slot),
      status: status,
    );
    if (!decision.changed) return false;
    ErrorReporter.log('mark attendance: ${status.name}');
    attendance
        .setStatus(
          subjectId: subjectId,
          date: date,
          slot: slot,
          status: status,
          knownOldStatus: decision.previousStatus,
        )
        .catchError((Object e, StackTrace st) {
      _pending.forget(subjectId: subjectId, dateId: dateId, slot: slot);
      // A rejected write means the mark was NOT saved — make it visible.
      ErrorReporter.report(e, st, reason: 'attendance_mark');
    });
    return true;
  }

  /// Mark [subjectId] on [date] with [status]. Pass [AttendanceStatus.unmarked]
  /// to clear the day. Keeps the aggregate percentage in sync.
  Future<void> setForDate(
    String subjectId,
    DateTime date,
    AttendanceStatus status,
  ) async =>
      markOccurrence(subjectId, date, '', status);

  /// Mark a specific class occurrence ([slot] = the session's start time, e.g.
  /// "09:00") on [date]. Idempotent per occurrence, so marking the same class
  /// from any screen — or tapping the same button repeatedly — never
  /// double-counts, while two different sessions of the same subject on the
  /// same day are counted separately.
  Future<void> setForOccurrence(
    String subjectId,
    DateTime date,
    String slot,
    AttendanceStatus status,
  ) async =>
      markOccurrence(subjectId, date, slot, status);
}
