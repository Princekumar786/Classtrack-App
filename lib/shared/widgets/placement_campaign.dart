import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/firebase_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/firestore_parsing.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/cms/domain/marketing.dart';
import '../../features/opportunities/domain/resource.dart';
import '../../features/opportunities/presentation/providers/opportunities_providers.dart';
import '../../features/opportunities/presentation/screens/resource_detail_screen.dart';
import '../../services/analytics_service.dart';
import 'ui_kit.dart';

/// Live, published campaigns for a [placement], targeted to the user's country
/// and priority-ordered. Students may read published campaigns (Firestore
/// rules); the app resolves each campaign's promoted resource for display.
final placementCampaignsProvider =
    StreamProvider.family<List<Campaign>, String>((ref, placement) {
  final db = ref.watch(firestoreProvider);
  final country = ref.watch(effectiveCountryProvider);
  return db
      .collection(AppConstants.campaignsCollection)
      .where('published', isEqualTo: true)
      .limit(50)
      .snapshots()
      .map((snap) {
    final all =
        parseDocsSafely(snap.docs, Campaign.fromMap, context: 'campaigns');
    return all
        .where((c) =>
            c.placement == placement &&
            c.isLive() &&
            _targets(c.countries, country))
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
  });
});

bool _targets(List<String> countries, String? country) {
  if (countries.isEmpty) return true;
  if (countries.any((c) => c.toLowerCase() == 'global')) return true;
  if (country == null) return false;
  return countries.any((c) => c.toLowerCase() == country.toLowerCase());
}

/// Renders the top live sponsored campaign for [placement] as a card promoting
/// its linked resource; tapping opens that resource's detail page. Shows
/// nothing unless a live campaign resolves to a currently-visible resource.
class PlacementCampaign extends ConsumerStatefulWidget {
  final String placement;
  final EdgeInsetsGeometry padding;
  const PlacementCampaign({
    super.key,
    required this.placement,
    this.padding = const EdgeInsets.only(bottom: 16),
  });

  @override
  ConsumerState<PlacementCampaign> createState() => _PlacementCampaignState();
}

class _PlacementCampaignState extends ConsumerState<PlacementCampaign> {
  String? _loggedViewId;

  void _logView(String id) {
    if (_loggedViewId == id) return;
    _loggedViewId = id;
    ref
        .read(analyticsProvider)
        .log('campaign_viewed', {'id': id, 'placement': widget.placement});
  }

  @override
  Widget build(BuildContext context) {
    final campaigns =
        ref.watch(placementCampaignsProvider(widget.placement)).valueOrNull ??
            const <Campaign>[];
    if (campaigns.isEmpty) return const SizedBox.shrink();
    final resources =
        ref.watch(visibleResourcesProvider).valueOrNull ?? const <Resource>[];

    // Pick the first live campaign whose promoted resource is currently visible.
    Campaign? campaign;
    Resource? resource;
    for (final c in campaigns) {
      if (c.resourceId == null || c.resourceId!.isEmpty) continue;
      for (final r in resources) {
        if (r.id == c.resourceId) {
          campaign = c;
          resource = r;
          break;
        }
      }
      if (campaign != null) break;
    }
    if (campaign == null || resource == null) return const SizedBox.shrink();

    final camp = campaign;
    final res = resource;
    WidgetsBinding.instance.addPostFrameCallback((_) => _logView(camp.id));

    return Padding(
      padding: widget.padding,
      child: _CampaignCard(
        campaign: camp,
        resource: res,
        onTap: () => _onTap(camp, res),
      ),
    );
  }

  void _onTap(Campaign campaign, Resource resource) {
    ref.read(analyticsProvider).log('campaign_clicked',
        {'id': campaign.id, 'placement': widget.placement});
    Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'Resource Detail'),
        builder: (_) => ResourceDetailScreen(resource: resource)));
  }
}

class _CampaignCard extends StatelessWidget {
  final Campaign campaign;
  final Resource resource;
  final VoidCallback onTap;
  const _CampaignCard({
    required this.campaign,
    required this.resource,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: softCard(context, radius: 18).copyWith(
            border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.5), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: resource.type.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(resource.type.icon,
                    color: resource.type.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: AppColors.accent),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'SPONSORED${campaign.company.isNotEmpty ? ' · ${campaign.company}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(resource.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('${resource.type.label} · ${resource.organization}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }
}
