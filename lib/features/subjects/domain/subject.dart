import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/validators.dart';

/// A named external resource attached to a subject (book, drive link, etc.).
class ResourceLink {
  final String title;
  final String url;

  const ResourceLink({required this.title, required this.url});

  Map<String, dynamic> toMap() => {'title': title, 'url': url};

  factory ResourceLink.fromMap(Map<String, dynamic> map) => ResourceLink(
        title: (map['title'] as String?) ?? '',
        url: (map['url'] as String?) ?? '',
      );
}

/// A subject/course. Stored at users/{uid}/subjects/{id}.
class Subject {
  final String id;
  final String name;
  final int colorHex; // ARGB int
  final String? professor;
  final int? credits;
  final String? classLink; // Zoom/Meet/Teams
  final String? room; // default room / location
  final List<ResourceLink> resourceLinks;

  /// Counter-based attendance. Only classes you explicitly mark are counted:
  /// [attended] (present) and [absent]. Unmarked classes count toward nothing.
  final int attended;
  final int absent;

  /// Classes that were cancelled — tracked separately and NOT counted toward
  /// the attendance percentage.
  final int cancelled;

  /// Per-subject attendance target (0–100). `null` means "follow the user's
  /// global target". Lets labs/theory carry different requirements (e.g. 80%
  /// vs 75%). Resolve with [effectiveTarget].
  final double? targetPercent;

  /// Optional course/term duration.
  final DateTime? startDate;
  final DateTime? endDate;

  /// Key into [SubjectIcons.catalog] for this subject's icon (null = default).
  final String? iconKey;

  /// The archived semester this subject belongs to. `null` = the current
  /// semester (everything created before semesters existed is current too).
  /// Only written by [SemesterRepository]; [toMap] omits it when null so a
  /// normal edit can never accidentally un-archive a subject.
  final String? semesterId;

  /// Official final result for an archived subject (optional, entered by the
  /// student from their marksheet). Overrides the grade computed from
  /// individual assessments when working out SGPA/CGPA.
  final String? finalGrade; // e.g. "A+", "O", "B"
  final double? finalGradePoints; // on the user's GPA scale

  final DateTime? createdAt;

  const Subject({
    required this.id,
    required this.name,
    required this.colorHex,
    this.professor,
    this.credits,
    this.classLink,
    this.room,
    this.resourceLinks = const [],
    this.attended = 0,
    this.absent = 0,
    this.cancelled = 0,
    this.targetPercent,
    this.startDate,
    this.endDate,
    this.iconKey,
    this.semesterId,
    this.finalGrade,
    this.finalGradePoints,
    this.createdAt,
  });

  /// True when this subject was archived by a semester wrap-up.
  bool get isArchived => semesterId != null;

  /// Total classes counted toward the percentage (only present + absent).
  int get held => attended + absent;
  double get percent => held == 0 ? 0 : (attended / held) * 100.0;
  int get missed => absent;

  /// This subject's effective attendance target: its own [targetPercent] when
  /// set, otherwise the supplied global [fallback].
  double effectiveTarget(double fallback) => targetPercent ?? fallback;

  /// True when this subject overrides the global target.
  bool get hasCustomTarget => targetPercent != null;

  // --- Course-timeline helpers (available when both dates are set) ----------

  bool get hasTerm => startDate != null && endDate != null;

  /// Whole days from today until the course ends (negative if past).
  int? get daysUntilEnd {
    if (endDate == null) return null;
    final now = DateTime.now();
    return DateTime(endDate!.year, endDate!.month, endDate!.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  int? get weeksTotal {
    if (!hasTerm) return null;
    final d = endDate!.difference(startDate!).inDays;
    return d <= 0 ? 1 : (d / 7).ceil();
  }

  int? get weekOfTerm {
    if (!hasTerm) return null;
    final elapsed = DateTime.now().difference(startDate!).inDays;
    if (elapsed < 0) return 0; // not started yet
    return ((elapsed / 7).floor() + 1).clamp(1, weeksTotal ?? 1);
  }

  /// 0..1 fraction of the term elapsed (null when no term set).
  double? get termProgress {
    if (!hasTerm) return null;
    final total = endDate!.difference(startDate!).inDays;
    if (total <= 0) return 1;
    final elapsed = DateTime.now().difference(startDate!).inDays;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  Subject copyWith({
    String? name,
    int? colorHex,
    String? professor,
    int? credits,
    String? classLink,
    String? room,
    List<ResourceLink>? resourceLinks,
    int? attended,
    int? absent,
    int? cancelled,
    double? targetPercent,
    DateTime? startDate,
    DateTime? endDate,
    String? iconKey,
    bool clearStartDate = false,
    bool clearEndDate = false,
    bool clearTarget = false,
  }) {
    return Subject(
      id: id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      professor: professor ?? this.professor,
      credits: credits ?? this.credits,
      classLink: classLink ?? this.classLink,
      room: room ?? this.room,
      resourceLinks: resourceLinks ?? this.resourceLinks,
      attended: attended ?? this.attended,
      absent: absent ?? this.absent,
      cancelled: cancelled ?? this.cancelled,
      targetPercent: clearTarget ? null : (targetPercent ?? this.targetPercent),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      iconKey: iconKey ?? this.iconKey,
      semesterId: semesterId,
      finalGrade: finalGrade,
      finalGradePoints: finalGradePoints,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': Validators.sanitizeText(name, maxLength: 120),
        'colorHex': colorHex,
        'professor': professor == null
            ? null
            : Validators.sanitizeText(professor, maxLength: 120),
        'credits': credits,
        'classLink': classLink,
        'room': room,
        'resourceLinks': resourceLinks.map((e) => e.toMap()).toList(),
        'attended': attended,
        'absent': absent,
        'held': held, // kept for backward compatibility
        'cancelled': cancelled,
        'targetPercent': targetPercent,
        'startDate':
            startDate != null ? Timestamp.fromDate(startDate!) : null,
        'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
        'iconKey': iconKey,
        // Archive fields are only written when set (see [semesterId]).
        if (semesterId != null) 'semesterId': semesterId,
        if (finalGrade != null) 'finalGrade': finalGrade,
        if (finalGradePoints != null) 'finalGradePoints': finalGradePoints,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory Subject.fromMap(String id, Map<String, dynamic> map) {
    final attended = (map['attended'] as num?)?.toInt() ?? 0;
    // Prefer the explicit 'absent' counter. Migrate older docs that only had
    // 'held' by deriving absent = held - attended (never negative).
    final absent = (map['absent'] as num?)?.toInt() ??
        (((map['held'] as num?)?.toInt() ?? attended) - attended)
            .clamp(0, 100000);
    return Subject(
      id: id,
      name: Validators.sanitizeText((map['name'] as String?) ?? 'Untitled',
          maxLength: 120),
      colorHex: (map['colorHex'] as num?)?.toInt() ?? 0xFF6366F1,
      professor: map['professor'] == null
          ? null
          : Validators.sanitizeText(map['professor'] as String, maxLength: 120),
      credits: (map['credits'] as num?)?.toInt(),
      classLink: map['classLink'] as String?,
      room: map['room'] as String?,
      resourceLinks: ((map['resourceLinks'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ResourceLink.fromMap)
          .toList(),
      attended: attended,
      absent: absent,
      cancelled: (map['cancelled'] as num?)?.toInt() ?? 0,
      targetPercent: (map['targetPercent'] as num?)?.toDouble(),
      startDate: (map['startDate'] as Timestamp?)?.toDate(),
      endDate: (map['endDate'] as Timestamp?)?.toDate(),
      iconKey: map['iconKey'] as String?,
      semesterId: map['semesterId'] as String?,
      finalGrade: map['finalGrade'] as String?,
      finalGradePoints: (map['finalGradePoints'] as num?)?.toDouble(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
