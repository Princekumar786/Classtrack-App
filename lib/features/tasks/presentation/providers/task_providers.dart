import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../services/notification_service.dart';
import '../../data/task_repository.dart';
import '../../domain/task_buckets.dart';
import '../../domain/task_item.dart';

final taskRepositoryProvider = Provider<TaskRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return TaskRepository(db: ref.watch(firestoreProvider), uid: uid);
});

final tasksStreamProvider = StreamProvider<List<TaskItem>>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchTasks();
});

/// Pending (not done) tasks only.
final pendingTasksProvider = Provider<List<TaskItem>>((ref) {
  final all = ref.watch(tasksStreamProvider).valueOrNull ?? const [];
  return all.where((t) => !t.done).toList();
});

/// Headline task numbers (pending / overdue / due today / this week / done).
/// Powers the Home "Tasks due" card.
final taskSummaryProvider = Provider<TaskSummary>((ref) {
  final all = ref.watch(tasksStreamProvider).valueOrNull ?? const [];
  return TaskSummary.of(all, DateTime.now());
});

/// Tasks due on a specific day.
final tasksForDayProvider =
    Provider.family<List<TaskItem>, DateTime>((ref, day) {
  final all = ref.watch(tasksStreamProvider).valueOrNull ?? const [];
  return all
      .where((t) => t.dueDate != null && DateUtilsX.isSameDay(t.dueDate!, day))
      .toList();
});

final taskControllerProvider = Provider<TaskController>((ref) {
  return TaskController(
    ref.watch(taskRepositoryProvider),
    ref.watch(notificationServiceProvider),
  );
});

class TaskController {
  final TaskRepository? _repo;
  final NotificationService _notifications;
  TaskController(this._repo, this._notifications);

  Future<void> add(TaskItem t) async => _repo?.add(t);
  Future<void> update(TaskItem t) async =>
      _repo?.update(t);

  Future<void> toggle(TaskItem t) async {
    if (_repo == null) return;
    await _repo.toggleDone(t);
    // If it just became done, cancel its reminder.
    if (!t.done) await _notifications.cancelTask(t.id);
  }

  Future<void> delete(String id) async {
    if (_repo == null) return;
    await _repo.delete(id);
    await _notifications.cancelTask(id);
  }
}
