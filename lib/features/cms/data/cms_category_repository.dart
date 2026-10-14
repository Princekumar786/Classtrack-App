import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/firestore_parsing.dart';
import '../domain/cms_category.dart';

/// Write-capable access to the managed `categories` taxonomy (CMS content
/// editors). Firestore rules are the authoritative gate; every write stamps
/// `updatedBy` to satisfy the rule and attribute the change.
class CmsCategoryRepository {
  final FirebaseFirestore _db;
  final String editorUid;
  CmsCategoryRepository({
    required FirebaseFirestore db,
    required this.editorUid,
  }) : _db = db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.categoriesCollection);

  Stream<List<CmsCategory>> watchAll() {
    return _col.snapshots().map(
      (snap) => parseDocsSafely(
        snap.docs,
        CmsCategory.fromMap,
        context: 'categories',
      ),
    );
  }

  Future<void> create(CmsCategory c) => _col.add({
    ...c.toMap(),
    'updatedBy': editorUid,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> update(CmsCategory c) => _col.doc(c.id).set({
    ...c.toMap(),
    'updatedBy': editorUid,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> setEnabled(String id, bool enabled) => _col.doc(id).set({
    'enabled': enabled,
    'updatedBy': editorUid,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> delete(String id) => _col.doc(id).delete();
}
