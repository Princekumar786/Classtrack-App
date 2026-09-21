import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/resource_repository.dart';
import '../../domain/recommendation.dart';
import '../../domain/recommendation_weights.dart';
import '../../domain/resource.dart';
import '../../domain/resource_type.dart';

/// Read-only repository over the unified `resources` collection.
final resourceRepositoryProvider = Provider<ResourceRepository>((ref) {
  return ResourceRepository(db: ref.watch(firestoreProvider));
});

/// Remotely-configurable recommendation weights (`config/recommendation`).
/// Falls back to [RecommendationWeights.defaults] when unset. Shared by the CMS
/// Settings editor and the personalization scoring (Phase 6).
final recommendationWeightsProvider =
    StreamProvider<RecommendationWeights>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection(AppConstants.configCollection)
      .doc(AppConstants.recommendationConfigDoc)
      .snapshots()
      .map((s) => RecommendationWeights.fromMap(s.data()));
});

/// All student-visible resources (priority-ordered). Base stream that the
/// Opportunities & Discounts surfaces derive from.
final visibleResourcesProvider = StreamProvider<List<Resource>>((ref) {
  return ref.watch(resourceRepositoryProvider).watchVisible();
});

/// How many opportunities / perks a FREE (non-Pro) member may browse in each
/// feed. They see the [kFreeResourceLimit] most-recently-updated of each; the
/// rest of the catalog requires Premium.
const int kFreeResourceLimit = 5;

/// Returns [items] sorted newest-first by [Resource.updatedAt] (falling back to
/// publishedAt, then createdAt), with undated items last. Pure + order-stable
/// so it can back the free-tier "latest N" preview and be unit-tested.
List<Resource> sortByRecency(List<Resource> items) {
  DateTime? key(Resource r) => r.updatedAt ?? r.publishedAt ?? r.createdAt;
  final out = [...items];
  out.sort((a, b) {
    final ka = key(a);
    final kb = key(b);
    if (ka == null && kb == null) return 0;
    if (ka == null) return 1; // undated → last
    if (kb == null) return -1;
    return kb.compareTo(ka); // newest first
  });
  return out;
}

/// The set of resource ids a free member may access from [items]: the
/// [kFreeResourceLimit] most-recently-updated. Returns null when [isPro] (no
/// limit) or when there's nothing to lock (≤ limit), so callers can treat null
/// as "show everything".
Set<String>? freeAllowedIds(List<Resource> items, {required bool isPro}) {
  if (isPro || items.length <= kFreeResourceLimit) return null;
  return sortByRecency(items)
      .take(kFreeResourceLimit)
      .map((r) => r.id)
      .toSet();
}

/// A single resource by id (for detail pages / deep links).
final resourceByIdProvider =
    StreamProvider.family<Resource?, String>((ref, id) {
  return ref.watch(resourceRepositoryProvider).watchById(id);
});

/// Active-feed opportunities (excludes discounts), country-filtered to the
/// signed-in user's profile country, then ranked by personalized match score.
final opportunitiesFeedProvider = Provider<List<Resource>>((ref) {
  final all = ref.watch(visibleResourcesProvider).valueOrNull ?? const [];
  final user = ref.watch(userProfileProvider).valueOrNull;
  final list = ResourceQueries.feed(all, country: user?.country)
      .where((r) => !r.type.isDiscount)
      // Editorial control (P1 §12): admins can exclude a resource from
      // algorithmic recommendations without hiding it from browse.
      .where((r) => r.recommendationEligible)
      .toList();
  return ref.watch(recommenderProvider).rank(list, user);
});

/// The recommendation engine, built from the remotely-configurable weights.
final recommenderProvider = Provider<Recommender>((ref) {
  final weights = ref.watch(recommendationWeightsProvider).valueOrNull ??
      RecommendationWeights.defaults;
  return Recommender(weights);
});

/// The personalized match score for a single resource (for match badges).
final resourceScoreProvider =
    Provider.family<RecommendationScore, Resource>((ref, r) {
  final user = ref.watch(userProfileProvider).valueOrNull;
  return ref.watch(recommenderProvider).score(r, user);
});

/// Active-feed discounts, country-filtered.
final discountsFeedProvider = Provider<List<Resource>>((ref) {
  final all = ref.watch(visibleResourcesProvider).valueOrNull ?? const [];
  final country = ref.watch(userProfileProvider).valueOrNull?.country;
  return ResourceQueries.feed(all,
      type: ResourceType.discount, country: country);
});

/// Feed filtered to a single [ResourceType], country-aware.
final resourcesByTypeProvider =
    Provider.family<List<Resource>, ResourceType>((ref, type) {
  final all = ref.watch(visibleResourcesProvider).valueOrNull ?? const [];
  final country = ref.watch(userProfileProvider).valueOrNull?.country;
  return ResourceQueries.feed(all, type: type, country: country);
});

// ── Saved / hidden opportunities ────────────────────────────────────────────

/// Per-user saved-resources repository (null when signed out).
final savedResourceRepositoryProvider =
    Provider<SavedResourceRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return SavedResourceRepository(db: ref.watch(firestoreProvider), uid: uid);
});

/// Set of saved resource ids (empty when signed out).
final savedResourceIdsProvider = StreamProvider<Set<String>>((ref) {
  final repo = ref.watch(savedResourceRepositoryProvider);
  if (repo == null) return Stream.value(const <String>{});
  return repo.watchSavedIds();
});

/// Ids the user hid ("not interested"), filtered out of the feeds by the UI.
final hiddenResourceIdsProvider = StreamProvider<Set<String>>((ref) {
  final repo = ref.watch(savedResourceRepositoryProvider);
  if (repo == null) return Stream.value(const <String>{});
  return repo.watchHiddenIds();
});

/// The user's saved resources, hydrated to live [Resource]s. Saved items remain
/// available even after their status changes (PRD §15).
final savedResourcesProvider = FutureProvider<List<Resource>>((ref) async {
  final ids = ref.watch(savedResourceIdsProvider).valueOrNull ?? const <String>{};
  if (ids.isEmpty) return const [];
  return ref.watch(resourceRepositoryProvider).fetchByIds(ids);
});

/// Save/unsave/hide actions for opportunities.
final savedResourceControllerProvider =
    Provider<SavedResourceController>((ref) {
  return SavedResourceController(ref.watch(savedResourceRepositoryProvider));
});

class SavedResourceController {
  final SavedResourceRepository? _repo;
  SavedResourceController(this._repo);

  bool get isReady => _repo != null;

  Future<void> save(Resource r) async => _repo?.save(r);
  Future<void> unsave(String id) async => _repo?.unsave(id);
  Future<void> hide(String id) async => _repo?.setHidden(id, true);
  Future<void> unhide(String id) async => _repo?.setHidden(id, false);

  /// Toggles saved state given the current saved-id set.
  Future<void> toggle(Resource r, Set<String> currentSaved) async {
    if (currentSaved.contains(r.id)) {
      await unsave(r.id);
    } else {
      await save(r);
    }
  }
}
