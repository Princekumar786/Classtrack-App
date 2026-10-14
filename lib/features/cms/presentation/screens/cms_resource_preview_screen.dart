import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../auth/domain/app_user.dart';
import '../../../auth/domain/profile_options.dart';
import '../../../opportunities/domain/resource.dart';
import '../../../opportunities/presentation/providers/opportunities_providers.dart';
import '../../../opportunities/presentation/widgets/resource_card.dart';

/// "Preview as student" — renders a resource exactly as the student app would,
/// using the REAL [ResourceCard] widget under a synthetic profile so admins can
/// see the card, match badge, status and targeting for a chosen audience
/// before publishing. Non-interactive (taps/saves are absorbed).
class CmsResourcePreviewScreen extends ConsumerStatefulWidget {
  final Resource resource;
  const CmsResourcePreviewScreen({super.key, required this.resource});

  @override
  ConsumerState<CmsResourcePreviewScreen> createState() =>
      _CmsResourcePreviewScreenState();
}

class _CmsResourcePreviewScreenState
    extends ConsumerState<CmsResourcePreviewScreen> {
  String? _country = 'India';
  final Set<String> _interests = {'Technology'};

  AppUser get _previewUser => AppUser(
    uid: 'preview',
    displayName: 'Preview student',
    country: _country,
    interests: _interests.toList(),
  );

  Resource get r => widget.resource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targeted = r.targetsCountry(_country);
    final match = r.type.isDiscount
        ? null
        : ref.watch(recommenderProvider).score(r, _previewUser);

    return Scaffold(
      appBar: AppBar(title: const Text('Preview as student')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _profileCard(theme),
          const SizedBox(height: 12),
          _matchSummary(
            theme,
            targeted,
            match?.score,
            match?.personalized ?? false,
          ),
          const SizedBox(height: 20),
          Text(
            'IN THE FEED',
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 1,
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 10),
          // The real feed card (non-interactive). Its own match badge reflects
          // the signed-in admin's profile; the profile-accurate match for the
          // previewed audience is shown in the summary above.
          AbsorbPointer(
            child: ResourceCard(
              resource: r,
              onTap: () {},
              previewCountry: _country,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'DETAIL PAGE',
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 1,
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 10),
          _detailPreview(theme),
        ],
      ),
    );
  }

  Widget _matchSummary(
    ThemeData theme,
    bool targeted,
    int? matchScore,
    bool personalized,
  ) {
    final ok = targeted;
    final color = ok ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: softCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.public_off_rounded,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  targeted
                      ? 'Visible to this student (country targeting matches).'
                      : 'Hidden from this student — does not target ${_country ?? "their country"}.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (matchScore != null) ...[
            const SizedBox(height: 8),
            Text(
              personalized
                  ? 'Recommendation match for this profile: $matchScore%'
                  : 'Recommendation match: $matchScore% (add interests/degree to personalise)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _profileCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: softCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_pin_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Preview profile',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _country,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Country'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Any')),
              ...ProfileOptions.countries.map(
                (c) => DropdownMenuItem(value: c, child: Text(c)),
              ),
            ],
            onChanged: (v) => setState(() => _country = v),
          ),
          // Interests only affect opportunity matching, not discounts.
          if (!r.type.isDiscount) ...[
            const SizedBox(height: 14),
            Text('Interests', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final i in ProfileOptions.interests)
                  _chip(
                    i,
                    _interests.contains(i),
                    () => setState(() {
                      if (!_interests.remove(i)) _interests.add(i);
                    }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? AppColors.primary : theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: selected ? AppColors.primary : theme.dividerColor,
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected
                  ? Colors.white
                  : theme.textTheme.bodyMedium?.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailPreview(ThemeData theme) {
    final isDiscount = r.type.isDiscount;
    final cta = isDiscount ? 'Redeem perk' : 'Apply now';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: softCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ResourceThumb(resource: r, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title.isEmpty ? 'Untitled' : r.title,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.brandName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ResourcePill(
                label: r.effectiveStatus.label,
                color: r.effectiveStatus.color,
              ),
              if (r.sponsored)
                const ResourcePill(label: 'Sponsored', color: AppColors.accent),
            ],
          ),
          if (isDiscount) _regionalOfferPreview(theme),
          if (r.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(r.description, style: theme.textTheme.bodyMedium),
          ],
          _detailSection(theme, 'Benefits', r.benefits),
          _detailSection(theme, 'How to apply', r.howToApply),
          _detailSection(theme, 'Eligibility', r.eligibility),
          _detailSection(theme, 'Redemption', r.redemptionInstructions),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: null, // preview only
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(cta),
          ),
        ],
      ),
    );
  }

  /// Shows the discount's country-resolved price + redemption link for the
  /// currently-selected preview country (drives home the regional-variant
  /// behaviour: change the Country dropdown to see US vs India vs UK).
  Widget _regionalOfferPreview(ThemeData theme) {
    final offer = r.effectiveOffer(_country);
    final usesVariant = r.regionalVariants.any((v) => v.matches(_country));
    final price = offer.discountText;
    final link = offer.url;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.public_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Offer for ${_country ?? "Any country"}'
                  '${usesVariant ? "" : " (default)"}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              price?.isNotEmpty == true ? price! : 'No price set',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              link?.isNotEmpty == true ? link! : 'No link set',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailSection(ThemeData theme, String title, String? body) {
    if (body == null || body.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
