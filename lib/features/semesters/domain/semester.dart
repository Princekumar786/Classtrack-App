import 'package:cloud_firestore/cloud_firestore.dart';

import '../../exams/domain/exam.dart';
import '../../grades/domain/grade_item.dart';
import '../../subjects/domain/subject.dart';

/// A wrapped-up (archived) semester. Stored at users/{uid}/semesters/{id}.
///
/// The semester doc only holds its name, dates and the optional official SGPA.
/// Its subjects, grades and exams stay in their normal collections, tagged with
/// `semesterId == id`, so marks can still be edited later and a wrap-up can be
/// undone by simply clearing the tag. All numbers (SGPA, attendance) are
/// computed live from that data by [SemesterStats].
class Semester {
  final String id;
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? wrappedAt;

  /// Official SGPA from the university result, when the student entered it.
  /// Wins over the computed SGPA.
  final double? officialSgpa;

  const Semester({
    required this.id,
    required this.name,
    this.startDate,
    this.endDate,
    this.wrappedAt,
    this.officialSgpa,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
        'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
        'wrappedAt': wrappedAt != null
            ? Timestamp.fromDate(wrappedAt!)
            : FieldValue.serverTimestamp(),
        'officialSgpa': officialSgpa,
      };

  factory Semester.fromMap(String id, Map<String, dynamic> map) => Semester(
        id: id,
        name: (map['name'] as String?)?.trim().isNotEmpty == true
            ? (map['name'] as String).trim()
            : 'Semester',
        startDate: (map['startDate'] as Timestamp?)?.toDate(),
        endDate: (map['endDate'] as Timestamp?)?.toDate(),
        wrappedAt: (map['wrappedAt'] as Timestamp?)?.toDate(),
        officialSgpa: (map['officialSgpa'] as num?)?.toDouble(),
      );
}

/// One subject's result inside a semester.
class SubjectResult {
  final Subject subject;
  final CourseGrade computed;

  /// Grade points used for SGPA: the official [Subject.finalGradePoints] when
  /// set, else derived from the assessments. Null = not graded.
  final double? points;
  final double credits;

  const SubjectResult({
    required this.subject,
    required this.computed,
    required this.points,
    required this.credits,
  });

  bool get isGraded => points != null;
  bool get hasOfficial => subject.finalGradePoints != null;

  /// Letter shown in lists: official grade if entered, else the computed one.
  String? get letter =>
      subject.finalGrade ?? (computed.count > 0 ? computed.letter : null);
}

/// Live numbers for one semester (or for the current one).
class SemesterStats {
  final List<SubjectResult> subjects;

  /// Credit-weighted grade points of graded subjects (null = nothing graded).
  final double? computedSgpa;

  /// Official SGPA override (from [Semester.officialSgpa]).
  final double? officialSgpa;
  final double gradedCredits;
  final int attended;
  final int held;
  final int examCount;
  final int gradeCount;

  const SemesterStats({
    required this.subjects,
    required this.computedSgpa,
    required this.officialSgpa,
    required this.gradedCredits,
    required this.attended,
    required this.held,
    required this.examCount,
    required this.gradeCount,
  });

  /// The SGPA to show: official when entered, else computed.
  double? get sgpa => officialSgpa ?? computedSgpa;

  double? get attendancePercent => held == 0 ? null : attended / held * 100;

  /// Credits counted when this semester feeds CGPA. When only an official
  /// SGPA exists (nothing graded per subject) every subject counts with its
  /// credits (default 1), so the semester still carries weight.
  double get cgpaCredits {
    if (gradedCredits > 0) return gradedCredits;
    if (officialSgpa == null) return 0;
    return subjects.fold<double>(0, (a, r) => a + r.credits);
  }

  /// Builds stats for the [subjects] of one semester. [grades]/[exams] may
  /// contain other items; only those linked to these subjects or carrying
  /// [semesterId] are counted.
  factory SemesterStats.compute({
    required List<Subject> subjects,
    required List<GradeItem> grades,
    required List<Exam> exams,
    required bool tenPoint,
    String? semesterId,
    double? officialSgpa,
  }) {
    final ids = {for (final s in subjects) s.id};
    final maxPoints = tenPoint ? 10.0 : 4.0;
    final results = <SubjectResult>[];
    double weighted = 0, credits = 0;
    int attended = 0, held = 0;
    for (final s in subjects) {
      final items = grades.where((g) => g.subjectId == s.id).toList();
      final course = CourseGrade.from(items);
      final official = s.finalGradePoints?.clamp(0.0, maxPoints).toDouble();
      final points = official ??
          (course.count > 0
              ? GradeScale.pointsFor(course.percent, tenPoint)
              : null);
      final c = (s.credits ?? 1).toDouble();
      results.add(SubjectResult(
          subject: s, computed: course, points: points, credits: c));
      if (points != null && c > 0) {
        weighted += points * c;
        credits += c;
      }
      attended += s.attended;
      held += s.held;
    }
    bool belongs(String? subjectId, String? sem) =>
        (subjectId != null && ids.contains(subjectId)) ||
        (semesterId != null && sem == semesterId);
    return SemesterStats(
      subjects: results,
      computedSgpa: credits > 0 ? weighted / credits : null,
      officialSgpa: officialSgpa?.clamp(0.0, maxPoints).toDouble(),
      gradedCredits: credits,
      attended: attended,
      held: held,
      examCount: exams.where((e) => belongs(e.subjectId, e.semesterId)).length,
      gradeCount:
          grades.where((g) => belongs(g.subjectId, g.semesterId)).length,
    );
  }
}

/// Credit-weighted CGPA across semesters. Null when none has an SGPA.
double? computeCgpa(Iterable<SemesterStats> semesters) {
  double weighted = 0, credits = 0;
  for (final s in semesters) {
    final sgpa = s.sgpa;
    final c = s.cgpaCredits;
    if (sgpa == null || c <= 0) continue;
    weighted += sgpa * c;
    credits += c;
  }
  return credits > 0 ? weighted / credits : null;
}

/// Suggests a name for the semester being wrapped up: "Semester N" from the
/// profile's semester number (else past count + 1), bumped past any name that
/// is already used so two wrap-ups never get the same default.
String suggestSemesterName({
  int? profileSemester,
  required List<String> existingNames,
}) {
  final used = {for (final n in existingNames) n.trim().toLowerCase()};
  var n = profileSemester ?? (existingNames.length + 1);
  if (n < 1) n = 1;
  while (used.contains('semester $n')) {
    n++;
  }
  return 'Semester $n';
}

/// True when an import looks like a NEW semester's timetable: the student
/// already has current subjects, and most of the incoming subject names don't
/// match them. Re-importing the same timetable (mostly matching) stays quiet.
bool looksLikeNewSemester({
  required Iterable<String> existingNames,
  required Iterable<String> incomingNames,
}) {
  String norm(String s) => s.trim().toLowerCase();
  final existing = {for (final n in existingNames) norm(n)}..remove('');
  final incoming = {for (final n in incomingNames) norm(n)}..remove('');
  if (existing.isEmpty || incoming.isEmpty) return false;
  final matched = incoming.where(existing.contains).length;
  return matched / incoming.length < 0.5;
}


/// Highest valid SGPA on the user's grading scale (10-point or 4.0).
double maxSgpaFor(bool tenPoint) => tenPoint ? 10.0 : 4.0;

/// Whether [value] is a valid SGPA on a scale whose top is [max].
bool isValidSgpa(double? value, double max) =>
    value != null && value.isFinite && value >= 0 && value <= max;
