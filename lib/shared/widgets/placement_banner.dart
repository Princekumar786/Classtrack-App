import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/firebase_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/destination_handler.dart';
import '../../core/utils/firestore_parsing.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/cms/domain/marketing.dart';
import '../../services/analytics_service.dart';
import '../../services/metrics_service.dart';

/// Live, published banners for a given [placement] (e.g. Opportunities,
/// Discounts), targeted to the user's country. Reuses the [CmsBanner] model —
/// the app only reads `published` banners (allowed by Firestore rules).
final placementBannersProvider =
    StreamProvider.family<List<CmsBanner>, String>((ref, placement) {
  final db = ref.watch(firestoreProvider);
  final country = ref.watch(effectiveCountryProvider);
  return db
      .collection(AppConstants.bannersCollection)
      .where('published', isEqualTo: true)
      .limit(50)
      .snapshots()
      .map((snap) {
    final banners =
        parseDocsSafely(snap.docs, CmsBanner.fromMap, context: 'banners');
    return banners
        .where((b) =>
            b.placement == placement &&
            b.isLive() &&
            _targets(b, country))
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
  });
});

bool _targets(CmsBanner b, String? country) {
  if (b.countries.isEmpty) return true;
  if (b.countries.any((c) => c.toLowerCase() == 'global')) return true;
  if (country == null) return false;
  return b.countries.any((c) => c.toLowerCase() == country.toLowerCase());
}

/// Renders the top live banner for [placement] (CMS-managed), or nothing when
/// there are none — so surfaces stay clean until marketing publishes one.
///
/// Emits `banner_viewed` once per banner shown and `banner_clicked` on tap,
/// both tagged with the placement so analytics can attribute by surface.
class PlacementBanner extends ConsumerStatefulWidget {
  final String placement;
  final EdgeInsetsGeometry padding;
  const PlacementBanner({
    super.key,
    required this.placement,
    this.padding = const EdgeInsets.only(bottom: 16),
  });

  @override
  ConsumerState<PlacementBanner> createState() => _PlacementBannerState();
}

class _PlacementBannerState extends ConsumerState<PlacementBanner> {
  String? _loggedViewId;

  void _logView(String id) {
    if (_loggedViewId == id) return;
    _loggedViewId = id;
    ref
        .read(analyticsProvider)
        .log('banner_viewed', {'id': id, 'placement': widget.placement});
    ref.read(metricsServiceProvider).recordBanner(id, 'impression');
  }

  @override
  Widget build(BuildContext context) {
    final banners = visibleBannersFor(
        ref,
        ref.watch(placementBannersProvider(widget.placement)).valueOrNull ??
            const []);
    if (banners.isEmpty) return const SizedBox.shrink();
    final banner = banners.first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _logView(banner.id));

    return Padding(
      padding: widget.padding,
      child: _BannerCard(banner: banner, onTap: () => _onTap(banner)),
    );
  }

  Future<void> _onTap(CmsBanner banner) async {
    ref.read(analyticsProvider).log(
        'banner_clicked', {'id': banner.id, 'placement': widget.placement});
    ref.read(metricsServiceProvider).recordBanner(banner.id, 'click');
    await handleDestination(context, ref, banner.destination);
  }
}

class _BannerCard extends StatelessWidget {
  final CmsBanner banner;
  final VoidCallback onTap;
  const _BannerCard({required this.banner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = banner.imageUrl != null && banner.imageUrl!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: hasImage
                ? null
                : const LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(20),
            image: hasImage
                ? DecorationImage(
                    image: ResizeImage(NetworkImage(banner.imageUrl!),
                        width: 1080),
                    fit: BoxFit.cover,
                    // Swallow load failures (offline / dead URL) so a
                    // NetworkImage SocketException/HttpException can't escape to
                    // FlutterError.onError and be reported as a fatal crash.
                    onError: (_, __) {},
                  )
                : null,
          ),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: hasImage
                  ? LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.15),
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (banner.sponsored)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('SPONSORED',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6)),
                        ),
                      Text(banner.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      if (banner.ctaLabel != null &&
                          banner.ctaLabel!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(banner.ctaLabel!,
                              style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
