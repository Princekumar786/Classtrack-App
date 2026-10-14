import 'package:flutter/material.dart';

/// The student's self-reported starting point. Drives how much time the AI
/// budgets per topic and which topics it can safely trim.
enum KnowledgeLevel { zero, basics, intermediate, advanced }

extension KnowledgeLevelX on KnowledgeLevel {
  String get title {
    switch (this) {
      case KnowledgeLevel.zero:
        return 'Starting from zero';
      case KnowledgeLevel.basics:
        return 'Know the basics';
      case KnowledgeLevel.intermediate:
        return 'Intermediate';
      case KnowledgeLevel.advanced:
        return 'Advanced';
    }
  }

  String get subtitle {
    switch (this) {
      case KnowledgeLevel.zero:
        return "I don't know the fundamentals.";
      case KnowledgeLevel.basics:
        return 'I understand the fundamentals but need to build further.';
      case KnowledgeLevel.intermediate:
        return 'I understand most concepts and want to go deeper.';
      case KnowledgeLevel.advanced:
        return 'I already know a lot and want focused, advanced topics.';
    }
  }

  /// Short label used in summaries ("Starting from basics").
  String get shortLabel {
    switch (this) {
      case KnowledgeLevel.zero:
        return 'Starting from zero';
      case KnowledgeLevel.basics:
        return 'Starting from basics';
      case KnowledgeLevel.intermediate:
        return 'Intermediate level';
      case KnowledgeLevel.advanced:
        return 'Advanced level';
    }
  }

  /// Multiplier applied to a topic's baseline minutes. A beginner needs more
  /// time on the same topic than someone already advanced.
  double get timeFactor {
    switch (this) {
      case KnowledgeLevel.zero:
        return 1.15;
      case KnowledgeLevel.basics:
        return 1.0;
      case KnowledgeLevel.intermediate:
        return 0.85;
      case KnowledgeLevel.advanced:
        return 0.7;
    }
  }
}

/// What the student is optimising for — kept conceptually separate from their
/// current [KnowledgeLevel]. Used only to bias topic selection and ordering,
/// never to generate study material.
enum LearningGoal { syllabus, exam, fundamentals, interview, project, explore }

extension LearningGoalX on LearningGoal {
  String get title {
    switch (this) {
      case LearningGoal.syllabus:
        return 'Complete my syllabus';
      case LearningGoal.exam:
        return 'Prepare for an exam';
      case LearningGoal.fundamentals:
        return 'Build strong fundamentals';
      case LearningGoal.interview:
        return 'Interview preparation';
      case LearningGoal.project:
        return 'Learn for a project';
      case LearningGoal.explore:
        return 'Explore the subject';
    }
  }

  String get subtitle {
    switch (this) {
      case LearningGoal.syllabus:
        return 'Cover the topics systematically.';
      case LearningGoal.exam:
        return 'Prioritize important topics and revision.';
      case LearningGoal.fundamentals:
        return 'Develop a solid understanding.';
      case LearningGoal.interview:
        return 'Focus on relevant concepts and problem-solving.';
      case LearningGoal.project:
        return 'Focus on what you need to build.';
      case LearningGoal.explore:
        return 'Build a broad understanding without a fixed outcome.';
    }
  }

  IconData get icon {
    switch (this) {
      case LearningGoal.syllabus:
        return Icons.checklist_rounded;
      case LearningGoal.exam:
        return Icons.school_outlined;
      case LearningGoal.fundamentals:
        return Icons.foundation_rounded;
      case LearningGoal.interview:
        return Icons.record_voice_over_outlined;
      case LearningGoal.project:
        return Icons.build_outlined;
      case LearningGoal.explore:
        return Icons.travel_explore_rounded;
    }
  }
}

/// The jurisdiction / curriculum a plan should be tailored to. Only matters for
/// region-sensitive subjects (law, governance, tax, accounting standards) — for
/// everything else the topics are the same worldwide.
enum StudyRegion { global, india, unitedStates, unitedKingdom }

extension StudyRegionX on StudyRegion {
  String get label {
    switch (this) {
      case StudyRegion.global:
        return 'Global / other';
      case StudyRegion.india:
        return 'India';
      case StudyRegion.unitedStates:
        return 'United States';
      case StudyRegion.unitedKingdom:
        return 'United Kingdom';
    }
  }

  /// Short tag used in summaries/pills.
  String get short {
    switch (this) {
      case StudyRegion.global:
        return 'Global';
      case StudyRegion.india:
        return 'India';
      case StudyRegion.unitedStates:
        return 'US';
      case StudyRegion.unitedKingdom:
        return 'UK';
    }
  }

  /// Best-effort mapping from a free-text profile country name.
  static StudyRegion fromCountryName(String? country) {
    if (country == null) return StudyRegion.global;
    final n = country.trim().toLowerCase();
    if (n.isEmpty) return StudyRegion.global;
    if (n.contains('india')) return StudyRegion.india;
    if (n.contains('united states') ||
        n == 'us' ||
        n == 'usa' ||
        n.contains('america')) {
      return StudyRegion.unitedStates;
    }
    if (n.contains('united kingdom') ||
        n == 'uk' ||
        n.contains('britain') ||
        n.contains('england') ||
        n.contains('scotland') ||
        n.contains('wales')) {
      return StudyRegion.unitedKingdom;
    }
    return StudyRegion.global;
  }
}

/// The academic level / lens the plan is for. The same subject is framed very
/// differently for, say, an LLB student vs an MBA student.
enum StudyProgram { general, school, undergraduate, postgraduate, professional }

extension StudyProgramX on StudyProgram {
  String get title {
    switch (this) {
      case StudyProgram.general:
        return 'General learning';
      case StudyProgram.school:
        return 'School / board';
      case StudyProgram.undergraduate:
        return 'Undergraduate';
      case StudyProgram.postgraduate:
        return 'Postgraduate / MBA';
      case StudyProgram.professional:
        return 'Professional exam';
    }
  }

  String get subtitle {
    switch (this) {
      case StudyProgram.general:
        return 'Just want to learn it well.';
      case StudyProgram.school:
        return 'Class 11–12 / board exam level.';
      case StudyProgram.undergraduate:
        return "Bachelor's — e.g. BA, BSc, LLB, B.Tech.";
      case StudyProgram.postgraduate:
        return "Master's — applied, managerial depth (MBA, MSc).";
      case StudyProgram.professional:
        return 'CA, CS, CFA, UPSC and similar.';
    }
  }

  String get short {
    switch (this) {
      case StudyProgram.general:
        return 'General';
      case StudyProgram.school:
        return 'School';
      case StudyProgram.undergraduate:
        return 'Undergrad';
      case StudyProgram.postgraduate:
        return 'PG / MBA';
      case StudyProgram.professional:
        return 'Professional';
    }
  }

  IconData get icon {
    switch (this) {
      case StudyProgram.general:
        return Icons.lightbulb_outline_rounded;
      case StudyProgram.school:
        return Icons.backpack_outlined;
      case StudyProgram.undergraduate:
        return Icons.school_outlined;
      case StudyProgram.postgraduate:
        return Icons.workspace_premium_outlined;
      case StudyProgram.professional:
        return Icons.badge_outlined;
    }
  }
}

/// Progress state of a single topic.
enum TopicStatus { notStarted, learning, completed }

extension TopicStatusX on TopicStatus {
  String get label {
    switch (this) {
      case TopicStatus.notStarted:
        return 'Not started';
      case TopicStatus.learning:
        return 'Still learning';
      case TopicStatus.completed:
        return 'Completed';
    }
  }
}

/// Relative cognitive load of a topic. Inferred by the planner and used both to
/// sequence work (front-load easier wins, avoid stacking hard topics on one
/// day) and to give the student an honest heads-up.
enum TopicDifficulty { easy, medium, hard }

extension TopicDifficultyX on TopicDifficulty {
  String get label {
    switch (this) {
      case TopicDifficulty.easy:
        return 'Easy';
      case TopicDifficulty.medium:
        return 'Medium';
      case TopicDifficulty.hard:
        return 'Challenging';
    }
  }

  /// Relative weight used when balancing a day's cognitive load.
  int get weight {
    switch (this) {
      case TopicDifficulty.easy:
        return 1;
      case TopicDifficulty.medium:
        return 2;
      case TopicDifficulty.hard:
        return 3;
    }
  }
}

/// One section of a topic's curriculum breakdown — a titled chunk with its own
/// time estimate and a list of subtopics to cover. This is a map of WHAT to
/// study, never the study material itself.
class TopicSection {
  final String title;
  final int minutes;
  final List<String> points;
  const TopicSection({
    required this.title,
    required this.minutes,
    this.points = const [],
  });

  Map<String, dynamic> toJson() =>
      {'title': title, 'minutes': minutes, 'points': points};

  factory TopicSection.fromJson(Map<String, dynamic> j) => TopicSection(
        title: j['title'] as String,
        minutes: (j['minutes'] as num?)?.toInt() ?? 15,
        points:
            (j['points'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

/// One learnable unit in a plan. Holds only *what* to cover and an estimate of
/// how long — never the study material itself.
class LearningTopic {
  final String id;
  final String title;

  /// AI estimate, in minutes. Always presented as an estimate ("~"), never as
  /// an exact figure.
  final int estMinutes;

  /// Bullet points describing what the student needs to cover. NOT notes.
  final List<String> objectives;

  /// The curriculum unit this topic belongs to (e.g. "Foundations",
  /// "Contract Law"). Used to group the roadmap.
  final String unit;

  /// Detailed curriculum breakdown shown on the Topic Detail screen.
  final List<TopicSection> sections;

  /// "Before marking complete, you should be able to…" — the bar for done.
  final List<String> completionCriteria;

  /// Relative difficulty, used for sequencing and shown to the student.
  final TopicDifficulty difficulty;

  /// True for spaced-review / consolidation checkpoints the planner inserts —
  /// these revisit earlier material rather than introduce new topics.
  final bool isReview;

  /// Real minutes the student has logged studying this topic (via the focus
  /// timer). Used to learn the student's true pace and recalibrate estimates.
  int actualMinutes;

  /// Study links the student attached (videos, articles, notes). http(s) only.
  final List<String> links;

  /// Subtopics the student has ticked off, by [subtopicKey]. Lets a student
  /// mark progress inside a topic before the whole topic is done.
  final Set<String> doneSubtopics;

  TopicStatus status;

  LearningTopic({
    required this.id,
    required this.title,
    required this.estMinutes,
    this.objectives = const [],
    this.unit = 'Topics',
    this.sections = const [],
    this.completionCriteria = const [],
    this.difficulty = TopicDifficulty.medium,
    this.isReview = false,
    this.actualMinutes = 0,
    this.links = const [],
    Set<String>? doneSubtopics,
    this.status = TopicStatus.notStarted,
  }) : doneSubtopics = doneSubtopics ?? <String>{};

  bool get isDone => status == TopicStatus.completed;

  /// Stable id for one subtopic: its section and its text.
  static String subtopicKey(String section, String point) => '$section::$point';

  /// Every checkable subtopic, in display order: each section's points (or
  /// the objectives when there is no breakdown). Duplicates are dropped.
  List<({String key, String section, String text})> get subtopics {
    final out = <({String key, String section, String text})>[];
    final seen = <String>{};
    void add(String section, String text) {
      final t = text.trim();
      if (t.isEmpty) return;
      final key = subtopicKey(section, t);
      if (seen.add(key)) out.add((key: key, section: section, text: t));
    }

    if (sections.isNotEmpty) {
      for (final s in sections) {
        for (final p in s.points) {
          add(s.title, p);
        }
      }
    } else {
      for (final o in objectives) {
        add("What you'll cover", o);
      }
    }
    return out;
  }

  int get subtopicTotal => subtopics.length;

  /// Ticked subtopics that still exist (a completed topic counts as all).
  int get subtopicsDone {
    if (isDone) return subtopicTotal;
    final keys = {for (final s in subtopics) s.key};
    return doneSubtopics.where(keys.contains).length;
  }

  /// 0..1 progress: 1 when complete, else the share of subtopics ticked.
  double get progress {
    if (isDone) return 1;
    final total = subtopicTotal;
    return total == 0 ? 0 : subtopicsDone / total;
  }

  LearningTopic copyWith({
    String? title,
    int? estMinutes,
    List<String>? objectives,
    String? unit,
    List<TopicSection>? sections,
    List<String>? completionCriteria,
    TopicDifficulty? difficulty,
    bool? isReview,
    int? actualMinutes,
    List<String>? links,
    Set<String>? doneSubtopics,
    TopicStatus? status,
  }) =>
      LearningTopic(
        id: id,
        title: title ?? this.title,
        estMinutes: estMinutes ?? this.estMinutes,
        objectives: objectives ?? this.objectives,
        unit: unit ?? this.unit,
        sections: sections ?? this.sections,
        completionCriteria: completionCriteria ?? this.completionCriteria,
        difficulty: difficulty ?? this.difficulty,
        isReview: isReview ?? this.isReview,
        actualMinutes: actualMinutes ?? this.actualMinutes,
        links: links ?? this.links,
        doneSubtopics: {...(doneSubtopics ?? this.doneSubtopics)},
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'estMinutes': estMinutes,
        'objectives': objectives,
        'unit': unit,
        'sections': sections.map((s) => s.toJson()).toList(),
        'completionCriteria': completionCriteria,
        'difficulty': difficulty.index,
        'isReview': isReview,
        'actualMinutes': actualMinutes,
        if (links.isNotEmpty) 'links': links,
        if (doneSubtopics.isNotEmpty) 'doneSubtopics': doneSubtopics.toList(),
        'status': status.index,
      };

  factory LearningTopic.fromJson(Map<String, dynamic> j) => LearningTopic(
        id: j['id'] as String,
        title: j['title'] as String,
        estMinutes: (j['estMinutes'] as num).toInt(),
        objectives:
            (j['objectives'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        unit: (j['unit'] as String?) ?? 'Topics',
        sections: (j['sections'] as List?)
                ?.map((e) => TopicSection.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        completionCriteria: (j['completionCriteria'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        difficulty:
            TopicDifficulty.values[(j['difficulty'] as num?)?.toInt() ?? 1],
        isReview: j['isReview'] == true,
        actualMinutes: (j['actualMinutes'] as num?)?.toInt() ?? 0,
        links: (j['links'] as List?)
                ?.map((e) => e.toString())
                .where(isStudyLink)
                .toList() ??
            const [],
        doneSubtopics:
            (j['doneSubtopics'] as List?)?.map((e) => e.toString()).toSet(),
        status: TopicStatus.values[(j['status'] as num?)?.toInt() ?? 0],
      );
}

/// True for an absolute http(s) URL with a host — the only links we store or
/// open (blocks `javascript:`, `file:`, intent URLs etc.).
bool isStudyLink(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      value.length <= 2000;
}

/// Normalises what a student typed into a storable link, or null if invalid.
/// Adds `https://` when they typed a bare domain ("youtube.com/watch?v=…").
String? normalizeStudyLink(String raw) {
  var v = raw.trim();
  if (v.isEmpty) return null;
  if (!v.contains('://')) v = 'https://$v';
  return isStudyLink(v) && v.contains('.') ? v : null;
}

/// A single study day inside a week — an ordered set of topic ids to cover.
class DayPlan {
  final int dayNumber; // 1-based across the whole plan
  final DateTime date;
  final List<String> topicIds;

  /// Marked complete explicitly by the student, independent of per-topic ticks.
  bool completed;

  DayPlan({
    required this.dayNumber,
    required this.date,
    required this.topicIds,
    this.completed = false,
  });

  Map<String, dynamic> toJson() => {
        'dayNumber': dayNumber,
        'date': date.toIso8601String(),
        'topicIds': topicIds,
        'completed': completed,
      };

  factory DayPlan.fromJson(Map<String, dynamic> j) => DayPlan(
        dayNumber: (j['dayNumber'] as num).toInt(),
        date: DateTime.parse(j['date'] as String),
        topicIds:
            (j['topicIds'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        completed: j['completed'] == true,
      );
}

/// A themed grouping of days ("Week 1 — Foundations").
class WeekPlan {
  final int weekNumber;
  final String title;
  final List<DayPlan> days;

  WeekPlan({
    required this.weekNumber,
    required this.title,
    required this.days,
  });

  Map<String, dynamic> toJson() => {
        'weekNumber': weekNumber,
        'title': title,
        'days': days.map((d) => d.toJson()).toList(),
      };

  factory WeekPlan.fromJson(Map<String, dynamic> j) => WeekPlan(
        weekNumber: (j['weekNumber'] as num).toInt(),
        title: j['title'] as String,
        days: (j['days'] as List)
            .map((e) => DayPlan.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A curriculum unit — a named group of consecutive topics ("Foundations",
/// "Contract Law", "Revision"). Derived from each topic's [LearningTopic.unit].
class PlanUnit {
  final String title;
  final List<LearningTopic> topics;
  const PlanUnit({required this.title, required this.topics});

  int get totalMinutes => topics.fold(0, (s, t) => s + t.estMinutes);
  int get completed => topics.where((t) => t.isDone).length;
  double get percent =>
      topics.isEmpty ? 0 : (completed / topics.length) * 100;
}

/// A complete, adaptive learning plan for one subject or topic.
class LearningPlan {
  final String id;
  final String subject;

  /// True when the student entered a narrow topic ("Normalization in DBMS")
  /// rather than a whole subject.
  final bool specificTopic;
  final KnowledgeLevel level;
  final LearningGoal goal;
  final bool hasSyllabus;

  /// Minutes the student can study on an active day.
  final int dailyMinutes;

  /// Weekdays the student will study (DateTime.monday..DateTime.sunday).
  final Set<int> studyDays;

  final DateTime targetDate;
  final DateTime createdAt;
  final String? note;

  final List<LearningTopic> topics;
  final List<WeekPlan> weeks;

  /// Jurisdiction / curriculum the plan is tailored to.
  final StudyRegion region;

  /// Academic level / lens (e.g. undergraduate vs MBA).
  final StudyProgram program;

  /// Whether the student has paused this plan.
  final bool paused;

  LearningPlan({
    required this.id,
    required this.subject,
    required this.specificTopic,
    required this.level,
    required this.goal,
    required this.hasSyllabus,
    required this.dailyMinutes,
    required this.studyDays,
    required this.targetDate,
    required this.createdAt,
    required this.topics,
    required this.weeks,
    this.region = StudyRegion.global,
    this.program = StudyProgram.general,
    this.paused = false,
    this.note,
  });

  int get totalTopics => topics.length;
  int get completedTopics => topics.where((t) => t.isDone).length;
  int get remainingTopics => totalTopics - completedTopics;

  /// Overall progress 0..100. Counts ticked subtopics too, so the ring moves
  /// as the student works through a topic, not only when it's fully done.
  double get percent => totalTopics == 0
      ? 0
      : topics.fold<double>(0, (s, t) => s + t.progress) / totalTopics * 100;

  /// Total estimated minutes across every topic.
  int get totalMinutes => topics.fold(0, (s, t) => s + t.estMinutes);

  /// Estimated minutes left for the not-yet-completed topics.
  int get remainingMinutes =>
      topics.where((t) => !t.isDone).fold(0, (s, t) => s + t.estMinutes);

  /// Whole days between now and the target date (never negative).
  int get daysToTarget {
    final now = DateTime.now();
    final d = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final t = DateTime(now.year, now.month, now.day);
    final diff = d.difference(t).inDays;
    return diff < 0 ? 0 : diff;
  }

  LearningTopic? topicById(String id) {
    for (final t in topics) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 1-based position of a topic in the overall sequence, or 0 if unknown.
  int positionOf(String topicId) {
    final i = topics.indexWhere((t) => t.id == topicId);
    return i < 0 ? 0 : i + 1;
  }

  /// Topics grouped into curriculum units, preserving sequence order.
  List<PlanUnit> get units {
    final out = <PlanUnit>[];
    for (final t in topics) {
      if (out.isNotEmpty && out.last.title == t.unit) {
        out.last.topics.add(t);
      } else {
        out.add(PlanUnit(title: t.unit, topics: [t]));
      }
    }
    return out;
  }

  /// The first day that still has an unfinished topic — the natural "next" day.
  DayPlan? get nextIncompleteDay {
    for (final w in weeks) {
      for (final d in w.days) {
        final hasOpen = d.topicIds
            .map(topicById)
            .any((t) => t != null && !t.isDone);
        if (hasOpen && !d.completed) return d;
      }
    }
    return null;
  }

  /// Total real minutes logged across all topics.
  int get totalStudiedMinutes =>
      topics.fold(0, (s, t) => s + t.actualMinutes);

  /// The student's observed pace: logged minutes ÷ estimated minutes on the
  /// topics they've actually worked on. >1 means they take longer than
  /// estimated; ~1 means estimates are accurate. Null until there's real data.
  double? get paceFactor {
    var est = 0;
    var act = 0;
    for (final t in topics) {
      if (t.actualMinutes > 0) {
        est += t.estMinutes;
        act += t.actualMinutes;
      }
    }
    if (est == 0 || act == 0) return null;
    return act / est;
  }

  /// The day the student should work on today: an incomplete day dated today or
  /// overdue, else the next incomplete day. Null when the plan is finished.
  DayPlan? get dayForToday {
    if (paused) return null;
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    DayPlan? firstOpen;
    for (final w in weeks) {
      for (final d in w.days) {
        final hasOpen =
            d.topicIds.map(topicById).any((x) => x != null && !x.isDone);
        if (!hasOpen || d.completed) continue;
        firstOpen ??= d;
        final dd = DateTime(d.date.year, d.date.month, d.date.day);
        if (!dd.isAfter(t0)) return d; // due today or overdue
      }
    }
    return firstOpen;
  }

  /// Every study day in order, across the whole plan (no week grouping).
  List<DayPlan> get allDays => [for (final w in weeks) ...w.days];

  /// True for a plan the student built by hand ("Build your own plan"):
  /// AI-only details (level, goal, "why this order") don't apply to it.
  bool get isCustom =>
      topics.isNotEmpty && topics.every((t) => t.unit == 'My topics');

  WeekPlan? weekOfDay(int dayNumber) {
    for (final w in weeks) {
      if (w.days.any((d) => d.dayNumber == dayNumber)) return w;
    }
    return null;
  }

  /// Returns a new [LearningPlan] with the given overrides. Used to give a
  /// mutated plan a fresh object identity so Riverpod's `learningPlanByIdProvider`
  /// (which dedupes by identity) notifies its listeners and screens rebuild.
  LearningPlan copyWith({
    String? subject,
    KnowledgeLevel? level,
    LearningGoal? goal,
    int? dailyMinutes,
    Set<int>? studyDays,
    DateTime? targetDate,
    String? note,
    List<LearningTopic>? topics,
    List<WeekPlan>? weeks,
    StudyRegion? region,
    StudyProgram? program,
    bool? paused,
  }) {
    return LearningPlan(
      id: id,
      subject: subject ?? this.subject,
      specificTopic: specificTopic,
      level: level ?? this.level,
      goal: goal ?? this.goal,
      hasSyllabus: hasSyllabus,
      dailyMinutes: dailyMinutes ?? this.dailyMinutes,
      studyDays: studyDays ?? this.studyDays,
      targetDate: targetDate ?? this.targetDate,
      createdAt: createdAt,
      note: note ?? this.note,
      topics: topics ?? this.topics,
      weeks: weeks ?? this.weeks,
      region: region ?? this.region,
      program: program ?? this.program,
      paused: paused ?? this.paused,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'specificTopic': specificTopic,
        'level': level.index,
        'goal': goal.index,
        'hasSyllabus': hasSyllabus,
        'dailyMinutes': dailyMinutes,
        'studyDays': studyDays.toList(),
        'targetDate': targetDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'note': note,
        'region': region.index,
        'program': program.index,
        'paused': paused,
        'topics': topics.map((t) => t.toJson()).toList(),
        'weeks': weeks.map((w) => w.toJson()).toList(),
      };

  factory LearningPlan.fromJson(Map<String, dynamic> j) => LearningPlan(
        id: j['id'] as String,
        subject: j['subject'] as String,
        specificTopic: j['specificTopic'] == true,
        level: KnowledgeLevel.values[(j['level'] as num?)?.toInt() ?? 0],
        goal: LearningGoal.values[(j['goal'] as num?)?.toInt() ?? 0],
        hasSyllabus: j['hasSyllabus'] == true,
        dailyMinutes: (j['dailyMinutes'] as num?)?.toInt() ?? 60,
        studyDays: ((j['studyDays'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toSet(),
        targetDate: DateTime.parse(j['targetDate'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        note: j['note'] as String?,
        region: StudyRegion.values[(j['region'] as num?)?.toInt() ?? 0],
        program: StudyProgram.values[(j['program'] as num?)?.toInt() ?? 0],
        paused: j['paused'] == true,
        topics: (j['topics'] as List)
            .map((e) => LearningTopic.fromJson(e as Map<String, dynamic>))
            .toList(),
        weeks: (j['weeks'] as List)
            .map((e) => WeekPlan.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Formats a minute count as a friendly estimate, e.g. 90 → "1h 30m".
String formatEstMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}


/// Sets a topic's status and keeps its subtopic ticks consistent:
/// completed ticks every subtopic, "not started" clears them, "still
/// learning" leaves them as they are.
void applyTopicStatus(LearningTopic topic, TopicStatus status) {
  topic.status = status;
  if (status == TopicStatus.completed) {
    topic.doneSubtopics
      ..clear()
      ..addAll(topic.subtopics.map((s) => s.key));
  } else if (status == TopicStatus.notStarted) {
    topic.doneSubtopics.clear();
  }
}

/// Ticks / unticks one subtopic and derives the topic's status from it:
/// every subtopic ticked → completed; some → still learning; none → not
/// started (unless the student had set "still learning" themselves).
void applySubtopic(LearningTopic topic, String key, bool done) {
  final keys = {for (final s in topic.subtopics) s.key};
  if (!keys.contains(key)) return;
  // Unticking one subtopic of a completed topic keeps the others ticked.
  if (topic.isDone && !done) {
    topic.doneSubtopics
      ..clear()
      ..addAll(keys);
  }
  done ? topic.doneSubtopics.add(key) : topic.doneSubtopics.remove(key);
  topic.doneSubtopics.removeWhere((k) => !keys.contains(k));
  final ticked = topic.doneSubtopics.length;
  if (ticked == keys.length) {
    topic.status = TopicStatus.completed;
  } else if (ticked > 0) {
    topic.status = TopicStatus.learning;
  } else if (topic.status == TopicStatus.completed) {
    topic.status = TopicStatus.notStarted;
  }
}
