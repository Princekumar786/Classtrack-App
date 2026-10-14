import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/firestore_parsing.dart';
import '../../opportunities/domain/resource.dart';
import '../../opportunities/domain/resource_status.dart';

/// Result of validating a resource before publish (PRD §18).
class ResourceValidation {
  final List<String> errors;
  const ResourceValidation(this.errors);
  bool get ok => errors.isEmpty;
}

/// Write-capable access to the unified `resources` collection, used ONLY by the
/// CMS (privileged roles). Reuses the shared [Resource] model + [Resource.toMap]
/// — no business logic is duplicated between the mobile app and the CMS.
///
/// Every write stamps `updatedBy` with the editor's uid, which (a) satisfies the
/// Firestore rule that self-attributes writes and (b) lets the audit-log trigger
/// record the actor. Firestore rules are the authoritative gate; this class
/// assumes the caller already holds an editor+ role.
class CmsResourceRepository {
  final FirebaseFirestore _db;
  final String editorUid;
  CmsResourceRepository({
    required FirebaseFirestore db,
    required this.editorUid,
  }) : _db = db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.resourcesCollection);

  /// Streams ALL resources (any status, incl. drafts) for the CMS library.
  /// Editors+ are allowed to read drafts by the security rules.
  Stream<List<Resource>> watchAll({int limit = 500}) {
    return _col
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => parseDocsSafely(
            snap.docs,
            Resource.fromMap,
            context: 'resources',
          ),
        );
  }

  Stream<Resource?> watchById(String id) => _col.doc(id).snapshots().map((s) {
    final data = s.data();
    return data == null ? null : Resource.fromMap(s.id, data);
  });

  /// Validates a resource for publishing. Mirrors the Firestore rule
  /// `publishableIfVisible` so the CMS can surface friendly errors BEFORE a
  /// write is attempted (the rule remains the authoritative server check).
  static ResourceValidation validateForPublish(Resource r) {
    final errors = <String>[];
    if (r.title.trim().isEmpty) errors.add('Title is required.');
    if (r.organization.trim().isEmpty) {
      errors.add('Organization / company is required to publish.');
    }
    final hasLink =
        (r.applicationUrl?.trim().isNotEmpty ?? false) ||
        (r.affiliateUrl?.trim().isNotEmpty ?? false);
    if (!hasLink) {
      errors.add('An application or affiliate link is required to publish.');
    }
    return ResourceValidation(errors);
  }

  /// Builds the Firestore payload for [r], stamping server-owned audit fields.
  Map<String, dynamic> _payload(Resource r, {DateTime? publishedAt}) {
    final map = r.toMap();
    map['updatedBy'] = editorUid;
    if (publishedAt != null) {
      map['publishedAt'] = Timestamp.fromDate(publishedAt);
    }
    return map;
  }

  /// Creates a new resource, returning its generated id. Drafts may be
  /// incomplete; visible statuses must pass [validateForPublish] (also enforced
  /// by rules).
  Future<String> create(Resource r) async {
    _assertWritable(r);
    final doc = _col.doc();
    await doc.set(
      _payload(
        r,
        publishedAt: r.status.isVisibleToStudents ? DateTime.now() : null,
      ),
    );
    return doc.id;
  }

  /// Updates an existing resource in place.
  Future<void> update(Resource r) async {
    _assertWritable(r);
    await _col
        .doc(r.id)
        .set(
          _payload(
            r,
            publishedAt: (r.publishedAt == null && r.status.isVisibleToStudents)
                ? DateTime.now()
                : null,
          ),
          SetOptions(merge: true),
        );
  }

  /// Changes only the stored status (publish / unpublish / archive / etc.).
  Future<void> setStatus(Resource r, ResourceStatus status) async {
    if (status.isVisibleToStudents) {
      final v = validateForPublish(r);
      if (!v.ok) {
        throw ArgumentError(v.errors.join(' '));
      }
    }
    await _col.doc(r.id).set({
      'status': status.key,
      'updatedBy': editorUid,
      'updatedAt': FieldValue.serverTimestamp(),
      if (status.isVisibleToStudents && r.publishedAt == null)
        'publishedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Duplicates a resource as a fresh draft (PRD §18 "Duplicate").
  Future<String> duplicate(Resource r) async {
    final copy = r.copyDraft(titleSuffix: ' (copy)');
    return create(copy);
  }

  Future<void> delete(String id) => _col.doc(id).delete();

  /// Guards visible-status writes against incomplete content before hitting the
  /// server (the rule enforces it too).
  void _assertWritable(Resource r) {
    if (r.status.isVisibleToStudents) {
      final v = validateForPublish(r);
      if (!v.ok) {
        throw ArgumentError(v.errors.join(' '));
      }
    }
  }
}
