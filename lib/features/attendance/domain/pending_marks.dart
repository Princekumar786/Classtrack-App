import 'attendance_record.dart';

/// What to do about a single mark request.
class MarkDecision {
  /// False when the occurrence is already in the requested status, so nothing
  /// should be written and no confirmation should be shown.
  final bool changed;

  /// The status the occurrence is moving FROM, to be handed to
  /// `AttendanceRepository.setStatus` as `knownOldStatus` so it can compute an
  /// exact counter delta. Null means "not known locally" — the repository falls
  /// back to a cache read.
  final AttendanceStatus? previousStatus;

  const MarkDecision({required this.changed, this.previousStatus});

  static const MarkDecision unchanged = MarkDecision(changed: false);
}

/// Tracks attendance marks this client has issued but not yet seen echoed back
/// by the Firestore records stream.
///
/// ## The bug this fixes
/// A mark is persisted as a dated record PLUS a `FieldValue.increment` delta on
/// the subject's `attended`/`absent`/`held` counters. The delta is derived from
/// the occurrence's previous status, which was read from the live records
/// stream. A Firestore local write only reaches that stream one or more
/// event-loop turns later, so two taps in quick succession both observed
/// "unmarked" and both applied `+1` — a single class counted two, four or five
/// times. The dated records deduplicate to one entry while the counters do not,
/// so the two sources disagree and the displayed percentage jumps around (and
/// snaps back whenever something rewrites the counters from the records).
///
/// Holding the locally-intended status makes the second tap a genuine no-op, so
/// the counters can never run ahead of the dated records.
///
/// Pure and framework-free so the ordering guarantees are unit-testable.
class PendingMarks {
  final Map<String, AttendanceStatus> _pending = <String, AttendanceStatus>{};

  static String keyFor(String subjectId, String dateId, String slot) =>
      '$subjectId|$dateId|$slot';

  /// Number of outstanding (unconfirmed) marks — for tests/diagnostics.
  int get length => _pending.length;

  /// The occurrence's status accounting for marks not yet echoed back.
  ///
  /// Self-healing: when [streamStatus] agrees with the pending intent the entry
  /// is dropped, so a later change made elsewhere (another device, the manual
  /// counts editor) is never masked indefinitely.
  AttendanceStatus? effectiveStatus({
    required String subjectId,
    required String dateId,
    required String slot,
    required AttendanceStatus? streamStatus,
  }) {
    final key = keyFor(subjectId, dateId, slot);
    final pending = _pending[key];
    if (pending == null) return streamStatus;
    if (streamStatus == pending) {
      _pending.remove(key); // confirmed — the stream is authoritative again
      return streamStatus;
    }
    return pending;
  }

  /// Decides whether a mark needs writing and records the intent if so.
  ///
  /// The intent is stored BEFORE the caller issues its (asynchronous) write, so
  /// another tap landing in the same event-loop turn observes it and is
  /// correctly rejected as a no-op.
  MarkDecision requestMark({
    required String subjectId,
    required String dateId,
    required String slot,
    required AttendanceStatus? streamStatus,
    required AttendanceStatus status,
  }) {
    final previous = effectiveStatus(
      subjectId: subjectId,
      dateId: dateId,
      slot: slot,
      streamStatus: streamStatus,
    );
    if (previous == status) return MarkDecision.unchanged;
    _pending[keyFor(subjectId, dateId, slot)] = status;
    return MarkDecision(changed: true, previousStatus: previous);
  }

  /// Drops a recorded intent because its write failed, letting the records
  /// stream become authoritative again rather than masking the real status.
  void forget({
    required String subjectId,
    required String dateId,
    required String slot,
  }) =>
      _pending.remove(keyFor(subjectId, dateId, slot));

  /// Slots on [dateId] for [subjectId] that have been marked (to anything other
  /// than "unmarked") but may not be visible on the records stream yet.
  ///
  /// Callers union this into the "already marked" set they pass to
  /// `nextAttendanceSlot`. Without the pending half, two quick taps on a day
  /// with two classes both saw an empty set and re-targeted the FIRST class,
  /// so the second class stayed unmarked while the first was written twice.
  Set<String> slotsFor(String subjectId, String dateId) {
    final prefix = '$subjectId|$dateId|';
    return <String>{
      for (final entry in _pending.entries)
        if (entry.key.startsWith(prefix) &&
            entry.value != AttendanceStatus.unmarked)
          entry.key.substring(prefix.length),
    };
  }
}
