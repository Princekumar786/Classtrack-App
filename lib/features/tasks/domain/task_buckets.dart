import 'task_item.dart';

/// Date groups used by the Tasks screen's "smart" list (Things / Todoist
/// style): what's late, what's today, what's next, what's later.
enum TaskBucket { overdue, today, tomorrow, thisWeek, later, noDate }

extension TaskBucketX on TaskBucket {
  String get label => switch (this) {
        TaskBucket.overdue => 'Overdue',
        TaskBucket.today => 'Today',
        TaskBucket.tomorrow => 'Tomorrow',
        TaskBucket.thisWeek => 'Next 7 days',
        TaskBucket.later => 'Later',
        TaskBucket.noDate => 'No due date',
      };
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Which date group a PENDING task belongs to, relative to [now].
TaskBucket bucketFor(TaskItem t, DateTime now) {
  final due = t.dueDate;
  if (due == null) return TaskBucket.noDate;
  final today = _day(now);
  final d = _day(due);
  if (d.isBefore(today)) return TaskBucket.overdue;
  final diff = d.difference(today).inDays;
  if (diff == 0) return TaskBucket.today;
  if (diff == 1) return TaskBucket.tomorrow;
  if (diff <= 7) return TaskBucket.thisWeek;
  return TaskBucket.later;
}

/// Groups pending tasks by [TaskBucket] (in bucket order, empty groups left
/// out). Inside a group: earliest due first, then High → Low priority.
Map<TaskBucket, List<TaskItem>> groupPendingTasks(
    Iterable<TaskItem> tasks, DateTime now) {
  final out = <TaskBucket, List<TaskItem>>{};
  for (final b in TaskBucket.values) {
    final items = tasks.where((t) => !t.done && bucketFor(t, now) == b).toList()
      ..sort(compareByDueThenPriority);
    if (items.isNotEmpty) out[b] = items;
  }
  return out;
}

/// Earliest due date first (no date last), ties broken High → Low priority.
int compareByDueThenPriority(TaskItem a, TaskItem b) {
  final ad = a.dueDate, bd = b.dueDate;
  if (ad != null && bd != null) {
    final c = ad.compareTo(bd);
    if (c != 0) return c;
  } else if (ad == null && bd != null) {
    return 1;
  } else if (ad != null && bd == null) {
    return -1;
  }
  return b.priority.index.compareTo(a.priority.index);
}

/// Headline numbers for the Home "Tasks due" card and the Tasks screen header.
class TaskSummary {
  final int pending;
  final int overdue;
  final int dueToday;

  /// Due in the next 7 days, today included (overdue NOT included).
  final int dueThisWeek;
  final int completed;

  const TaskSummary({
    required this.pending,
    required this.overdue,
    required this.dueToday,
    required this.dueThisWeek,
    required this.completed,
  });

  int get total => pending + completed;

  /// 0..1 share of all items that are done (0 when there are none).
  double get progress => total == 0 ? 0 : completed / total;

  factory TaskSummary.of(Iterable<TaskItem> tasks, DateTime now) {
    var pending = 0, overdue = 0, today = 0, week = 0, done = 0;
    for (final t in tasks) {
      if (t.done) {
        done++;
        continue;
      }
      pending++;
      switch (bucketFor(t, now)) {
        case TaskBucket.overdue:
          overdue++;
        case TaskBucket.today:
          today++;
          week++;
        case TaskBucket.tomorrow:
        case TaskBucket.thisWeek:
          week++;
        case TaskBucket.later:
        case TaskBucket.noDate:
          break;
      }
    }
    return TaskSummary(
      pending: pending,
      overdue: overdue,
      dueToday: today,
      dueThisWeek: week,
      completed: done,
    );
  }
}
