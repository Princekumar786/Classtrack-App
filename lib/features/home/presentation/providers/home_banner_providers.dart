import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/utils/firestore_parsing.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../cms/domain/marketing.dart';

/// Live, published banners for the Home placement, targeted to the user's
/// country. Reuses the [CmsBanner] model (single source of truth); the app only
/// reads published banners (allowed by Firestore rules).
final homeBannersProvider = StreamProvider<List<CmsBanner>>((ref) {
  final db = ref.watch(firestoreProvider);
  final country = ref.watch(effectiveCountryProvider);
  return db
      .collection(AppConstants.bannersCollection)
      .where('published', isEqualTo: true)
      .limit(20)
      .snapshots()
      .map((snap) {
    final banners =
        parseDocsSafely(snap.docs, CmsBanner.fromMap, context: 'banners');
    final home = banners
        .where((b) =>
            b.placement == Placements.home &&
            b.isLive() &&
            _targets(b, country))
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    return home;
  });
});

bool _targets(CmsBanner b, String? country) {
  if (b.countries.isEmpty) return true;
  if (b.countries.any((c) => c.toLowerCase() == 'global')) return true;
  if (country == null) return false;
  return b.countries.any((c) => c.toLowerCase() == country.toLowerCase());
}
