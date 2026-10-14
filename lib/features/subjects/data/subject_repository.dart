import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/firestore_parsing.dart';
import '../domain/subject.dart';

/// Narrows [delta] so applying it to a counter currently at [current] can never
/// push it below zero. Pure so the "counters never go negative" guarantee stays
/// unit-testable now that [SubjectRepository.adjust] writes increments (which
/// cannot clamp themselves) instead of absolute totals.
int clampCounterDelta(int delta, int current) =>
    delta < -current ? -current : delta;

/// CRUD for users/{uid}/subjects.
class SubjectRepository {
  final FirebaseFirestore _db;
  final String uid;

  SubjectRepository({required FirebaseFirestore db, required this.uid})
      : _db = db;

  CollectionReference<Map<String, dynamic>> get _col => _db
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .collection(AppConstants.subjectsCollection);

  /// Current-semester subjects only (archived ones are hidden).
  Stream<List<Subject>> watchSubjects() => watchAllSubjects()
      .map((list) => list.where((s) => s.semesterId == null).toList());

  /// Every subject, including archived semesters.
  Stream<List<Subject>> watchAllSubjects() {
    return _col.orderBy('name').snapshots().map(
          (snap) =>
              parseDocsSafely(snap.docs, Subject.fromMap, context: 'subjects'),
        );
  }

  Stream<Subject?> watchSubject(String id) {
    return _col.doc(id).snapshots().map(
          (snap) => snap.exists ? Subject.fromMap(snap.id, snap.data()!) : null,
        );
  }

  Future<String> create(Subject subject) async {
    final ref = await _col.add(subject.toMap());
    return ref.id;
  }

  /// One-shot read of the current semester's subjects (used by import to reuse
  /// existing subjects instead of creating duplicates on re-import). Archived
  /// subjects are skipped so a new semester's "Mathematics" becomes a fresh
  /// subject instead of inheriting last semester's attendance.
  Future<List<Subject>> getAll({bool includeArchived = false}) async {
    final snap = await _col.get();
    final list =
        parseDocsSafely(snap.docs, Subject.fromMap, context: 'subjects');
    return includeArchived
        ? list
        : list.where((s) => s.semesterId == null).toList();
  }

  /// Create with a known id (used by AI import batch writes).
  Future<void> setWithId(String id, Subject subject) =>
      _col.doc(id).set(subject.toMap());

  /// Saves a subject's EDITABLE details (name, colour, links, term, target…).
  ///
  /// Never writes the attendance counters: those only change through
  /// increments ([adjust], `AttendanceRepository.setStatus`) or the manual
  /// counts editor ([setAttendance]). Writing the counters snapshotted when an
  /// edit screen opened used to silently undo any mark made meanwhile (e.g.
  /// from a notification or another device) — a lost update.
  Future<void> update(Subject subject) => _col
      .doc(subject.id)
      .set(subjectDetailsMap(subject), SetOptions(merge: true));

  /// Adjust attendance counters safely (never below 0). Only present/absent
  /// count toward the percentage; cancelled is tracked separately.
  ///
  /// Offline-safe: a `runTransaction` here would need a live server connection
  /// and silently fail to apply while offline (the reason quick Present/Absent
  /// taps sometimes "didn't register" or landed late).
  ///
  /// Uses `FieldValue.increment` rather than writing absolute totals. Writing
  /// absolute values here was a LOST-UPDATE bug: the dated mark path
  /// ([AttendanceRepository.setStatus]) also adjusts these counters via
  /// increments, so a stepper adjustment that read the counters before a mark's
  /// increment was visible would write back a total that silently discarded it —
  /// the attendance number appeared to jump back to an older value. Increments
  /// from both paths are commutative, so they compose correctly instead.
  ///
  /// The cache-first read is still used, but only to CLAMP the delta so a
  /// counter can never be driven below zero (an increment alone cannot express
  /// "subtract, but stop at 0").
  Future<void> adjust(String id,
      {int attendedDelta = 0,
      int absentDelta = 0,
      int cancelledDelta = 0}) async {
    final ref = _col.doc(id);
    final data = await _readCounters(ref);
    final curAttended = (data['attended'] as num?)?.toInt() ?? 0;
    // Migrate legacy docs that only stored 'held'.
    final curAbsent = (data['absent'] as num?)?.toInt() ??
        (((data['held'] as num?)?.toInt() ?? curAttended) - curAttended)
            .clamp(0, 100000);
    final curCancelled = (data['cancelled'] as num?)?.toInt() ?? 0;

    // Never let a decrement take a counter below 0.
    final attended = clampCounterDelta(attendedDelta, curAttended);
    final absent = clampCounterDelta(absentDelta, curAbsent);
    final cancelled = clampCounterDelta(cancelledDelta, curCancelled);

    if (attended == 0 && absent == 0 && cancelled == 0) return;

    await ref.set(
        {
          'attended': FieldValue.increment(attended),
          'absent': FieldValue.increment(absent),
          // held is always attended + absent.
          'held': FieldValue.increment(attended + absent),
          'cancelled': FieldValue.increment(cancelled),
        },
        SetOptions(merge: true));
  }

  /// Reads a subject's counter map without forcing a server round-trip. The
  /// subject doc is almost always already cached (it is live-streamed by
  /// [watchSubjects]), so this resolves instantly even offline.
  Future<Map<String, dynamic>> _readCounters(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      return cached.data() ?? <String, dynamic>{};
    } catch (_) {
      try {
        return (await ref.get()).data() ?? <String, dynamic>{};
      } catch (_) {
        return <String, dynamic>{};
      }
    }
  }

  /// Directly set the counters (from the manual "tune" edit dialog).
  ///
  /// DRIFT GUARD: the subject counters drive the attendance percentage while
  /// the dated attendance records drive the calendar. If the manual editor
  /// wrote an absolute total BELOW what the dated records already contribute,
  /// the two sources would contradict each other (e.g. "2 present" overall but
  /// 5 days marked present on the calendar). We therefore clamp each counter to
  /// its dated-records contribution ([minAttended]/[minAbsent]/[minCancelled],
  /// passed in by the caller which has the deduped records) so the stored total
  /// is ALWAYS >= the sum of dated marks — the two views can never drift apart.
  /// The portion above the dated contribution is persisted as an explicit
  /// `manual*` baseline (classes not tracked day-by-day) for transparency.
  Future<void> setAttendance(String id, int attended, int absent,
      {int? cancelled,
      int minAttended = 0,
      int minAbsent = 0,
      int minCancelled = 0}) {
    final floorA = minAttended < 0 ? 0 : minAttended;
    final floorB = minAbsent < 0 ? 0 : minAbsent;
    final a = attended < floorA ? floorA : attended;
    final b = absent < floorB ? floorB : absent;
    final map = <String, dynamic>{
      'attended': a,
      'absent': b,
      'held': a + b,
      'manualAttended': a - floorA,
      'manualAbsent': b - floorB,
    };
    if (cancelled != null) {
      final floorC = minCancelled < 0 ? 0 : minCancelled;
      final c = cancelled < floorC ? floorC : cancelled;
      map['cancelled'] = c;
      map['manualCancelled'] = c - floorC;
    }
    return _col.doc(id).set(map, SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    // Keep the student's marks and exams: unlink them from the subject so they
    // show under "Other grades" / "No subject" instead of silently vanishing
    // (they used to stay in the database pointing at a deleted subject, which
    // hid them from every screen and from the GPA).
    final user = _db.collection(AppConstants.usersCollection).doc(uid);
    for (final name in const ['grades', 'exams']) {
      final linked =
          await user.collection(name).where('subjectId', isEqualTo: id).get();
      for (final d in linked.docs) {
        await d.reference.update({'subjectId': null});
      }
    }
    // Delete nested sessions + attendance first.
    final sessions =
        await _col.doc(id).collection(AppConstants.sessionsCollection).get();
    for (final s in sessions.docs) {
      await s.reference.delete();
    }
    final attendance =
        await _col.doc(id).collection(AppConstants.attendanceCollection).get();
    for (final a in attendance.docs) {
      await a.reference.delete();
    }
    await _col.doc(id).delete();
  }

  String newId() => _col.doc().id;
}


/// The subject fields a details edit may write: [Subject.toMap] minus the
/// attendance counters and `createdAt`. Pure — unit tested.
Map<String, dynamic> subjectDetailsMap(Subject subject) {
  const counterKeys = {'attended', 'absent', 'held', 'cancelled', 'createdAt'};
  return Map<String, dynamic>.from(subject.toMap())
    ..removeWhere((k, _) => counterKeys.contains(k));
}
