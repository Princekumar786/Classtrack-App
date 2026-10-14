import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../opportunities/domain/resource.dart';
import '../../data/cms_resource_repository.dart';

/// Write-capable resource repository bound to the signed-in editor (null when
/// signed out). The CMS assumes the caller holds an editor+ role; Firestore
/// rules are the authoritative gate.
final cmsResourceRepositoryProvider = Provider<CmsResourceRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return CmsResourceRepository(
    db: ref.watch(firestoreProvider),
    editorUid: uid,
  );
});

/// All resources (any status, incl. drafts) for the CMS library.
final cmsResourcesProvider = StreamProvider<List<Resource>>((ref) {
  final repo = ref.watch(cmsResourceRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchAll();
});
