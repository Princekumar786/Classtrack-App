import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../data/grade_repository.dart';
import '../../domain/grade_item.dart';

final gradeRepositoryProvider = Provider<GradeRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return GradeRepository(db: ref.watch(firestoreProvider), uid: uid);
});

final gradesStreamProvider = StreamProvider<List<GradeItem>>((ref) {
  final repo = ref.watch(gradeRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchGrades();
});

/// Grades belonging to a single subject.
final gradesForSubjectProvider =
    Provider.family<List<GradeItem>, String>((ref, subjectId) {
  final all = ref.watch(gradesStreamProvider).valueOrNull ?? const [];
  return all.where((g) => g.subjectId == subjectId).toList();
});

/// Grades not linked to any current subject: no subject at all, or pointing at
/// a subject that no longer exists (deleted before the unlink fix). Orphans are
/// only detected once subjects have loaded, so nothing flickers in on start-up.
final unassignedGradesProvider = Provider<List<GradeItem>>((ref) {
  final all = ref.watch(gradesStreamProvider).valueOrNull ?? const [];
  final subjects = ref.watch(subjectsStreamProvider).valueOrNull;
  final ids = subjects?.map((s) => s.id).toSet();
  return all
      .where((g) =>
          g.subjectId == null || (ids != null && !ids.contains(g.subjectId)))
      .toList();
});

/// Every grade, including archived semesters (Past semesters screens).
final allGradesStreamProvider = StreamProvider<List<GradeItem>>((ref) {
  final repo = ref.watch(gradeRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchAllGrades();
});

/// Aggregated grade for one subject.
final courseGradeProvider =
    Provider.family<CourseGrade, String>((ref, subjectId) {
  return CourseGrade.from(ref.watch(gradesForSubjectProvider(subjectId)));
});

/// Overall GPA (4.0 scale) across all subjects that have grades, weighted by
/// each subject's credits (default 1 when unset).
class GpaSummary {
  final double gpa;
  final int gradedSubjects;
  final double averagePercent;
  final double maxPoints;

  const GpaSummary(
      {required this.gpa,
      required this.gradedSubjects,
      required this.averagePercent,
      this.maxPoints = 4.0});

  static const empty =
      GpaSummary(gpa: 0, gradedSubjects: 0, averagePercent: 0);
}

final gpaSummaryProvider = Provider<GpaSummary>((ref) {
  final tenPoint = ref.watch(gpaScaleProvider) == GpaScaleType.ten;
  final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
  double pointsXCredits = 0;
  double creditSum = 0;
  double percentSum = 0;
  int graded = 0;
  for (final s in subjects) {
    final course = ref.watch(courseGradeProvider(s.id));
    if (course.count == 0) continue;
    final credits = (s.credits ?? 1).toDouble();
    pointsXCredits += GradeScale.pointsFor(course.percent, tenPoint) * credits;
    creditSum += credits;
    percentSum += course.percent;
    graded++;
  }
  final maxPoints = tenPoint ? 10.0 : 4.0;
  if (graded == 0) return GpaSummary(maxPoints: maxPoints, gpa: 0, gradedSubjects: 0, averagePercent: 0);
  return GpaSummary(
    gpa: creditSum > 0 ? pointsXCredits / creditSum : 0,
    gradedSubjects: graded,
    averagePercent: percentSum / graded,
    maxPoints: maxPoints,
  );
});

final gradeControllerProvider = Provider<GradeController>((ref) {
  return GradeController(ref.watch(gradeRepositoryProvider));
});

class GradeController {
  final GradeRepository? _repo;
  GradeController(this._repo);

  Future<void> add(GradeItem g) async => _repo?.add(g);
  Future<void> update(GradeItem g) async => _repo?.update(g);
  Future<void> delete(String id) async => _repo?.delete(id);
}
