import 'dart:math' as math;

import 'learning_plan.dart';

/// A topic template in the built-in subject library: a title, an approximate
/// baseline time (minutes, for a "know the basics" learner), the objectives the
/// student needs to cover and an optional explicit difficulty (otherwise it is
/// inferred from the baseline time).
///
/// Objectives describe *what* to learn — never the study material itself.
class _TopicTemplate {
  final String title;
  final int baseMinutes;
  final List<String> objectives;
  const _TopicTemplate(this.title, this.baseMinutes, this.objectives);

  TopicDifficulty get difficulty => _inferDifficulty(baseMinutes);

  static TopicDifficulty _inferDifficulty(int base) {
    if (base <= 25) return TopicDifficulty.easy;
    if (base <= 38) return TopicDifficulty.medium;
    return TopicDifficulty.hard;
  }
}

/// The parameters gathered by the Create-a-Plan wizard.
class PlanRequest {
  final String subject;
  final bool specificTopic;
  final KnowledgeLevel level;
  final LearningGoal goal;

  /// Topics extracted from an uploaded syllabus. Empty when skipped.
  final List<String> syllabusTopics;
  final int dailyMinutes;
  final Set<int> studyDays;
  final DateTime targetDate;
  final String? note;

  /// Jurisdiction / curriculum and academic lens — used to tailor
  /// region-sensitive subjects (law, tax, governance) and depth.
  final StudyRegion region;
  final StudyProgram program;

  const PlanRequest({
    required this.subject,
    required this.specificTopic,
    required this.level,
    required this.goal,
    required this.dailyMinutes,
    required this.studyDays,
    required this.targetDate,
    this.syllabusTopics = const [],
    this.note,
    this.region = StudyRegion.global,
    this.program = StudyProgram.general,
  });

  bool get hasSyllabus => syllabusTopics.isNotEmpty;
}

/// Turns a [PlanRequest] into a concrete [LearningPlan].
///
/// The planner behaves like a knowledgeable study coach:
///  • it recognises hundreds of subject names and aliases (fuzzy matching);
///  • it picks a pedagogically-ordered topic set from a curated knowledge base,
///    biased by the student's goal and trimmed by their level;
///  • it tags each topic with a difficulty and estimates time honestly;
///  • it weaves in spaced-review checkpoints and a final revision block;
///  • it lays everything out across the real study days before the deadline,
///    balancing each day's load and quietly increasing the daily dose only as
///    much as needed to keep the deadline realistic.
///
/// It is fully deterministic and on-device — it never fabricates notes,
/// resources or fake "technical processing", and every time is an estimate.
class LearningPlanGenerator {
  const LearningPlanGenerator();

  static int _idSeed = 0;
  static String _nextId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_idSeed++}';

  LearningPlan generate(PlanRequest req) {
    final topics = _buildTopics(req);
    final weeks = _schedule(topics, req);
    return LearningPlan(
      id: _nextId('plan'),
      subject: req.subject.trim(),
      specificTopic: req.specificTopic,
      level: req.level,
      goal: req.goal,
      hasSyllabus: req.hasSyllabus,
      dailyMinutes: req.dailyMinutes,
      studyDays: req.studyDays,
      targetDate: req.targetDate,
      createdAt: DateTime.now(),
      note: req.note,
      topics: topics,
      weeks: weeks,
      region: req.region,
      program: req.program,
    );
  }

  /// Assembles a full plan from an externally-produced (e.g. AI or user-built)
  /// ordered list of core topics: it lays the plan out across the study days,
  /// and (when [addReviews]) also weaves in spaced-review checkpoints.
  LearningPlan assembleFromCore(PlanRequest req, List<LearningTopic> core,
      {bool addReviews = true}) {
    // Enrich AI topics that arrived without a curriculum breakdown / unit.
    final enriched = <LearningTopic>[];
    for (var i = 0; i < core.length; i++) {
      final t = core[i];
      enriched.add(LearningTopic(
        id: t.id,
        title: t.title,
        estMinutes: t.estMinutes,
        objectives: t.objectives,
        unit: t.unit == 'Topics' ? _phaseUnit(i, core.length) : t.unit,
        sections: t.sections.isNotEmpty
            ? t.sections
            : _sectionsFor(t.title, t.objectives, t.estMinutes),
        completionCriteria: t.completionCriteria.isNotEmpty
            ? t.completionCriteria
            : _criteriaFor(t.title, t.objectives),
        difficulty: t.difficulty,
        isReview: t.isReview,
        actualMinutes: t.actualMinutes,
        links: t.links,
        doneSubtopics: t.doneSubtopics,
        status: t.status,
      ));
    }
    final topics =
        addReviews ? _withReviewCheckpoints(enriched, req) : enriched;
    final weeks = _schedule(topics, req);
    return LearningPlan(
      id: _nextId('plan'),
      subject: req.subject.trim(),
      specificTopic: req.specificTopic,
      level: req.level,
      goal: req.goal,
      hasSyllabus: req.hasSyllabus,
      dailyMinutes: req.dailyMinutes,
      studyDays: req.studyDays,
      targetDate: req.targetDate,
      createdAt: DateTime.now(),
      note: req.note,
      topics: topics,
      weeks: weeks,
      region: req.region,
      program: req.program,
    );
  }

  /// Rebuilds the schedule for the *remaining* topics of an existing plan,
  /// keeping completed topics as-is. Used by the Adjust / reschedule flows.
  LearningPlan replan(
    LearningPlan plan, {
    int? dailyMinutes,
    Set<int>? studyDays,
    DateTime? targetDate,
  }) {
    final req = PlanRequest(
      subject: plan.subject,
      specificTopic: plan.specificTopic,
      level: plan.level,
      goal: plan.goal,
      dailyMinutes: dailyMinutes ?? plan.dailyMinutes,
      studyDays: studyDays ?? plan.studyDays,
      targetDate: targetDate ?? plan.targetDate,
      note: plan.note,
      region: plan.region,
      program: plan.program,
    );
    final remaining = plan.topics.where((t) => !t.isDone).toList();
    final weeks = _schedule(remaining, req);
    return LearningPlan(
      id: plan.id,
      subject: plan.subject,
      specificTopic: plan.specificTopic,
      level: plan.level,
      goal: plan.goal,
      hasSyllabus: plan.hasSyllabus,
      dailyMinutes: req.dailyMinutes,
      studyDays: req.studyDays,
      targetDate: req.targetDate,
      createdAt: plan.createdAt,
      note: plan.note,
      topics: plan.topics,
      weeks: weeks,
      region: plan.region,
      program: plan.program,
    );
  }

  // ---------------------------------------------------------------------------
  // Topic selection
  // ---------------------------------------------------------------------------

  List<LearningTopic> _buildTopics(PlanRequest req) {
    List<_TopicTemplate> templates;
    bool fromKnowledgeBase = false;

    if (req.hasSyllabus) {
      templates = req.syllabusTopics
          .map((t) => _TopicTemplate(t.trim(), 30, _genericObjectives(t)))
          .toList();
    } else {
      final key = _matchSubject(req.subject);
      if (key != null && _jurisdictionalKeys.contains(key)) {
        // Law / governance / tax: branch by jurisdiction + academic lens.
        templates = _jurisdictionalTopics(key, req.region, req.program);
        fromKnowledgeBase = true;
      } else if (key != null) {
        templates = List<_TopicTemplate>.from(_library[key]!);
        fromKnowledgeBase = true;
      } else if (req.specificTopic || _looksLikeTopic(req.subject)) {
        templates = _topicBreakdown(req.subject);
      } else {
        templates = _genericSubject(req.subject);
      }
    }

    // Goal- and level-aware shaping (only for knowledge-base subjects, where we
    // know the pedagogical order well enough to trim safely).
    if (fromKnowledgeBase) {
      templates = _shapeForGoalAndLevel(templates, req);
    }

    final factor = req.level.timeFactor;
    final total = templates.length;
    final core = <LearningTopic>[
      for (var i = 0; i < templates.length; i++)
        _makeTopic(
          templates[i],
          minutes: _roundMinutes((templates[i].baseMinutes * factor).round()),
          unit: _phaseUnit(i, total),
        ),
    ];

    return _withReviewCheckpoints(core, req);
  }

  /// Builds a full [LearningTopic] from a template, synthesising its curriculum
  /// breakdown (sections + subtopics) and completion criteria from the topic's
  /// objectives. This maps WHAT to cover — never the study material.
  LearningTopic _makeTopic(
    _TopicTemplate t, {
    required int minutes,
    required String unit,
  }) {
    return LearningTopic(
      id: _nextId('t'),
      title: t.title,
      estMinutes: minutes,
      objectives: t.objectives,
      unit: unit,
      difficulty: t.difficulty,
      sections: _sectionsFor(t.title, t.objectives, minutes),
      completionCriteria: _criteriaFor(t.title, t.objectives),
    );
  }

  /// A phased curriculum unit name based on a topic's position in the sequence.
  static String _phaseUnit(int index, int total) {
    if (total <= 3) return 'Core Topics';
    final frac = index / total;
    if (frac < 0.34) return 'Foundations';
    if (frac < 0.7) return 'Core Concepts';
    return 'Advanced Topics';
  }

  /// Splits a topic into a clean curriculum breakdown: an orientation section,
  /// the core concepts (the real objectives), an application section and a
  /// Builds a topic's curriculum breakdown from its ACTUAL subtopics
  /// (objectives) — so every topic reads specifically, not from a generic
  /// template. Adds only a short, topic-named self-check.
  List<TopicSection> _sectionsFor(
      String title, List<String> objectives, int minutes) {
    final objs =
        objectives.map((o) => o.trim()).where((o) => o.isNotEmpty).toList();

    // No known subtopics (e.g. a manual topic with none added): keep it honest
    // and specific to the title rather than inventing generic filler.
    if (objs.isEmpty) {
      return [
        TopicSection(
          title: 'What to cover',
          minutes: minutes,
          points: ['Study the key ideas of $title'],
        ),
      ];
    }

    final selfCheck = (minutes * 0.2).round().clamp(5, 15);
    final contentMin = (minutes - selfCheck).clamp(10, minutes);
    final check = TopicSection(
      title: 'Self-check',
      minutes: selfCheck,
      points: [
        'Recall $title without looking',
        'Explain each point in your own words',
      ],
    );

    // Few subtopics → one specific content section. Many → split into two so
    // the map reads as a real progression, still driven by the real subtopics.
    if (objs.length <= 3) {
      return [
        TopicSection(
            title: 'Key concepts', minutes: contentMin, points: objs),
        check,
      ];
    }
    final mid = (objs.length / 2).ceil();
    final half = (contentMin / 2).round();
    return [
      TopicSection(
          title: 'Core concepts',
          minutes: half,
          points: objs.sublist(0, mid)),
      TopicSection(
          title: 'Going deeper',
          minutes: contentMin - half,
          points: objs.sublist(mid)),
      check,
    ];
  }

  /// Derives "you should be able to…" completion criteria from the objectives.
  List<String> _criteriaFor(String title, List<String> objectives) {
    final crit = <String>[];
    for (final o in objectives.take(4)) {
      final s = o.trim();
      if (s.isEmpty) continue;
      final lowered = s[0].toLowerCase() + s.substring(1);
      crit.add('Explain $lowered');
    }
    if (crit.isEmpty) {
      crit.add('Confidently recall the key points of $title');
    }
    return crit;
  }

  /// Drops the gentlest intro topics for advanced learners and interview
  /// preparation, keeping the most goal-relevant portion.
  List<_TopicTemplate> _shapeForGoalAndLevel(
      List<_TopicTemplate> templates, PlanRequest req) {
    var list = List<_TopicTemplate>.from(templates);

    // Level trimming — advanced students skip the very first foundational items.
    if (list.length > 8) {
      switch (req.level) {
        case KnowledgeLevel.advanced:
          list = list.sublist((list.length * 0.30).round());
          break;
        case KnowledgeLevel.intermediate:
          list = list.sublist((list.length * 0.12).round());
          break;
        case KnowledgeLevel.basics:
        case KnowledgeLevel.zero:
          break;
      }
    }

    // Interview prep favours the deeper, applied second half; exam & explore
    // keep breadth; syllabus/fundamentals/project keep the natural order.
    if (req.goal == LearningGoal.interview && list.length > 8) {
      list = list.sublist((list.length * 0.15).round());
    }
    return list;
  }

  /// Inserts spaced-review checkpoints roughly every six new topics and a final
  /// goal-appropriate revision block — the hallmark of a plan that actually
  /// helps retention.
  List<LearningTopic> _withReviewCheckpoints(
      List<LearningTopic> core, PlanRequest req) {
    if (core.length < 5) return core;
    final out = <LearningTopic>[];
    var sinceReview = 0;
    for (var i = 0; i < core.length; i++) {
      out.add(core[i]);
      sinceReview++;
      final isLast = i == core.length - 1;
      if (sinceReview >= 6 && !isLast) {
        out.add(_reviewTopic(
          'Checkpoint: review & self-test',
          const [
            'Revisit the topics you have covered so far',
            'Test yourself with quick recall questions',
            'Flag any weak areas to revisit',
          ],
          20,
        ));
        sinceReview = 0;
      }
    }
    out.add(_finalRevisionTopic(req.goal));
    return out;
  }

  LearningTopic _reviewTopic(String title, List<String> objs, int minutes) =>
      LearningTopic(
        id: _nextId('r'),
        title: title,
        estMinutes: minutes,
        objectives: objs,
        unit: 'Revision',
        difficulty: TopicDifficulty.easy,
        isReview: true,
        sections: [
          TopicSection(title: 'Recall & self-test', minutes: minutes, points: objs),
        ],
        completionCriteria: const [
          'Recall the key ideas without notes',
          'Identify and close your weak areas',
        ],
      );

  LearningTopic _finalRevisionTopic(LearningGoal goal) {
    switch (goal) {
      case LearningGoal.exam:
        return _reviewTopic('Exam revision & practice', const [
          'Review every topic end to end',
          'Solve past-paper / practice questions under time',
          'Prioritise high-weight and weak areas',
        ], 45);
      case LearningGoal.interview:
        return _reviewTopic('Mock questions & problem practice', const [
          'Practice common interview questions',
          'Explain concepts out loud',
          'Time yourself on problem solving',
        ], 45);
      case LearningGoal.project:
        return _reviewTopic('Apply it: mini build', const [
          'Combine what you learned into a small project',
          'Identify gaps as you build',
        ], 45);
      default:
        return _reviewTopic('Full revision & self-test', const [
          'Review all topics from start to finish',
          'Focus extra time on your weakest areas',
          'Do a short self-test to confirm retention',
        ], 40);
    }
  }

  static int _roundMinutes(int m) {
    final snapped = (m / 5).round() * 5;
    return snapped < 15 ? 15 : snapped;
  }

  // ---------------------------------------------------------------------------
  // Scheduling — deadline-aware, load-balanced
  // ---------------------------------------------------------------------------

  List<WeekPlan> _schedule(List<LearningTopic> topics, PlanRequest req) {
    if (topics.isEmpty) return const [];

    final studyDays =
        req.studyDays.isEmpty ? {1, 2, 3, 4, 5, 6, 7} : req.studyDays;

    // The real study dates available between today and the deadline.
    final today = _dateOnly(DateTime.now());
    final target = _dateOnly(req.targetDate);
    final availableDates = <DateTime>[];
    var cursor = today;
    while (!cursor.isAfter(target)) {
      if (studyDays.contains(cursor.weekday)) availableDates.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    final totalMinutes = topics.fold<int>(0, (s, t) => s + t.estMinutes);

    // Deadline-fitting daily budget: study a little more per day if that's what
    // it takes to finish on time — but never blow past ~2.4× the chosen dose
    // (beyond that we simply run past the deadline rather than propose an
    // unrealistic day).
    var budget = req.dailyMinutes;
    if (availableDates.isNotEmpty) {
      final needed = (totalMinutes / availableDates.length).ceil();
      budget = math.max(budget, needed);
    }
    budget = budget.clamp(req.dailyMinutes, (req.dailyMinutes * 2.4).round());
    final headroom = (budget * 1.15).round();

    // Pack topics into days, capping both minutes and cognitive load so we
    // never stack several hard topics on one day.
    const maxTopicsPerDay = 4;
    const maxWeightPerDay = 6;
    final buckets = <List<LearningTopic>>[];
    var current = <LearningTopic>[];
    var curMinutes = 0;
    var curWeight = 0;
    for (final t in topics) {
      final full = current.isNotEmpty &&
          (curMinutes + t.estMinutes > headroom ||
              current.length >= maxTopicsPerDay ||
              curWeight + t.difficulty.weight > maxWeightPerDay);
      if (full) {
        buckets.add(current);
        current = [];
        curMinutes = 0;
        curWeight = 0;
      }
      current.add(t);
      curMinutes += t.estMinutes;
      curWeight += t.difficulty.weight;
    }
    if (current.isNotEmpty) buckets.add(current);

    // Assign calendar dates. Use the deadline window first; if the plan needs
    // more days than the window offers, keep going on the next study weekdays.
    final days = <DayPlan>[];
    var extraCursor = availableDates.isNotEmpty
        ? availableDates.last.add(const Duration(days: 1))
        : today;
    for (var i = 0; i < buckets.length; i++) {
      DateTime date;
      if (i < availableDates.length) {
        date = availableDates[i];
      } else {
        while (!studyDays.contains(extraCursor.weekday)) {
          extraCursor = extraCursor.add(const Duration(days: 1));
        }
        date = extraCursor;
        extraCursor = extraCursor.add(const Duration(days: 1));
      }
      days.add(DayPlan(
        dayNumber: i + 1,
        date: date,
        topicIds: buckets[i].map((t) => t.id).toList(),
      ));
    }

    // Group study days into themed weeks with a pedagogical arc.
    const daysPerWeek = 5;
    final totalWeeks = (days.length / daysPerWeek).ceil();
    final weeks = <WeekPlan>[];
    for (var i = 0; i < days.length; i += daysPerWeek) {
      final slice = days.sublist(i, math.min(i + daysPerWeek, days.length));
      final index = (i ~/ daysPerWeek) + 1;
      weeks.add(WeekPlan(
        weekNumber: index,
        title: _weekTitle(index, totalWeeks, req.goal),
        days: slice,
      ));
    }
    return weeks;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _weekTitle(int index, int totalWeeks, LearningGoal goal) {
    if (index == 1) return 'Foundations';
    if (index == totalWeeks) {
      switch (goal) {
        case LearningGoal.exam:
          return 'Exam readiness';
        case LearningGoal.interview:
          return 'Interview readiness';
        case LearningGoal.project:
          return 'Build & apply';
        default:
          return 'Consolidation';
      }
    }
    const mid = ['Core concepts', 'Building up', 'Going deeper', 'Applied'];
    return mid[(index - 2) % mid.length];
  }

  // ---------------------------------------------------------------------------
  // Subject matching — aliases + fuzzy
  // ---------------------------------------------------------------------------

  /// Keys that must be resolved through the jurisdiction-aware builders rather
  /// than the flat [_library].
  static const Set<String> _jurisdictionalKeys = {
    'business law',
    'corporate governance',
    'taxation',
    'political science',
  };

  Iterable<String> get _candidateKeys =>
      [..._library.keys, ..._jurisdictionalKeys];

  /// Words too generic to carry meaning when matching a subject — a shared
  /// "corporate" must NOT bridge "corporate governance" → "corporate finance".
  static const Set<String> _stopWords = {
    'introduction', 'intro', 'to', 'of', 'and', 'the', 'in', 'for', 'a', 'an',
    'basics', 'basic', 'fundamentals', 'fundamental', 'management', 'studies',
    'study', 'course', 'principles', 'system', 'systems', 'corporate',
    'business', 'general', 'advanced', 'applied', 'my', 'complete', 'full',
  };

  /// Whether the Create-a-Plan wizard should ask for course/curriculum &
  /// country for this subject. True for jurisdiction- or curriculum-sensitive
  /// subjects (law, tax, governance, accounting standards, professional exams);
  /// false for universal subjects like DBMS, Python or Mathematics — so we
  /// never ask for a country unnecessarily.
  bool needsCurriculumContext(String subject) {
    final key = _matchSubject(subject);
    if (key != null && _jurisdictionalKeys.contains(key)) return true;
    final n = _normaliseKey(subject);
    const triggers = [
      'law', 'tax', 'gst', 'vat', 'governance', 'accounting', 'audit',
      'company', 'constitution', 'compliance', 'regulation', 'legal',
      'contract', 'ca', 'cs', 'cfa', 'upsc', 'politics', 'political',
      'civics', 'polity', 'government', 'parliament', 'elections',
    ];
    final tokens = n.split(' ').toSet();
    return triggers.any((t) => tokens.contains(t) || n.contains('$t '));
  }

  /// A short, honest rationale for the topic order shown on the overview.
  String whyThisOrder() =>
      'We start with the foundations because they are prerequisites for the '
      'later topics, then build up to the more advanced material and finish '
      'with revision.';

  /// Resolves a free-text subject to a knowledge-base key, via exact match,
  /// a rich alias table, then stopword-filtered token-overlap matching.
  String? _matchSubject(String input) {
    final norm = _normaliseKey(input);
    if (norm.isEmpty) return null;
    if (_library.containsKey(norm) || _jurisdictionalKeys.contains(norm)) {
      return norm;
    }
    if (_aliases.containsKey(norm)) return _aliases[norm];

    final tokens = norm.split(' ').where((t) => t.isNotEmpty).toSet();

    // Single-word alias as a whole word (avoids "tax" matching "relaxation").
    for (final e in _aliases.entries) {
      if (!e.key.contains(' ') && tokens.contains(e.key)) return e.value;
    }
    // Multi-word alias contained anywhere in the input.
    for (final e in _aliases.entries) {
      if (e.key.contains(' ') && norm.contains(e.key)) return e.value;
    }
    // A whole candidate key contained in the input (or vice-versa).
    for (final key in _candidateKeys) {
      if (norm.contains(key) || key.contains(norm)) return key;
    }

    // Stopword-filtered token overlap: only count meaningful shared words, and
    // require either 2+ shared words or that the match covers ALL of the key's
    // meaningful words — so a lone generic word can never force a wrong match.
    final inputSignificant =
        tokens.where((t) => t.length > 2 && !_stopWords.contains(t)).toSet();
    if (inputSignificant.isEmpty) return null;
    String? best;
    var bestScore = 0;
    for (final key in _candidateKeys) {
      final keyTokens = key
          .split(' ')
          .where((t) => t.length > 2 && !_stopWords.contains(t))
          .toSet();
      if (keyTokens.isEmpty) continue;
      final score = keyTokens.intersection(inputSignificant).length;
      final acceptable = score >= 2 || score == keyTokens.length;
      if (score > bestScore && acceptable) {
        bestScore = score;
        best = key;
      }
    }
    return bestScore > 0 ? best : null;
  }

  /// Heuristic: multi-word phrases with connective words read like a narrow
  /// topic ("normalization in dbms") rather than a whole subject.
  bool _looksLikeTopic(String input) {
    final n = _normaliseKey(input);
    return n.contains(' in ') || n.contains(' of ') || n.contains(' for ');
  }

  // ---------------------------------------------------------------------------
  // Jurisdiction- & program-aware subjects (law, governance, tax)
  // ---------------------------------------------------------------------------

  List<_TopicTemplate> _jurisdictionalTopics(
      String key, StudyRegion region, StudyProgram program) {
    switch (key) {
      case 'business law':
        return _businessLaw(region, program);
      case 'corporate governance':
        return _corporateGovernance(region, program);
      case 'taxation':
        return _taxation(region, program);
      case 'political science':
        return _politicalScience(region, program);
      default:
        return _genericSubject(key);
    }
  }

  /// Adds a closing topic that reframes the subject for the student's program:
  /// a managerial/applied lens for MBA & general learners, a doctrinal/exam
  /// lens for undergraduate & professional students.
  List<_TopicTemplate> _programLens(
    List<_TopicTemplate> base,
    StudyProgram program,
    _TopicTemplate managerial,
    _TopicTemplate academic,
  ) {
    switch (program) {
      case StudyProgram.postgraduate:
      case StudyProgram.general:
        return [...base, managerial];
      case StudyProgram.undergraduate:
      case StudyProgram.professional:
        return [...base, academic];
      case StudyProgram.school:
        return base;
    }
  }

  List<_TopicTemplate> _businessLaw(StudyRegion region, StudyProgram program) {
    late List<_TopicTemplate> base;
    switch (region) {
      case StudyRegion.india:
        base = const [
          _TopicTemplate('Introduction to Business Law (India)', 25, [
            'Sources of law and the legal environment',
            'Overview of key commercial statutes',
          ]),
          _TopicTemplate('Indian Contract Act, 1872 — Essentials', 40, [
            'Offer, acceptance and agreement',
            'Essentials of a valid contract',
          ]),
          _TopicTemplate('Consideration & Capacity', 30, [
            'Meaning and rules of consideration',
            'Competency to contract',
          ]),
          _TopicTemplate('Performance, Breach & Remedies', 40, [
            'Discharge of contracts',
            'Remedies for breach',
          ]),
          _TopicTemplate('Sale of Goods Act, 1930', 35, [
            'Conditions and warranties',
            'Transfer of ownership and delivery',
          ]),
          _TopicTemplate('Partnership Act & LLP', 35, [
            'Nature of partnership and LLP',
            'Rights and duties of partners',
          ]),
          _TopicTemplate('Companies Act, 2013 — Basics', 40, [
            'Types of companies and incorporation',
            'Key features of a company',
          ]),
          _TopicTemplate('Negotiable Instruments Act, 1881', 30, [
            'Cheques, bills and promissory notes',
            'Dishonour and consequences',
          ]),
          _TopicTemplate('Consumer Protection Act, 2019', 30, [
            'Consumer rights and forums',
            'Redressal mechanisms',
          ]),
        ];
        break;
      case StudyRegion.unitedStates:
        base = const [
          _TopicTemplate('Introduction to the US Legal System', 25, [
            'Common law, statutes and jurisdiction',
            'Federal vs state law',
          ]),
          _TopicTemplate('Contract Law (Common Law)', 40, [
            'Formation, consideration and defenses',
            'Breach and remedies',
          ]),
          _TopicTemplate('Sales & the UCC (Article 2)', 35, [
            'Contracts for the sale of goods',
            'Warranties and risk of loss',
          ]),
          _TopicTemplate('Torts & Negligence', 40, [
            'Intentional torts and negligence',
            'Product liability basics',
          ]),
          _TopicTemplate('Business Organizations', 40, [
            'Sole proprietorship, partnership, LLC, corporation',
            'Choosing an entity',
          ]),
          _TopicTemplate('Agency & Employment Law', 35, [
            'Agency relationships',
            'At-will employment and key statutes',
          ]),
          _TopicTemplate('Intellectual Property', 35, [
            'Patents, copyrights, trademarks, trade secrets',
            'Business use of IP',
          ]),
          _TopicTemplate('Securities & Antitrust Basics', 40, [
            'Securities regulation (SEC) overview',
            'Antitrust principles',
          ]),
        ];
        break;
      case StudyRegion.unitedKingdom:
        base = const [
          _TopicTemplate('The English Legal System', 25, [
            'Sources of law and court structure',
            'Common law and equity',
          ]),
          _TopicTemplate('Contract Law', 40, [
            'Formation and terms',
            'Breach and remedies',
          ]),
          _TopicTemplate('Tort Law', 40, [
            'Negligence and duty of care',
            'Liability',
          ]),
          _TopicTemplate('Sale of Goods & Consumer Rights Act 2015', 35, [
            'Implied terms',
            'Consumer remedies',
          ]),
          _TopicTemplate('Business Organisations (Companies Act 2006)', 40, [
            'Company formation and types',
            "Directors' duties",
          ]),
          _TopicTemplate('Partnership & Agency', 30, [
            'Partnerships and LLPs',
            'Agency relationships',
          ]),
          _TopicTemplate('Employment Law', 35, [
            'Employment contracts',
            'Unfair dismissal basics',
          ]),
          _TopicTemplate('Intellectual Property', 30, [
            'Patents, copyright, trademarks',
            'Protecting business assets',
          ]),
        ];
        break;
      case StudyRegion.global:
        base = const [
          _TopicTemplate('Sources & Nature of Law', 25, [
            'Legal systems around the world',
            'How commercial law works',
          ]),
          _TopicTemplate('Contract Law Fundamentals', 40, [
            'Formation and validity',
            'Breach and remedies',
          ]),
          _TopicTemplate('Torts / Civil Wrongs', 35, [
            'Negligence and liability',
            'Common examples',
          ]),
          _TopicTemplate('Business Structures', 35, [
            'Sole trader, partnership, company',
            'Choosing a structure',
          ]),
          _TopicTemplate('Sale of Goods & Contracts', 35, [
            'Terms, conditions and warranties',
            'Passing of ownership',
          ]),
          _TopicTemplate('Agency & Employment', 30, [
            'Agency relationships',
            'Employment basics',
          ]),
          _TopicTemplate('Intellectual Property', 30, [
            'Patents, copyright, trademarks',
            'Why IP matters',
          ]),
          _TopicTemplate('Consumer Protection & Disputes', 30, [
            'Consumer rights',
            'Dispute resolution',
          ]),
        ];
        break;
    }
    return _programLens(
      base,
      program,
      const _TopicTemplate('Legal risk & compliance for managers', 35, [
        'Spot legal risk in business decisions',
        'Build a practical compliance mindset',
      ]),
      const _TopicTemplate('Case law & legal reasoning', 35, [
        'Read and brief landmark cases',
        'Apply legal reasoning to problems',
      ]),
    );
  }

  List<_TopicTemplate> _corporateGovernance(
      StudyRegion region, StudyProgram program) {
    late List<_TopicTemplate> base;
    switch (region) {
      case StudyRegion.india:
        base = const [
          _TopicTemplate('Introduction to Corporate Governance', 25, [
            'What governance is and why it matters',
            'The agency problem',
          ]),
          _TopicTemplate('Companies Act, 2013 & Governance', 40, [
            'Governance provisions in the Act',
            'Board and shareholder framework',
          ]),
          _TopicTemplate('Board of Directors & Committees', 40, [
            'Board composition and roles',
            'Audit, nomination & remuneration committees',
          ]),
          _TopicTemplate('SEBI LODR Regulations', 40, [
            'Listing obligations and disclosures',
            'Governance norms for listed firms',
          ]),
          _TopicTemplate('Independent Directors & Audit Committee', 35, [
            'Role and independence',
            'Audit committee responsibilities',
          ]),
          _TopicTemplate('Shareholder Rights & Activism', 35, [
            'Minority protection',
            'Voting and engagement',
          ]),
          _TopicTemplate('Related Party Transactions', 30, [
            'Disclosure and approval',
            'Conflicts of interest',
          ]),
          _TopicTemplate('Governance Failures & Cases', 30, [
            'Lessons from Indian cases (e.g. Satyam)',
            'What went wrong',
          ]),
          _TopicTemplate('ESG & Sustainability Reporting', 35, [
            'ESG basics and BRSR',
            'Why it matters to boards',
          ]),
        ];
        break;
      case StudyRegion.unitedStates:
        base = const [
          _TopicTemplate('Introduction to Corporate Governance', 25, [
            'Governance and the agency problem',
            'Ownership vs control',
          ]),
          _TopicTemplate('Board Structure & Fiduciary Duties', 40, [
            'Duty of care and loyalty',
            'Board committees',
          ]),
          _TopicTemplate('Sarbanes-Oxley Act (SOX)', 40, [
            'Internal controls and certification',
            'Audit committee requirements',
          ]),
          _TopicTemplate('Dodd-Frank & SEC Regulation', 40, [
            'Say-on-pay and disclosures',
            'SEC oversight',
          ]),
          _TopicTemplate('Shareholder Rights (Delaware Law)', 35, [
            'Delaware corporate law',
            'Shareholder litigation',
          ]),
          _TopicTemplate('Executive Compensation', 35, [
            'Pay structures and incentives',
            'Alignment with performance',
          ]),
          _TopicTemplate('Audit & Internal Controls', 35, [
            'Role of external auditors',
            'Control frameworks',
          ]),
          _TopicTemplate('Ethics, CSR & ESG', 35, [
            'Stakeholder governance',
            'ESG disclosure trends',
          ]),
        ];
        break;
      case StudyRegion.unitedKingdom:
        base = const [
          _TopicTemplate('Introduction to Corporate Governance', 25, [
            'Governance and the agency problem',
            'The UK approach',
          ]),
          _TopicTemplate('UK Corporate Governance Code', 40, [
            'Comply-or-explain principle',
            'Main principles of the Code',
          ]),
          _TopicTemplate('Evolution: Cadbury to today', 30, [
            'Cadbury, Greenbury, Hampel reports',
            'How the Code evolved',
          ]),
          _TopicTemplate('Board Effectiveness & Roles', 40, [
            'Chair, CEO and NEDs',
            'Board evaluation',
          ]),
          _TopicTemplate("Directors' Duties (Companies Act 2006)", 40, [
            'Statutory duties of directors',
            'Accountability',
          ]),
          _TopicTemplate('Audit, Risk & the FRC', 35, [
            'Audit committees and risk',
            'Role of the FRC',
          ]),
          _TopicTemplate('Stewardship & Shareholder Engagement', 35, [
            'UK Stewardship Code',
            'Institutional investors',
          ]),
          _TopicTemplate('Executive Pay & ESG', 35, [
            'Remuneration reporting',
            'ESG expectations',
          ]),
        ];
        break;
      case StudyRegion.global:
        base = const [
          _TopicTemplate('Introduction & the Agency Problem', 25, [
            'Separation of ownership and control',
            'Why governance matters',
          ]),
          _TopicTemplate('Board Roles & Structures', 40, [
            'Board composition and committees',
            'One-tier vs two-tier boards',
          ]),
          _TopicTemplate("Directors' Duties & Accountability", 35, [
            'Duties of care and loyalty',
            'Accountability mechanisms',
          ]),
          _TopicTemplate('Shareholders vs Stakeholders', 35, [
            'Competing models of governance',
            'Stakeholder theory',
          ]),
          _TopicTemplate('Internal Controls & Audit', 35, [
            'Control frameworks',
            'Role of auditors',
          ]),
          _TopicTemplate('Executive Compensation', 30, [
            'Incentive design',
            'Pay and performance',
          ]),
          _TopicTemplate('Transparency & Disclosure', 30, [
            'Reporting and disclosure norms',
            'Market discipline',
          ]),
          _TopicTemplate('Ethics, CSR & ESG', 35, [
            'Corporate responsibility',
            'ESG frameworks',
          ]),
        ];
        break;
    }
    return _programLens(
      base,
      program,
      const _TopicTemplate('Board effectiveness & stakeholder strategy', 35, [
        'How boards create value',
        'Managing stakeholders and ESG strategically',
      ]),
      const _TopicTemplate('Statutory provisions & case study', 35, [
        'Key statutory duties in depth',
        'Analyse a governance failure case',
      ]),
    );
  }

  List<_TopicTemplate> _taxation(StudyRegion region, StudyProgram program) {
    late List<_TopicTemplate> base;
    switch (region) {
      case StudyRegion.india:
        base = const [
          _TopicTemplate('Basics of Income Tax (India)', 30, [
            'Assessee, previous year, assessment year',
            'Structure of the Income Tax Act',
          ]),
          _TopicTemplate('Residential Status & Scope', 35, [
            'Determining residential status',
            'Scope of total income',
          ]),
          _TopicTemplate('Income from Salary & House Property', 40, [
            'Salary components and exemptions',
            'House property computation',
          ]),
          _TopicTemplate('PGBP & Capital Gains', 45, [
            'Business/profession income',
            'Short vs long-term capital gains',
          ]),
          _TopicTemplate('Deductions (Chapter VI-A)', 35, [
            '80C, 80D and other deductions',
            'Reducing taxable income',
          ]),
          _TopicTemplate('Computation of Total Income & Tax', 40, [
            'Aggregating heads of income',
            'Applying slab rates',
          ]),
          _TopicTemplate('TDS & Advance Tax', 30, [
            'Tax deducted at source',
            'Advance tax instalments',
          ]),
          _TopicTemplate('GST — Basics', 40, [
            'Concept of GST and supply',
            'Input tax credit basics',
          ]),
          _TopicTemplate('Filing Returns', 25, [
            'Types of ITR',
            'Filing process and deadlines',
          ]),
        ];
        break;
      case StudyRegion.unitedStates:
        base = const [
          _TopicTemplate('US Tax System Overview', 30, [
            'Federal, state and local taxes',
            'Progressive tax structure',
          ]),
          _TopicTemplate('Filing Status & Gross Income', 35, [
            'Filing statuses',
            'What counts as income',
          ]),
          _TopicTemplate('Deductions & Credits', 40, [
            'Standard vs itemized deductions',
            'Common tax credits',
          ]),
          _TopicTemplate('Computing Federal Income Tax', 40, [
            'Taxable income and brackets',
            'Tax liability',
          ]),
          _TopicTemplate('Payroll Taxes & FICA', 30, [
            'Social Security and Medicare',
            'Withholding',
          ]),
          _TopicTemplate('Capital Gains & Investments', 35, [
            'Short vs long-term gains',
            'Investment income',
          ]),
          _TopicTemplate('Business Taxation Basics', 40, [
            'Pass-through vs corporate tax',
            'Self-employment tax',
          ]),
          _TopicTemplate('State & Local Taxes', 25, [
            'Sales and state income tax',
            'Variation across states',
          ]),
        ];
        break;
      case StudyRegion.unitedKingdom:
        base = const [
          _TopicTemplate('UK Tax System Overview', 30, [
            'HMRC and the tax year',
            'Main UK taxes',
          ]),
          _TopicTemplate('Income Tax & Personal Allowance', 40, [
            'Tax bands and allowance',
            'Computing income tax',
          ]),
          _TopicTemplate('National Insurance', 30, [
            'NI classes and contributions',
            'Who pays what',
          ]),
          _TopicTemplate('Capital Gains Tax', 35, [
            'Chargeable gains and reliefs',
            'Annual exempt amount',
          ]),
          _TopicTemplate('VAT', 35, [
            'How VAT works',
            'Registration and rates',
          ]),
          _TopicTemplate('Corporation Tax Basics', 35, [
            'Company profits and rates',
            'Filing basics',
          ]),
          _TopicTemplate('PAYE & Self Assessment', 30, [
            'PAYE system',
            'Self-assessment returns',
          ]),
        ];
        break;
      case StudyRegion.global:
        base = const [
          _TopicTemplate('Principles of Taxation', 30, [
            'Why governments tax',
            'Canons of taxation',
          ]),
          _TopicTemplate('Direct vs Indirect Taxes', 30, [
            'Income vs consumption taxes',
            'Examples of each',
          ]),
          _TopicTemplate('Income Tax Basics', 40, [
            'Taxable income',
            'Rates and brackets',
          ]),
          _TopicTemplate('Deductions & Exemptions', 35, [
            'Reducing taxable income',
            'Common reliefs',
          ]),
          _TopicTemplate('Computing Tax Liability', 40, [
            'Step-by-step computation',
            'Worked example',
          ]),
          _TopicTemplate('Consumption / VAT Taxes', 35, [
            'How VAT/GST works',
            'Input credits',
          ]),
          _TopicTemplate('Corporate Taxation', 35, [
            'Taxing company profits',
            'Basic concepts',
          ]),
          _TopicTemplate('Filing & Compliance', 25, [
            'Returns and deadlines',
            'Record keeping',
          ]),
        ];
        break;
    }
    return _programLens(
      base,
      program,
      const _TopicTemplate('Tax planning for decisions', 35, [
        'Legitimate tax planning basics',
        'Tax impact of business/personal decisions',
      ]),
      const _TopicTemplate('Computation practice & problems', 40, [
        'Work through computation problems',
        'Practice exam-style questions',
      ]),
    );
  }

  List<_TopicTemplate> _politicalScience(
      StudyRegion region, StudyProgram program) {
    late List<_TopicTemplate> base;
    switch (region) {
      case StudyRegion.india:
        base = const [
          _TopicTemplate('Introduction to Political Science', 25, [
            'Meaning, scope and nature',
            'Key concepts: state, power, authority',
          ]),
          _TopicTemplate('The Indian Constitution — Basics', 40, [
            'Making and salient features',
            'Preamble and its significance',
          ]),
          _TopicTemplate('Fundamental Rights & Duties', 40, [
            'Rights, duties and DPSPs',
            'Landmark provisions',
          ]),
          _TopicTemplate('Union Government', 40, [
            'President, PM and Council of Ministers',
            'Powers and functions',
          ]),
          _TopicTemplate('Parliament & Legislature', 40, [
            'Lok Sabha and Rajya Sabha',
            'Law-making process',
          ]),
          _TopicTemplate('Judiciary', 35, [
            'Supreme Court and High Courts',
            'Judicial review',
          ]),
          _TopicTemplate('Federalism in India', 35, [
            'Centre-state relations',
            'Distribution of powers',
          ]),
          _TopicTemplate('Elections & Political Parties', 35, [
            'Election Commission and process',
            'Party system in India',
          ]),
          _TopicTemplate('Local Government', 30, [
            'Panchayati Raj and municipalities',
            '73rd & 74th Amendments',
          ]),
        ];
        break;
      case StudyRegion.unitedStates:
        base = const [
          _TopicTemplate('Introduction to Political Science', 25, [
            'Core concepts and methods',
            'State, power and authority',
          ]),
          _TopicTemplate('US Constitution & Federalism', 40, [
            'Founding principles',
            'Federal vs state powers',
          ]),
          _TopicTemplate('Separation of Powers', 35, [
            'Checks and balances',
            'Three branches',
          ]),
          _TopicTemplate('Congress', 40, [
            'House and Senate',
            'The legislative process',
          ]),
          _TopicTemplate('The Presidency', 35, [
            'Powers of the executive',
            'The bureaucracy',
          ]),
          _TopicTemplate('The Supreme Court', 35, [
            'Judicial review',
            'Landmark cases',
          ]),
          _TopicTemplate('Elections & Parties', 40, [
            'Electoral system and primaries',
            'The two-party system',
          ]),
          _TopicTemplate('Civil Rights & Liberties', 35, [
            'The Bill of Rights',
            'Key movements',
          ]),
          _TopicTemplate('Public Policy', 30, [
            'How policy is made',
            'Interest groups',
          ]),
        ];
        break;
      case StudyRegion.unitedKingdom:
        base = const [
          _TopicTemplate('Introduction to Political Science', 25, [
            'Core concepts and methods',
            'State, power and authority',
          ]),
          _TopicTemplate('The UK Constitution', 40, [
            'Uncodified constitution',
            'Sources and conventions',
          ]),
          _TopicTemplate('Parliament & Sovereignty', 40, [
            'Commons and Lords',
            'Parliamentary sovereignty',
          ]),
          _TopicTemplate('The Executive', 35, [
            'PM and Cabinet',
            'The civil service',
          ]),
          _TopicTemplate('Judiciary & Rule of Law', 35, [
            'The Supreme Court',
            'Rule of law',
          ]),
          _TopicTemplate('Elections & Parties', 40, [
            'First-past-the-post',
            'The party system',
          ]),
          _TopicTemplate('Devolution', 30, [
            'Scotland, Wales, Northern Ireland',
            'Distribution of powers',
          ]),
          _TopicTemplate('Pressure Groups & Media', 30, [
            'Interest groups',
            'Role of the media',
          ]),
        ];
        break;
      case StudyRegion.global:
        base = const [
          _TopicTemplate('Introduction to Political Science', 25, [
            'Meaning, scope and methods',
            'State, power and authority',
          ]),
          _TopicTemplate('Political Theory & Ideologies', 40, [
            'Liberalism, socialism, conservatism',
            'Democracy and its forms',
          ]),
          _TopicTemplate('State & Sovereignty', 35, [
            'Elements of the state',
            'Sovereignty',
          ]),
          _TopicTemplate('Systems of Government', 40, [
            'Presidential vs parliamentary',
            'Unitary vs federal',
          ]),
          _TopicTemplate('Constitutions & Rights', 35, [
            'Role of constitutions',
            'Rights and duties',
          ]),
          _TopicTemplate('Organs of Government', 40, [
            'Legislature, executive, judiciary',
            'Separation of powers',
          ]),
          _TopicTemplate('Parties & Elections', 35, [
            'Party systems',
            'Electoral systems',
          ]),
          _TopicTemplate('International Relations — Basics', 35, [
            'States and the international system',
            'Key theories',
          ]),
          _TopicTemplate('Comparative Politics', 30, [
            'Comparing political systems',
            'Case studies',
          ]),
        ];
        break;
    }
    return _programLens(
      base,
      program,
      const _TopicTemplate('Current affairs & policy application', 35, [
        'Connect theory to current events',
        'Analyse a real policy issue',
      ]),
      const _TopicTemplate('Political thinkers & theory in depth', 35, [
        'Study key thinkers and texts',
        'Practice analytical answers',
      ]),
    );
  }

  static String _normaliseKey(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(
          RegExp(r'\s+'), ' ');

  // ---------------------------------------------------------------------------
  // Objective helpers / fallbacks
  // ---------------------------------------------------------------------------

  static List<String> _genericObjectives(String title) => [
        'Understand the core idea behind $title',
        'Learn the key terms and definitions',
        'Work through a simple example and self-check',
      ];

  List<_TopicTemplate> _topicBreakdown(String topic) {
    final t = topic.trim();
    return [
      _TopicTemplate('Introduction to $t', 25, [
        'Understand what $t means and why it matters',
        'Learn the key terminology',
      ]),
      _TopicTemplate('Core concepts of $t', 35, [
        'Break down the main components',
        'Understand how the pieces fit together',
      ]),
      const _TopicTemplate('Rules & techniques', 35, [
        'Learn the standard rules and methods',
        'See how each is applied',
      ]),
      const _TopicTemplate('Worked examples', 30, [
        'Follow step-by-step examples',
        'Identify common patterns',
      ]),
      const _TopicTemplate('Practice & recall', 30, [
        'Attempt practice problems',
        'Self-check your understanding',
      ]),
      const _TopicTemplate('Common mistakes & review', 25, [
        'Review frequent errors and edge cases',
        'Consolidate the whole topic',
      ]),
    ];
  }

  List<_TopicTemplate> _genericSubject(String subject) {
    final s = subject.trim();
    return [
      _TopicTemplate('Introduction to $s', 25, _genericObjectives(s)),
      _TopicTemplate('Key terminology', 25, [
        'Learn the vocabulary used across $s',
        'Understand how terms relate',
      ]),
      const _TopicTemplate('Fundamental concepts', 40, [
        'Cover the foundational ideas',
        'Understand why they matter',
      ]),
      _TopicTemplate('Core principles', 40, [
        'Study the central principles of $s',
        'See how they are applied',
      ]),
      const _TopicTemplate('Intermediate topics', 45, [
        'Build on the fundamentals',
        'Connect concepts together',
      ]),
      const _TopicTemplate('Applied concepts', 40, [
        'Apply what you have learned',
        'Work through examples',
      ]),
      const _TopicTemplate('Advanced topics', 45, [
        'Explore deeper, specialised areas',
        'Understand real-world use',
      ]),
      const _TopicTemplate('Practice & problems', 35, [
        'Attempt practice questions',
        'Reinforce weak areas',
      ]),
      const _TopicTemplate('Review & consolidation', 30, [
        'Revisit the full picture',
        'Fill any remaining gaps',
      ]),
    ];
  }

  // ---------------------------------------------------------------------------
  // Alias table (free text → knowledge-base key)
  // ---------------------------------------------------------------------------

  static const Map<String, String> _aliases = {
    'database': 'dbms',
    'databases': 'dbms',
    'database management system': 'dbms',
    'database management systems': 'dbms',
    'rdbms': 'dbms',
    'sql': 'dbms',
    'os': 'operating systems',
    'operating system': 'operating systems',
    'dsa': 'data structures & algorithms',
    'data structures': 'data structures & algorithms',
    'algorithms': 'data structures & algorithms',
    'data structure and algorithms': 'data structures & algorithms',
    'cn': 'computer networks',
    'networking': 'computer networks',
    'computer network': 'computer networks',
    'ml': 'machine learning',
    'machine learning basics': 'machine learning',
    'ai': 'machine learning',
    'python programming': 'python',
    'python3': 'python',
    'java programming': 'java',
    'core java': 'java',
    'c programming': 'c programming',
    'clanguage': 'c programming',
    'web dev': 'web development',
    'web development': 'web development',
    'frontend': 'web development',
    'html css javascript': 'web development',
    'javascript': 'web development',
    'js': 'web development',
    'stats': 'statistics',
    'statistics and probability': 'statistics',
    'probability': 'statistics',
    'accounts': 'financial accounting',
    'accountancy': 'financial accounting',
    'accounting': 'financial accounting',
    'fa': 'financial accounting',
    'cost accounting': 'cost accounting',
    'costing': 'cost accounting',
    'corporate finance': 'corporate finance',
    'financial management': 'corporate finance',
    'finance': 'corporate finance',
    'micro economics': 'microeconomics',
    'macro economics': 'macroeconomics',
    'economics': 'economics',
    'marketing': 'marketing management',
    'digital marketing': 'digital marketing',
    'hr': 'human resource management',
    'hrm': 'human resource management',
    'ob': 'organizational behaviour',
    'organisational behaviour': 'organizational behaviour',
    'organizational behavior': 'organizational behaviour',
    'business law': 'business law',
    'law': 'business law',
    'company law': 'business law',
    'commercial law': 'business law',
    'legal studies': 'business law',
    'mercantile law': 'business law',
    'corporate governance': 'corporate governance',
    'governance': 'corporate governance',
    'cg': 'corporate governance',
    'taxation': 'taxation',
    'tax': 'taxation',
    'taxes': 'taxation',
    'income tax': 'taxation',
    'direct tax': 'taxation',
    'political science': 'political science',
    'politics': 'political science',
    'poli sci': 'political science',
    'pol science': 'political science',
    'civics': 'political science',
    'polity': 'political science',
    'data analysis': 'data analytics',
    'analytics': 'data analytics',
    'calc': 'calculus',
    'maths': 'calculus',
    'mathematics': 'calculus',
    'physics': 'physics (mechanics)',
    'mechanics': 'physics (mechanics)',
    'communication': 'communication skills',
    'soft skills': 'communication skills',
    'software engineering': 'software engineering',
    'sdlc': 'software engineering',
  };

  // ---------------------------------------------------------------------------
  // Built-in subject knowledge base
  // ---------------------------------------------------------------------------

  static const Map<String, List<_TopicTemplate>> _library = {
    'financial accounting': [
      _TopicTemplate('Introduction to Accounting', 20, [
        'Meaning, objectives and scope of accounting',
        'Users of accounting information',
      ]),
      _TopicTemplate('Accounting Principles', 20, [
        'Concepts, conventions and assumptions',
        'The accounting equation',
      ]),
      _TopicTemplate('Accounting Standards', 20, [
        'Purpose and role of standards',
        'An overview of common standards',
      ]),
      _TopicTemplate('Journal Entries', 30, [
        'Meaning and purpose of journal entries',
        'Rules of debit and credit',
        'Types of journal entries',
      ]),
      _TopicTemplate('Ledger Accounts', 30, [
        'Posting from journal to ledger',
        'Balancing ledger accounts',
      ]),
      _TopicTemplate('Trial Balance', 30, [
        'Purpose of the trial balance',
        'How to prepare and balance it',
      ]),
      _TopicTemplate('Rectification of Errors', 35, [
        'Types of accounting errors',
        'How to correct them',
      ]),
      _TopicTemplate('Depreciation', 35, [
        'Meaning and causes of depreciation',
        'Straight-line vs written-down methods',
      ]),
      _TopicTemplate('Bank Reconciliation Statement', 35, [
        'Why cash book and passbook differ',
        'Preparing a reconciliation',
      ]),
      _TopicTemplate('Bills of Exchange', 30, [
        'Key terms and parties',
        'Accounting treatment',
      ]),
      _TopicTemplate('Final Accounts', 45, [
        'Trading and profit & loss account',
        'Preparing the balance sheet',
      ]),
      _TopicTemplate('Adjusting Entries', 30, [
        'Outstanding and prepaid items',
        'Accruals and provisions',
      ]),
      _TopicTemplate('Inventory Valuation', 30, [
        'FIFO, LIFO and weighted average',
        'Impact on profit',
      ]),
      _TopicTemplate('Cash Flow Statement', 40, [
        'Operating, investing and financing flows',
        'Preparing the statement',
      ]),
      _TopicTemplate('Ratio Analysis', 40, [
        'Liquidity, solvency and profitability ratios',
        'Interpreting the results',
      ]),
    ],
    'cost accounting': [
      _TopicTemplate('Introduction to Cost Accounting', 25, [
        'Cost accounting vs financial accounting',
        'Cost objects and cost units',
      ]),
      _TopicTemplate('Cost Classification', 30, [
        'Fixed, variable and semi-variable costs',
        'Direct vs indirect costs',
      ]),
      _TopicTemplate('Material Costing', 35, [
        'Stock valuation methods',
        'EOQ and reorder levels',
      ]),
      _TopicTemplate('Labour Costing', 30, [
        'Time and piece-rate systems',
        'Labour turnover',
      ]),
      _TopicTemplate('Overheads', 40, [
        'Allocation, apportionment and absorption',
        'Overhead recovery rates',
      ]),
      _TopicTemplate('Job & Batch Costing', 35, [
        'Costing for specific orders',
        'Job cost sheets',
      ]),
      _TopicTemplate('Process Costing', 45, [
        'Equivalent units',
        'Normal and abnormal loss',
      ]),
      _TopicTemplate('Marginal Costing & CVP', 45, [
        'Contribution and break-even analysis',
        'Cost-volume-profit relationships',
      ]),
      _TopicTemplate('Standard Costing & Variances', 45, [
        'Setting standards',
        'Material, labour and overhead variances',
      ]),
      _TopicTemplate('Budgeting', 40, [
        'Types of budgets',
        'Flexible and cash budgets',
      ]),
    ],
    'corporate finance': [
      _TopicTemplate('Introduction to Corporate Finance', 25, [
        'Role and goals of financial management',
        'Time value of money',
      ]),
      _TopicTemplate('Time Value of Money', 40, [
        'Present and future value',
        'Annuities and discounting',
      ]),
      _TopicTemplate('Risk and Return', 40, [
        'Measuring risk and return',
        'Diversification basics',
      ]),
      _TopicTemplate('Cost of Capital', 45, [
        'Cost of debt and equity',
        'Weighted average cost of capital',
      ]),
      _TopicTemplate('Capital Budgeting', 45, [
        'NPV, IRR and payback',
        'Evaluating investment projects',
      ]),
      _TopicTemplate('Capital Structure', 40, [
        'Debt vs equity mix',
        'Leverage and its effects',
      ]),
      _TopicTemplate('Working Capital Management', 35, [
        'Managing cash, receivables and inventory',
        'Operating cycle',
      ]),
      _TopicTemplate('Dividend Policy', 30, [
        'Dividend theories',
        'Payout decisions',
      ]),
      _TopicTemplate('Valuation', 40, [
        'Valuing bonds and shares',
        'Discounted cash flow',
      ]),
    ],
    'economics': [
      _TopicTemplate('Introduction to Economics', 25, [
        'Micro vs macro economics',
        'Scarcity and choice',
      ]),
      _TopicTemplate('Demand & Supply', 35, [
        'Laws of demand and supply',
        'Market equilibrium',
      ]),
      _TopicTemplate('Elasticity', 35, [
        'Price, income and cross elasticity',
        'Applications',
      ]),
      _TopicTemplate('Consumer Behaviour', 35, [
        'Utility analysis',
        'Indifference curves',
      ]),
      _TopicTemplate('Production & Costs', 40, [
        'Production function',
        'Cost concepts',
      ]),
      _TopicTemplate('Market Structures', 45, [
        'Perfect competition and monopoly',
        'Monopolistic and oligopoly',
      ]),
      _TopicTemplate('National Income', 40, [
        'GDP, GNP and measurement',
        'Circular flow',
      ]),
      _TopicTemplate('Inflation & Unemployment', 35, [
        'Causes and effects',
        'Policy responses',
      ]),
      _TopicTemplate('Money & Banking', 35, [
        'Functions of money',
        'Role of the central bank',
      ]),
      _TopicTemplate('Fiscal & Monetary Policy', 40, [
        'Government spending and taxes',
        'Interest-rate policy',
      ]),
    ],
    'microeconomics': [
      _TopicTemplate('Scarcity & Opportunity Cost', 25, [
        'Basic economic problem',
        'Production possibility frontier',
      ]),
      _TopicTemplate('Demand & Supply', 35, [
        'Determinants and shifts',
        'Equilibrium price and quantity',
      ]),
      _TopicTemplate('Elasticity', 35, [
        'Types of elasticity',
        'Applications to pricing',
      ]),
      _TopicTemplate('Consumer Theory', 40, [
        'Utility and marginal utility',
        'Budget lines and indifference curves',
      ]),
      _TopicTemplate('Theory of Production', 40, [
        'Short-run and long-run production',
        'Returns to scale',
      ]),
      _TopicTemplate('Costs of Production', 40, [
        'Fixed, variable and marginal cost',
        'Cost curves',
      ]),
      _TopicTemplate('Perfect Competition', 40, [
        'Firm and market equilibrium',
        'Short vs long run',
      ]),
      _TopicTemplate('Monopoly & Imperfect Competition', 45, [
        'Monopoly pricing',
        'Monopolistic competition and oligopoly',
      ]),
      _TopicTemplate('Factor Markets', 35, [
        'Wages, rent, interest and profit',
        'Marginal productivity',
      ]),
    ],
    'macroeconomics': [
      _TopicTemplate('Introduction to Macroeconomics', 25, [
        'Scope and key questions',
        'Stock vs flow variables',
      ]),
      _TopicTemplate('National Income Accounting', 40, [
        'GDP measurement approaches',
        'Nominal vs real GDP',
      ]),
      _TopicTemplate('Aggregate Demand & Supply', 45, [
        'AD-AS model',
        'Equilibrium output',
      ]),
      _TopicTemplate('Consumption & Investment', 40, [
        'Keynesian consumption function',
        'Multiplier effect',
      ]),
      _TopicTemplate('Money & Inflation', 40, [
        'Money supply and demand',
        'Causes of inflation',
      ]),
      _TopicTemplate('Unemployment', 30, [
        'Types of unemployment',
        'Measurement',
      ]),
      _TopicTemplate('Fiscal Policy', 40, [
        'Government spending and taxation',
        'Budget deficits',
      ]),
      _TopicTemplate('Monetary Policy', 40, [
        'Central bank tools',
        'Interest rates and transmission',
      ]),
      _TopicTemplate('Open Economy & Trade', 35, [
        'Balance of payments',
        'Exchange rates',
      ]),
    ],
    'marketing management': [
      _TopicTemplate('Introduction to Marketing', 25, [
        'Core marketing concepts',
        'Marketing vs selling',
      ]),
      _TopicTemplate('Marketing Environment', 30, [
        'Micro and macro environment',
        'Environmental scanning',
      ]),
      _TopicTemplate('Consumer Behaviour', 35, [
        'Factors influencing buyers',
        'The buying decision process',
      ]),
      _TopicTemplate('Market Segmentation', 35, [
        'Bases of segmentation',
        'Targeting and positioning',
      ]),
      _TopicTemplate('Product Decisions', 35, [
        'Product levels and mix',
        'Product life cycle',
      ]),
      _TopicTemplate('Pricing Decisions', 40, [
        'Pricing objectives',
        'Pricing methods',
      ]),
      _TopicTemplate('Distribution Channels', 30, [
        'Channel levels',
        'Channel management',
      ]),
      _TopicTemplate('Promotion Mix', 35, [
        'Advertising, sales promotion, PR',
        'Personal selling',
      ]),
      _TopicTemplate('Digital Marketing', 35, [
        'Online channels overview',
        'Social media basics',
      ]),
      _TopicTemplate('Marketing Strategy', 40, [
        'Building a marketing plan',
        'Competitive strategy',
      ]),
    ],
    'digital marketing': [
      _TopicTemplate('Digital Marketing Overview', 25, [
        'Channels and the customer journey',
        'Inbound vs outbound',
      ]),
      _TopicTemplate('Website & Landing Pages', 30, [
        'Conversion-focused design',
        'Calls to action',
      ]),
      _TopicTemplate('Search Engine Optimisation', 45, [
        'On-page and off-page SEO',
        'Keywords and intent',
      ]),
      _TopicTemplate('Search & Display Ads', 40, [
        'PPC fundamentals',
        'Campaign structure',
      ]),
      _TopicTemplate('Social Media Marketing', 35, [
        'Platform strategies',
        'Content calendars',
      ]),
      _TopicTemplate('Content Marketing', 35, [
        'Content types and funnels',
        'Storytelling',
      ]),
      _TopicTemplate('Email Marketing', 30, [
        'List building and segmentation',
        'Automation basics',
      ]),
      _TopicTemplate('Analytics & Measurement', 40, [
        'Key metrics and KPIs',
        'Reading analytics dashboards',
      ]),
    ],
    'human resource management': [
      _TopicTemplate('Introduction to HRM', 25, [
        'Scope and functions of HRM',
        'Role of the HR manager',
      ]),
      _TopicTemplate('Human Resource Planning', 35, [
        'Forecasting demand and supply',
        'Job analysis',
      ]),
      _TopicTemplate('Recruitment & Selection', 35, [
        'Sources of recruitment',
        'Selection process',
      ]),
      _TopicTemplate('Training & Development', 35, [
        'Training methods',
        'Evaluating effectiveness',
      ]),
      _TopicTemplate('Performance Appraisal', 35, [
        'Appraisal methods',
        'Common errors',
      ]),
      _TopicTemplate('Compensation & Benefits', 35, [
        'Wage and salary administration',
        'Incentives',
      ]),
      _TopicTemplate('Employee Relations', 30, [
        'Grievance handling',
        'Discipline',
      ]),
      _TopicTemplate('Industrial Relations', 35, [
        'Trade unions',
        'Collective bargaining',
      ]),
    ],
    'organizational behaviour': [
      _TopicTemplate('Introduction to OB', 25, [
        'What OB studies',
        'Individual, group and organisation levels',
      ]),
      _TopicTemplate('Personality & Attitudes', 35, [
        'Personality traits',
        'Job attitudes',
      ]),
      _TopicTemplate('Perception & Learning', 35, [
        'Perception process',
        'Learning theories',
      ]),
      _TopicTemplate('Motivation Theories', 40, [
        'Content and process theories',
        'Applying motivation at work',
      ]),
      _TopicTemplate('Group Dynamics', 35, [
        'Group formation',
        'Team effectiveness',
      ]),
      _TopicTemplate('Leadership', 40, [
        'Trait, behavioural and contingency theories',
        'Leadership styles',
      ]),
      _TopicTemplate('Communication', 30, [
        'Communication process',
        'Barriers',
      ]),
      _TopicTemplate('Organisational Culture & Change', 40, [
        'Culture and its dimensions',
        'Managing change',
      ]),
    ],
    'business law': [
      _TopicTemplate('Introduction to Business Law', 25, [
        'Nature and sources of law',
        'Legal environment of business',
      ]),
      _TopicTemplate('Indian Contract Act — Basics', 35, [
        'Essentials of a valid contract',
        'Offer and acceptance',
      ]),
      _TopicTemplate('Consideration & Capacity', 30, [
        'Meaning of consideration',
        'Competency to contract',
      ]),
      _TopicTemplate('Performance & Discharge', 35, [
        'Performance of contracts',
        'Modes of discharge',
      ]),
      _TopicTemplate('Breach & Remedies', 35, [
        'Types of breach',
        'Remedies available',
      ]),
      _TopicTemplate('Sale of Goods Act', 35, [
        'Conditions and warranties',
        'Transfer of ownership',
      ]),
      _TopicTemplate('Partnership Act', 35, [
        'Nature of partnership',
        'Rights and duties of partners',
      ]),
      _TopicTemplate('Negotiable Instruments', 30, [
        'Cheques, bills and promissory notes',
        'Key features',
      ]),
      _TopicTemplate('Consumer Protection', 30, [
        'Consumer rights',
        'Redressal mechanisms',
      ]),
    ],
    'dbms': [
      _TopicTemplate('Introduction to DBMS', 25, [
        'What a database and DBMS are',
        'Advantages over file systems',
      ]),
      _TopicTemplate('Database Architecture', 25, [
        'Three-schema architecture',
        'Data independence',
      ]),
      _TopicTemplate('ER Model', 35, [
        'Entities, attributes and relationships',
        'Drawing ER diagrams',
      ]),
      _TopicTemplate('Relational Model', 30, [
        'Relations, tuples and keys',
        'Integrity constraints',
      ]),
      _TopicTemplate('Relational Algebra', 40, [
        'Selection, projection and joins',
        'Set operations',
      ]),
      _TopicTemplate('SQL Basics', 40, [
        'DDL and DML statements',
        'Querying with SELECT',
      ]),
      _TopicTemplate('Advanced SQL', 40, [
        'Joins, subqueries and grouping',
        'Views and constraints',
      ]),
      _TopicTemplate('Normalization', 45, [
        'Functional dependencies',
        '1NF, 2NF, 3NF and BCNF',
        'Why we normalise',
      ]),
      _TopicTemplate('Transactions', 40, [
        'ACID properties',
        'Transaction states',
      ]),
      _TopicTemplate('Concurrency Control', 45, [
        'Locking protocols',
        'Serializability',
      ]),
      _TopicTemplate('Indexing', 40, [
        'B-trees and hashing',
        'When indexes help',
      ]),
      _TopicTemplate('Recovery & Logging', 35, [
        'Log-based recovery',
        'Checkpoints',
      ]),
      _TopicTemplate('Query Processing', 35, [
        'Query evaluation',
        'Basic optimisation',
      ]),
      _TopicTemplate('NoSQL Overview', 25, [
        'Types of NoSQL databases',
        'When to use them',
      ]),
    ],
    'operating systems': [
      _TopicTemplate('Introduction to OS', 25, [
        'Role and functions of an OS',
        'Types of operating systems',
      ]),
      _TopicTemplate('Process Management', 35, [
        'Processes and process states',
        'Process control block',
      ]),
      _TopicTemplate('CPU Scheduling', 45, [
        'Scheduling criteria',
        'FCFS, SJF, Round Robin',
      ]),
      _TopicTemplate('Threads & Concurrency', 35, [
        'Threads vs processes',
        'Multithreading models',
      ]),
      _TopicTemplate('Process Synchronization', 45, [
        'Critical section problem',
        'Semaphores and mutexes',
      ]),
      _TopicTemplate('Deadlocks', 45, [
        'Conditions for deadlock',
        'Prevention, avoidance, detection',
      ]),
      _TopicTemplate('Memory Management', 45, [
        'Paging and segmentation',
        'Address translation',
      ]),
      _TopicTemplate('Virtual Memory', 45, [
        'Demand paging',
        'Page replacement algorithms',
      ]),
      _TopicTemplate('File Systems', 30, [
        'File concepts and access',
        'Directory structures',
      ]),
      _TopicTemplate('Disk Scheduling', 35, [
        'Disk structure',
        'FCFS, SSTF, SCAN',
      ]),
      _TopicTemplate('I/O Systems', 25, [
        'I/O hardware and software',
        'Buffering',
      ]),
    ],
    'data structures & algorithms': [
      _TopicTemplate('Complexity Analysis', 35, [
        'Big-O, big-Theta and big-Omega',
        'Time vs space trade-offs',
      ]),
      _TopicTemplate('Arrays & Strings', 30, [
        'Traversal and manipulation',
        'Common patterns (two pointers)',
      ]),
      _TopicTemplate('Linked Lists', 35, [
        'Singly and doubly linked lists',
        'Insertion, deletion, reversal',
      ]),
      _TopicTemplate('Stacks & Queues', 30, [
        'LIFO and FIFO structures',
        'Applications',
      ]),
      _TopicTemplate('Recursion & Backtracking', 45, [
        'Thinking recursively',
        'Backtracking template',
      ]),
      _TopicTemplate('Sorting Algorithms', 40, [
        'Merge, quick and heap sort',
        'Stability and complexity',
      ]),
      _TopicTemplate('Searching & Binary Search', 35, [
        'Binary search and variants',
        'Search on answer',
      ]),
      _TopicTemplate('Hashing', 35, [
        'Hash tables and collisions',
        'When to use hashing',
      ]),
      _TopicTemplate('Trees & BST', 45, [
        'Binary trees and traversals',
        'Binary search trees',
      ]),
      _TopicTemplate('Heaps & Priority Queues', 40, [
        'Heap operations',
        'Applications',
      ]),
      _TopicTemplate('Graphs & Traversals', 45, [
        'Representations',
        'BFS and DFS',
      ]),
      _TopicTemplate('Shortest Paths & MST', 45, [
        'Dijkstra and Bellman-Ford',
        'Kruskal and Prim',
      ]),
      _TopicTemplate('Dynamic Programming', 50, [
        'Overlapping subproblems',
        'Classic DP patterns',
      ]),
      _TopicTemplate('Greedy Algorithms', 40, [
        'Greedy choice property',
        'Common greedy problems',
      ]),
    ],
    'computer networks': [
      _TopicTemplate('Introduction & Topologies', 25, [
        'Network types and topologies',
        'Uses of networks',
      ]),
      _TopicTemplate('OSI & TCP/IP Models', 40, [
        'Layered architecture',
        'Encapsulation',
      ]),
      _TopicTemplate('Physical Layer', 30, [
        'Signals and media',
        'Bandwidth and data rate',
      ]),
      _TopicTemplate('Data Link Layer', 40, [
        'Framing and error control',
        'MAC and switching',
      ]),
      _TopicTemplate('Network Layer & IP', 45, [
        'IP addressing and subnetting',
        'Routing basics',
      ]),
      _TopicTemplate('Routing Algorithms', 45, [
        'Distance vector and link state',
        'Routing protocols',
      ]),
      _TopicTemplate('Transport Layer', 45, [
        'TCP vs UDP',
        'Flow and congestion control',
      ]),
      _TopicTemplate('Application Layer', 35, [
        'HTTP, DNS, SMTP',
        'Client-server model',
      ]),
      _TopicTemplate('Network Security Basics', 35, [
        'Threats and encryption',
        'Firewalls',
      ]),
    ],
    'machine learning': [
      _TopicTemplate('What is Machine Learning', 25, [
        'Supervised, unsupervised, reinforcement',
        'Typical ML workflow',
      ]),
      _TopicTemplate('Data Preprocessing', 40, [
        'Cleaning and encoding',
        'Feature scaling',
      ]),
      _TopicTemplate('Linear Regression', 45, [
        'Hypothesis and cost function',
        'Gradient descent',
      ]),
      _TopicTemplate('Logistic Regression', 45, [
        'Classification and sigmoid',
        'Decision boundaries',
      ]),
      _TopicTemplate('Model Evaluation', 40, [
        'Train/validation/test split',
        'Accuracy, precision, recall, ROC',
      ]),
      _TopicTemplate('Overfitting & Regularization', 40, [
        'Bias-variance trade-off',
        'L1/L2 regularization',
      ]),
      _TopicTemplate('Decision Trees & Ensembles', 45, [
        'Trees, random forests, boosting',
        'Feature importance',
      ]),
      _TopicTemplate('Clustering', 40, [
        'K-means and hierarchical clustering',
        'Choosing k',
      ]),
      _TopicTemplate('Dimensionality Reduction', 40, [
        'PCA intuition',
        'When to reduce dimensions',
      ]),
      _TopicTemplate('Intro to Neural Networks', 45, [
        'Neurons and activation',
        'Forward and back propagation (intuition)',
      ]),
    ],
    'python': [
      _TopicTemplate('Getting Started with Python', 25, [
        'Installing Python and running scripts',
        'Using the interpreter',
      ]),
      _TopicTemplate('Variables & Data Types', 30, [
        'Numbers, strings and booleans',
        'Type conversion',
      ]),
      _TopicTemplate('Operators & Expressions', 25, [
        'Arithmetic and logical operators',
        'Operator precedence',
      ]),
      _TopicTemplate('Control Flow', 35, [
        'if / elif / else',
        'while and for loops',
      ]),
      _TopicTemplate('Functions', 35, [
        'Defining and calling functions',
        'Arguments and return values',
      ]),
      _TopicTemplate('Lists & Tuples', 35, [
        'Creating and indexing sequences',
        'Common operations',
      ]),
      _TopicTemplate('Dictionaries & Sets', 30, [
        'Key-value pairs',
        'Set operations',
      ]),
      _TopicTemplate('Strings & Formatting', 30, [
        'String methods',
        'f-strings and formatting',
      ]),
      _TopicTemplate('File Handling', 30, [
        'Reading and writing files',
        'Working with paths',
      ]),
      _TopicTemplate('Error Handling', 30, [
        'try / except / finally',
        'Raising exceptions',
      ]),
      _TopicTemplate('Modules & Packages', 25, [
        'Importing modules',
        'The standard library',
      ]),
      _TopicTemplate('Object-Oriented Python', 45, [
        'Classes and objects',
        'Inheritance and methods',
      ]),
      _TopicTemplate('Comprehensions & Generators', 40, [
        'List/dict comprehensions',
        'Generators and iterators',
      ]),
      _TopicTemplate('Working with Libraries', 30, [
        'Using pip',
        'A first look at popular libraries',
      ]),
    ],
    'java': [
      _TopicTemplate('Java Basics & JVM', 30, [
        'How Java runs (JVM, JDK, JRE)',
        'Writing and compiling a program',
      ]),
      _TopicTemplate('Variables & Data Types', 30, [
        'Primitives and references',
        'Type casting',
      ]),
      _TopicTemplate('Operators & Control Flow', 35, [
        'Conditionals and loops',
        'Switch statements',
      ]),
      _TopicTemplate('Methods & Arrays', 35, [
        'Defining methods',
        'Arrays and iteration',
      ]),
      _TopicTemplate('OOP: Classes & Objects', 40, [
        'Encapsulation',
        'Constructors',
      ]),
      _TopicTemplate('Inheritance & Polymorphism', 45, [
        'Extending classes',
        'Overriding and overloading',
      ]),
      _TopicTemplate('Interfaces & Abstraction', 40, [
        'Abstract classes and interfaces',
        'When to use each',
      ]),
      _TopicTemplate('Exception Handling', 35, [
        'try/catch/finally',
        'Checked vs unchecked',
      ]),
      _TopicTemplate('Collections Framework', 45, [
        'List, Set, Map',
        'Iterators and generics',
      ]),
      _TopicTemplate('Strings & Wrapper Classes', 30, [
        'String, StringBuilder',
        'Autoboxing',
      ]),
      _TopicTemplate('File I/O & Streams', 35, [
        'Reading and writing files',
        'Streams basics',
      ]),
    ],
    'c programming': [
      _TopicTemplate('Introduction to C', 25, [
        'Structure of a C program',
        'Compiling and running',
      ]),
      _TopicTemplate('Variables & Data Types', 30, [
        'Types and sizes',
        'Format specifiers',
      ]),
      _TopicTemplate('Operators & Expressions', 30, [
        'Arithmetic, relational, logical',
        'Precedence',
      ]),
      _TopicTemplate('Control Statements', 35, [
        'if, switch, loops',
        'break and continue',
      ]),
      _TopicTemplate('Functions', 35, [
        'Declaration and definition',
        'Call by value',
      ]),
      _TopicTemplate('Arrays & Strings', 35, [
        'Single and multi-dimensional arrays',
        'String functions',
      ]),
      _TopicTemplate('Pointers', 45, [
        'Pointer basics',
        'Pointers and arrays',
      ]),
      _TopicTemplate('Structures & Unions', 40, [
        'Defining structures',
        'Unions',
      ]),
      _TopicTemplate('Dynamic Memory', 40, [
        'malloc, calloc, free',
        'Memory leaks',
      ]),
      _TopicTemplate('File Handling', 35, [
        'File pointers',
        'Reading and writing files',
      ]),
    ],
    'web development': [
      _TopicTemplate('How the Web Works', 25, [
        'Client-server and HTTP',
        'Browsers and rendering',
      ]),
      _TopicTemplate('HTML Fundamentals', 30, [
        'Document structure',
        'Semantic elements',
      ]),
      _TopicTemplate('CSS Fundamentals', 40, [
        'Selectors and the box model',
        'Colours and typography',
      ]),
      _TopicTemplate('Responsive Layout', 45, [
        'Flexbox and grid',
        'Media queries',
      ]),
      _TopicTemplate('JavaScript Basics', 45, [
        'Variables, types and functions',
        'DOM manipulation',
      ]),
      _TopicTemplate('Events & Forms', 40, [
        'Handling events',
        'Form validation',
      ]),
      _TopicTemplate('Async JS & Fetch', 45, [
        'Promises and async/await',
        'Calling APIs',
      ]),
      _TopicTemplate('Intro to a Framework', 45, [
        'Component thinking',
        'State and props (concept)',
      ]),
      _TopicTemplate('Version Control with Git', 30, [
        'Commits, branches, merges',
        'Working with remotes',
      ]),
      _TopicTemplate('Deploying a Site', 30, [
        'Hosting basics',
        'Domains and HTTPS',
      ]),
    ],
    'software engineering': [
      _TopicTemplate('Introduction to SE', 25, [
        'Software process and quality',
        'Roles in a team',
      ]),
      _TopicTemplate('Software Development Life Cycle', 35, [
        'Waterfall, iterative, spiral',
        'When each fits',
      ]),
      _TopicTemplate('Agile & Scrum', 35, [
        'Agile values',
        'Sprints, roles and ceremonies',
      ]),
      _TopicTemplate('Requirements Engineering', 40, [
        'Eliciting requirements',
        'Functional vs non-functional',
      ]),
      _TopicTemplate('Software Design', 45, [
        'Modularity and coupling/cohesion',
        'Design principles',
      ]),
      _TopicTemplate('UML & Modelling', 40, [
        'Use case and class diagrams',
        'Sequence diagrams',
      ]),
      _TopicTemplate('Testing & QA', 40, [
        'Unit, integration, system testing',
        'Test cases',
      ]),
      _TopicTemplate('Maintenance & Project Management', 35, [
        'Types of maintenance',
        'Estimation and risk',
      ]),
    ],
    'statistics': [
      _TopicTemplate('Introduction to Statistics', 25, [
        'Population vs sample',
        'Types of data',
      ]),
      _TopicTemplate('Descriptive Statistics', 40, [
        'Mean, median, mode',
        'Variance and standard deviation',
      ]),
      _TopicTemplate('Data Visualisation', 30, [
        'Histograms and box plots',
        'Reading distributions',
      ]),
      _TopicTemplate('Probability Basics', 40, [
        'Rules of probability',
        'Conditional probability',
      ]),
      _TopicTemplate('Probability Distributions', 45, [
        'Binomial and normal',
        'Using distribution tables',
      ]),
      _TopicTemplate('Sampling & Estimation', 40, [
        'Sampling methods',
        'Confidence intervals',
      ]),
      _TopicTemplate('Hypothesis Testing', 45, [
        'Null and alternative hypotheses',
        't-tests and p-values',
      ]),
      _TopicTemplate('Correlation & Regression', 45, [
        'Correlation coefficient',
        'Simple linear regression',
      ]),
      _TopicTemplate('Chi-Square & ANOVA', 40, [
        'Goodness of fit',
        'Comparing group means',
      ]),
    ],
    'data analytics': [
      _TopicTemplate('Introduction to Data Analytics', 25, [
        'What data analytics is',
        'The analytics workflow',
      ]),
      _TopicTemplate('Types of Analytics', 25, [
        'Descriptive, diagnostic, predictive',
        'Prescriptive analytics',
      ]),
      _TopicTemplate('Data Collection & Sources', 30, [
        'Structured vs unstructured data',
        'Sampling basics',
      ]),
      _TopicTemplate('Data Cleaning', 40, [
        'Handling missing values',
        'Removing duplicates and outliers',
      ]),
      _TopicTemplate('Descriptive Statistics', 40, [
        'Mean, median, mode, variance',
        'Distributions',
      ]),
      _TopicTemplate('Data Visualization', 35, [
        'Choosing the right chart',
        'Dashboards',
      ]),
      _TopicTemplate('Exploratory Data Analysis', 45, [
        'Finding patterns and correlations',
        'Feature relationships',
      ]),
      _TopicTemplate('Inferential Statistics', 45, [
        'Hypothesis testing',
        'Confidence intervals',
      ]),
      _TopicTemplate('Regression', 45, [
        'Linear regression',
        'Interpreting results',
      ]),
      _TopicTemplate('Intro to Predictive Modelling', 40, [
        'Training vs test data',
        'Evaluating models',
      ]),
      _TopicTemplate('Tools: SQL & Spreadsheets', 35, [
        'Querying data',
        'Pivot tables and formulas',
      ]),
    ],
    'calculus': [
      _TopicTemplate('Functions & Graphs', 30, [
        'Types of functions',
        'Domain and range',
      ]),
      _TopicTemplate('Limits', 40, [
        'Concept of a limit',
        'Evaluating limits',
      ]),
      _TopicTemplate('Continuity', 30, [
        'Continuous functions',
        'Types of discontinuity',
      ]),
      _TopicTemplate('Derivatives', 45, [
        'Definition and rules',
        'Product, quotient, chain rule',
      ]),
      _TopicTemplate('Applications of Derivatives', 45, [
        'Maxima and minima',
        'Rates of change',
      ]),
      _TopicTemplate('Integration', 45, [
        'Antiderivatives',
        'Definite integrals',
      ]),
      _TopicTemplate('Techniques of Integration', 45, [
        'Substitution',
        'Integration by parts',
      ]),
      _TopicTemplate('Applications of Integration', 40, [
        'Area under curves',
        'Volumes',
      ]),
      _TopicTemplate('Differential Equations (Intro)', 40, [
        'First-order equations',
        'Separable equations',
      ]),
    ],
    'physics (mechanics)': [
      _TopicTemplate('Units & Measurement', 25, [
        'SI units and dimensions',
        'Significant figures',
      ]),
      _TopicTemplate('Kinematics', 40, [
        'Motion in a straight line',
        'Equations of motion',
      ]),
      _TopicTemplate('Projectile & 2D Motion', 40, [
        'Vectors',
        'Projectile trajectories',
      ]),
      _TopicTemplate("Newton's Laws of Motion", 45, [
        'Three laws',
        'Free-body diagrams',
      ]),
      _TopicTemplate('Friction & Circular Motion', 40, [
        'Types of friction',
        'Centripetal force',
      ]),
      _TopicTemplate('Work, Energy & Power', 45, [
        'Work-energy theorem',
        'Conservation of energy',
      ]),
      _TopicTemplate('Momentum & Collisions', 40, [
        'Conservation of momentum',
        'Elastic and inelastic collisions',
      ]),
      _TopicTemplate('Rotational Motion', 45, [
        'Torque and moment of inertia',
        'Angular momentum',
      ]),
      _TopicTemplate('Gravitation', 35, [
        "Newton's law of gravitation",
        'Orbits',
      ]),
    ],
    'communication skills': [
      _TopicTemplate('Communication Basics', 20, [
        'The communication process',
        'Verbal vs non-verbal',
      ]),
      _TopicTemplate('Barriers to Communication', 25, [
        'Common barriers',
        'Overcoming them',
      ]),
      _TopicTemplate('Listening Skills', 25, [
        'Active listening',
        'Giving feedback',
      ]),
      _TopicTemplate('Written Communication', 35, [
        'Emails and reports',
        'Clarity and tone',
      ]),
      _TopicTemplate('Presentation Skills', 40, [
        'Structuring a talk',
        'Delivery and visuals',
      ]),
      _TopicTemplate('Group Discussions & Interviews', 35, [
        'GD strategies',
        'Interview communication',
      ]),
      _TopicTemplate('Body Language', 25, [
        'Posture and gestures',
        'Eye contact',
      ]),
    ],
  };
}
