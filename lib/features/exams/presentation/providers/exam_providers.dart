import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../services/notification_service.dart';
import '../../data/exam_repository.dart';
import '../../domain/exam.dart';

final examRepositoryProvider = Provider<ExamRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return ExamRepository(db: ref.watch(firestoreProvider), uid: uid);
});

final examsStreamProvider = StreamProvider<List<Exam>>((ref) {
  final repo = ref.watch(examRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchExams();
});

/// Every exam, including archived semesters (Past semesters screens).
final allExamsStreamProvider = StreamProvider<List<Exam>>((ref) {
  final repo = ref.watch(examRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchAllExams();
});

/// Upcoming (today or later) exams, soonest first.
final upcomingExamsProvider = Provider<List<Exam>>((ref) {
  final all = ref.watch(examsStreamProvider).valueOrNull ?? const [];
  return all.where((e) => e.daysUntil >= 0).toList();
});

/// Past exams, most recent first.
final pastExamsProvider = Provider<List<Exam>>((ref) {
  final all = ref.watch(examsStreamProvider).valueOrNull ?? const [];
  return all.where((e) => e.daysUntil < 0).toList().reversed.toList();
});

/// The soonest upcoming exam, or null.
final nextExamProvider = Provider<Exam?>((ref) {
  final up = ref.watch(upcomingExamsProvider);
  return up.isEmpty ? null : up.first;
});

final examControllerProvider = Provider<ExamController>((ref) {
  return ExamController(
    ref.watch(examRepositoryProvider),
    ref.watch(notificationServiceProvider),
  );
});

class ExamController {
  final ExamRepository? _repo;
  final NotificationService _notifications;
  ExamController(this._repo, this._notifications);

  Future<void> add(Exam e) async => _repo?.add(e);
  Future<void> update(Exam e) async => _repo?.update(e);

  Future<void> delete(String id) async {
    if (_repo == null) return;
    await _repo.delete(id);
    await _notifications.cancelExam(id);
  }
}
