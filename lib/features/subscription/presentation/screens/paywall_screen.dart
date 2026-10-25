import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../../core/utils/url_launcher_util.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/analytics_service.dart';
import '../../data/subscription_service.dart';
import '../../domain/paywall_pricing.dart';
import '../../domain/pro_constants.dart';
import '../../domain/pro_features.dart';
import '../../domain/upgrade_reason.dart';
import '../providers/subscription_providers.dart';

export '../../domain/upgrade_reason.dart' show UpgradeReason;

/// Opens the ClassTrack Pro pricing page. Returns true if the user became Pro.
///
/// [reason] tailors the headline and highlights the matching "WHY PRO?" row,
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

/// Pricing-page palette. The page follows the app theme: a light lavender
/// version in light mode and the original dark "store sheet" in dark mode.
class _Palette {
  const _Palette({
    required this.bg,
    required this.card,
    required this.cardBorder,
    required this.lip,
    required this.purple,
    required this.proBand,
    required this.muted,
    required this.cross,
    required this.sparkle,
    required this.text,
    required this.textSoft,
    required this.brand,
    required this.tagline,
    required this.pillBg,
    required this.pillFg,
    required this.onPurple,
    required this.ctaBg,
    required this.ctaFg,
    required this.ctaLip,
    required this.errorIcon,
    required this.errorText,
    required this.glow,
  });

  final Color bg, card, cardBorder, lip, purple, proBand, muted, cross, sparkle;
  final Color text, textSoft, brand, tagline, pillBg, pillFg, onPurple;
  final Color ctaBg, ctaFg, ctaLip, errorIcon, errorText;

  /// Strength of the purple glow behind the WHY PRO? card.
  final double glow;

  static const dark = _Palette(
    bg: Color(0xFF111113),
    card: Color(0xFF1B1B1F),
    cardBorder: Color(0xFF3A3A42),
    lip: Color(0xFF4A4A52),
    purple: Color(0xFFA78BFA),
    proBand: Color(0xFF242230),
    muted: Color(0xFF9A9AA3),
    cross: Color(0xFF6E6E78),
    sparkle: Color(0xFF84CC16),
    text: Colors.white,
    textSoft: Colors.white70,
    brand: Color(0xFF8E8E96),
    tagline: Color(0xFFB4B4BC),
    pillBg: Colors.white,
    pillFg: Color(0xFF1E1B4B),
    onPurple: Color(0xFF1E1B4B),
    ctaBg: Colors.white,
    ctaFg: Color(0xFF111113),
    ctaLip: Color(0xFFA78BFA),
    errorIcon: Color(0xFFF87171),
    errorText: Color(0xFFFCA5A5),
    glow: 1,
  );

  static const light = _Palette(
    bg: Color(0xFFF6F4FE),
    card: Colors.white,
    cardBorder: Color(0xFFE2DEF5),
    lip: Color(0xFFD9D4F0),
    purple: AppColors.primary,
    proBand: Color(0xFFEFEBFD),
    muted: AppColors.lightTextSecondary,
    cross: Color(0xFFA3A2B5),
    sparkle: Color(0xFF65A30D),
    text: AppColors.ink,
    textSoft: AppColors.lightTextSecondary,
    brand: Color(0xFFC9C4E6),
    tagline: AppColors.lightTextSecondary,
    pillBg: AppColors.primary,
    pillFg: Colors.white,
    onPurple: Colors.white,
    ctaBg: AppColors.primary,
    ctaFg: Colors.white,
    ctaLip: AppColors.primaryDark,
    errorIcon: Color(0xFFDC2626),
    errorText: Color(0xFFB91C1C),
    glow: 0.45,
  );
}

/// A paid, time-limited introductory discount surfaced by the store — e.g.
/// "50% off your first year". Distinct from a free trial (price 0).
class _IntroOffer {
  final int percentOff;
  final String priceString;
  const _IntroOffer({required this.percentOff, required this.priceString});
}

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.reason = UpgradeReason.general});

  /// What brought the student here (tailors headline + table highlight).
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

  /// Colours for the current theme (set at the top of [build]).
  _Palette _p = _Palette.light;

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

  /// Annual is pre-selected: it's the best-value plan, and pre-selecting it
  /// nudges toward the higher-value choice. Falls back to monthly, then the
  /// first package, when no annual plan is configured.
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
      final ok = await ref.read(subscriptionServiceProvider).purchase(selected);
      if (!mounted) return;
      if (ok) {
        ref.read(analyticsProvider).log('paywall_purchased', {
          'reason': widget.reason.id,
          'package': selected.packageType.name,
        });
        // Self-heal the server-trusted flag immediately rather than waiting on
        // the RevenueCat webhook, so gated features unlock right away.
        unawaited(reconcileServerEntitlement(ref.read(firebaseFunctionsProvider)));
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
      unawaited(reconcileServerEntitlement(ref.read(firebaseFunctionsProvider)));
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = result.message;
      });
    }
  }

  Future<void> _openUrl(String url) async {
    await safeLaunchUri(Uri.parse(url));
  }

  bool get _plansReady =>
      !_loading && ProConstants.enabled && _packages.isNotEmpty;

  bool get _canBuy => _selected != null && !_busy && ProConstants.enabled;

  @override
  Widget build(BuildContext context) {
    // Follow the app theme: light page in light mode, dark page in dark mode.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _p = isDark ? _Palette.dark : _Palette.light;
    return Theme(
      data: isDark ? AppTheme.dark() : AppTheme.light(),
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        return Scaffold(
          backgroundColor: _p.bg,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _topBar(),
                        _header(theme),
                        const SizedBox(height: 30),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _planArea(theme),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                            child: _errorBanner(theme, _error!),
                          ),
                        const SizedBox(height: 20),
                        _whyProSection(theme),
                      ],
                    ),
                  ),
                ),
                _bottomBar(theme),
              ],
            ),
          ),
        );
      }),
    );
  }

  // --- Top bar & header ----------------------------------------------------

  Widget _topBar() => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: IconButton(
            tooltip: 'Close',
            icon: Icon(Icons.close_rounded, color: _p.textSoft, size: 28),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ),
      );

  Widget _header(ThemeData theme) {
    final contextual = widget.reason != UpgradeReason.general;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Semantics(
            header: true,
            label: 'ClassTrack Pro',
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Text(
                      'CLASSTRACK',
                      style: TextStyle(
                        color: _p.brand,
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                        height: 1,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _p.pillBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _p.bg, width: 3),
                      ),
                      child: Text(
                        'PRO',
                        style: TextStyle(
                          color: _p.pillFg,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'THE '),
                TextSpan(text: 'BEST', style: TextStyle(color: _p.purple)),
                const TextSpan(text: ' CLASSTRACK EXPERIENCE'),
              ]),
              style: theme.textTheme.titleSmall?.copyWith(
                color: _p.tagline,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (contextual) ...[
            const SizedBox(height: 12),
            Text(
              widget.reason.copy.paywallHeadline,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: _p.text, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  // --- Plans -----------------------------------------------------------------

  Widget _planArea(ThemeData theme) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: _p.purple)),
      );
    }
    if (!ProConstants.enabled) {
      return _notice(theme,
          'Subscriptions aren\'t set up yet. Add your RevenueCat key and store products to enable Pro.');
    }
    if (_packages.isEmpty) {
      return _notice(theme, 'No plans available right now. Please check back shortly.');
    }
    return Column(
      children: [for (final p in _orderedPackages()) _planCard(theme, p)],
    );
  }

  /// Shortest plan first (monthly → quarterly → annual), lifetime last.
  List<Package> _orderedPackages() {
    int rank(PackageType t) => switch (t) {
          PackageType.weekly => 0,
          PackageType.monthly => 1,
          PackageType.twoMonth => 2,
          PackageType.threeMonth => 3,
          PackageType.sixMonth => 4,
          PackageType.annual => 5,
          PackageType.lifetime => 6,
          _ => 1,
        };
    return [..._packages]
      ..sort((a, b) => rank(a.packageType).compareTo(rank(b.packageType)));
  }

  Widget _planCard(ThemeData theme, Package package) {
    final selected = package.identifier == _selected?.identifier;
    final product = package.storeProduct;
    final popular = package.packageType == PackageType.annual && _packages.length > 1;
    final offer = _introOffer(package);
    final compareAt = offer != null ? product.priceString : _compareAtLabel(package);
    final price = offer?.priceString ?? product.priceString;
    final sub = _planSubtitle(package);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      decoration: BoxDecoration(
        color: _p.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: selected ? _p.purple : _p.cardBorder, width: 1.6),
        // The solid "lip" under each card (no blur) from the reference design.
        boxShadow: [
          BoxShadow(color: selected ? _p.purple : _p.lip, offset: const Offset(0, 5)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_planName(package.packageType),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                        color: _p.text, fontWeight: FontWeight.w500)),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub,
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: _p.muted, fontWeight: FontWeight.w400, fontSize: 13)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Prices shrink to fit on narrow phones instead of overflowing.
          Flexible(
            flex: 5,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (compareAt != null) ...[
                    Text(compareAt,
                        // Same font family as the price so ₹ always renders.
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _p.cross,
                          fontWeight: FontWeight.w400,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: _p.cross,
                        )),
                    const SizedBox(width: 10),
                  ],
                  Text(price,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: selected ? _p.purple : _p.text,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: '${_planName(package.packageType)}, $price'
          '${sub != null ? ', $sub' : ''}${popular ? ', most popular' : ''}',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.only(top: popular ? 18 : 0, bottom: 18),
          child: GestureDetector(
            onTap: _busy ? null : () => setState(() => _selected = package),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                card,
                if (popular)
                  Positioned(
                    top: -17,
                    right: 34,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: _p.purple,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      ),
                      child: Text('MOST POPULAR',
                          style: TextStyle(
                              color: _p.onPurple,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "₹1,197" — what the same months cost on the monthly plan, when cheaper.
  String? _compareAtLabel(Package package) {
    final months = _monthsOf(package.packageType);
    Package? monthly;
    for (final p in _packages) {
      if (p.packageType == PackageType.monthly) monthly = p;
    }
    final full = PaywallPricing.compareAtPrice(
      monthlyPrice: monthly?.storeProduct.price,
      months: months,
      planPrice: package.storeProduct.price,
    );
    if (full == null) return null;
    return _money(full, package.storeProduct.currencyCode, decimals: 0);
  }

  /// Small line under a plan name: trial / intro-offer terms (always shown so
  /// billing is never a surprise), per-month for annual, or lifetime note.
  String? _planSubtitle(Package package) {
    final product = package.storeProduct;
    final trial = _freeTrialLabel(product);
    if (trial != null) return '$trial, then ${product.priceString}';
    final offer = _introOffer(package);
    if (offer != null) {
      return 'Save ${offer.percentOff}% on your first ${_periodNoun(package.packageType)}';
    }
    if (package.packageType == PackageType.annual && product.price > 0) {
      final pm = _money(product.price / 12, product.currencyCode, decimals: 0);
      return pm == null ? null : 'Just $pm/month';
    }
    if (package.packageType == PackageType.lifetime) return 'One-time payment';
    return null;
  }

  // --- WHY PRO? --------------------------------------------------------------

  Widget _whyProSection(ThemeData theme) {
    return Container(
      // The purple glow behind the card.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _p.bg,
            _p.purple.withValues(alpha: 0.45 * _p.glow),
            _p.purple.withValues(alpha: 0.30 * _p.glow),
            _p.bg,
          ],
          stops: const [0, 0.12, 0.9, 1],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 24),
      child: Container(
        decoration: BoxDecoration(
          color: _p.card,
          borderRadius: BorderRadius.circular(34),
        ),
        padding: const EdgeInsets.fromLTRB(18, 30, 14, 24),
        child: Column(
          children: [
            Semantics(
              header: true,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Text('WHY PRO?',
                      style: TextStyle(
                        color: _p.purple,
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        letterSpacing: -1,
                      )),
                  Positioned(
                    top: -10,
                    right: 70,
                    child: ExcludeSemantics(
                      child: Icon(Icons.auto_awesome, color: _p.sparkle, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            _comparisonTable(theme),
            const SizedBox(height: 24),
            _LipButton(
              _p,
              label: 'RESTORE PURCHASES',
              onTap: _busy ? null : _restore,
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => _showAllFeatures(theme),
              child: Text('See everything in Pro',
                  style: TextStyle(color: _p.purple, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  static const double _colW = 66;

  Widget _comparisonTable(ThemeData theme) {
    final highlight = widget.reason;
    final label = theme.textTheme.titleMedium?.copyWith(color: _p.text, fontWeight: FontWeight.w500);
    return Stack(
      children: [
        // Shaded "Pro" column behind the rows.
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: _colW,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _p.proBand,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(children: [
                const Spacer(),
                SizedBox(width: _colW, child: Center(child: Text('Free', style: label))),
                SizedBox(
                  width: _colW,
                  child: Center(
                    child: Text('Pro',
                        style: label?.copyWith(color: _p.purple, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
            for (final row in planComparison)
              Semantics(
                label: '${row.feature}: Free ${_spoken(row.free)}, Pro ${_spoken(row.pro)}',
                child: ExcludeSemantics(
                  child: Container(
                    decoration: BoxDecoration(
                      color: row.reason == highlight && highlight != UpgradeReason.general
                          ? _p.purple.withValues(alpha: 0.12)
                          : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Row(children: [
                      const SizedBox(width: 4),
                      Icon(row.icon, color: row.color, size: 24),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(row.feature,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: row.reason == highlight ? _p.purple : _p.text,
                              fontWeight:
                                  row.reason == highlight ? FontWeight.w700 : FontWeight.w500,
                            )),
                      ),
                      SizedBox(width: _colW, child: Center(child: _cell(theme, row.free, pro: false))),
                      SizedBox(width: _colW, child: Center(child: _cell(theme, row.pro, pro: true))),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _spoken(String? v) => v == null
      ? 'not included'
      : v == PlanComparisonRow.included
          ? 'included'
          : v;

  Widget _cell(ThemeData theme, String? v, {required bool pro}) {
    if (v == null) return Icon(Icons.close_rounded, color: _p.cross, size: 26);
    if (v == PlanComparisonRow.included) {
      return Icon(Icons.check_rounded, color: _p.purple, size: 26);
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(v,
          maxLines: 1,
          style: theme.textTheme.bodySmall?.copyWith(
            color: pro ? _p.purple : _p.muted,
            fontWeight: FontWeight.w800,
          )),
    );
  }

  void _showAllFeatures(ThemeData theme) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _p.card,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text('Everything in Pro',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: _p.text, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final f in ProFeatures.all)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(f.icon, color: _p.purple),
                title: Text(f.title,
                    style: TextStyle(color: _p.text, fontWeight: FontWeight.w700)),
                subtitle: Text(f.subtitle, style: TextStyle(color: _p.muted)),
              ),
          ],
        ),
      ),
    );
  }

  // --- Bottom bar: CTA + legal ---------------------------------------------

  Widget _bottomBar(ThemeData theme) {
    return Container(
      color: _p.bg,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_plansReady)
            _CtaButton(
              _p,
              label: _ctaLabel(),
              busy: _busy,
              onTap: _canBuy ? _buy : null,
            ),
          const SizedBox(height: 12),
          _legal(theme),
        ],
      ),
    );
  }

  Widget _legal(ThemeData theme) {
    final ios = theme.platform == TargetPlatform.iOS;
    final account = ios ? 'Apple ID' : 'Google Play account';
    final settings = ios ? 'App Store account settings' : 'Google Play subscription settings';
    final lifetime = _selected?.packageType == PackageType.lifetime;
    // Kept short on purpose. Price, period and any trial terms are already on
    // each plan card; this line covers what Google Play requires on top:
    // who charges, that it renews, and how to cancel. Apple additionally
    // requires the "24 hours before" wording, so iOS keeps it.
    final billing = lifetime
        ? 'One-time payment charged to your $account. No renewals.'
        : ios
            ? 'Charged to your $account. Auto-renews unless cancelled 24 h before '
                'the period ends, in $settings.'
            : 'Charged to your $account. Auto-renews until you cancel in '
                'Play Store › Subscriptions.';
    final style = theme.textTheme.bodySmall?.copyWith(color: _p.muted, fontSize: 11, height: 1.3);
    final link = style?.copyWith(
        color: _p.text, decoration: TextDecoration.underline, decorationColor: _p.text);
    return Column(
      children: [
        Text(billing, textAlign: TextAlign.center, style: style),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            Text('By continuing you agree to our ', style: style),
            GestureDetector(
              onTap: () => _openUrl(AppConstants.termsUrl),
              child: Text('Terms of Use', style: link),
            ),
            Text(' and ', style: style),
            GestureDetector(
              onTap: () => _openUrl(AppConstants.privacyPolicyUrl),
              child: Text('Privacy Policy', style: link),
            ),
            Text('.', style: style),
          ],
        ),
      ],
    );
  }

  String _ctaLabel() {
    final p = _selected;
    if (p == null) return 'CONTINUE';
    if (_freeTrialLabel(p.storeProduct) != null) return 'START FREE TRIAL';
    return 'PURCHASE ${_planName(p.packageType).toUpperCase()}';
  }

  // --- Pricing helpers --------------------------------------------------------

  /// Detects a paid, discounted introductory offer (not a free trial).
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
        final fullUnits =
            (fullMicros != null && fullMicros > 0) ? fullMicros / 1e6 : product.price;
        final pct = PaywallPricing.percentOff(fullUnits, introUnits);
        if (pct != null) {
          return _IntroOffer(percentOff: pct, priceString: intro.price.formatted);
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

  /// "7-day free trial" when the product has a zero-cost introductory offer.
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

  /// Localized money, e.g. "₹1,197". Null if the currency can't be formatted.
  static String? _money(double amount, String currencyCode, {int decimals = 2}) {
    try {
      return NumberFormat.simpleCurrency(name: currencyCode, decimalDigits: decimals)
          .format(amount);
    } catch (_) {
      return null;
    }
  }

  static int? _monthsOf(PackageType t) => switch (t) {
        PackageType.monthly => 1,
        PackageType.twoMonth => 2,
        PackageType.threeMonth => 3,
        PackageType.sixMonth => 6,
        PackageType.annual => 12,
        _ => null,
      };

  static String _planName(PackageType t) => switch (t) {
        PackageType.weekly => 'Pro Weekly',
        PackageType.monthly => 'Pro Monthly',
        PackageType.twoMonth => 'Pro 2 Months',
        PackageType.threeMonth => 'Pro Quarterly',
        PackageType.sixMonth => 'Pro 6 Months',
        PackageType.annual => 'Pro Annual',
        PackageType.lifetime => 'Pro Lifetime',
        _ => 'Pro',
      };

  static String _periodNoun(PackageType t) => switch (t) {
        PackageType.weekly => 'week',
        PackageType.monthly => 'month',
        PackageType.twoMonth => '2 months',
        PackageType.threeMonth => '3 months',
        PackageType.sixMonth => '6 months',
        PackageType.annual => 'year',
        _ => 'period',
      };

  Widget _notice(ThemeData theme, String text) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _p.cardBorder),
        ),
        child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: _p.muted)),
      );

  Widget _errorBanner(ThemeData theme, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, color: _p.errorIcon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall?.copyWith(color: _p.errorText)),
          ),
        ]),
      );
}

/// Solid "PURCHASE PRO …" button with a coloured lip (white in dark mode,
/// purple in light mode).
class _CtaButton extends StatelessWidget {
  final _Palette _p;
  final String label;
  final bool busy;
  final VoidCallback? onTap;
  const _CtaButton(this._p, {required this.label, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled || busy ? 1 : 0.55,
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            child: Container(
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _p.ctaBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _p.ctaLip, width: 1.6),
                boxShadow: [BoxShadow(color: _p.ctaLip, offset: const Offset(0, 6))],
              ),
              child: busy
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.6, color: _p.ctaFg),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label,
                          style: TextStyle(
                            color: _p.ctaFg,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          )),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined pill with a grey lip (e.g. "RESTORE PURCHASES").
class _LipButton extends StatelessWidget {
  final _Palette _p;
  final String label;
  final VoidCallback? onTap;
  const _LipButton(this._p, {required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: _p.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _p.cardBorder, width: 1.4),
              boxShadow: [BoxShadow(color: _p.lip, offset: const Offset(0, 4))],
            ),
            child: Text(label,
                style: TextStyle(
                  color: onTap == null ? _p.muted : _p.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                )),
          ),
        ),
      ),
    );
  }
}
