import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/destination_handler.dart';
import '../../../../services/analytics_service.dart';
import '../../../../services/metrics_service.dart';
import '../../../cms/domain/marketing.dart';
import '../providers/home_banner_providers.dart';

/// Renders the top live Home banner (CMS-managed). Emits `banner_viewed` once
/// per banner shown and `banner_clicked` on tap (PRD §20). Shows nothing when
/// there are no banners, so it's invisible until marketing publishes one — and
/// requires no app release to change (PRD §19).
class HomeBanner extends ConsumerStatefulWidget {
  const HomeBanner({super.key});

  @override
  ConsumerState<HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends ConsumerState<HomeBanner> {
  String? _loggedViewId;

  void _logView(String id) {
    if (_loggedViewId == id) return;
    _loggedViewId = id;
    ref.read(analyticsProvider).log('banner_viewed', {'id': id});
    ref.read(metricsServiceProvider).recordBanner(id, 'impression');
  }

  @override
  Widget build(BuildContext context) {
    final banners = visibleBannersFor(
        ref, ref.watch(homeBannersProvider).valueOrNull ?? const []);
    if (banners.isEmpty) return const SizedBox.shrink();
    final banner = banners.first;
    // Log a view once the banner is on screen for this session.
    WidgetsBinding.instance.addPostFrameCallback((_) => _logView(banner.id));

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: _BannerCard(banner: banner, onTap: () => _onTap(banner)),
    );
  }

  Future<void> _onTap(CmsBanner banner) async {
    ref.read(analyticsProvider).log('banner_clicked', {'id': banner.id});
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
                    // Swallow load failures (offline / dead URL). Without an
                    // onError, a NetworkImage SocketException/HttpException here
                    // escapes to FlutterError.onError and is reported as a
                    // fatal crash; the banner simply falls back to its gradient.
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
