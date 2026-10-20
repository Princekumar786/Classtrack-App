import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/models/checklist_item.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';

enum TaskPriority { low, medium, high }

extension TaskPriorityX on TaskPriority {
  String get label => switch (this) {
        TaskPriority.low => 'Low',
        TaskPriority.medium => 'Medium',
        TaskPriority.high => 'High',
      };

  Color get color => switch (this) {
        TaskPriority.low => AppColors.info,
        TaskPriority.medium => AppColors.warning,
        TaskPriority.high => AppColors.danger,
      };

  static TaskPriority parse(String? v) => TaskPriority.values.firstWhere(
        (e) => e.name == v,
        orElse: () => TaskPriority.medium,
      );
}

/// The kind of item: a plain to-do, a college assignment (homework, lab
/// record, project — usually tied to a subject), a calendar event (e.g. a
/// class, meeting or webinar imported from Google Calendar), or a video (e.g.
/// a YouTube tutorial the student wants to watch on a given day).
///
/// Stored by [Enum.name]. Older app versions that don't know `assignment`
/// fall back to [TaskType.task] in [TaskTypeX.parse], so nothing breaks.
enum TaskType { task, assignment, event, video }

extension TaskTypeX on TaskType {
  String get label => switch (this) {
        TaskType.task => 'Task',
        TaskType.assignment => 'Assignment',
        TaskType.event => 'Event',
        TaskType.video => 'Video',
      };

  /// Plural label used for tabs and section titles.
  String get pluralLabel => switch (this) {
        TaskType.task => 'To-dos',
        TaskType.assignment => 'Assignments',
        TaskType.event => 'Events',
        TaskType.video => 'Videos',
      };

  IconData get icon => switch (this) {
        TaskType.task => Icons.check_circle_outline_rounded,
        TaskType.assignment => Icons.assignment_rounded,
        TaskType.event => Icons.event_rounded,
        TaskType.video => Icons.play_circle_fill_rounded,
      };

  Color get color => switch (this) {
        TaskType.task => AppColors.primary,
        TaskType.assignment => AppColors.accent,
        TaskType.event => AppColors.info,
        TaskType.video => AppColors.coral,
      };

  /// Parses the stored enum name. Accepts the legacy `"course"` value so items
  /// created before the Course → Event rename keep working.
  static TaskType parse(String? v) {
    if (v == 'course') return TaskType.event; // backward compatibility
    return TaskType.values.firstWhere(
      (e) => e.name == v,
      orElse: () => TaskType.task,
    );
  }
}

/// A task / assignment / deadline / course / video. Stored at
/// users/{uid}/tasks/{id}.
class TaskItem {
  final String id;
  final String title;
  final String? note;
  final String? subjectId; // optional link to a subject
  final DateTime? dueDate;
  final bool done;
  final TaskPriority priority;
  final TaskType type;
  final String? link; // optional external URL (course / video / resource)
  final String? thumbnail; // optional preview image URL (e.g. video thumbnail)
  final List<ChecklistItem> subtasks;
  final DateTime? createdAt;

  /// Stable id of the external source this item was imported from (e.g. a
  /// Google Calendar event's iCalUID/id). Lets re-imports recognise an item
  /// they already created and skip it instead of adding a duplicate. Null for
  /// items created by hand.
  final String? sourceId;

  const TaskItem({
    required this.id,
    required this.title,
    this.note,
    this.subjectId,
    this.dueDate,
    this.done = false,
    this.priority = TaskPriority.medium,
    this.type = TaskType.task,
    this.link,
    this.thumbnail,
    this.subtasks = const [],
    this.createdAt,
    this.sourceId,
  });

  bool get isOverdue =>
      !done &&
      dueDate != null &&
      dueDate!.isBefore(DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day));

  bool get hasLink => link != null && link!.trim().isNotEmpty;

  bool get hasSubtasks => subtasks.isNotEmpty;
  int get subtasksDone => subtasks.where((s) => s.done).length;

  TaskItem copyWith({
    String? title,
    String? note,
    String? subjectId,
    DateTime? dueDate,
    bool? done,
    TaskPriority? priority,
    TaskType? type,
    String? link,
    String? thumbnail,
    List<ChecklistItem>? subtasks,
    String? sourceId,
    bool clearDue = false,
    bool clearSubject = false,
    bool clearLink = false,
  }) {
    return TaskItem(
      id: id,
      title: title ?? this.title,
      note: note ?? this.note,
      subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
      dueDate: clearDue ? null : (dueDate ?? this.dueDate),
      done: done ?? this.done,
      priority: priority ?? this.priority,
      type: type ?? this.type,
      link: clearLink ? null : (link ?? this.link),
      thumbnail: clearLink ? null : (thumbnail ?? this.thumbnail),
      subtasks: subtasks ?? this.subtasks,
      createdAt: createdAt,
      sourceId: sourceId ?? this.sourceId,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': Validators.sanitizeText(title, maxLength: 200),
        'note': note == null
            ? null
            : Validators.sanitizeText(note, multiline: true),
        'subjectId': subjectId,
        'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
        'done': done,
        'priority': priority.name,
        'type': type.name,
        'link': link,
        'thumbnail': thumbnail,
        'subtasks': ChecklistItem.listToMap(subtasks),
        'sourceId': sourceId,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory TaskItem.fromMap(String id, Map<String, dynamic> map) {
    return TaskItem(
      id: id,
      title: Validators.sanitizeText((map['title'] as String?) ?? '',
          maxLength: 200),
      note: map['note'] == null
          ? null
          : Validators.sanitizeText(map['note'] as String, multiline: true),
      subjectId: map['subjectId'] as String?,
      dueDate: (map['dueDate'] as Timestamp?)?.toDate(),
      done: (map['done'] as bool?) ?? false,
      priority: TaskPriorityX.parse(map['priority'] as String?),
      type: TaskTypeX.parse(map['type'] as String?),
      link: map['link'] as String?,
      thumbnail: map['thumbnail'] as String?,
      subtasks: ChecklistItem.listFrom(map['subtasks']),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      sourceId: map['sourceId'] as String?,
    );
  }
}
