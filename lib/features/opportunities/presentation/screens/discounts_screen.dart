import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/placement_banner.dart';
import '../../../../shared/widgets/placement_campaign.dart';
import '../../../../shared/widgets/illustrations.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/screens/edit_profile_screen.dart';
import '../../../cms/domain/marketing.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../data/resource_repository.dart';
import '../../domain/resource.dart';
import '../providers/opportunities_providers.dart';
import '../widgets/premium_gate.dart';
import '../widgets/resource_card.dart';
import 'resource_detail_screen.dart';
import 'saved_opportunities_screen.dart';

/// The Perks surface — exclusive student discounts. Same unified `resources`
/// model as Opportunities (type == discount), so it reuses [ResourceThumb] and
/// [ResourceDetailScreen] (which renders the redemption instructions, optional
/// verification note and the external "Get deal" CTA).
///
/// Redesigned as a savings-first destination: a savings hero, category chips,
/// a "Featured perks" carousel and a "Top deals" list.
class DiscountsScreen extends ConsumerStatefulWidget {
  const DiscountsScreen({super.key});

  @override
  ConsumerState<DiscountsScreen> createState() => _DiscountsScreenState();
}

class _DiscountsScreenState extends ConsumerState<DiscountsScreen> {
  String? _category; // null = All
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _open(Resource r) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResourceDetailScreen(resource: r)));

  void _openAll(List<Resource> perks, {int lockedCount = 0}) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              _AllPerksScreen(perks: perks, lockedCount: lockedCount),
        ),
      );

  void _openSaved() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedOpportunitiesScreen()));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(visibleResourcesProvider);
    final country = ref.watch(userProfileProvider).valueOrNull?.country;
    final hidden = ref.watch(hiddenResourceIdsProvider).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perks'),
        actions: [
          IconButton(
            icon: Icon(
                _searching ? Icons.search_off_rounded : Icons.search_rounded),
            tooltip: 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchCtrl.clear();
                _query = '';
              }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_border_rounded),
            tooltip: 'Saved',
            onPressed: _openSaved,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search perks & brands',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _query = '';
                          _searching = false;
                        });
                      },
                    ),
                    filled: true,
                    fillColor: theme.cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  ),
                ),
              ),
            Expanded(
              child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _messageState(
          theme,
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load perks",
          body: 'Check your connection and try again.',
          onRetry: () => ref.invalidate(visibleResourcesProvider),
        ),
        data: (all) {
          final perks = all
              .where((r) => r.type.isDiscount)
              .where((r) => r.isInActiveFeed)
              .where((r) => r.targetsCountry(country))
              .where((r) => !hidden.contains(r.id))
              .toList();

          if (perks.isEmpty) {
            final hasProfile = ref
                    .watch(userProfileProvider)
                    .valueOrNull
                    ?.hasAnyProfileDetails ??
                false;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: softCard(context),
                  child: Column(
                    children: [
                      const EmptyIllustration(
                          icon: Icons.redeem_rounded,
                          color: AppColors.primary),
                      const SizedBox(height: 10),
                      Text('Fresh student perks are on the way',
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 6),
                      Text(
                        hasProfile
                            ? "We're lining up exclusive student discounts matched to you. Check back soon."
                            : 'Add your country & interests so we can match the best student discounts to you.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                        textAlign: TextAlign.center,
                      ),
                      if (!hasProfile) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary),
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const EditProfileScreen())),
                          child: const Text('Complete your profile'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }

          final categories = <String>{for (final d in perks) ...d.categories}
              .toList()
            ..sort();

          final filtered = ResourceQueries.search(
            _category == null
                ? perks
                : perks.where((d) => d.categories.contains(_category)).toList(),
            _query,
          );

          // Featured (carousel) vs the rest (top deals list).
          final featured = filtered.where((d) => d.featured).toList();
          final featuredCarousel =
              featured.isNotEmpty ? featured : filtered.take(3).toList();
          final featuredIds = featuredCarousel.map((e) => e.id).toSet();
          final allDeals =
              filtered.where((d) => !featuredIds.contains(d.id)).toList();

          // ── Premium gate ──────────────────────────────────────────────
          // Free members browse only the 5 most-recently-updated perks. The
          // allowed set is computed from the full active perk feed (not the
          // filtered/searched list) so it can't be bypassed by search or a
          // category. The featured carousel above stays a free teaser; the
          // rest is unlocked with Premium via the upsell card appended below.
          final isPro = ref.watch(isProProvider);
          final allowedIds = freeAllowedIds(perks, isPro: isPro);
          final lockedCount =
              allowedIds == null ? 0 : perks.length - allowedIds.length;
          final deals = allowedIds == null
              ? allDeals
              : allDeals.where((d) => allowedIds.contains(d.id)).toList();

          final totalSavings = perks.fold<num>(
              0, (sum, r) => sum + (_savingsAmount(r) ?? 0));

          final header = <Widget>[
            _SavingsHero(
              totalSavings: totalSavings,
              perksCount: perks.length,
              onViewSavings: _openSaved,
            ),
            const SizedBox(height: 18),
            if (categories.isNotEmpty) ...[
              _CategoryChips(
                categories: categories,
                selected: _category,
                onSelect: (c) => setState(() => _category = c),
              ),
              const SizedBox(height: 20),
            ],
            const PlacementBanner(placement: Placements.discounts),
            const PlacementCampaign(placement: Placements.discounts),
            if (featuredCarousel.isNotEmpty) ...[
              SectionHeader(
                title: '🔥 Featured perks',
                actionLabel: 'See all',
                onAction: () => _openAll(
                  allowedIds == null
                      ? filtered
                      : filtered
                          .where((d) => allowedIds.contains(d.id))
                          .toList(),
                  lockedCount: lockedCount,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                // Grow with the OS text size so card text never overflows.
                height: 214.0 +
                    (MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6) - 1.0) *
                        90.0,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: featuredCarousel.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, i) => _FeaturedPerkCard(
                    resource: featuredCarousel[i],
                    accentIndex: i,
                    country: country,
                    onTap: () => _open(featuredCarousel[i]),
                  ),
                ),
              ),
              const SizedBox(height: 22),
            ],
            if (deals.isNotEmpty) ...[
              SectionHeader(
                title: 'Top deals for you',
                actionLabel: _category == null ? null : 'Clear',
                onAction: _category == null
                    ? null
                    : () => setState(() => _category = null),
              ),
              const SizedBox(height: 12),
            ] else if (featuredCarousel.isEmpty)
              _messageState(
                theme,
                icon: Icons.filter_alt_off_rounded,
                title: 'No matches',
                body: 'Try a different category.',
              ),
          ];

          // Lazy list: only visible deal rows (and their image streams) build.
          final showUpsell = lockedCount > 0;
          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, 32 + MediaQuery.viewPaddingOf(context).bottom),
            itemCount:
                header.length + deals.length + (showUpsell ? 1 : 0),
            itemBuilder: (_, i) {
              if (i < header.length) return header[i];
              final idx = i - header.length;
              if (idx < deals.length) {
                final r = deals[idx];
                return _DealRow(resource: r, onTap: () => _open(r));
              }
              return const PremiumUnlockCard(
                noun: 'perks',
              );
            },
          );
        },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageState(ThemeData theme,
      {required IconData icon,
      required String title,
      required String body,
      VoidCallback? onRetry}) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyIllustration(icon: icon, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Best-effort parse of a rupee savings amount from a perk's text (e.g.
/// "Save ₹589/year"). Returns null when no amount is present.
num? _savingsAmount(Resource r) {
  for (final s in [r.discountText, r.terms, r.description, r.title]) {
    if (s == null || s.isEmpty) continue;
    final m = RegExp(r'(?:₹|rs\.?\s?)\s?([\d,]+)', caseSensitive: false)
        .firstMatch(s);
    if (m != null) {
      final n = num.tryParse(m.group(1)!.replaceAll(',', ''));
      if (n != null && n > 0) return n;
    }
  }
  return null;
}

String _formatRupees(num v) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(v);

/// The savings hero banner: a soft lavender gradient card with a gift motif,
/// the total unlocked savings and a "View my savings" affordance.
class _SavingsHero extends StatelessWidget {
  final num totalSavings;
  final int perksCount;
  final VoidCallback onViewSavings;
  const _SavingsHero({
    required this.totalSavings,
    required this.perksCount,
    required this.onViewSavings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAmount = totalSavings > 0;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: AppColors.softShadow(opacity: 0.28, blur: 26),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Decorative translucent circles for depth.
          Positioned(
            right: -26,
            top: -28,
            child: _blob(96, Colors.white.withValues(alpha: 0.12)),
          ),
          Positioned(
            right: 40,
            bottom: -34,
            child: _blob(72, Colors.white.withValues(alpha: 0.08)),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome_rounded,
                                color: Colors.white, size: 14),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text("You're saving big!",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        hasAmount
                            ? _formatRupees(totalSavings)
                            : '$perksCount ${perksCount == 1 ? 'perk' : 'perks'}',
                        style: theme.textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasAmount
                            ? 'saved with student perks'
                            : 'Exclusive student deals, unlocked',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9)),
                      ),
                      const SizedBox(height: 16),
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onViewSavings,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text('View my savings',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium?.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded,
                                    size: 18, color: AppColors.primary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.redeem_rounded,
                        size: 30, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Horizontal category filter chips (All + each category), matching the app's
/// [FilterPill] language.
class _CategoryChips extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  static const _icons = <String, IconData>{
    'tech': Icons.laptop_mac_rounded,
    'technology': Icons.laptop_mac_rounded,
    'learning': Icons.menu_book_rounded,
    'education': Icons.menu_book_rounded,
    'lifestyle': Icons.spa_rounded,
    'travel': Icons.flight_takeoff_rounded,
    'food': Icons.restaurant_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'entertainment': Icons.movie_rounded,
    'software': Icons.apps_rounded,
    'music': Icons.music_note_rounded,
    'gaming': Icons.sports_esports_rounded,
    'fashion': Icons.checkroom_rounded,
    'health': Icons.favorite_rounded,
    'finance': Icons.account_balance_wallet_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterPill(
              label: 'All',
              icon: Icons.grid_view_rounded,
              selected: selected == null,
              onTap: () => onSelect(null),
            ),
          ),
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterPill(
                label: c,
                icon: _icons[c.toLowerCase()] ?? Icons.redeem_rounded,
                selected: selected == c,
                onTap: () => onSelect(selected == c ? null : c),
              ),
            ),
        ],
      ),
    );
  }
}

/// A rich, tinted featured-perk card for the horizontal carousel.
class _FeaturedPerkCard extends StatelessWidget {
  final Resource resource;
  final int accentIndex;
  final String? country;
  final VoidCallback onTap;
  const _FeaturedPerkCard({
    required this.resource,
    required this.accentIndex,
    required this.onTap,
    this.country,
  });

  // Rotating soft palettes to give the carousel visual variety.
  static const _palettes = [
    (Color(0xFFE7E1FB), AppColors.primary),
    (Color(0xFFE1F3E9), AppColors.success),
    (Color(0xFFFBEAD6), AppColors.accent),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (paletteBg, accent) = _palettes[accentIndex % _palettes.length];
    // The palette backgrounds are light pastels; in dark mode they'd wash out
    // the near-white brand/title text. Use a subtle accent-tinted dark surface
    // there so the card keeps its colour while the text stays legible.
    final bg = theme.brightness == Brightness.dark
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.16), AppColors.darkSurface)
        : paletteBg;
    final days = resource.daysUntilDeadline;
    final limited = days != null && days >= 0 && days <= 14;
    final badgeLabel = limited
        ? 'Limited time'
        : (resource.sponsored || resource.verified ? 'Exclusive' : 'Popular');

    final save = _savingsAmount(resource);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 176,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.22), width: 1),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star_rounded, size: 13, color: accent),
                const SizedBox(width: 3),
                Text(badgeLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: accent, fontWeight: FontWeight.w700, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 12),
            ResourceThumb(resource: resource, size: 40, preferLogo: true),
            const SizedBox(height: 10),
            Text(resource.brandName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            if ((resource.effectiveOffer(country).discountText?.isNotEmpty ??
                false))
              Text(resource.effectiveOffer(country).discountText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: accent, fontWeight: FontWeight.w800)),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: save != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('Save ${_formatRupees(save)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                  color: accent, fontWeight: FontWeight.w700)),
                        )
                      : Text(resource.eligibility ?? 'Student offer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor)),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 30,
                  height: 30,
                  decoration:
                      const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 16, color: accent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact "Top deals" list row: logo, name + subtitle, a discount pill and a
/// "View deal" affordance with an inline save toggle.
class _DealRow extends ConsumerWidget {
  final Resource resource;
  final VoidCallback onTap;
  const _DealRow({required this.resource, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final saved = ref.watch(savedResourceIdsProvider).valueOrNull ?? const {};
    final isSaved = saved.contains(resource.id);
    final subtitle = resource.description.isNotEmpty
        ? resource.description
        : (resource.eligibility ?? resource.organization);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: softCard(context, radius: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResourceThumb(resource: resource, size: 48, preferLogo: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(resource.brandName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 3),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (resource.discountText != null &&
                    resource.discountText!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(resource.discountText!,
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 11)),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View perk',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
                    const Icon(Icons.chevron_right_rounded,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: () {
                        final ctrl =
                            ref.read(savedResourceControllerProvider);
                        if (!ctrl.isReady) return;
                        ctrl.toggle(resource, saved);
                      },
                      child: Icon(
                        isSaved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 20,
                        color: isSaved ? AppColors.primary : theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}



/// Full, scrollable list of every available perk (opened from "See all").
/// For free members this is the same gated set as the main screen, with a
/// Premium upsell footer when [lockedCount] perks are still locked.
class _AllPerksScreen extends StatelessWidget {
  final List<Resource> perks;
  final int lockedCount;
  const _AllPerksScreen({required this.perks, this.lockedCount = 0});

  @override
  Widget build(BuildContext context) {
    final showUpsell = lockedCount > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('All perks')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        itemCount: perks.length + (showUpsell ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= perks.length) {
            return const PremiumUnlockCard(noun: 'perks');
          }
          final r = perks[i];
          return _DealRow(
            resource: r,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ResourceDetailScreen(resource: r))),
          );
        },
      ),
    );
  }
}
