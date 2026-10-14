import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../data/cms_category_repository.dart';
import '../../domain/cms_category.dart';

final cmsCategoryRepositoryProvider = Provider<CmsCategoryRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return CmsCategoryRepository(
    db: ref.watch(firestoreProvider),
    editorUid: uid,
  );
});

final cmsCategoriesProvider = StreamProvider<List<CmsCategory>>((ref) {
  final repo = ref.watch(cmsCategoryRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchAll();
});
