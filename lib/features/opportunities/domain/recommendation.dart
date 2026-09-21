import '../../auth/domain/app_user.dart';
import 'recommendation_weights.dart';
import 'resource.dart';

/// Recommendation match tiers shown to students (PRD §12).
enum MatchTier {
  highlyRecommended('Highly Recommended'),
  recommended('Recommended'),
  goodMatch('Good Match'),
  explore('Explore');

  const MatchTier(this.label);
  final String label;
}

/// The result of scoring a [Resource] against a student profile.
class RecommendationScore {
  /// Normalized 0–100 match score.
  final int score;
  final MatchTier tier;

  /// True when at least one profile-based signal (country/degree/department/
  /// year/interest/career) applied — i.e. the score reflects real
  /// personalization, not just recency/deadline. Match badges use this so we
  /// never show a "match %" that ignores the student's profile.
  final bool personalized;

  /// Which signals contributed (for "why recommended" explanations / debugging).
  final List<String> reasons;

  const RecommendationScore(this.score, this.tier, this.personalized,
      this.reasons);

  static const none = RecommendationScore(0, MatchTier.explore, false, []);
}

/// A simple, transparent weighted-scoring recommender (PRD §12). No ML — each
/// matching signal adds its configured weight; the raw total is normalized to
/// 0–100 against the sum of the weights that were *applicable* to this
/// resource+profile, so a resource that doesn't target (say) a department isn't
/// penalised for it. Deadline relevance and freshness always apply.
///
/// Weights are remotely configurable via [RecommendationWeights]
/// (`config/recommendation`), so tuning needs no app release.
class Recommender {
  final RecommendationWeights weights;
  final DateTime now;

  Recommender(this.weights, {DateTime? now}) : now = now ?? DateTime.now();

  RecommendationScore score(Resource r, AppUser? user) {
    var earned = 0;
    var applicable = 0;
    final reasons = <String>[];

    void signal(bool targeted, bool matched, int weight, String reason) {
      if (!targeted) return; // resource doesn't use this signal → not applicable
      applicable += weight;
      if (matched) {
        earned += weight;
        reasons.add(reason);
      }
    }

    final profileCountry = user?.country;
    // Country: applies whenever the resource targets specific countries.
    final targetsSpecificCountries = r.countries.isNotEmpty &&
        !r.countries.any((c) => c.toLowerCase() == 'global');
    signal(
      targetsSpecificCountries,
      profileCountry != null && r.targetsCountry(profileCountry),
      weights.countryMatch,
      'Available in your country',
    );

    // Degree.
    signal(
      r.targetDegrees.isNotEmpty,
      _containsCi(r.targetDegrees, user?.degree),
      weights.degreeMatch,
      'Matches your degree',
    );

    // Department.
    signal(
      r.targetDepartments.isNotEmpty,
      _containsCi(r.targetDepartments, user?.department),
      weights.departmentMatch,
      'Matches your department',
    );

    // Interests (any overlap).
    signal(
      r.targetInterests.isNotEmpty,
      _overlapsCi(r.targetInterests, user?.interests ?? const []),
      weights.interestMatch,
      'Matches your interests',
    );

    // Career goal.
    signal(
      r.targetCareerGoals.isNotEmpty,
      _containsCi(r.targetCareerGoals, user?.careerGoal),
      weights.careerGoal,
      'Fits your career goal',
    );

    // At least one profile signal was applicable AND the student actually has
    // profile data → the score reflects real personalization.
    final personalized = applicable > 0 && (user?.hasAnyProfileDetails ?? false);

    // Deadline relevance: always applicable. Sooner (but not past) scores higher.
    applicable += weights.deadlineRelevance;
    final deadlineFactor = _deadlineFactor(r);
    if (deadlineFactor > 0) {
      earned += (weights.deadlineRelevance * deadlineFactor).round();
      if (deadlineFactor >= 0.5) reasons.add('Closing soon');
    }

    // Freshness: always applicable. Newer content scores higher.
    applicable += weights.freshness;
    final freshFactor = _freshnessFactor(r);
    if (freshFactor > 0) {
      earned += (weights.freshness * freshFactor).round();
      if (freshFactor >= 0.7) reasons.add('Newly added');
    }

    final normalized =
        applicable == 0 ? 0 : ((earned / applicable) * 100).round().clamp(0, 100);

    return RecommendationScore(
        normalized, _tier(normalized), personalized, reasons);
  }

  /// Sorts [resources] by score (desc) for a [user]; featured/sponsored and
  /// priority act as tie-breakers so curated items lead within a score band.
  List<Resource> rank(List<Resource> resources, AppUser? user) {
    final scored = resources
        .map((r) => (r, score(r, user).score))
        .toList()
      ..sort((a, b) {
        final byScore = b.$2.compareTo(a.$2);
        if (byScore != 0) return byScore;
        final byFeatured =
            (b.$1.featured ? 1 : 0).compareTo(a.$1.featured ? 1 : 0);
        if (byFeatured != 0) return byFeatured;
        final bySponsored =
            (b.$1.sponsored ? 1 : 0).compareTo(a.$1.sponsored ? 1 : 0);
        if (bySponsored != 0) return bySponsored;
        return b.$1.priority.compareTo(a.$1.priority);
      });
    return scored.map((e) => e.$1).toList();
  }

  MatchTier _tier(int score) {
    if (score >= 80) return MatchTier.highlyRecommended;
    if (score >= 60) return MatchTier.recommended;
    if (score >= 35) return MatchTier.goodMatch;
    return MatchTier.explore;
  }

  /// 0..1 by how soon the deadline is: within 3 days → 1.0, within 30 → scaled,
  /// none → 0.5 (mildly relevant), past → 0.
  double _deadlineFactor(Resource r) {
    final d = r.daysUntilDeadline;
    if (d == null) return 0.5;
    if (d < 0) return 0;
    if (d <= 3) return 1.0;
    if (d >= 30) return 0.2;
    return 1.0 - ((d - 3) / 27) * 0.8;
  }

  /// 0..1 by how recently published: <=7 days → 1.0, >=60 → 0, else scaled.
  double _freshnessFactor(Resource r) {
    final published = r.publishedAt ?? r.createdAt;
    if (published == null) return 0.4;
    final age = now.difference(published).inDays;
    if (age <= 7) return 1.0;
    if (age >= 60) return 0.0;
    return 1.0 - ((age - 7) / 53);
  }

  static bool _containsCi(List<String> list, String? value) {
    if (value == null || value.isEmpty) return false;
    final v = value.toLowerCase();
    return list.any((e) => e.toLowerCase() == v);
  }

  static bool _overlapsCi(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return false;
    final bl = b.map((e) => e.toLowerCase()).toSet();
    return a.any((e) => bl.contains(e.toLowerCase()));
  }
}
