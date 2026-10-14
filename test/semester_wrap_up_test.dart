// Semester wrap-up: SGPA/CGPA maths, wrap-up selection, archive/restore
// round-trip, the "new semester" import detection, the Wrapped card copy, and
// the grade-delete fix (deleting a subject keeps its grades and exams).
import 'package:classtrack/features/exams/data/exam_repository.dart';
import 'package:classtrack/features/exams/domain/exam.dart';
import 'package:classtrack/features/grades/data/grade_repository.dart';
import 'package:classtrack/features/grades/domain/grade_item.dart';
import 'package:classtrack/features/semesters/data/semester_repository.dart';
import 'package:classtrack/features/semesters/domain/semester.dart';
import 'package:classtrack/features/semesters/domain/semester_wrapped.dart';
import 'package:classtrack/features/subjects/data/subject_repository.dart';
import 'package:classtrack/features/subjects/domain/subject.dart';
import 'package:classtrack/features/subscription/domain/upgrade_reason.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Subject _subject(String id,
        {int? credits,
        int attended = 0,
        int absent = 0,
        double? finalPoints,
        String? semesterId}) =>
    Subject(
      id: id,
      name: id,
      colorHex: 0xFF000000,
      credits: credits,
      attended: attended,
      absent: absent,
      finalGradePoints: finalPoints,
      semesterId: semesterId,
    );

GradeItem _grade(String id, String? subjectId, double score,
        {String? semesterId}) =>
    GradeItem(
        id: id,
        subjectId: subjectId,
        title: id,
        score: score,
        maxScore: 100,
        semesterId: semesterId);

Exam _exam(String id, String? subjectId, DateTime date) =>
    Exam(id: id, title: id, subjectId: subjectId, date: date);

const uid = 'u1';

void main() {
  group('SemesterStats', () {
    test('SGPA is credit-weighted and official points win', () {
      final stats = SemesterStats.compute(
        subjects: [
          _subject('maths', credits: 4, attended: 30, absent: 10),
          _subject('physics', credits: 2, attended: 20, absent: 0, finalPoints: 7),
          _subject('art'), // no marks, no result: not graded
        ],
        grades: [_grade('g1', 'maths', 92), _grade('g2', 'physics', 40)],
        exams: const [],
        tenPoint: true,
      );
      // maths 92% -> 10 pts x4, physics official 7 x2 -> (40+14)/6 = 9.0
      expect(stats.computedSgpa, closeTo(9.0, 1e-9));
      expect(stats.gradedCredits, 6);
      expect(stats.subjects.where((r) => r.isGraded).length, 2);
      expect(stats.attendancePercent, closeTo(50 / 60 * 100, 1e-9));
    });

    test('official SGPA overrides computed; nothing graded gives null', () {
      final empty = SemesterStats.compute(
          subjects: [_subject('a')],
          grades: const [],
          exams: const [],
          tenPoint: false);
      expect(empty.sgpa, isNull);
      expect(empty.cgpaCredits, 0);

      final official = SemesterStats.compute(
          subjects: [_subject('a', credits: 3), _subject('b')],
          grades: const [],
          exams: const [],
          tenPoint: true,
          officialSgpa: 8.4);
      expect(official.sgpa, 8.4);
      expect(official.cgpaCredits, 4); // 3 + default 1
    });

    test('CGPA weights each semester by its credits', () {
      SemesterStats sem(double sgpa, int credits) => SemesterStats.compute(
          subjects: [_subject('x', credits: credits)],
          grades: const [],
          exams: const [],
          tenPoint: true,
          officialSgpa: sgpa);
      expect(computeCgpa([sem(8, 20), sem(9, 20)]), closeTo(8.5, 1e-9));
      expect(computeCgpa([sem(6, 10), sem(9, 30)]), closeTo(8.25, 1e-9));
      expect(computeCgpa(const []), isNull);
    });
  });

  group('WrapUpPlan', () {
    final now = DateTime(2026, 12, 1);
    test('takes selected subjects with their grades and exams', () {
      final plan = WrapUpPlan.build(
        selectedSubjectIds: {'a'},
        grades: [
          _grade('ga', 'a', 50),
          _grade('gb', 'b', 50),
          _grade('gnone', null, 50),
          _grade('gold', 'a', 50, semesterId: 'old'),
        ],
        exams: [
          _exam('ea', 'a', DateTime(2026, 11, 1)),
          _exam('eaNext', 'a', DateTime(2026, 12, 20)),
          _exam('eb', 'b', DateTime(2026, 11, 1)),
          _exam('pastNone', null, DateTime(2026, 11, 1)),
          _exam('nextNone', null, DateTime(2026, 12, 20)),
        ],
        includeUnlinked: true,
        currentSubjectIds: {'a', 'b'},
        now: now,
      );
      expect(plan.subjectIds, ['a']);
      expect(plan.gradeIds, unorderedEquals(['ga', 'gnone']));
      // Upcoming exams with no subject stay current; already-archived skipped.
      expect(plan.examIds, unorderedEquals(['ea', 'eaNext', 'pastNone']));
      expect(plan.upcomingExamIds, ['eaNext']);
    });

    test('grades of a deleted subject count as unlinked', () {
      final plan = WrapUpPlan.build(
        selectedSubjectIds: const {},
        grades: [_grade('orphan', 'gone', 70)],
        exams: const [],
        includeUnlinked: true,
        currentSubjectIds: {'a'},
        now: now,
      );
      expect(plan.gradeIds, ['orphan']);
      final off = WrapUpPlan.build(
        selectedSubjectIds: const {},
        grades: [_grade('orphan', 'gone', 70)],
        exams: const [],
        includeUnlinked: false,
        currentSubjectIds: {'a'},
        now: now,
      );
      expect(off.isEmpty, isTrue);
    });
  });

  group('naming and import detection', () {
    test('suggestSemesterName uses profile number and skips used names', () {
      expect(suggestSemesterName(profileSemester: 3, existingNames: const []),
          'Semester 3');
      expect(
          suggestSemesterName(
              profileSemester: 3, existingNames: const ['Semester 3']),
          'Semester 4');
      expect(suggestSemesterName(existingNames: const ['A', 'B']),
          'Semester 3');
    });

    test('looksLikeNewSemester only fires for mostly-new subjects', () {
      expect(
          looksLikeNewSemester(
              existingNames: ['Maths', 'Physics'],
              incomingNames: ['DBMS', 'OS', 'Networks']),
          isTrue);
      // Re-importing the same timetable (case/space-insensitive) stays quiet.
      expect(
          looksLikeNewSemester(
              existingNames: ['Maths', 'Physics'],
              incomingNames: [' maths', 'PHYSICS', 'Lab']),
          isFalse);
      // First import ever: nothing to wrap up.
      expect(
          looksLikeNewSemester(existingNames: [], incomingNames: ['DBMS']),
          isFalse);
    });
  });

  group('SemesterWrapped', () {
    test('leads with SGPA and builds share text', () {
      final stats = SemesterStats.compute(
        subjects: [_subject('a', credits: 4, attended: 45, absent: 5)],
        grades: [_grade('g', 'a', 95)],
        exams: const [],
        tenPoint: true,
      );
      final w = SemesterWrapped.build(
          semesterName: 'Semester 3', stats: stats, tenPoint: true);
      expect(w.heroValue, '10.00');
      expect(w.heroLabel, 'SGPA / 10');
      expect(w.headline, 'Absolutely crushed it');
      expect(w.stats.first, ('Attendance', '90%'));
      expect(w.shareText, contains('SGPA 10.00/10'));
      expect(w.stats.length, lessThanOrEqualTo(3));
    });

    test('falls back to attendance when there are no marks', () {
      final stats = SemesterStats.compute(
        subjects: [_subject('a', attended: 6, absent: 4)],
        grades: const [],
        exams: const [],
        tenPoint: false,
      );
      final w = SemesterWrapped.build(
          semesterName: 'Sem', stats: stats, tenPoint: false);
      expect(w.heroValue, '60%');
      expect(w.heroLabel, 'attendance');
      expect(w.headline, 'Made it through');
    });
  });

  test('semesters is a Pro reason with complete copy', () {
    final c = UpgradeReason.semesters.copy;
    expect(c.title, isNotEmpty);
    expect(c.isLimit, isFalse);
    expect(planComparison.any((r) => r.reason == UpgradeReason.semesters),
        isTrue);
  });

  group('Firestore flows', () {
    late FakeFirebaseFirestore db;
    late SubjectRepository subjects;
    late GradeRepository grades;
    late ExamRepository exams;
    late SemesterRepository semesters;
    late DocumentReference<Map<String, dynamic>> user;

    setUp(() async {
      db = FakeFirebaseFirestore();
      subjects = SubjectRepository(db: db, uid: uid);
      grades = GradeRepository(db: db, uid: uid);
      exams = ExamRepository(db: db, uid: uid);
      semesters = SemesterRepository(db: db, uid: uid);
      user = db.collection('users').doc(uid);
      await user.collection('subjects').doc('maths').set(
          {'name': 'Maths', 'colorHex': 1, 'attended': 8, 'absent': 2});
      await user.collection('subjects').doc('physics').set(
          {'name': 'Physics', 'colorHex': 1, 'attended': 1, 'absent': 1});
      await user.collection('grades').doc('g1').set(
          {'subjectId': 'maths', 'title': 'Mid', 'score': 80, 'maxScore': 100});
      await user.collection('exams').doc('e1').set({
        'subjectId': 'maths',
        'title': 'Final',
        'date': Timestamp.fromDate(DateTime(2026, 11, 20)),
      });
    });

    test('wrap-up hides items from current streams; restore brings them back',
        () async {
      final id = await semesters.wrapUp(
        name: 'Semester 3',
        plan: const WrapUpPlan(
            subjectIds: ['maths'], gradeIds: ['g1'], examIds: ['e1']),
      );

      final current = await subjects.watchSubjects().first;
      expect(current.map((s) => s.id), ['physics']);
      expect(await grades.watchGrades().first, isEmpty);
      expect(await exams.watchExams().first, isEmpty);
      // Import only reuses current-semester subjects.
      expect((await subjects.getAll()).map((s) => s.id), ['physics']);
      expect(await subjects.getAll(includeArchived: true), hasLength(2));

      final all = await subjects.watchAllSubjects().first;
      final maths = all.firstWhere((s) => s.id == 'maths');
      expect(maths.semesterId, id);
      expect(maths.attended, 8, reason: 'attendance is kept as-is');
      final saved = await semesters.watchSemesters().first;
      expect(saved.single.name, 'Semester 3');

      // Editing an archived subject must not un-archive it.
      await subjects.update(maths.copyWith(room: 'B12'));
      expect((await subjects.watchSubjects().first).map((s) => s.id),
          ['physics']);

      await semesters.setFinalResult('maths',
          finalGrade: 'A+', finalGradePoints: 9, credits: 4);
      final withResult = (await subjects.watchAllSubjects().first)
          .firstWhere((s) => s.id == 'maths');
      expect(withResult.finalGrade, 'A+');
      expect(withResult.finalGradePoints, 9);
      expect(withResult.credits, 4);

      await semesters.restore(id);
      expect(await subjects.watchSubjects().first, hasLength(2));
      expect(await grades.watchGrades().first, hasLength(1));
      expect(await exams.watchExams().first, hasLength(1));
      expect(await semesters.watchSemesters().first, isEmpty);
    });

    test('deleting a subject keeps its grades and exams, unlinked', () async {
      await subjects.delete('maths');
      final g = await grades.watchGrades().first;
      expect(g.single.id, 'g1');
      expect(g.single.subjectId, isNull);
      final e = await exams.watchExams().first;
      expect(e.single.subjectId, isNull);
      expect((await subjects.watchSubjects().first).map((s) => s.id),
          ['physics']);
    });
  });
}
