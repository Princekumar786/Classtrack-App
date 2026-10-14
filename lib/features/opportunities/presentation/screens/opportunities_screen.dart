import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/metrics_service.dart';
import '../../../../core/utils/date_utils.dart';
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
import '../../domain/resource_type.dart';
import '../providers/opportunities_providers.dart';
import '../widgets/premium_gate.dart';
import '../widgets/resource_card.dart';
import 'discounts_screen.dart';
import 'resource_detail_screen.dart';
import 'saved_opportunities_screen.dart';

/// The Opportunities destination: a live feed of scholarships, internships,
/// competitions, etc. (perks have their own surface). A featured carousel sits
/// atop a personalized "Recommended for you" list, with category chips and a
/// filter sheet over the unified `resources` collection.
class OpportunitiesScreen extends ConsumerStatefulWidget {
  const OpportunitiesScreen({super.key});

  @override
  ConsumerState<OpportunitiesScreen> createState() =>
      _OpportunitiesScreenState();
}

class _OpportunitiesScreenState extends ConsumerState<OpportunitiesScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _searching = false;
  ResourceType? _type; // null = All
  bool _remoteOnly = false;
  bool _paidOnly = false;
  bool _verifiedOnly = false;

  bool get _hasFilters =>
      _type != null ||
      _remoteOnly ||
      _paidOnly ||
      _verifiedOnly ||
      _query.isNotEmpty;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _open(Resource r) => Navigator.of(
    context,
  ).push(MaterialPageRoute(settings: const RouteSettings(name: 'Resource Detail'), builder: (_) => ResourceDetailScreen(resource: r)));

  void _openFeatured(List<Resource> items) => Navigator.of(context).push(
    MaterialPageRoute(
          settings: const RouteSettings(name: 'All Featured Opportunities'),
          builder: (_) => _AllFeaturedOppsScreen(items: items)),
  );

  void _clearAll() {
    _searchCtrl.clear();
    setState(() {
      _type = null;
      _remoteOnly = false;
      _paidOnly = false;
      _verifiedOnly = false;
      _query = '';
    });
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          Widget toggle(
            String label,
            IconData icon,
            bool value,
            ValueChanged<bool> onChanged,
          ) => SwitchListTile(
            value: value,
            activeThumbColor: AppColors.primary,
            onChanged: (v) {
              setSheet(() {});
              onChanged(v);
            },
            secondary: Icon(icon, color: AppColors.primary),
            title: Text(label, style: theme.textTheme.titleMedium),
          );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Text('Filters', style: theme.textTheme.titleLarge),
                  ),
                  toggle(
                    'Remote only',
                    Icons.public_rounded,
                    _remoteOnly,
                    (v) => setState(() => _remoteOnly = v),
                  ),
                  toggle(
                    'Paid / stipend',
                    Icons.payments_rounded,
                    _paidOnly,
                    (v) => setState(() => _paidOnly = v),
                  ),
                  toggle(
                    'Verified only',
                    Icons.verified_rounded,
                    _verifiedOnly,
                    (v) => setState(() => _verifiedOnly = v),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _clearAll();
                              Navigator.pop(ctx);
                            },
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Show results'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(visibleResourcesProvider);
    final country = ref.watch(effectiveCountryProvider);
    final hidden = ref.watch(hiddenResourceIdsProvider).valueOrNull ?? const {};
    // Clearance so the last card is never hidden behind the floating bottom
    // nav bar + FAB (larger on devices with a 3-button system nav).
    final bottomClear = 120.0 + MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Opportunities'),
        actions: [
          IconButton(
            icon: Icon(
              _searching ? Icons.search_off_rounded : Icons.search_rounded,
            ),
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
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.tune_rounded),
                if (_remoteOnly || _paidOnly || _verifiedOnly)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Filters',
            onPressed: _openFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.card_giftcard_outlined),
            tooltip: 'Perks',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(settings: const RouteSettings(name: 'Discounts'), builder: (_) => const DiscountsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_border_rounded),
            tooltip: 'Saved',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'Saved Opportunities'),
                builder: (_) => const SavedOpportunitiesScreen(),
              ),
            ),
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
                    hintText: 'Search opportunities',
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => _messageState(
                  theme,
                  icon: Icons.cloud_off_rounded,
                  title: "Couldn't load opportunities",
                  body: 'Check your connection and try again.',
                  onRetry: () => ref.invalidate(visibleResourcesProvider),
                ),
                data: (all) {
                  final opportunities = all
                      .where((r) => !r.type.isDiscount)
                      .where((r) => r.isInActiveFeed)
                      .where((r) => r.targetsCountry(country))
                      .where((r) => !hidden.contains(r.id))
                      .toList();

                  if (opportunities.isEmpty) {
                    return _emptyContentState(theme);
                  }

                  final types = <ResourceType>{
                    for (final r in opportunities) r.type,
                  }.toList()..sort((a, b) => a.label.compareTo(b.label));

                  var list = _type == null
                      ? opportunities
                      : opportunities.where((r) => r.type == _type).toList();
                  list = ResourceQueries.search(list, _query);
                  if (_remoteOnly) {
                    list = list.where((r) => r.remote == true).toList();
                  }
                  if (_paidOnly) {
                    list = list.where((r) => r.paid == true).toList();
                  }
                  if (_verifiedOnly) {
                    list = list.where((r) => r.verified).toList();
                  }
                  list = ref
                      .read(recommenderProvider)
                      .rank(list, ref.watch(userProfileProvider).valueOrNull);

                  // Featured carousel: ONLY items actually flagged featured in
                  // the CMS — so it's hidden (no empty gap) until you feature
                  // something.
                  final featured = list
                      .where((r) => r.featured)
                      .take(8)
                      .toList();

                  // ── Premium gate ────────────────────────────────────────
                  // Free members browse only the 5 most-recently-updated
                  // opportunities. The allowed set is computed from the full
                  // active feed (not the filtered/searched list) so it can't be
                  // bypassed by searching or filtering. The featured carousel
                  // above stays a free teaser; the remaining catalogue is
                  // unlocked with Premium via the upsell card appended below.
                  final isPro = ref.watch(isProProvider);
                  final allowedIds =
                      freeAllowedIds(opportunities, isPro: isPro);
                  final lockedCount = allowedIds == null
                      ? 0
                      : opportunities.length - allowedIds.length;
                  if (allowedIds != null) {
                    list =
                        list.where((r) => allowedIds.contains(r.id)).toList();
                  }

                  return _CategoryChips(
                    types: types,
                    selected: _type,
                    onSelect: (t) => setState(() => _type = t),
                    child: list.isEmpty
                        ? _messageState(
                            theme,
                            icon: Icons.filter_alt_off_rounded,
                            title: 'No matches',
                            body: 'Try clearing search or filters.',
                            onClear: _hasFilters ? _clearAll : null,
                          )
                        : Builder(
                            builder: (context) {
                              // The featured carousel needs a bounded height, but
                              // a hard 190px clipped 2-line titles (the "BOTTOM
                              // OVERFLOWED BY 10px" card) — and worse as the user
                              // scales text up (we allow up to 1.3x). Only the
                              // text inside the card scales, so add headroom
                              // proportional to the text scale.
                              final ts = MediaQuery.textScalerOf(
                                context,
                              ).scale(1.0).clamp(1.0, 1.6);
                              final carouselHeight = 204.0 + (ts - 1.0) * 90.0;
                              final header = <Widget>[
                                const PlacementBanner(
                                  placement: Placements.opportunities,
                                ),
                                const PlacementCampaign(
                                  placement: Placements.opportunities,
                                ),
                                if (featured.isNotEmpty && !_hasFilters) ...[
                                  SectionHeader(
                                    title: '🔥 Featured',
                                    actionLabel: featured.length > 1
                                        ? 'See all'
                                        : null,
                                    onAction: featured.length > 1
                                        ? () => _openFeatured(featured)
                                        : null,
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    height: carouselHeight,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: featured.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 14),
                                      itemBuilder: (_, i) => _FeaturedOppCard(
                                        resource: featured[i],
                                        accentIndex: i,
                                        onTap: () => _open(featured[i]),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                ],
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 20,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Recommended for you',
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Personalized picks based on your profile and activity',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.hintColor,
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ];
                              // Lazy list: only visible cards (and their image
                              // streams) are built, keeping scroll smooth.
                              final showUpsell = lockedCount > 0;
                              return ListView.builder(
                                padding: EdgeInsets.fromLTRB(
                                  20,
                                  4,
                                  20,
                                  bottomClear,
                                ),
                                itemCount: header.length +
                                    list.length +
                                    (showUpsell ? 1 : 0),
                                itemBuilder: (_, i) {
                                  if (i < header.length) return header[i];
                                  final idx = i - header.length;
                                  if (idx < list.length) {
                                    final r = list[idx];
                                    return _OpportunityCard(
                                      resource: r,
                                      onTap: () => _open(r),
                                    );
                                  }
                                  return const PremiumUnlockCard(
                                    noun: 'opportunities',
                                  );
                                },
                              );
                            },
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageState(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String body,
    VoidCallback? onClear,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyIllustration(icon: icon, color: AppColors.primary),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
            if (onClear != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Clear filters'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyContentState(ThemeData theme) {
    final hasProfile =
        ref.watch(userProfileProvider).valueOrNull?.hasAnyProfileDetails ??
        false;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          20, 24, 20, 120 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: softCard(context),
          child: Column(
            children: [
              const EmptyIllustration(
                icon: Icons.rocket_launch_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(height: 10),
              Text(
                'New opportunities are on the way',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                hasProfile
                    ? "We're curating scholarships, internships and deals matched to you. Check back soon."
                    : 'Add your country, degree & interests so we can match the best opportunities to you.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
                textAlign: TextAlign.center,
              ),
              if (!hasProfile) ...[
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      settings: const RouteSettings(name: 'Edit Profile'),
                      builder: (_) => const EditProfileScreen(),
                    ),
                  ),
                  child: const Text('Complete your profile'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Wraps content with a sticky-ish horizontal category chip bar on top.
class _CategoryChips extends StatelessWidget {
  final List<ResourceType> types;
  final ResourceType? selected;
  final ValueChanged<ResourceType?> onSelect;
  final Widget child;
  const _CategoryChips({
    required this.types,
    required this.selected,
    required this.onSelect,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CatChip(
                  label: 'All',
                  icon: Icons.grid_view_rounded,
                  accent: AppColors.primary,
                  selected: selected == null,
                  onTap: () => onSelect(null),
                ),
              ),
              for (final t in types)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _CatChip(
                    label: t.label,
                    icon: t.icon,
                    accent: t.color,
                    selected: selected == t,
                    onTap: () => onSelect(selected == t ? null : t),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: child),
      ],
    );
  }
}

/// A compact, soft category chip: filled tint + coloured icon when idle, solid
/// accent when selected. Deliberately lighter than [FilterPill] (smaller text,
/// no heavy border) so a bar of long labels stays clean and scannable.
class _CatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip({
    required this.label,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? accent
        : (theme.brightness == Brightness.dark
              ? AppColors.darkSurfaceAlt
              : accent.withValues(alpha: 0.10));
    final fg = selected ? Colors.white : accent;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? Colors.white
                      : theme.textTheme.bodyMedium?.color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact, tinted featured-opportunity card for the horizontal row — styled
/// to match the Perks "Featured" cards.
class _FeaturedOppCard extends ConsumerWidget {
  final Resource resource;
  final int accentIndex;
  final VoidCallback onTap;
  const _FeaturedOppCard({
    required this.resource,
    required this.accentIndex,
    required this.onTap,
  });

  static const _palettes = [
    (Color(0xFFE7E1FB), AppColors.primary),
    (Color(0xFFE1F3E9), AppColors.success),
    (Color(0xFFFBEAD6), AppColors.accent),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (paletteBg, accent) = _palettes[accentIndex % _palettes.length];
    // The palette backgrounds are light pastels; in dark mode they'd wash out
    // the near-white title text. Use a subtle accent-tinted dark surface there
    // so the card keeps its colour while the text stays legible.
    final bg = theme.brightness == Brightness.dark
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.16),
            AppColors.darkSurface,
          )
        : paletteBg;
    final match = ref.watch(resourceScoreProvider(resource));
    final showMatch = match.personalized && match.score >= 40;
    // Feed impression for sponsor reporting (deduped per session).
    ref.read(metricsServiceProvider).recordImpression(resource.id);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 178,
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
                Icon(Icons.workspace_premium_rounded, size: 13, color: accent),
                const SizedBox(width: 3),
                Text(
                  'Featured',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ResourceThumb(resource: resource, size: 40, preferLogo: true),
            const SizedBox(height: 10),
            Text(
              resource.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              resource.type.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    showMatch
                        ? '${match.score}% match'
                        : (resource.deadline != null
                              ? 'By ${DateUtilsX.prettyDate(resource.deadline!)}'
                              : resource.organization),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: showMatch ? AppColors.success : theme.hintColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Full list of featured opportunities (opened from "See all").
class _AllFeaturedOppsScreen extends StatelessWidget {
  final List<Resource> items;
  const _AllFeaturedOppsScreen({required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Featured')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final r = items[i];
          return _OpportunityCard(
            resource: r,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'Resource Detail'),
                builder: (_) => ResourceDetailScreen(resource: r),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A rich recommended-opportunity card: type + match tags, title, org, a meta
/// row (deadline / stipend / location) and a match score, with an inline save.
class _OpportunityCard extends ConsumerWidget {
  final Resource resource;
  final VoidCallback onTap;
  const _OpportunityCard({required this.resource, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final saved = ref.watch(savedResourceIdsProvider).valueOrNull ?? const {};
    final isSaved = saved.contains(resource.id);
    final match = ref.watch(resourceScoreProvider(resource));

    final published = resource.publishedAt ?? resource.createdAt;
    final isNew =
        published != null && DateTime.now().difference(published).inDays <= 14;
    final showMatch = match.personalized && match.score >= 40;
    // Feed impression for sponsor reporting (deduped per session).
    ref.read(metricsServiceProvider).recordImpression(resource.id);

    // Compact, single inline meta line — only the bits that actually exist, so
    // the card never reserves empty space.
    final metaBits = <Widget>[
      if (resource.deadline != null)
        _MetaBit(
            icon: Icons.event_rounded,
            label: 'By ${DateUtilsX.prettyDate(resource.deadline!)}',
            color: theme.hintColor),
      if (resource.paid == true)
        const _MetaBit(
            icon: Icons.payments_rounded,
            label: 'Paid',
            color: AppColors.success),
      if (showMatch)
        _MetaBit(
            icon: Icons.auto_awesome_rounded,
            label: '${match.score}% match',
            color: AppColors.success)
      else if (isNew)
        const _MetaBit(
            icon: Icons.fiber_manual_record,
            label: 'Newly added',
            color: AppColors.info),
      if (resource.sponsored)
        const _MetaBit(
            icon: Icons.star_rounded,
            label: 'Sponsored',
            color: AppColors.accent),
    ];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: softCard(context, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ResourceThumb(resource: resource, size: 44, preferLogo: true),
                const SizedBox(width: 12),
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
                          if (resource.verified)
                            const Icon(
                              Icons.verified_rounded,
                              size: 15,
                              color: AppColors.info,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        resource.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        resource.organization,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
                _SaveIcon(resource: resource, isSaved: isSaved, saved: saved),
              ],
            ),
            if (metaBits.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: metaBits,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tiny inline meta item: a small icon + label. Keeps opportunity cards
/// compact — no boxed strips or reserved rows, so short listings stay short.
class _MetaBit extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MetaBit(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SaveIcon extends ConsumerWidget {
  final Resource resource;
  final bool isSaved;
  final Set<String> saved;
  const _SaveIcon({
    required this.resource,
    required this.isSaved,
    required this.saved,
  });

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
        ctrl.toggle(resource, saved);
      },
    );
  }
}
