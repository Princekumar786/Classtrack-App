import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/firestore_parsing.dart';
import '../domain/media_asset.dart';

/// Uploads/lists/deletes CMS media (Cloud Storage under `cms/media/**`, indexed
/// in `mediaAssets`). Authorization is enforced by Storage + Firestore rules;
/// this assumes the caller holds a content/marketing role.
class MediaRepository {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final String uid;
  MediaRepository({
    required FirebaseFirestore db,
    required FirebaseStorage storage,
    required this.uid,
  }) : _db = db,
       _storage = storage;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.mediaAssetsCollection);

  Stream<List<MediaAsset>> watchAll({int limit = 200}) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => parseDocsSafely(
            snap.docs,
            MediaAsset.fromMap,
            context: 'mediaAssets',
          ),
        );
  }

  /// Uploads [bytes] and indexes the asset; returns the created record.
  Future<MediaAsset> upload({
    required Uint8List bytes,
    required String filename,
    String? contentType,
  }) async {
    final safe = sanitizeMediaFilename(filename);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final path = 'cms/media/$id/$safe';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();
    final doc = await _col.add({
      'url': url,
      'name': safe,
      'path': path,
      'contentType': contentType,
      'size': bytes.length,
      'updatedBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return MediaAsset(
      id: doc.id,
      url: url,
      name: safe,
      path: path,
      contentType: contentType,
      size: bytes.length,
      createdAt: DateTime.now(),
    );
  }

  /// Deletes the Storage object (best-effort) and its index doc.
  Future<void> delete(MediaAsset asset) async {
    try {
      await _storage.ref(asset.path).delete();
    } catch (_) {
      // Object may already be gone; still remove the index entry.
    }
    await _col.doc(asset.id).delete();
  }
}
