import '../../../core/constants/app_constants.dart';

/// One parsed session inside a parsed subject (editable in the review screen).
class ParsedSession {
  String day; // "Monday".."Sunday"
  String start; // "HH:MM"
  String end; // "HH:MM"
  String? room;

  /// When set, this is a ONE-OFF session on this specific calendar date rather
  /// than a weekly-recurring one. Keeps single events (a one-time webinar,
  /// make-up class, etc.) from repeating every week / showing on the import day.
  DateTime? date;

  ParsedSession({
    required this.day,
    required this.start,
    required this.end,
    this.room,
    this.date,
  });

  int? get dayIndex => Weekdays.parse(day);

  /// True when this is a weekly-recurring session (no specific date attached).
  bool get isRecurring => date == null;

  factory ParsedSession.fromJson(Map<String, dynamic> json) => ParsedSession(
        day: (json['day'] as String?) ?? 'Monday',
        start: (json['start'] as String?) ?? '09:00',
        end: (json['end'] as String?) ?? '10:00',
        room: json['room'] as String?,
      );
}

/// One parsed task/assignment/deadline extracted from a one-off calendar event
/// (editable in the review screen). Committed to the Tasks list rather than to
/// attendance, so homework/quizzes/submissions don't inflate attendance.
class ParsedTask {
  String title;
  DateTime? due;
  String? link;
  bool include; // user toggle in review screen

  ParsedTask({
    required this.title,
    this.due,
    this.link,
    this.include = true,
  });
}

/// One parsed subject with its sessions.
class ParsedSubject {
  String name;
  String? professor;
  String? classLink; // Zoom/Meet/Teams link (optional)
  DateTime? startDate; // optional term start
  DateTime? endDate; // optional term end
  List<ParsedSession> sessions;
  bool include; // user toggle in review screen

  ParsedSubject({
    required this.name,
    this.professor,
    this.classLink,
    this.startDate,
    this.endDate,
    required this.sessions,
    this.include = true,
  });

  factory ParsedSubject.fromJson(Map<String, dynamic> json) => ParsedSubject(
        name: (json['name'] as String?) ?? 'Untitled',
        professor: json['professor'] as String?,
        classLink: json['classLink'] as String? ?? json['link'] as String?,
        startDate: _parseDate(json['startDate']),
        endDate: _parseDate(json['endDate']),
        sessions: ((json['sessions'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ParsedSession.fromJson)
            .toList(),
      );

  static DateTime? _parseDate(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }
}

/// Full result returned by the parseSchedule Cloud Function.
class ParsedSchedule {
  final List<ParsedSubject> subjects;

  /// One-off items that look like assignments/deadlines rather than classes.
  /// Routed to the Tasks list on commit (not to attendance).
  final List<ParsedTask> tasks;

  final String confidence; // high | medium | low

  ParsedSchedule({
    required this.subjects,
    this.tasks = const [],
    required this.confidence,
  });

  factory ParsedSchedule.fromJson(Map<String, dynamic> json) => ParsedSchedule(
        subjects: ((json['subjects'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ParsedSubject.fromJson)
            .toList(),
        confidence: (json['confidence'] as String?) ?? 'low',
      );

  bool get isEmpty => subjects.isEmpty && tasks.isEmpty;

  // ── Local draft format ────────────────────────────────────────────────────
  // A full round-trip of everything the review screen can edit (include
  // toggles, one-off session dates, term dates, tasks), used to keep an
  // unsaved import across the app being killed. Separate from [fromJson],
  // which reads the Cloud Function's reply and must stay as it is.

  Map<String, dynamic> toDraftJson() => {
        'confidence': confidence,
        'subjects': [
          for (final s in subjects)
            {
              'name': s.name,
              'professor': s.professor,
              'classLink': s.classLink,
              'startDate': s.startDate?.toIso8601String(),
              'endDate': s.endDate?.toIso8601String(),
              'include': s.include,
              'sessions': [
                for (final x in s.sessions)
                  {
                    'day': x.day,
                    'start': x.start,
                    'end': x.end,
                    'room': x.room,
                    'date': x.date?.toIso8601String(),
                  },
              ],
            },
        ],
        'tasks': [
          for (final t in tasks)
            {
              'title': t.title,
              'due': t.due?.toIso8601String(),
              'link': t.link,
              'include': t.include,
            },
        ],
      };

  factory ParsedSchedule.fromDraftJson(Map<String, dynamic> json) {
    DateTime? date(dynamic v) => v is String ? DateTime.tryParse(v) : null;
    List<Map<String, dynamic>> maps(dynamic v) =>
        ((v as List<dynamic>?) ?? const []).whereType<Map<String, dynamic>>().toList();
    return ParsedSchedule(
      confidence: (json['confidence'] as String?) ?? 'low',
      subjects: [
        for (final s in maps(json['subjects']))
          ParsedSubject(
            name: (s['name'] as String?) ?? 'Untitled',
            professor: s['professor'] as String?,
            classLink: s['classLink'] as String?,
            startDate: date(s['startDate']),
            endDate: date(s['endDate']),
            include: (s['include'] as bool?) ?? true,
            sessions: [
              for (final x in maps(s['sessions']))
                ParsedSession(
                  day: (x['day'] as String?) ?? 'Monday',
                  start: (x['start'] as String?) ?? '09:00',
                  end: (x['end'] as String?) ?? '10:00',
                  room: x['room'] as String?,
                  date: date(x['date']),
                ),
            ],
          ),
      ],
      tasks: [
        for (final t in maps(json['tasks']))
          ParsedTask(
            title: (t['title'] as String?) ?? '',
            due: date(t['due']),
            link: t['link'] as String?,
            include: (t['include'] as bool?) ?? true,
          ),
      ],
    );
  }
}
