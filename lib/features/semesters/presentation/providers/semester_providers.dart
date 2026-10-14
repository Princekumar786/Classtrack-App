import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../services/notification_service.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../grades/presentation/providers/grade_providers.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../data/semester_repository.dart';
import '../../domain/semester.dart';

final semesterRepositoryProvider = Provider<SemesterRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return SemesterRepository(db: ref.watch(firestoreProvider), uid: uid);
});

/// Past (wrapped-up) semesters, newest first.
final semestersStreamProvider = StreamProvider<List<Semester>>((ref) {
  final repo = ref.watch(semesterRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchSemesters();
});

final semesterByIdProvider = Provider.family<Semester?, String>((ref, id) {
  final list = ref.watch(semestersStreamProvider).valueOrNull ?? const [];
  for (final s in list) {
    if (s.id == id) return s;
  }
  return null;
});

/// Live SGPA/attendance for one archived semester.
final semesterStatsProvider =
    Provider.family<SemesterStats, String>((ref, semesterId) {
  final tenPoint = ref.watch(gpaScaleProvider) == GpaScaleType.ten;
  final subjects = (ref.watch(allSubjectsStreamProvider).valueOrNull ?? const [])
      .where((s) => s.semesterId == semesterId)
      .toList();
  final grades = (ref.watch(allGradesStreamProvider).valueOrNull ?? const [])
      .where((g) => g.semesterId == semesterId)
      .toList();
  final exams = (ref.watch(allExamsStreamProvider).valueOrNull ?? const [])
      .where((e) => e.semesterId == semesterId)
      .toList();
  return SemesterStats.compute(
    subjects: subjects,
    grades: grades,
    exams: exams,
    tenPoint: tenPoint,
    semesterId: semesterId,
    officialSgpa: ref.watch(semesterByIdProvider(semesterId))?.officialSgpa,
  );
});

/// CGPA across all past semesters (null until one has an SGPA).
final cgpaProvider = Provider<double?>((ref) {
  final semesters = ref.watch(semestersStreamProvider).valueOrNull ?? const [];
  return computeCgpa(
      semesters.map((s) => ref.watch(semesterStatsProvider(s.id))));
});

final semesterControllerProvider = Provider<SemesterController>((ref) {
  return SemesterController(
    ref.watch(semesterRepositoryProvider),
    ref.watch(notificationServiceProvider),
  );
});

class SemesterController {
  final SemesterRepository? _repo;
  final NotificationService _notifications;
  SemesterController(this._repo, this._notifications);

  /// Archives [plan] into a new semester. Class reminders and check-ins for
  /// archived subjects are pruned automatically by the reminder sync (they
  /// leave the current timetable); exam reminders must be cancelled here.
  Future<String?> wrapUp({
    required String name,
    DateTime? startDate,
    DateTime? endDate,
    double? officialSgpa,
    required WrapUpPlan plan,
  }) async {
    final repo = _repo;
    if (repo == null) return null;
    final id = await repo.wrapUp(
      name: name,
      startDate: startDate,
      endDate: endDate,
      officialSgpa: officialSgpa,
      plan: plan,
    );
    for (final examId in plan.examIds) {
      try {
        await _notifications.cancelExam(examId);
      } catch (_) {
        // Best effort: a missing reminder is not an error.
      }
    }
    return id;
  }

  Future<void> restore(String semesterId) async => _repo?.restore(semesterId);

  Future<void> rename(String id, String name) async => _repo?.rename(id, name);

  Future<void> setOfficialSgpa(String id, double? sgpa) async =>
      _repo?.setOfficialSgpa(id, sgpa);

  Future<void> setFinalResult(String subjectId,
          {String? finalGrade, double? finalGradePoints, int? credits}) async =>
      _repo?.setFinalResult(subjectId,
          finalGrade: finalGrade,
          finalGradePoints: finalGradePoints,
          credits: credits);
}
