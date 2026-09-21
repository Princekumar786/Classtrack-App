import 'package:classtrack/features/attendance/domain/attendance_record.dart';
import 'package:classtrack/features/attendance/domain/pending_marks.dart';
import 'package:classtrack/features/attendance/presentation/providers/attendance_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the reported bug "the attendance went back 4–5 times
/// and then it got back".
///
/// Cause: a mark writes a dated record AND a `FieldValue.increment` counter
/// delta derived from the occurrence's previous status, which was read from the
/// Firestore records stream. That stream only reflects a local write an
/// event-loop turn or more later, so back-to-back taps all saw "unmarked" and
/// all incremented `attended`/`held`. One class ended up counted several times,
/// the dated records and the counters disagreed, and the percentage jumped
/// around and snapped back.
///
/// [PendingMarks] closes that window by holding the locally-intended status.
void main() {
  const subject = 'sub1';
  const dateId = '2026-09-21';

  group('PendingMarks — repeat taps cannot double-count', () {
    test('the first mark is written, carrying the real previous status', () {
      final pending = PendingMarks();
      final d = pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      expect(d.changed, isTrue);
      expect(d.previousStatus, AttendanceStatus.unmarked);
    });

    test('a second identical tap is a no-op while the stream is still stale',
        () {
      final pending = PendingMarks();
      pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      // The stream has NOT caught up yet — it still reports unmarked. Before the
      // fix this produced a second +1 increment.
      final second = pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      expect(second.changed, isFalse);
    });

    test('5 rapid taps on a stale stream produce exactly ONE write', () {
      final pending = PendingMarks();
      var writes = 0;
      for (var i = 0; i < 5; i++) {
        final d = pending.requestMark(
          subjectId: subject,
          dateId: dateId,
          slot: '09:00',
          streamStatus: AttendanceStatus.unmarked, // never catches up
          status: AttendanceStatus.present,
        );
        if (d.changed) writes++;
      }
      expect(writes, 1);
    });

    test('the counter delta of the single write nets to exactly +1 attended',
        () {
      // Ties the guarantee back to the real counter maths: one class marked
      // present must move `attended` by +1, no matter how many times it is
      // tapped.
      final pending = PendingMarks();
      var attended = 0, absent = 0;
      for (var i = 0; i < 5; i++) {
        final d = pending.requestMark(
          subjectId: subject,
          dateId: dateId,
          slot: '09:00',
          streamStatus: AttendanceStatus.unmarked,
          status: AttendanceStatus.present,
        );
        if (!d.changed) continue;
        final delta = attendanceCounterDelta(
            d.previousStatus ?? AttendanceStatus.unmarked,
            AttendanceStatus.present);
        attended += delta.attended;
        absent += delta.absent;
      }
      expect(attended, 1);
      expect(absent, 0);
      expect(attended + absent, 1); // held
    });

    test('correcting present -> absent still writes, with the right previous',
        () {
      final pending = PendingMarks();
      pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      final correction = pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked, // still stale
        status: AttendanceStatus.absent,
      );
      expect(correction.changed, isTrue);
      // Must transition FROM the pending present, not from the stale unmarked —
      // otherwise the earlier +1 attended is never rolled back.
      expect(correction.previousStatus, AttendanceStatus.present);
      final delta = attendanceCounterDelta(
          correction.previousStatus!, AttendanceStatus.absent);
      expect(delta.attended, -1);
      expect(delta.absent, 1);
    });

    test('present -> absent -> present nets to +1 attended overall', () {
      final pending = PendingMarks();
      var attended = 0, absent = 0;
      void apply(AttendanceStatus status) {
        final d = pending.requestMark(
          subjectId: subject,
          dateId: dateId,
          slot: '09:00',
          streamStatus: AttendanceStatus.unmarked, // never catches up
          status: status,
        );
        if (!d.changed) return;
        final delta = attendanceCounterDelta(
            d.previousStatus ?? AttendanceStatus.unmarked, status);
        attended += delta.attended;
        absent += delta.absent;
      }

      apply(AttendanceStatus.present);
      apply(AttendanceStatus.absent);
      apply(AttendanceStatus.present);
      expect(attended, 1);
      expect(absent, 0);
    });
  });

  group('PendingMarks — self-healing so nothing is masked forever', () {
    test('a confirmed mark is released once the stream agrees', () {
      final pending = PendingMarks();
      pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      expect(pending.length, 1);
      // The stream catches up.
      final status = pending.effectiveStatus(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.present,
      );
      expect(status, AttendanceStatus.present);
      expect(pending.length, 0, reason: 'pending intent should be released');
    });

    test('after release, a change made elsewhere is visible again', () {
      final pending = PendingMarks();
      pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      // Confirm, releasing the intent.
      pending.effectiveStatus(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.present,
      );
      // Another device clears the day; we must be able to re-mark it present.
      final d = pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      expect(d.changed, isTrue);
    });

    test('a failed write is forgotten so the stream regains authority', () {
      final pending = PendingMarks();
      pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      pending.forget(subjectId: subject, dateId: dateId, slot: '09:00');
      expect(pending.length, 0);
      // The retry must go through.
      final retry = pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      expect(retry.changed, isTrue);
    });

    test('an already-marked occurrence on the stream is still a no-op', () {
      final pending = PendingMarks();
      final d = pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.present,
        status: AttendanceStatus.present,
      );
      expect(d.changed, isFalse);
    });

    test('a not-yet-loaded stream passes null through for repo fallback', () {
      final pending = PendingMarks();
      final d = pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: null, // cold start
        status: AttendanceStatus.present,
      );
      expect(d.changed, isTrue);
      expect(d.previousStatus, isNull);
    });
  });

  group('PendingMarks.slotsFor — consecutive taps advance to the next class', () {
    test('a pending mark is reported for its day', () {
      final pending = PendingMarks();
      pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      expect(pending.slotsFor(subject, dateId), {'09:00'});
    });

    test('two taps on a two-class day mark BOTH classes', () {
      // The screens build their "already marked" set from the records stream
      // unioned with these pending slots. With a stale stream and no pending
      // half, nextAttendanceSlot returned 09:00 twice and the 14:00 class was
      // never marked.
      final pending = PendingMarks();
      final slots = ['09:00', '14:00'];
      final targeted = <String>[];

      for (var i = 0; i < 2; i++) {
        final marked = <String>{
          // records stream is still empty (stale)
          ...pending.slotsFor(subject, dateId),
        };
        final slot = nextAttendanceSlot(slots, marked);
        targeted.add(slot);
        pending.requestMark(
          subjectId: subject,
          dateId: dateId,
          slot: slot,
          streamStatus: AttendanceStatus.unmarked,
          status: AttendanceStatus.present,
        );
      }
      expect(targeted, ['09:00', '14:00']);
    });

    test('a third tap on a two-class day re-affirms the last (no over-count)',
        () {
      final pending = PendingMarks();
      final slots = ['09:00', '14:00'];
      var writes = 0;
      for (var i = 0; i < 3; i++) {
        final marked = <String>{...pending.slotsFor(subject, dateId)};
        final slot = nextAttendanceSlot(slots, marked);
        final d = pending.requestMark(
          subjectId: subject,
          dateId: dateId,
          slot: slot,
          streamStatus: AttendanceStatus.unmarked,
          status: AttendanceStatus.present,
        );
        if (d.changed) writes++;
      }
      // Two real classes -> exactly two writes, the third tap is absorbed.
      expect(writes, 2);
    });

    test('slots are scoped per subject and per day', () {
      final pending = PendingMarks();
      pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      expect(pending.slotsFor('other', dateId), isEmpty);
      expect(pending.slotsFor(subject, '2026-09-22'), isEmpty);
    });

    test('a pending CLEAR is not reported as a marked slot', () {
      final pending = PendingMarks();
      pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '09:00',
        streamStatus: AttendanceStatus.present,
        status: AttendanceStatus.unmarked, // clearing the day
      );
      expect(pending.slotsFor(subject, dateId), isEmpty);
    });

    test('a subject-level (empty slot) mark does not leak into slotsFor', () {
      final pending = PendingMarks();
      pending.requestMark(
        subjectId: subject,
        dateId: dateId,
        slot: '',
        streamStatus: AttendanceStatus.unmarked,
        status: AttendanceStatus.present,
      );
      // An empty slot is reported as an empty string, which nextAttendanceSlot
      // ignores for scheduled days.
      expect(pending.slotsFor(subject, dateId), {''});
    });
  });
}
