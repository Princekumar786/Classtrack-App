import 'package:classtrack/features/subjects/data/subject_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// [SubjectRepository.adjust] now writes `FieldValue.increment` deltas instead
/// of absolute totals, so that a stepper adjustment can no longer discard a
/// dated mark's increment that hadn't become visible yet (which showed up as the
/// attendance number jumping back to an older value).
///
/// An increment cannot clamp itself, so the delta is narrowed up-front by
/// [clampCounterDelta]. These tests pin the "counters never go negative"
/// guarantee that the old read-modify-write code provided.
void main() {
  group('clampCounterDelta', () {
    test('a positive delta is never altered', () {
      expect(clampCounterDelta(1, 0), 1);
      expect(clampCounterDelta(5, 3), 5);
      expect(clampCounterDelta(1, 100), 1);
    });

    test('zero stays zero', () {
      expect(clampCounterDelta(0, 0), 0);
      expect(clampCounterDelta(0, 7), 0);
    });

    test('a decrement within range is kept in full', () {
      expect(clampCounterDelta(-1, 5), -1);
      expect(clampCounterDelta(-5, 5), -5);
    });

    test('a decrement past zero is narrowed to land exactly on zero', () {
      expect(clampCounterDelta(-1, 0), 0);
      expect(clampCounterDelta(-3, 1), -1);
      expect(clampCounterDelta(-10, 2), -2);
    });

    test('applying the clamped delta never yields a negative counter', () {
      for (var current = 0; current <= 5; current++) {
        for (var delta = -8; delta <= 8; delta++) {
          final result = current + clampCounterDelta(delta, current);
          expect(result, greaterThanOrEqualTo(0),
              reason: 'current=$current delta=$delta');
        }
      }
    });

    test('a decrement from zero is a no-op, so no write is needed', () {
      // adjust() skips the write entirely when every clamped delta is 0.
      expect(clampCounterDelta(-1, 0), 0);
      expect(clampCounterDelta(-1, 0) == 0, isTrue);
    });
  });
}
