import 'dart:async';


import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/illustrations.dart';
import '../../../../shared/widgets/sweep_shimmer.dart';
import '../../data/subscription_service.dart';
import '../../domain/paywall_pricing.dart';
import '../../domain/pro_constants.dart';
import '../../domain/pro_features.dart';
import '../../domain/upgrade_reason.dart';
import '../providers/subscription_providers.dart';

export '../../domain/upgrade_reason.dart' show UpgradeReason;

// TODO(paywall conversion — do later): higher-impact levers to A/B test:
//   1. Replace the generic 5-star "Loved by students everywhere" pill with a
//      REAL, specific stat (e.g. "Join 12,000+ students" or "4.8★ on Google
//      Play") — specific proof converts far better than generic praise.
//   2. Add a free-trial timeline ("Today: full access → Day 5: reminder →
//      Day 7: billed") to remove billing anxiety and lift trial starts.
//   3. Add a compact Free-vs-Pro comparison (loss aversion beats a plain
//      benefits list).
//   4. Add gentle urgency for the discount (e.g. "offer ends soon").
//   5. Make the hero sell an outcome ("Never drop below 75% again") rather
//      than being purely decorative; quantify benefit copy.
// NOTE: the free-trial toggle was intentionally removed per product decision.

/// Opens the ClassTrack Pro pricing page. Returns true if the user became Pro.
///
/// [reason] tailors the headline and highlights the matching Free-vs-Pro row,
/// so a student who hit a limit sees exactly what Pro changes for them.
/// Prefer [showUpgradePrompt] (upgrade_prompt.dart) at limit/gate call sites —
/// it explains the limit first, then calls this.
Future<bool> showPaywall(BuildContext context,
    {UpgradeReason reason = UpgradeReason.general}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
        settings: RouteSettings(name: 'Paywall', arguments: reason.id),
        builder: (_) => PaywallScreen(reason: reason),
        fullscreenDialog: true),
  );
  return result ?? false;
}

/// A paid, time-limited introductory discount surfaced by the store — e.g.
/// "50% off your first year". This is the offer a user would otherwise only see
/// on the store's purchase sheet; we detect it up front so it's visible right
/// on the paywall. Distinct from a free trial (price 0), handled separately.
class _IntroOffer {
  /// Whole-number percent off the normal price, e.g. 50 for "50% off".
  final int percentOff;

  /// Localized, store-provided discounted price string, e.g. "₹499".
  final String priceString;

  const _IntroOffer({required this.percentOff, required this.priceString});
}

/// The short, scannable value checklist — benefit-first, one line each, so the
/// whole offer reads at a glance.
const List<_Benefit> _benefits = [
  _Benefit(Icons.auto_awesome_rounded,
      'Unlimited AI study assistant — ask anything, anytime'),
  _Benefit(Icons.document_scanner_rounded,
      'Unlimited timetable scans from a photo, PDF or text'),
  _Benefit(Icons.shield_moon_rounded,
      'Attendance risk alerts & safe-skip counts'),
  _Benefit(Icons.explore_rounded,
      'Scholarships, perks, insights & Google Calendar sync'),
];

class _Benefit {
  final IconData icon;
  final String text;
  const _Benefit(this.icon, this.text);
}

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.reason = UpgradeReason.general});

  /// What brought the student here (tailors hero + comparison highlight).
  final UpgradeReason reason;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  List<Package> _packages = const [];
  Package? _selected;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).log('paywall_viewed', {'reason': widget.reason.id});
    _load();
  }

  Future<void> _load() async {
    final service = ref.read(subscriptionServiceProvider);
    final packages = await service.fetchPackages();
    if (!mounted) return;
    setState(() {
      _packages = packages;
      _selected = packages.isNotEmpty ? _preferAnnual(packages) : null;
      _loading = false;
    });
  }

  /// Annual is pre-selected: it's the best-value, most-popular plan, and
  /// pre-selecting it nudges toward the higher-value choice. Falls back to
  /// monthly, then the first package, when no annual plan is configured.
  Package _preferAnnual(List<Package> packages) => packages.firstWhere(
        (p) => p.packageType == PackageType.annual,
        orElse: () => packages.firstWhere(
          (p) => p.packageType == PackageType.monthly,
          orElse: () => packages.first,
        ),
      );

  Future<void> _buy() async {
    final selected = _selected;
    if (selected == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok =
          await ref.read(subscriptionServiceProvider).purchase(selected);
      if (!mounted) return;
      if (ok) {
        ref.read(analyticsProvider).log('paywall_purchased', {
          'reason': widget.reason.id,
          'package': selected.packageType.name,
        });
        // Self-heal the server-trusted flag immediately rather than waiting on
        // the RevenueCat webhook, so gated features unlock right away.
        unawaited(reconcileServerEntitlement(
            ref.read(firebaseFunctionsProvider)));
        Navigator.of(context).pop(true);
      } else {
        setState(() => _busy = false); // user cancelled
      }
    } on SubscriptionException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(subscriptionServiceProvider).restore();
    if (!mounted) return;
    if (result.isPro) {
      unawaited(reconcileServerEntitlement(
          ref.read(firebaseFunctionsProvider)));
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = result.message;
      });
    }
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  bool get _canBuy => _selected != null && !_busy && ProConstants.enabled;

  /// True when the currently selected plan has a free trial available.
  bool get _selectedHasTrial =>
      _selected != null && _freeTrialLabel(_selected!.storeProduct) != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plansReady =
        !_loading && ProConstants.enabled && _packages.isNotEmpty;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(theme),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.reason == UpgradeReason.general) ...[
                      _socialProof(theme),
                      const SizedBox(height: 6),
                      _heroIllustration(theme),
                    ] else
                      _contextHero(theme),
                    const SizedBox(height: 6),
                    _title(theme),
                    const SizedBox(height: 16),
                    _benefitList(theme),
                    const SizedBox(height: 22),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (!ProConstants.enabled)
                      _notice(theme,
                          'Subscriptions aren\'t set up yet. Add your RevenueCat key and store products to enable Pro.')
                    else if (_packages.isEmpty)
                      _notice(theme,
                          'No plans available right now. Please check back shortly.')
                    else
                      _plansStacked(theme),
                    if (plansReady) ...[
                      const SizedBox(height: 14),
                      _reassurance(theme),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _errorBanner(theme, _error!),
                    ],
                    const SizedBox(height: 22),
                    _comparison(theme),
                    const SizedBox(height: 16),
                    _everythingIncluded(theme),
                  ],
                ),
              ),
            ),
            _bottomBar(theme),
          ],
        ),
      ),
    );
  }

  // --- Top bar (close + restore) -------------------------------------------

  Widget _topBar(ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
        child: Row(
          children: [
            IconButton(
              style: IconButton.styleFrom(
                backgroundColor: theme.cardColor,
                shape: const CircleBorder(),
              ),
              icon: Icon(Icons.close_rounded, color: theme.hintColor, size: 22),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            const Spacer(),
            TextButton(
              onPressed: _busy ? null : _restore,
              child: const Text('Restore'),
            ),
          ],
        ),
      );

  // --- Social proof ---------------------------------------------------------

  /// A gentle social-proof pill (five stars + a short line). Customize the copy
  /// with a real rating/stat once you have one to show.
  Widget _socialProof(ThemeData theme) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.lavender,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 5; i++)
                const Icon(Icons.star_rounded,
                    color: AppColors.accent, size: 16),
              const SizedBox(width: 8),
              Text('Loved by students everywhere',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 400.ms);

  // --- Hero: a student-life illustration (no logo, no mascot) ---------------

  Widget _heroIllustration(ThemeData theme) => const AuthIllustration(
        height: 168,
      ).animate().fadeIn(duration: 500.ms);

  Widget _title(ThemeData theme) => Column(
        children: [
          Text(
              widget.reason == UpgradeReason.general
                  ? 'ClassTrack Pro'
                  : widget.reason.copy.paywallHeadline,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 6),
          Text(
              widget.reason == UpgradeReason.general
                  ? 'Unlock your best semester yet.'
                  : 'ClassTrack Pro unlocks this — and everything else.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.hintColor, height: 1.35)),
        ],
      );

  // --- Contextual hero (opened from a limit / gate) -------------------------

  Widget _contextHero(ThemeData theme) {
    final copy = widget.reason.copy;
    Widget medal = Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(copy.color, Colors.white, 0.25)!, copy.color],
        ),
        boxShadow: [
          BoxShadow(color: copy.color.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 12)),
        ],
      ),
      child: Icon(copy.icon, color: Colors.white, size: 44),
    );
    if (!MediaQuery.of(context).disableAnimations) {
      medal = medal.animate().scaleXY(begin: 0.7, duration: 520.ms, curve: Curves.easeOutBack).fadeIn(duration: 260.ms);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(children: [
        Stack(alignment: Alignment.center, children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(shape: BoxShape.circle, color: copy.color.withValues(alpha: 0.08)),
          ),
          medal,
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: copy.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(copy.highlight,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(color: copy.color, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  // --- Free vs Pro comparison ----------------------------------------------

  Widget _comparison(ThemeData theme) {
    final highlight = widget.reason;
    final border = theme.dividerColor.withValues(alpha: 0.5);
    Widget cell(String? v, {required bool pro}) {
      if (v == null) {
        return Icon(Icons.remove_rounded, size: 18, color: theme.hintColor.withValues(alpha: 0.6));
      }
      if (v == 'Included') {
        return Icon(Icons.check_circle_rounded, size: 18, color: pro ? AppColors.primary : AppColors.success);
      }
      return Text(v,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: pro ? FontWeight.w800 : FontWeight.w500,
            color: pro ? AppColors.primary : null,
          ));
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: AppColors.primary.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Expanded(flex: 5, child: Text('Compare plans', style: theme.textTheme.labelLarge)),
            Expanded(flex: 3, child: Text('Free', textAlign: TextAlign.center, style: theme.textTheme.labelMedium)),
            Expanded(
              flex: 3,
              child: Text('Pro',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        for (final row in planComparison)
          Semantics(
            label: '${row.feature}: Free ${row.free ?? 'not included'}, Pro ${row.pro}',
            child: ExcludeSemantics(
              child: Container(
                decoration: BoxDecoration(
                  color: row.reason == highlight ? highlight.copy.color.withValues(alpha: 0.10) : null,
                  border: Border(top: BorderSide(color: border)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(children: [
                  Expanded(
                    flex: 5,
                    child: Text(row.feature,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: row.reason == highlight ? FontWeight.w800 : FontWeight.w600,
                        )),
                  ),
                  Expanded(flex: 3, child: Center(child: cell(row.free, pro: false))),
                  Expanded(flex: 3, child: Center(child: cell(row.pro, pro: true))),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  // --- Benefit checklist ----------------------------------------------------

  Widget _benefitList(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final b in _benefits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(b.icon, color: AppColors.primary, size: 15),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(b.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600, height: 1.3)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  // --- Plans (stacked full-width cards) ------------------------------------

  Widget _plansStacked(ThemeData theme) {
    final plans = _orderedPackages();
    return Column(
      children: [
        for (final p in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _planTile(theme, p),
          ),
      ],
    );
  }

  /// Best plan first (annual), then other cadences, with lifetime last.
  List<Package> _orderedPackages() {
    int rank(PackageType t) => switch (t) {
          PackageType.annual => 0,
          PackageType.sixMonth => 1,
          PackageType.threeMonth => 2,
          PackageType.twoMonth => 3,
          PackageType.monthly => 4,
          PackageType.weekly => 5,
          PackageType.lifetime => 6,
          _ => 4,
        };
    final list = [..._packages];
    list.sort((a, b) => rank(a.packageType).compareTo(rank(b.packageType)));
    return list;
  }

  Widget _planTile(ThemeData theme, Package package) {
    final selected = identical(package, _selected) ||
        package.identifier == _selected?.identifier;
    final product = package.storeProduct;
    final popular =
        package.packageType == PackageType.annual && _packages.length > 1;
    final savings = _badgeFor(package);
    final perMonth = _perMonthLabel(package);
    final trial = _freeTrialLabel(product);
    final offer = _introOffer(package);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _selected = package),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (popular
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : theme.dividerColor),
            width: selected ? 2 : 1.2,
          ),
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : theme.cardColor,
          boxShadow:
              selected ? AppColors.softShadow(opacity: 0.10, blur: 20) : null,
        ),
        child: Column(
          children: [
            if (popular)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                  ),
                ),
                child: Text('⭐  MOST POPULAR  ·  BEST VALUE',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? AppColors.primary : theme.hintColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(_periodLabel(package.packageType),
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800)),
                            ),
                            if (trial != null) ...[
                              const SizedBox(width: 8),
                              _pill('FREE TRIAL', AppColors.success, theme),
                            ] else if (offer != null) ...[
                              const SizedBox(width: 8),
                              _pill('SAVE ${offer.percentOff}%',
                                  AppColors.danger, theme),
                            ] else if (savings != null) ...[
                              const SizedBox(width: 8),
                              _pill(savings, AppColors.success, theme),
                            ],
                          ],
                        ),
                        if (_planSubtitle(package, trial, perMonth) !=
                            null) ...[
                          const SizedBox(height: 3),
                          Text(_planSubtitle(package, trial, perMonth)!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Localized, store-provided price — never hardcoded.
                      // When a discounted intro offer exists, show the offer
                      // price prominently with the normal price struck out.
                      if (offer != null)
                        Text(product.priceString,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.hintColor,
                                decoration: TextDecoration.lineThrough)),
                      Text(offer?.priceString ?? product.priceString,
                          style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                              color: offer != null ? AppColors.primary : null)),
                      Text(_perPeriodWord(package.packageType),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color, ThemeData theme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(text,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
      );

  /// Subtitle that anchors value: trial terms, per-month equivalent for annual,
  /// or a plain billing cadence.
  String? _planSubtitle(Package package, String? trial, String? perMonth) {
    final product = package.storeProduct;
    if (trial != null) {
      return '$trial, then ${product.priceString} ${_perPeriodWord(package.packageType)}';
    }
    final offer = _introOffer(package);
    if (offer != null) {
      return '${offer.priceString} now, then ${product.priceString} ${_perPeriodWord(package.packageType)}';
    }
    if (perMonth != null) {
      return 'Just $perMonth · billed yearly';
    }
    if (package.packageType == PackageType.lifetime) {
      return 'One-time payment — yours forever';
    }
    if (product.description.isNotEmpty) return product.description;
    return null;
  }

  // --- Reassurance ----------------------------------------------------------

  Widget _reassurance(ThemeData theme) {
    Widget item(IconData icon, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.success, size: 16),
            const SizedBox(width: 5),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        item(Icons.verified_rounded, 'Cancel anytime'),
        if (_selectedHasTrial) ...[
          const SizedBox(width: 16),
          item(Icons.lock_open_rounded, 'No payment due today'),
        ],
      ],
    );
  }

  // --- Everything included (full feature list, collapsed) — kept at the end -

  Widget _everythingIncluded(ThemeData theme) => Material(
        // Material (not a coloured Container) so the tile's ink renders.
        color: theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            leading:
                const Icon(Icons.checklist_rounded, color: AppColors.primary),
            title: Text('Everything included in Pro',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            children: [
              for (final f in ProFeatures.all)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.title,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            Text(f.subtitle,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.hintColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  // --- Bottom bar: CTA + legal ----------------------------------------------

  Widget _bottomBar(ThemeData theme) {
    final canBuy = !_loading && ProConstants.enabled && _packages.isNotEmpty;
    final sub = _ctaSubcaption();
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canBuy && sub != null) ...[
                Text(sub,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600, color: theme.hintColor)),
                const SizedBox(height: 10),
              ],
              if (canBuy)
                _GradientButton(
                  enabled: _canBuy,
                  busy: _busy,
                  label: _ctaLabel(),
                  onTap: _buy,
                ),
              const SizedBox(height: 8),
              _legalFooter(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legalFooter(ThemeData theme) {
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.hintColor, fontSize: 11, height: 1.3);
    final link =
        style?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('By continuing you agree to our ', style: style),
        GestureDetector(
          onTap: () => _openUrl(AppConstants.termsUrl),
          child: Text('Terms of Service', style: link),
        ),
        Text(' and ', style: style),
        GestureDetector(
          onTap: () => _openUrl(AppConstants.privacyPolicyUrl),
          child: Text('Privacy Policy', style: link),
        ),
      ],
    );
  }

  // --- CTA copy -------------------------------------------------------------

  String _ctaLabel() {
    final p = _selected;
    if (p == null) return 'Continue';
    if (_selectedHasTrial) return 'Start my free trial';
    if (p.packageType == PackageType.lifetime) return 'Unlock Pro forever';
    return 'Unlock ClassTrack Pro';
  }

  String? _ctaSubcaption() {
    final p = _selected;
    if (p == null || !ProConstants.enabled) return null;
    final product = p.storeProduct;
    final trial = _freeTrialLabel(product);
    if (trial != null) {
      return '$trial, then ${product.priceString} ${_perPeriodWord(p.packageType)} · cancel anytime';
    }
    final offer = _introOffer(p);
    if (offer != null) {
      final period = _perPeriodWord(p.packageType).replaceFirst('per ', '');
      return 'Save ${offer.percentOff}% — ${offer.priceString} for your first '
          '$period, then ${product.priceString} ${_perPeriodWord(p.packageType)} · cancel anytime';
    }
    if (p.packageType == PackageType.lifetime) {
      return '${product.priceString} once. No subscription, yours forever.';
    }
    return '${product.priceString} ${_perPeriodWord(p.packageType)} · cancel anytime';
  }

  // --- Pricing helpers ------------------------------------------------------

  /// Detects a paid, discounted introductory offer on [package] (e.g. "60% off
  /// your first year") so it can be shown on the paywall instead of only on the
  /// store's purchase sheet. Returns null when there's no such offer, or when
  /// the intro is actually a free trial (that's handled by [_freeTrialLabel]).
  _IntroOffer? _introOffer(Package package) {
    final product = package.storeProduct;

    // Google Play: the offer lives on the default subscription option as a paid
    // "intro phase" (a free trial would be a freePhase, which we ignore here).
    final option = product.defaultOption;
    if (option != null) {
      final intro = option.introPhase;
      if (intro != null && intro.price.amountMicros > 0) {
        final introUnits = intro.price.amountMicros / 1e6;
        final fullMicros = option.fullPricePhase?.price.amountMicros;
        final fullUnits = (fullMicros != null && fullMicros > 0)
            ? fullMicros / 1e6
            : product.price;
        final pct = PaywallPricing.percentOff(fullUnits, introUnits);
        if (pct != null) {
          return _IntroOffer(
              percentOff: pct, priceString: intro.price.formatted);
        }
      }
    }

    // iOS / cross-platform fallback: a non-zero introductory price.
    final intro = product.introductoryPrice;
    if (intro != null && intro.price > 0) {
      final pct = PaywallPricing.percentOff(product.price, intro.price);
      if (pct != null) {
        return _IntroOffer(percentOff: pct, priceString: intro.priceString);
      }
    }
    return null;
  }

  /// A short marketing badge: savings % on the annual plan (vs 12× monthly),
  /// or "BEST VALUE"/"BEST DEAL" when a percentage can't be computed.
  String? _badgeFor(Package package) {
    if (package.packageType == PackageType.lifetime) return 'BEST DEAL';
    if (package.packageType != PackageType.annual) return null;
    Package? monthly;
    for (final p in _packages) {
      if (p.packageType == PackageType.monthly) {
        monthly = p;
        break;
      }
    }
    if (monthly == null) return 'BEST VALUE';
    final yearIfMonthly = monthly.storeProduct.price * 12;
    if (yearIfMonthly <= 0) return 'BEST VALUE';
    final pct = (1 - package.storeProduct.price / yearIfMonthly) * 100;
    return pct >= 1 ? 'SAVE ${pct.round()}%' : 'BEST VALUE';
  }

  /// Per-month equivalent for an annual plan (localized). Null otherwise.
  String? _perMonthLabel(Package package) {
    final product = package.storeProduct;
    if (package.packageType != PackageType.annual || product.price <= 0) {
      return null;
    }
    try {
      final formatter = NumberFormat.simpleCurrency(name: product.currencyCode);
      return '${formatter.format(product.price / 12)}/mo';
    } catch (_) {
      return null;
    }
  }

  /// A human-readable free-trial label (e.g. "7-day free trial") when the
  /// selected product has a zero-cost introductory offer.
  String? _freeTrialLabel(StoreProduct product) {
    final intro = product.introductoryPrice;
    if (intro == null || intro.price > 0) return null;
    final n = intro.periodNumberOfUnits <= 0 ? 1 : intro.periodNumberOfUnits;
    final unit = switch (intro.periodUnit) {
      PeriodUnit.day => 'day',
      PeriodUnit.week => 'week',
      PeriodUnit.month => 'month',
      PeriodUnit.year => 'year',
      PeriodUnit.unknown => 'day',
    };
    return '$n-$unit free trial';
  }

  String _perPeriodWord(PackageType type) => switch (type) {
        PackageType.annual => 'per year',
        PackageType.sixMonth => 'per 6 months',
        PackageType.threeMonth => 'per 3 months',
        PackageType.twoMonth => 'per 2 months',
        PackageType.monthly => 'per month',
        PackageType.weekly => 'per week',
        PackageType.lifetime => 'one-time',
        _ => '',
      };

  String _periodLabel(PackageType type) => switch (type) {
        PackageType.annual => 'Yearly',
        PackageType.sixMonth => '6 months',
        PackageType.threeMonth => '3 months',
        PackageType.twoMonth => '2 months',
        PackageType.monthly => 'Monthly',
        PackageType.weekly => 'Weekly',
        PackageType.lifetime => 'Lifetime',
        _ => 'Plan',
      };

  Widget _notice(ThemeData theme, String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text, style: theme.textTheme.bodySmall),
      );

  Widget _errorBanner(ThemeData theme, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.danger, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.danger)),
            ),
          ],
        ),
      );
}

/// The primary purchase button: a bold gradient CTA pill with a busy state.
class _GradientButton extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final String label;
  final VoidCallback onTap;
  const _GradientButton({
    required this.enabled,
    required this.busy,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !busy;
    final button = Opacity(
      opacity: active ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: active ? onTap : null,
          child: Ink(
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.40),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.6, color: Colors.white),
                    )
                  : Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
    );
    // A slow, periodic shimmer sweep on the live CTA keeps the eye drawn to the
    // primary action without being distracting (only when it's actionable).
    // SweepShimmer applies its mask only during each sweep, not every frame.
    if (!active) return button;
    return SweepShimmer(
      delay: const Duration(milliseconds: 1600),
      every: const Duration(seconds: 5),
      duration: const Duration(milliseconds: 1400),
      color: Colors.white.withValues(alpha: 0.35),
      child: button,
    );
  }
}
