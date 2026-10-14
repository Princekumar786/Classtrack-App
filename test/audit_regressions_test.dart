import 'package:flutter_test/flutter_test.dart';

import 'package:classtrack/features/semesters/domain/semester.dart';
import 'package:classtrack/features/subjects/data/subject_repository.dart';
import 'package:classtrack/features/subjects/domain/subject.dart';

/// Regression tests for bugs found in the full-app audit (2026-10-14).
void main() {
  test('editing a subject never writes attendance counters (lost update)', () {
    final m = subjectDetailsMap(const Subject(
        id: 's', name: 'DBMS', colorHex: 0xFF000000, attended: 9, absent: 2));
    expect(m['name'], 'DBMS');
    for (final k in ['attended', 'absent', 'held', 'cancelled', 'createdAt']) {
      expect(m.containsKey(k), isFalse, reason: k);
    }
  });

  test('SGPA limit follows the grading scale', () {
    expect(isValidSgpa(9.5, maxSgpaFor(true)), isTrue);
    expect(isValidSgpa(9.5, maxSgpaFor(false)), isFalse); // 4.0 scale
    expect(isValidSgpa(3.7, maxSgpaFor(false)), isTrue);
    expect(isValidSgpa(-1, 10), isFalse);
    expect(isValidSgpa(null, 10), isFalse);
  });
}
