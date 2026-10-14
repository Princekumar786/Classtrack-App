import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/metrics_service.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/resource.dart';
import '../../domain/resource_status.dart';
import '../providers/opportunities_providers.dart';

/// A thumbnail that shows the resource's logo/image filling a rounded tile like
/// a native app icon, falling back to a clean brand monogram (e.g. "A" for
/// Apple) when there's no image or it fails to load.
///
/// When [preferLogo] is true the uploaded brand [Resource.logoUrl] is used
/// first (better for small card thumbnails), otherwise the wide hero
/// [Resource.imageUrl] wins.
class ResourceThumb extends StatefulWidget {
  final Resource resource;
  final double size;
  final bool preferLogo;
  const ResourceThumb({
    super.key,
    required this.resource,
    this.size = 52,
    this.preferLogo = false,
  });

  /// The brand initial for the monogram fallback (e.g. "Think-cell" → "T").
  static String _monogram(String brand) {
    final s = brand.trim();
    if (s.isEmpty) return '';
    return s[0].toUpperCase();
  }

  @override
  State<ResourceThumb> createState() => _ResourceThumbState();
}

class _ResourceThumbState extends State<ResourceThumb> {
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _aspect; // width / height, once the image resolves
  bool _failed = false;

  /// Ordered image sources to try (real brand logo → stored icon → favicon).
  /// We advance to the next on load error, falling back to a monogram when all
  /// fail. This replaces generic/unrelated icons with the brand's real logo.
  List<String> _candidates = const [];
  int _idx = 0;

  /// The registrable-ish domain from the resource's links, used to fetch a
  /// real brand logo/favicon (e.g. spotify.com → logo.clearbit.com/spotify.com).
  String? get _brandDomain {
    final r = widget.resource;
    for (final raw in [r.applicationUrl, r.affiliateUrl, r.officialWebsite]) {
      final s = raw?.trim() ?? '';
      if (s.isEmpty) continue;
      try {
        final host = Uri.parse(s).host.toLowerCase().replaceFirst('www.', '');
        if (host.isNotEmpty && host.contains('.')) return host;
      } catch (_) {/* skip malformed */}
    }
    return null;
  }

  /// Whether [url] is a generic (non-brand) icons8 icon — i.e. an icons8 image
  /// whose filename doesn't mention the brand/domain (e.g. a "bot" icon on a
  /// Claude listing). Those are the "unrelated icons" we want to replace.
  bool _isGenericIcon(String url, String brandName, String? domain) {
    final u = url.toLowerCase();
    if (!u.contains('icons8.com')) return false; // uploaded/clearbit/wiki: keep
    final name = u.split('/').last.split('.').first;
    final tokens = <String>{
      ...brandName.toLowerCase().split(RegExp(r'[^a-z0-9]+')),
      if (domain != null) domain.split('.').first,
    }..removeWhere((t) => t.length < 3);
    // Brand-matched icons8 icon (e.g. .../spotify.png) is fine; keep it.
    return !tokens.any((t) => name.contains(t));
  }

  /// Builds the ordered list of image URLs to attempt.
  List<String> _buildCandidates() {
    final r = widget.resource;
    final domain = _brandDomain;
    final logo = r.logoUrl?.trim();
    final hero = r.imageUrl?.trim();
    final primary = widget.preferLogo
        ? ((logo != null && logo.isNotEmpty) ? logo : hero)
        : r.displayImage;

    final out = <String>[];
    void add(String? u) {
      if (u == null || u.isEmpty) return;
      if (!out.contains(u)) out.add(u);
    }

    final primaryIsGeneric = primary != null &&
        _isGenericIcon(primary, r.brandName, domain);

    // Prefer a brand-specific stored image first; if it's a generic icon,
    // prefer the real brand logo (Clearbit) instead and keep the icon as a
    // later fallback.
    if (primary != null && !primaryIsGeneric) add(primary);
    if (domain != null) add('https://logo.clearbit.com/$domain');
    add(primary); // generic icon (if any) as a fallback before the favicon
    if (domain != null) {
      add('https://www.google.com/s2/favicons?domain=$domain&sz=128');
    }
    return out;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ResourceThumb old) {
    super.didUpdateWidget(old);
    if (old.resource.id != widget.resource.id ||
        old.resource.logoUrl != widget.resource.logoUrl ||
        old.resource.imageUrl != widget.resource.imageUrl ||
        old.size != widget.size ||
        old.preferLogo != widget.preferLogo) {
      _aspect = null;
      _failed = false;
      _resolve();
    }
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _resolve() {
    _detach();
    _provider = null;
    _candidates = _buildCandidates();
    _idx = 0;
    if (_candidates.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    _failed = false;
    _resolveCurrent();
  }

  /// Resolves the candidate at [_idx]; on error advances to the next source,
  /// and only shows the monogram once every source has failed.
  void _resolveCurrent() {
    _detach();
    if (_idx >= _candidates.length) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final url = _candidates[_idx];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final target = (widget.size * dpr).round().clamp(48, 512);
    final provider = ResizeImage(NetworkImage(url), width: target);
    _provider = provider;

    final listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (mounted) setState(() => _aspect = h == 0 ? 1 : w / h);
      },
      onError: (_, __) {
        // Try the next source (real logo → icon → favicon → monogram).
        if (!mounted) return;
        _idx++;
        if (_idx < _candidates.length) {
          _resolveCurrent();
        } else {
          setState(() => _failed = true);
        }
      },
    );
    _listener = listener;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    stream.addListener(listener);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.resource;
    final size = widget.size;
    final color = r.type.color;
    final radius = size * 0.28;

    // Clean brand monogram used while loading and whenever there's no image —
    // far more professional than a generic type icon (think Gmail avatars).
    final letter = ResourceThumb._monogram(r.brandName);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: letter.isEmpty
          ? Icon(r.type.icon, color: color, size: size * 0.42)
          : Text(
              letter,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.4,
                height: 1,
              ),
            ),
    );

    // Show the monogram until the image has resolved (no white flash / no
    // fit-flash), then render with the fit chosen from its true aspect ratio.
    if (_candidates.isEmpty || _failed || _provider == null || _aspect == null) {
      return fallback;
    }

    final squareish = _aspect! >= 0.8 && _aspect! <= 1.25;
    if (squareish) {
      // App-icon style: fill the rounded tile edge-to-edge.
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image(
          image: _provider!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    // Wide / tall logo or wordmark: show it in full on a clean white tile,
    // never cropped.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(size * 0.14),
      child: Image(
        image: _provider!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
    );
  }
}

/// A small status/deadline chip.
class ResourcePill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const ResourcePill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 8 : 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Feed card for a single [Resource] (opportunity or discount). Includes an
/// inline save (bookmark) toggle.
class ResourceCard extends ConsumerWidget {
  final Resource resource;
  final VoidCallback onTap;

  /// When set (e.g. in the CMS "preview as student"), resolves the discount's
  /// regional price for this country instead of the signed-in user's profile.
  final String? previewCountry;
  const ResourceCard(
      {super.key,
      required this.resource,
      required this.onTap,
      this.previewCountry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final saved = ref.watch(savedResourceIdsProvider).valueOrNull ?? const {};
    final isSaved = saved.contains(resource.id);
    final status = resource.effectiveStatus;
    final days = resource.daysUntilDeadline;
    final match = ref.watch(resourceScoreProvider(resource));

    // A single, most-relevant meta line keeps the card scannable (signal over
    // noise): discount value → non-active status → closing-soon → match.
    IconData? metaIcon;
    String? metaLabel;
    Color metaColor = theme.hintColor;
    if (resource.type.isDiscount) {
      final country =
          previewCountry ?? ref.watch(effectiveCountryProvider);
      final price = resource.effectiveOffer(country).discountText;
      if (price != null && price.isNotEmpty) {
        metaIcon = Icons.redeem_rounded;
        metaLabel = price;
        metaColor = AppColors.success;
      }
    } else if (status != ResourceStatus.active) {
      metaIcon = Icons.schedule_rounded;
      metaLabel = status.label;
      metaColor = status.color;
    } else if (days != null && days <= 7) {
      metaIcon = Icons.schedule_rounded;
      if (days > 1) {
        metaLabel = 'Closes in $days days';
        metaColor = AppColors.warning;
      } else if (days == 1) {
        metaLabel = 'Closes tomorrow';
        metaColor = AppColors.warning;
      } else if (days == 0) {
        metaLabel = 'Closes today';
        metaColor = AppColors.danger;
      } else {
        metaLabel = 'Closed';
        metaColor = AppColors.danger;
      }
    } else if (match.personalized && match.score >= 60) {
      metaIcon = Icons.auto_awesome_rounded;
      metaLabel = '${match.score}% match';
      metaColor = AppColors.success;
    }

    // Feed impression for sponsor reporting (deduped per session). Skipped in
    // the CMS "preview as student" so staff browsing isn't counted.
    if (previewCountry == null) {
      ref.read(metricsServiceProvider).recordImpression(resource.id);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: softCard(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResourceThumb(resource: resource, size: 60, preferLogo: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ResourcePill(
                        label: resource.type.label,
                        color: resource.type.color,
                        icon: resource.type.icon,
                      ),
                      if (resource.sponsored)
                        const ResourcePill(
                            label: 'Sponsored',
                            color: AppColors.accent,
                            icon: Icons.star_rounded),
                      if (resource.verified)
                        const Icon(Icons.verified_rounded,
                            size: 16, color: AppColors.info),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(resource.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700, height: 1.15)),
                  const SizedBox(height: 3),
                  Text(resource.brandName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor)),
                  if (metaLabel != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(metaIcon, size: 13, color: metaColor),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(metaLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: metaColor,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _SaveButton(resource: resource, isSaved: isSaved),
          ],
        ),
      ),
    );
  }
}

class _SaveButton extends ConsumerWidget {
  final Resource resource;
  final bool isSaved;
  const _SaveButton({required this.resource, required this.isSaved});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(
        isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        color: isSaved ? AppColors.primary : Theme.of(context).hintColor,
      ),
      tooltip: isSaved ? 'Saved' : 'Save',
      onPressed: () {
        final ctrl = ref.read(savedResourceControllerProvider);
        if (!ctrl.isReady) return;
        final saved = ref.read(savedResourceIdsProvider).valueOrNull ?? const {};
        ctrl.toggle(resource, saved);
      },
    );
  }
}
