import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/providers/gemini_provider.dart';
import '../../../../services/notification_service.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../data/ai_plan_service.dart';
import '../../data/learning_plan_repository.dart';
import '../../domain/learning_plan.dart';
import '../../domain/learning_plan_generator.dart';

/// Number of active learning plans a free user may keep. Creating beyond this
/// requires ClassTrack Pro.
const int kFreeLearningPlanLimit = 2;

/// The plan-generation engine (stateless — safe to share).
final learningPlanGeneratorProvider =
    Provider<LearningPlanGenerator>((ref) => const LearningPlanGenerator());

/// Best-effort AI topic generator (Gemini via Cloud Functions).
final aiPlanServiceProvider = Provider<AiPlanService>((ref) {
  return AiPlanService(ref.watch(geminiServiceProvider));
});

/// Cloud repository for the signed-in user's plans (null when logged out).
final learningPlanRepositoryProvider =
    Provider<LearningPlanRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return LearningPlanRepository(db: ref.watch(firestoreProvider), uid: uid);
});

/// Store of the signed-in user's learning plans, backed by Firestore
/// (`users/{uid}/learningPlans`). It streams the cloud collection into [state]
/// and writes every mutation back — so plans survive sign-out/sign-in and sync
/// across devices. Mutations update [state] optimistically for instant UI.
class LearningPlannerController extends StateNotifier<List<LearningPlan>> {
  LearningPlannerController(this._repo) : super(const []) {
    final repo = _repo;
    if (repo != null) {
      _sub = repo.watchPlans().listen((plans) {
        if (mounted) state = plans;
      });
    }
  }

  final LearningPlanRepository? _repo;
  StreamSubscription<List<LearningPlan>>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  LearningPlan? byId(String id) {
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Replaces [plan] in [state] (fresh identity) and persists it to Firestore.
  Future<void> _commit(LearningPlan plan) async {
    state = [
      for (final p in state)
        if (p.id == plan.id) plan else p,
    ];
    await _repo?.save(plan);
  }

  Future<void> addPlan(LearningPlan plan) async {
    state = [plan, ...state];
    await _repo?.save(plan);
    // Count every created plan toward the lifetime total so the free-tier
    // limit can't be bypassed by deleting and recreating plans.
    await _repo?.incrementPlansCreated();
  }

  Future<void> deletePlan(String id) async {
    state = state.where((p) => p.id != id).toList();
    await _repo?.delete(id);
  }

  /// Replaces a plan in place (keeping its position in the list).
  Future<void> updatePlan(LearningPlan plan) => _commit(plan);

  Future<void> setTopicStatus(
      String planId, String topicId, TopicStatus status) async {
    final plan = byId(planId);
    if (plan == null) return;
    final topic = plan.topicById(topicId);
    if (topic == null) return;
    topic.status = status;
    await _commit(plan.copyWith());
  }

  Future<void> markDayComplete(
      String planId, int dayNumber, bool complete) async {
    final plan = byId(planId);
    if (plan == null) return;
    for (final w in plan.weeks) {
      for (final d in w.days) {
        if (d.dayNumber == dayNumber) {
          d.completed = complete;
          if (complete) {
            for (final id in d.topicIds) {
              final t = plan.topicById(id);
              if (t != null && !t.isDone) t.status = TopicStatus.completed;
            }
          }
        }
      }
    }
    await _commit(plan.copyWith());
  }

  /// Recomputes the remaining schedule with new time/deadline settings.
  Future<void> replan(
    String planId, {
    int? dailyMinutes,
    Set<int>? studyDays,
    DateTime? targetDate,
    LearningPlanGenerator generator = const LearningPlanGenerator(),
  }) async {
    final plan = byId(planId);
    if (plan == null) return;
    final updated = generator.replan(
      plan,
      dailyMinutes: dailyMinutes,
      studyDays: studyDays,
      targetDate: targetDate,
    );
    await updatePlan(updated);
  }

  /// Removes a topic entirely and reschedules the remaining plan.
  Future<void> removeTopic(String planId, String topicId,
      {LearningPlanGenerator generator = const LearningPlanGenerator()}) async {
    final plan = byId(planId);
    if (plan == null) return;
    final topics = plan.topics.where((t) => t.id != topicId).toList();
    final updated = plan.copyWith(topics: topics);
    final rescheduled = generator.replan(updated);
    await updatePlan(rescheduled);
  }

  /// Adds a custom topic to the end of a plan and reschedules.
  Future<void> addCustomTopic(String planId, String title, int minutes,
      {LearningPlanGenerator generator = const LearningPlanGenerator()}) async {
    final plan = byId(planId);
    if (plan == null) return;
    final t = LearningTopic(
      id: 'c_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      estMinutes: minutes,
      unit: plan.topics.isNotEmpty ? plan.topics.last.unit : 'Topics',
      sections: [
        TopicSection(title: 'Core concepts', minutes: minutes, points: [title]),
      ],
      completionCriteria: ['Understand $title'],
    );
    final updated = plan.copyWith(topics: [...plan.topics, t]);
    await updatePlan(generator.replan(updated));
  }

  /// Adds extra minutes to a topic's estimate (rebuilds the topic in place).
  Future<void> addTopicTime(String planId, String topicId, int extra) async {
    final plan = byId(planId);
    if (plan == null) return;
    final topics = [
      for (final t in plan.topics)
        if (t.id == topicId)
          LearningTopic(
            id: t.id,
            title: t.title,
            estMinutes: t.estMinutes + extra,
            objectives: t.objectives,
            unit: t.unit,
            sections: t.sections,
            completionCriteria: t.completionCriteria,
            difficulty: t.difficulty,
            isReview: t.isReview,
            actualMinutes: t.actualMinutes,
            status: t.status,
          )
        else
          t,
    ];
    await _commit(plan.copyWith(topics: topics));
  }

  /// Moves a topic to a different day in the schedule.
  Future<void> moveTopicToDay(
      String planId, String topicId, int targetDayNumber) async {
    final plan = byId(planId);
    if (plan == null) return;
    for (final w in plan.weeks) {
      for (final d in w.days) {
        d.topicIds.remove(topicId);
        if (d.dayNumber == targetDayNumber && !d.topicIds.contains(topicId)) {
          d.topicIds.add(topicId);
        }
      }
    }
    await _commit(plan.copyWith());
  }

  /// Updates the plan's level (and reschedules; times are unchanged).
  Future<void> setLevel(String planId, KnowledgeLevel level,
      {LearningPlanGenerator generator = const LearningPlanGenerator()}) async {
    final plan = byId(planId);
    if (plan == null) return;
    await updatePlan(generator.replan(plan.copyWith(level: level)));
  }

  /// Pauses / resumes a plan.
  Future<void> setPaused(String planId, bool paused) async {
    final plan = byId(planId);
    if (plan == null) return;
    await _commit(plan.copyWith(paused: paused));
  }

  /// Records real study minutes against a topic (from the focus timer).
  Future<void> logTopicTime(
      String planId, String topicId, int minutes) async {
    if (minutes <= 0) return;
    final plan = byId(planId);
    if (plan == null) return;
    final topic = plan.topicById(topicId);
    if (topic == null) return;
    topic.actualMinutes += minutes;
    await _commit(plan.copyWith());
  }

  /// Recalibrates the estimates of the not-yet-done topics using the student's
  /// observed pace, then reschedules. Returns the pace factor applied (or null
  /// when there isn't enough data yet).
  Future<double?> recalibrateRemaining(String planId,
      {LearningPlanGenerator generator = const LearningPlanGenerator()}) async {
    final plan = byId(planId);
    if (plan == null) return null;
    final pace = plan.paceFactor;
    if (pace == null || (pace - 1).abs() < 0.1) return pace; // already accurate
    final factor = pace.clamp(0.5, 2.0);
    final topics = [
      for (final t in plan.topics)
        if (t.isDone)
          t
        else
          LearningTopic(
            id: t.id,
            title: t.title,
            estMinutes: ((t.estMinutes * factor) / 5).round() * 5,
            objectives: t.objectives,
            unit: t.unit,
            sections: [
              for (final s in t.sections)
                TopicSection(
                    title: s.title,
                    minutes: ((s.minutes * factor) / 5).round() * 5,
                    points: s.points),
            ],
            completionCriteria: t.completionCriteria,
            difficulty: t.difficulty,
            isReview: t.isReview,
            actualMinutes: t.actualMinutes,
            status: t.status,
          ),
    ];
    await updatePlan(generator.replan(plan.copyWith(topics: topics)));
    return factor;
  }
}

final learningPlansProvider =
    StateNotifierProvider<LearningPlannerController, List<LearningPlan>>((ref) {
  return LearningPlannerController(ref.watch(learningPlanRepositoryProvider));
});

/// Convenience: a single plan by id, reactive to store changes.
final learningPlanByIdProvider =
    Provider.family<LearningPlan?, String>((ref, id) {
  final plans = ref.watch(learningPlansProvider);
  for (final p in plans) {
    if (p.id == id) return p;
  }
  return null;
});

/// Lifetime number of plans the user has ever created (never decreases on
/// delete). Falls back to 0 while loading or when logged out.
final plansCreatedCountProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(learningPlanRepositoryProvider);
  if (repo == null) return Stream.value(0);
  return repo.watchPlansCreated();
});

/// How many of the free plan slots a free user has consumed. This is the
/// lifetime created count, but never less than the number of plans currently
/// held (so legacy users who created plans before the counter existed are
/// still gated correctly).
final usedPlanSlotsProvider = Provider<int>((ref) {
  final created = ref.watch(plansCreatedCountProvider).maybeWhen(
        data: (v) => v,
        orElse: () => 0,
      );
  final active = ref.watch(learningPlansProvider).length;
  return created > active ? created : active;
});

/// Whether the user is allowed to create another plan right now: Pro users are
/// unlimited; free users may create up to [kFreeLearningPlanLimit] plans over
/// the app's lifetime. Deleting a plan does NOT free up a slot.
final canCreatePlanProvider = Provider<bool>((ref) {
  final isPro = ref.watch(isProProvider);
  if (isPro) return true;
  return ref.watch(usedPlanSlotsProvider) < kFreeLearningPlanLimit;
});

/// The single most urgent plan + day to study today, across all active plans
/// (overdue/soonest first). Null when nothing is due. Powers the "Today" card.
final todayFocusProvider = Provider<({LearningPlan plan, DayPlan day})?>((ref) {
  final plans = ref.watch(learningPlansProvider);
  ({LearningPlan plan, DayPlan day})? best;
  for (final p in plans) {
    if (p.paused) continue;
    final d = p.dayForToday;
    if (d == null) continue;
    if (best == null || d.date.isBefore(best.day.date)) {
      best = (plan: p, day: d);
    }
  }
  return best;
});

/// Schedules a daily study reminder while the student has an active, unfinished
/// plan; cancels it when there's nothing left to study. Watch once in the shell.
final plannerReminderSyncProvider = Provider<void>((ref) {
  final plans = ref.watch(learningPlansProvider);
  final active = plans.any((p) => !p.paused && p.remainingTopics > 0);
  final svc = ref.read(notificationServiceProvider);
  try {
    if (active) {
      svc.scheduleStudyReminder(
        hour: 18,
        minute: 0,
        title: 'Time to study 📚',
        body: "Open your plan and knock out today's topics.",
      );
    } else {
      svc.cancelStudyReminder();
    }
  } catch (_) {
    // Notifications are a bonus — never let scheduling break the app.
  }
});
