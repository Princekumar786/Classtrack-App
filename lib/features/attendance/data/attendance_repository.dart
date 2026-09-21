import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/firestore_parsing.dart';
import '../domain/attendance_record.dart';

/// CRUD for users/{uid}/subjects/{subjectId}/attendance.
class AttendanceRepository {
  final FirebaseFirestore _db;
  final String uid;

  AttendanceRepository({required FirebaseFirestore db, required this.uid})
      : _db = db;

  CollectionReference<Map<String, dynamic>> _col(String subjectId) => _db
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .collection(AppConstants.subjectsCollection)
      .doc(subjectId)
      .collection(AppConstants.attendanceCollection);

  DocumentReference<Map<String, dynamic>> _subjectRef(String subjectId) => _db
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .collection(AppConstants.subjectsCollection)
      .doc(subjectId);

  Stream<List<AttendanceRecord>> watchForSubject(String subjectId) {
    return _col(subjectId).snapshots().map(
          (snap) => mapDocsSafely(
            snap.docs,
            (d) => AttendanceRecord.fromMap(d.id, subjectId, d.data()),
            context: 'attendance',
          ),
        );
  }

  /// Set the attendance status for [subjectId] on [date] AND keep the subject's
  /// aggregate counters (attended / absent / cancelled) in sync — using an
  /// OFFLINE-SAFE write. Passing [AttendanceStatus.unmarked] clears that day's
  /// record and rolls back its counter contribution. No-op when the status is
  /// unchanged.
  ///
  /// Why not a transaction? `runTransaction` requires a live server round-trip
  /// and does NOT apply to the local cache offline. Students mark attendance
  /// inside classrooms where signal is often poor, so a transaction would
  /// silently fail (the tap "didn't stick") or only commit minutes later when
  /// connectivity returned (marks landing "late"). A [WriteBatch] of plain
  /// writes is applied to the local cache synchronously — the UI updates
  /// instantly — and is flushed to the server automatically once online.
  /// `FieldValue.increment` is commutative, so several marks queued offline
  /// reconcile correctly on sync.
  Future<void> setStatus({
    required String subjectId,
    required DateTime date,
    required AttendanceStatus status,
    String slot = '',
    AttendanceStatus? knownOldStatus,
  }) async {
    final dateId = DateUtilsX.dateId(date);
    // A specific class occurrence gets its own record ("{dateId}__{slot}") so a
    // subject that meets twice in one day can be marked twice. A subject-level
    // mark (slot == '') keeps the legacy doc id == dateId for compatibility.
    final recordId =
        slot.isEmpty ? dateId : '${dateId}__${slot.replaceAll(':', '')}';
    final subjectRef = _subjectRef(subjectId);
    final recordRef = _col(subjectId).doc(recordId);

    // Resolve the PREVIOUS status. Prefer the caller-supplied [knownOldStatus],
    // which comes from the live, already-loaded attendance records (the same
    // local cache the aggregate counters live in) — it is both accurate and
    // instant. Only when the caller doesn't know it (e.g. a cold-start
    // notification mark before the stream has loaded) do we fall back to a
    // cache-first read.
    //
    // Why this matters: the old code ALWAYS did a `Source.cache` read here,
    // which returns "unmarked" on a cache MISS even when a record actually
    // exists (uncached day, fresh cold start). That made the counter delta
    // below non-idempotent — re-marking the same class then re-added its
    // contribution via `FieldValue.increment`, so `attended`/`absent` drifted
    // upward ("the count increases drastically"). Using the known status makes
    // the delta a correct state-transition every time. It also removes an async
    // round-trip before the write, so marks land instantly (no "late" update).
    final oldStatus = knownOldStatus ?? await _readStatus(recordRef);
    if (oldStatus == status) return;

    final delta = attendanceCounterDelta(oldStatus, status);

    final batch = _db.batch();
    if (status == AttendanceStatus.unmarked) {
      batch.delete(recordRef);
    } else {
      final record = AttendanceRecord(
        id: recordId,
        dateId: dateId,
        slot: slot,
        subjectId: subjectId,
        date: DateTime(date.year, date.month, date.day),
        status: status,
        markedAt: DateTime.now(),
      );
      batch.set(recordRef, record.toMap());
    }
    batch.set(
      subjectRef,
      {
        'attended': FieldValue.increment(delta.attended),
        'absent': FieldValue.increment(delta.absent),
        'held': FieldValue.increment(delta.attended + delta.absent),
        'cancelled': FieldValue.increment(delta.cancelled),
      },
      SetOptions(merge: true),
    );

    // Do NOT await server acknowledgement here — the local cache write above is
    // already applied, so callers get an instant, durable result. The returned
    // future still completes/rejects on eventual server sync for error surfacing.
    await batch.commit();
  }

  /// Reads the current status of [recordRef] without forcing a server trip.
  Future<AttendanceStatus> _readStatus(
    DocumentReference<Map<String, dynamic>> recordRef,
  ) async {
    try {
      final cached =
          await recordRef.get(const GetOptions(source: Source.cache));
      if (cached.exists) {
        return AttendanceStatusX.parse(cached.data()?['status'] as String?);
      }
      // Cached "not found" — treat as unmarked (the common new-mark case).
      return AttendanceStatus.unmarked;
    } catch (_) {
      // Not in cache at all. Fall back to a normal get (server when online,
      // cache when offline); any failure is treated as a fresh mark.
      try {
        final snap = await recordRef.get();
        return snap.exists
            ? AttendanceStatusX.parse(snap.data()?['status'] as String?)
            : AttendanceStatus.unmarked;
      } catch (_) {
        return AttendanceStatus.unmarked;
      }
    }
  }

  Future<void> mark({
    required String subjectId,
    required DateTime date,
    required AttendanceStatus status,
  }) async {
    final dateId = DateUtilsX.dateId(date);
    final record = AttendanceRecord(
      dateId: dateId,
      subjectId: subjectId,
      date: DateTime(date.year, date.month, date.day),
      status: status,
      markedAt: DateTime.now(),
    );
    await _col(subjectId).doc(dateId).set(record.toMap());
  }

  Future<void> clear(String subjectId, DateTime date) =>
      _col(subjectId).doc(DateUtilsX.dateId(date)).delete();
}
