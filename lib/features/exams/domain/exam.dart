import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/checklist_item.dart';

/// A scheduled exam / test. Stored at users/{uid}/exams/{id}.
class Exam {
  final String id;
  final String title;
  final String? subjectId;
  final DateTime date; // date + time of the exam
  final String? room;
  final String? note; // syllabus / topics
  final List<ChecklistItem> topics; // revision checklist for prep readiness
  final DateTime? createdAt;

  /// Archived semester this exam belongs to (null = current semester).
  /// Omitted from [toMap] when null so edits never un-archive it.
  final String? semesterId;

  const Exam({
    required this.id,
    required this.title,
    this.subjectId,
    required this.date,
    this.room,
    this.note,
    this.topics = const [],
    this.createdAt,
    this.semesterId,
  });

  /// Whole days from today (date-only) until the exam. Negative if past.
  int get daysUntil {
    final now = DateTime.now();
    final examDay = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    return examDay.difference(today).inDays;
  }

  bool get isPast => date.isBefore(DateTime.now());

  bool get hasTopics => topics.isNotEmpty;
  int get topicsDone => topics.where((t) => t.done).length;

  /// Preparation readiness (0..1) from the revision checklist; 0 when empty.
  double get readiness =>
      topics.isEmpty ? 0 : topicsDone / topics.length;

  String get countdownLabel {
    final d = daysUntil;
    if (d < 0) return 'Done';
    if (d == 0) return 'Today';
    if (d == 1) return 'Tomorrow';
    return 'in $d days';
  }

  Exam copyWith({
    String? title,
    String? subjectId,
    DateTime? date,
    String? room,
    String? note,
    List<ChecklistItem>? topics,
    bool clearSubject = false,
    bool clearRoom = false,
    bool clearNote = false,
  }) {
    return Exam(
      id: id,
      title: title ?? this.title,
      subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
      date: date ?? this.date,
      room: clearRoom ? null : (room ?? this.room),
      note: clearNote ? null : (note ?? this.note),
      topics: topics ?? this.topics,
      createdAt: createdAt,
      semesterId: semesterId,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'subjectId': subjectId,
        'date': Timestamp.fromDate(date),
        'room': room,
        'note': note,
        'topics': ChecklistItem.listToMap(topics),
        if (semesterId != null) 'semesterId': semesterId,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory Exam.fromMap(String id, Map<String, dynamic> map) {
    return Exam(
      id: id,
      title: (map['title'] as String?) ?? 'Exam',
      subjectId: map['subjectId'] as String?,
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      room: map['room'] as String?,
      note: map['note'] as String?,
      topics: ChecklistItem.listFrom(map['topics']),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      semesterId: map['semesterId'] as String?,
    );
  }
}
