import 'package:cloud_firestore/cloud_firestore.dart';

/// A single graded assessment (exam, quiz, assignment...) for a subject.
/// Stored at users/{uid}/grades/{id}.
class GradeItem {
  final String id;
  final String? subjectId; // optional link to a subject
  final String title; // e.g. "Midterm", "Assignment 2"
  final double score; // marks earned
  final double maxScore; // marks out of
  final double? weight; // % of the final grade this assessment is worth
  final DateTime? date;
  final DateTime? createdAt;

  /// Archived semester this grade belongs to (null = current semester).
  /// Omitted from [toMap] when null so edits never un-archive it.
  final String? semesterId;

  const GradeItem({
    required this.id,
    this.subjectId,
    required this.title,
    required this.score,
    required this.maxScore,
    this.weight,
    this.date,
    this.createdAt,
    this.semesterId,
  });

  /// Percentage scored on this assessment (0..100, can exceed 100 for bonus).
  double get percent =>
      maxScore > 0 ? (score / maxScore) * 100.0 : 0.0;

  bool get hasWeight => weight != null && weight! > 0;

  GradeItem copyWith({
    String? subjectId,
    String? title,
    double? score,
    double? maxScore,
    double? weight,
    DateTime? date,
    bool clearSubject = false,
    bool clearWeight = false,
    bool clearDate = false,
  }) {
    return GradeItem(
      id: id,
      subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
      title: title ?? this.title,
      score: score ?? this.score,
      maxScore: maxScore ?? this.maxScore,
      weight: clearWeight ? null : (weight ?? this.weight),
      date: clearDate ? null : (date ?? this.date),
      createdAt: createdAt,
      semesterId: semesterId,
    );
  }

  Map<String, dynamic> toMap() => {
        'subjectId': subjectId,
        'title': title,
        'score': score,
        'maxScore': maxScore,
        'weight': weight,
        'date': date != null ? Timestamp.fromDate(date!) : null,
        if (semesterId != null) 'semesterId': semesterId,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory GradeItem.fromMap(String id, Map<String, dynamic> map) {
    return GradeItem(
      id: id,
      subjectId: map['subjectId'] as String?,
      title: (map['title'] as String?) ?? 'Untitled',
      score: (map['score'] as num?)?.toDouble() ?? 0,
      maxScore: (map['maxScore'] as num?)?.toDouble() ?? 0,
      weight: (map['weight'] as num?)?.toDouble(),
      date: (map['date'] as Timestamp?)?.toDate(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      semesterId: map['semesterId'] as String?,
    );
  }
}

/// Grade → GPA (4.0 scale) and letter conversions.
class GradeScale {
  GradeScale._();

  static double gpaPoints(double percent) {
    if (percent >= 90) return 4.0;
    if (percent >= 85) return 3.7;
    if (percent >= 80) return 3.3;
    if (percent >= 75) return 3.0;
    if (percent >= 70) return 2.7;
    if (percent >= 65) return 2.3;
    if (percent >= 60) return 2.0;
    if (percent >= 55) return 1.7;
    if (percent >= 50) return 1.0;
    return 0.0;
  }

  /// 10-point CGPA mapping (common in Indian universities).
  static double gpaPoints10(double percent) {
    if (percent >= 90) return 10;
    if (percent >= 80) return 9;
    if (percent >= 70) return 8;
    if (percent >= 60) return 7;
    if (percent >= 50) return 6;
    if (percent >= 45) return 5;
    if (percent >= 40) return 4;
    return 0;
  }

  /// Points on the selected scale (4.0 when [tenPoint] is false, else 10-point).
  static double pointsFor(double percent, bool tenPoint) =>
      tenPoint ? gpaPoints10(percent) : gpaPoints(percent);

  static String letter(double percent) {
    if (percent >= 90) return 'A';
    if (percent >= 85) return 'A-';
    if (percent >= 80) return 'B+';
    if (percent >= 75) return 'B';
    if (percent >= 70) return 'B-';
    if (percent >= 65) return 'C+';
    if (percent >= 60) return 'C';
    if (percent >= 55) return 'C-';
    if (percent >= 50) return 'D';
    return 'F';
  }
}

/// Aggregated grade for one subject, derived from its [GradeItem]s.
class CourseGrade {
  /// Weighted (or simple) current percentage across recorded assessments.
  final double percent;

  /// Total weight (%) already accounted for by recorded assessments.
  /// 0 when no weights are used.
  final double gradedWeight;
  final int count;
  final bool usesWeights;

  const CourseGrade({
    required this.percent,
    required this.gradedWeight,
    required this.count,
    required this.usesWeights,
  });

  static const empty =
      CourseGrade(percent: 0, gradedWeight: 0, count: 0, usesWeights: false);

  double get gpaPoints => GradeScale.gpaPoints(percent);
  String get letter => GradeScale.letter(percent);

  /// Build a summary from a subject's grade items.
  factory CourseGrade.from(List<GradeItem> items) {
    if (items.isEmpty) return empty;
    final weighted = items.where((g) => g.hasWeight).toList();
    if (weighted.isNotEmpty) {
      final wSum = weighted.fold<double>(0, (a, g) => a + g.weight!);
      final pts = weighted.fold<double>(0, (a, g) => a + g.percent * g.weight!);
      return CourseGrade(
        percent: wSum > 0 ? pts / wSum : 0,
        gradedWeight: wSum,
        count: items.length,
        usesWeights: true,
      );
    }
    final avg = items.fold<double>(0, (a, g) => a + g.percent) / items.length;
    return CourseGrade(
      percent: avg,
      gradedWeight: 0,
      count: items.length,
      usesWeights: false,
    );
  }

  /// The average needed on the remaining weight to hit [target]% overall.
  /// Only meaningful when weights are used and some weight remains.
  /// Returns null when not computable.
  double? neededOnRemaining(double target) {
    if (!usesWeights) return null;
    final remaining = 100 - gradedWeight;
    if (remaining <= 0) return null;
    // currentContribution = percent * gradedWeight / 100 (points out of 100)
    final currentContribution = percent * gradedWeight / 100;
    final needed = (target - currentContribution) * 100 / remaining;
    return needed;
  }
}
