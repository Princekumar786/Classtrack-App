import 'package:classtrack/features/learning_planner/domain/learning_plan.dart';
import 'package:classtrack/features/learning_planner/domain/learning_plan_generator.dart';
import 'package:flutter_test/flutter_test.dart';

PlanRequest _req(
  String subject, {
  StudyRegion region = StudyRegion.global,
  StudyProgram program = StudyProgram.general,
  KnowledgeLevel level = KnowledgeLevel.basics,
}) =>
    PlanRequest(
      subject: subject,
      specificTopic: false,
      level: level,
      goal: LearningGoal.fundamentals,
      dailyMinutes: 60,
      studyDays: const {1, 2, 3, 4, 5},
      targetDate: DateTime.now().add(const Duration(days: 30)),
      region: region,
      program: program,
    );

void main() {
  const gen = LearningPlanGenerator();

  test('Corporate Governance no longer maps to Corporate Finance', () {
    final plan = gen.generate(_req('Corporate Governance',
        region: StudyRegion.india, program: StudyProgram.undergraduate));
    final titles = plan.topics.map((t) => t.title.toLowerCase()).join(' | ');
    expect(titles.contains('governance'), isTrue);
    // Corporate Finance signature topics must NOT appear.
    expect(titles.contains('cost of capital'), isFalse);
    expect(titles.contains('capital budgeting'), isFalse);
    expect(titles.contains('working capital'), isFalse);
  });

  test('Business Law is jurisdiction-specific (US vs India)', () {
    final india = gen.generate(_req('Business Law', region: StudyRegion.india));
    final us =
        gen.generate(_req('Business Law', region: StudyRegion.unitedStates));
    final indiaTitles = india.topics.map((t) => t.title).join(' | ');
    final usTitles = us.topics.map((t) => t.title).join(' | ');

    expect(indiaTitles.contains('Indian Contract Act'), isTrue);
    expect(usTitles.contains('Indian Contract Act'), isFalse);
    expect(
        usTitles.toLowerCase().contains('ucc') ||
            usTitles.contains('Torts') ||
            usTitles.contains('US Legal System'),
        isTrue);
  });

  test('Same subject differs by program (undergraduate vs MBA)', () {
    final ug = gen.generate(
        _req('Business Law', program: StudyProgram.undergraduate));
    final mba = gen.generate(
        _req('Business Law', program: StudyProgram.postgraduate));
    final ugTitles = ug.topics.map((t) => t.title).join(' | ');
    final mbaTitles = mba.topics.map((t) => t.title).join(' | ');

    expect(ugTitles.contains('Case law & legal reasoning'), isTrue);
    expect(mbaTitles.contains('Legal risk & compliance for managers'), isTrue);
    expect(ugTitles == mbaTitles, isFalse);
  });

  test('Taxation adapts to region (UK vs India)', () {
    final india = gen.generate(_req('Taxation', region: StudyRegion.india));
    final uk =
        gen.generate(_req('Taxation', region: StudyRegion.unitedKingdom));
    final indiaTitles = india.topics.map((t) => t.title).join(' | ');
    final ukTitles = uk.topics.map((t) => t.title).join(' | ');

    expect(indiaTitles.toLowerCase().contains('gst'), isTrue);
    expect(ukTitles.contains('VAT') || ukTitles.contains('National Insurance'),
        isTrue);
    expect(ukTitles.toLowerCase().contains('gst'), isFalse);
  });

  test('region & program survive a JSON round-trip', () {
    final plan = gen.generate(_req('Taxation',
        region: StudyRegion.unitedKingdom, program: StudyProgram.professional));
    final round = LearningPlan.fromJson(plan.toJson());
    expect(round.region, StudyRegion.unitedKingdom);
    expect(round.program, StudyProgram.professional);
  });

  test('fromCountryName maps profile country to region', () {
    expect(StudyRegionX.fromCountryName('India'), StudyRegion.india);
    expect(StudyRegionX.fromCountryName('United States'),
        StudyRegion.unitedStates);
    expect(StudyRegionX.fromCountryName('United Kingdom'),
        StudyRegion.unitedKingdom);
    expect(StudyRegionX.fromCountryName(null), StudyRegion.global);
    expect(StudyRegionX.fromCountryName('Nigeria'), StudyRegion.global);
  });

  test('topics carry a curriculum breakdown (sections + criteria)', () {
    final plan = gen.generate(_req('DBMS'));
    final t = plan.topics.firstWhere((t) => !t.isReview);
    expect(t.sections, isNotEmpty);
    expect(t.completionCriteria, isNotEmpty);
    // Section minutes should roughly sum to the topic estimate.
    final sum = t.sections.fold<int>(0, (s, e) => s + e.minutes);
    expect(sum, greaterThan(0));
  });

  test('plan groups topics into curriculum units incl. Revision', () {
    final plan = gen.generate(_req('DBMS'));
    expect(plan.units.length, greaterThanOrEqualTo(2));
    expect(plan.units.any((u) => u.title == 'Revision'), isTrue);
  });

  test('needsCurriculumContext true for law, false for generic subjects', () {
    expect(gen.needsCurriculumContext('Business Law'), isTrue);
    expect(gen.needsCurriculumContext('Taxation'), isTrue);
    expect(gen.needsCurriculumContext('Corporate Governance'), isTrue);
    expect(gen.needsCurriculumContext('Politics'), isTrue);
    expect(gen.needsCurriculumContext('Python'), isFalse);
    expect(gen.needsCurriculumContext('DBMS'), isFalse);
    expect(gen.needsCurriculumContext('Mathematics'), isFalse);
  });

  test('Politics adapts to location (India vs US)', () {
    final india = gen.generate(_req('Politics', region: StudyRegion.india));
    final us = gen.generate(
        _req('Political Science', region: StudyRegion.unitedStates));
    final indiaTitles = india.topics.map((t) => t.title).join(' | ');
    final usTitles = us.topics.map((t) => t.title).join(' | ');
    expect(indiaTitles.contains('Indian Constitution'), isTrue);
    expect(usTitles.contains('US Constitution & Federalism'), isTrue);
    expect(usTitles.contains('Indian Constitution'), isFalse);
  });

  test('paceFactor reflects logged vs estimated time', () {
    final plan = gen.generate(_req('DBMS'));
    final t = plan.topics.first;
    expect(plan.paceFactor, isNull); // no data yet
    t.actualMinutes = t.estMinutes * 2; // took twice as long
    expect(plan.paceFactor, closeTo(2.0, 0.001));
    expect(plan.totalStudiedMinutes, t.estMinutes * 2);
  });

  test('dayForToday returns a due day for a fresh plan', () {
    final plan = gen.generate(_req('DBMS'));
    expect(plan.dayForToday, isNotNull);
  });

  test('manual plan keeps exactly the user topics (no auto-review)', () {
    final core = [
      LearningTopic(id: 'a', title: 'My topic A', estMinutes: 30),
      LearningTopic(id: 'b', title: 'My topic B', estMinutes: 45),
      LearningTopic(id: 'c', title: 'My topic C', estMinutes: 20),
    ];
    final plan =
        gen.assembleFromCore(_req('My revision'), core, addReviews: false);
    expect(plan.topics.length, 3);
    expect(plan.topics.any((t) => t.isReview), isFalse);
    expect(plan.topics.first.sections, isNotEmpty);
    expect(plan.weeks.isNotEmpty, isTrue);
  });

  test('topic sections are specific (real subtopics, no generic filler)', () {
    final plan = gen.generate(_req('DBMS'));
    final norm = plan.topics.firstWhere((t) => t.title == 'Normalization');
    final allPoints =
        norm.sections.expand((s) => s.points).map((p) => p.toLowerCase());
    // Real DBMS concepts should appear...
    expect(
        allPoints.any((p) => p.contains('functional dependencies')), isTrue);
    // ...and the old generic filler must NOT.
    for (final t in plan.topics) {
      final pts = t.sections.expand((s) => s.points).map((p) => p.toLowerCase());
      expect(pts.contains('work through examples'), isFalse);
      expect(pts.contains('connect the ideas together'), isFalse);
      expect(pts.contains('test your understanding'), isFalse);
    }
  });

  test('manual topic uses the user-provided subtopics', () {
    final core = [
      LearningTopic(
        id: 'x',
        title: 'My topic',
        estMinutes: 40,
        objectives: const ['My subtopic A', 'My subtopic B'],
      ),
    ];
    final plan =
        gen.assembleFromCore(_req('Custom'), core, addReviews: false);
    final pts = plan.topics.first.sections.expand((s) => s.points).toList();
    expect(pts.contains('My subtopic A'), isTrue);
    expect(pts.contains('My subtopic B'), isTrue);
  });
}
