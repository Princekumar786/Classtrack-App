import 'semester.dart';

/// Content of the "Semester Wrapped" share card, built from real stats.
/// Pure so the wording rules are unit-testable.
class SemesterWrapped {
  final String semesterName;
  final String emoji;
  final String headline;

  /// Hero stat (SGPA when known, else attendance %), and what it means.
  final String heroValue;
  final String heroLabel;

  /// Up to three small stats shown under the hero (label, value).
  final List<(String, String)> stats;
  final String shareText;

  const SemesterWrapped({
    required this.semesterName,
    required this.emoji,
    required this.headline,
    required this.heroValue,
    required this.heroLabel,
    required this.stats,
    required this.shareText,
  });

  factory SemesterWrapped.build({
    required String semesterName,
    required SemesterStats stats,
    required bool tenPoint,
  }) {
    final maxLabel = tenPoint ? '10' : '4.0';
    final maxPoints = tenPoint ? 10.0 : 4.0;
    final sgpa = stats.sgpa;
    final att = stats.attendancePercent;
    final attLabel = att == null ? null : '${att.round()}%';

    // Headline: brag about the stronger of grades vs attendance.
    final gradeRatio = sgpa == null ? null : sgpa / maxPoints;
    final attRatio = att == null ? null : att / 100;
    final best = [gradeRatio, attRatio].whereType<double>().fold<double?>(
        null, (a, b) => a == null || b > a ? b : a);
    final (headline, emoji) = best == null
        ? ('Semester complete', '🎓')
        : best >= 0.9
            ? ('Absolutely crushed it', '🏆')
            : best >= 0.75
                ? ('Strong semester', '🔥')
                : ('Made it through', '💪');

    final small = <(String, String)>[];
    if (sgpa != null && attLabel != null) small.add(('Attendance', attLabel));
    if (stats.attended > 0) small.add(('Classes attended', '${stats.attended}'));
    small.add(('Subjects', '${stats.subjects.length}'));
    if (small.length < 3 && stats.examCount > 0) {
      small.add(('Exams', '${stats.examCount}'));
    }

    final String heroValue;
    final String heroLabel;
    if (sgpa != null) {
      heroValue = sgpa.toStringAsFixed(2);
      heroLabel = 'SGPA / $maxLabel';
    } else if (attLabel != null) {
      heroValue = attLabel;
      heroLabel = 'attendance';
    } else {
      heroValue = '${stats.subjects.length}';
      heroLabel = stats.subjects.length == 1 ? 'subject done' : 'subjects done';
    }

    final parts = <String>[
      if (sgpa != null) 'SGPA ${sgpa.toStringAsFixed(2)}/$maxLabel',
      if (attLabel != null) '$attLabel attendance',
    ];
    final shareText = parts.isEmpty
        ? '$semesterName — wrapped! $emoji'
        : '$semesterName wrapped: ${parts.join(' · ')} $emoji';

    return SemesterWrapped(
      semesterName: semesterName,
      emoji: emoji,
      headline: headline,
      heroValue: heroValue,
      heroLabel: heroLabel,
      stats: small.take(3).toList(),
      shareText: shareText,
    );
  }
}
