import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/firestore_parsing.dart';
import '../domain/resource.dart';
import '../domain/resource_status.dart';
import '../domain/resource_type.dart';

/// Read-only access to the unified `resources` collection.
///
/// Content is authored by the CMS; the app never writes here (Firestore rules
/// enforce that). Visibility is gated in the query — only statuses students may
/// see are fetched — and re-checked client-side via [Resource.isVisibleToStudents]
/// so a stored status whose date-driven [Resource.effectiveStatus] turns hidden
/// can never slip through.
class ResourceRepository {
  final FirebaseFirestore _db;
  ResourceRepository({required FirebaseFirestore db}) : _db = db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.resourcesCollection);

  /// Stored statuses that are ever visible to students (excludes draft/hidden).
  static final List<String> _visibleStatusKeys = ResourceStatus.values
      .where((s) => s.isVisibleToStudents)
      .map((s) => s.key)
      .toList();

  /// Streams all student-visible resources, highest [Resource.priority] first.
  /// Callers (Phase 3 UI) apply type/country/search filtering on top.
  ///
  /// Resilient by design: each document is parsed in isolation so one malformed
  /// record (e.g. a mistyped field entered in the CMS) can never break the
  /// whole feed. Ordering is done client-side so the query needs no composite
  /// index (avoids a "requires an index" failure that would blank the screen).
  ///
  /// NOTE: the limit must comfortably exceed the total number of visible
  /// resources. Opportunities and Perks share this one stream, and the query
  /// has no server-side ordering, so too small a limit lets one type (whichever
  /// has lower document IDs) crowd the other out of the window.
  Stream<List<Resource>> watchVisible({int limit = 1500}) {
    if (_visibleStatusKeys.isEmpty) {
      return Stream.value(const <Resource>[]);
    }
    return _col
        .where('status', whereIn: _visibleStatusKeys)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final out = <Resource>[];
      for (final d in snap.docs) {
        try {
          final r = Resource.fromMap(d.id, d.data());
          if (r.isVisibleToStudents) out.add(r);
        } catch (_) {
          // Skip a single malformed document rather than failing the feed.
        }
      }
      out.sort((a, b) => b.priority.compareTo(a.priority));
      return out;
    });
  }

  /// Streams a single resource by id (null if missing/removed).
  Stream<Resource?> watchById(String id) {
    return _col.doc(id).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return Resource.fromMap(snap.id, data);
    });
  }

  /// One-shot fetch of several resources by id (used to hydrate saved items).
  /// Firestore `whereIn` caps at 30 ids per query, so requests are chunked.
  Future<List<Resource>> fetchByIds(Iterable<String> ids) async {
    final list = ids.where((e) => e.isNotEmpty).toList();
    if (list.isEmpty) return const [];
    final out = <Resource>[];
    for (var i = 0; i < list.length; i += 30) {
      final chunk = list.sublist(i, (i + 30).clamp(0, list.length));
      final snap =
          await _col.where(FieldPath.documentId, whereIn: chunk).get();
      out.addAll(
          parseDocsSafely(snap.docs, Resource.fromMap, context: 'resources'));
    }
    return out;
  }

  /// Resolves an SEO [slug] to a resource (for future web/deep-link routing).
  Future<Resource?> fetchBySlug(String slug) async {
    final snap = await _col.where('slug', isEqualTo: slug).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    return Resource.fromMap(d.id, d.data());
  }
}

/// Per-user saved / hidden opportunities under `users/{uid}/savedResources`.
///
/// Saved items persist even after the underlying resource's status changes
/// (PRD §15) — we only store the id + light metadata and hydrate the live
/// resource on demand.
class SavedResourceRepository {
  final FirebaseFirestore _db;
  final String uid;
  SavedResourceRepository({required FirebaseFirestore db, required this.uid})
      : _db = db;

  CollectionReference<Map<String, dynamic>> get _col => _db
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .collection(AppConstants.savedResourcesCollection);

  /// Streams the set of saved resource ids (excludes ones the user hid).
  Stream<Set<String>> watchSavedIds() {
    return _col.snapshots().map((snap) => snap.docs
        .where((d) => (d.data()['hidden'] as bool?) != true)
        .map((d) => d.id)
        .toSet());
  }

  /// Streams ids the user explicitly hid ("not interested").
  Stream<Set<String>> watchHiddenIds() {
    return _col
        .where('hidden', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  Future<void> save(Resource r) => _col.doc(r.id).set({
        'savedAt': FieldValue.serverTimestamp(),
        'type': r.type.key,
        'title': r.title,
        'hidden': false,
      }, SetOptions(merge: true));

  Future<void> unsave(String id) => _col.doc(id).delete();

  Future<void> setHidden(String id, bool hidden) => _col.doc(id).set({
        'hidden': hidden,
        'hiddenAt': hidden ? FieldValue.serverTimestamp() : null,
      }, SetOptions(merge: true));
}

/// Lightweight in-memory helpers used by the feed/detail UIs (Phase 3). Kept
/// here so filtering/search logic is unit-testable without widgets.
class ResourceQueries {
  ResourceQueries._();

  /// Opportunities = everything that is not a discount.
  static List<Resource> opportunities(List<Resource> all) =>
      all.where((r) => !r.type.isDiscount).toList();

  static List<Resource> discounts(List<Resource> all) =>
      all.where((r) => r.type.isDiscount).toList();

  /// Case-insensitive keyword search across title/organization/tags/description.
  static List<Resource> search(List<Resource> all, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((r) {
      return r.title.toLowerCase().contains(q) ||
          r.organization.toLowerCase().contains(q) ||
          (r.company?.toLowerCase().contains(q) ?? false) ||
          r.description.toLowerCase().contains(q) ||
          r.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  /// Filter by type + country, keeping only feed-visible resources.
  static List<Resource> feed(
    List<Resource> all, {
    ResourceType? type,
    String? country,
    bool activeOnly = true,
  }) {
    return all.where((r) {
      if (activeOnly && !r.isInActiveFeed) return false;
      if (type != null && r.type != type) return false;
      if (!r.targetsCountry(country)) return false;
      return true;
    }).toList();
  }

  /// Related resources for a detail page: manually-curated
  /// [Resource.relatedResourceIds] first (honouring editorial intent), then
  /// auto-filled with other active resources of the same type — so a detail
  /// page never dead-ends. Excludes the current resource and duplicates.
  static List<Resource> related(
    Resource current,
    List<Resource> all, {
    int limit = 4,
  }) {
    final byId = {for (final r in all) r.id: r};
    final out = <Resource>[];
    final seen = <String>{current.id};

    for (final id in current.relatedResourceIds) {
      if (out.length >= limit) return out;
      final r = byId[id];
      if (r != null && !seen.contains(r.id) && r.isVisibleToStudents) {
        out.add(r);
        seen.add(r.id);
      }
    }
    for (final r in all) {
      if (out.length >= limit) break;
      if (seen.contains(r.id)) continue;
      if (r.type == current.type && r.isInActiveFeed) {
        out.add(r);
        seen.add(r.id);
      }
    }
    return out;
  }
}
