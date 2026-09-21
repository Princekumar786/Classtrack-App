import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/illustrations.dart';
import '../../data/subscription_service.dart';
import '../../domain/pro_constants.dart';
import '../../domain/pro_features.dart';
import '../providers/subscription_providers.dart';

/// Opens the ClassTrack Pro paywall. Returns true if the user became Pro.
Future<bool> showPaywall(BuildContext context) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
        builder: (_) => const PaywallScreen(), fullscreenDialog: true),
  );
  return result ?? false;
}

/// Outcome-led value statements — what Pro actually *does for you*, not a
/// feature dump. Kept short and benefit-first for conversion.
class _Outcome {
  final IconData icon;
  final String title;
  final String text;
  const _Outcome(this.icon, this.title, this.text);
}

const List<_Outcome> _outcomes = [
  _Outcome(
    Icons.explore_rounded,
    'Every opportunity & perk, unlocked',
    'Free members only see the latest few. Go Pro to browse the whole library of scholarships, internships and student discounts — and search it all.',
  ),
  _Outcome(
    Icons.auto_awesome_rounded,
    'An AI study partner, always on',
    'Ask anything, anytime — plan your week, prep for exams, understand a topic. No monthly limit.',
  ),
  _Outcome(
    Icons.document_scanner_rounded,
    'Your timetable, built in seconds',
    'Snap a photo, upload a PDF or paste text and let AI turn it into your schedule — as many as you like.',
  ),
  _Outcome(
    Icons.shield_moon_rounded,
    'Never drop below your target',
    'Know exactly how many classes you can safely skip, and get warned the night before you’d slip.',
  ),
  _Outcome(
    Icons.insights_rounded,
    'See where you’re headed',
    'Attendance forecasts, grade trends and spending projections — your whole semester at a glance.',
  ),
];

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

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

  Package _preferAnnual(List<Package> packages) => packages.firstWhere(
        (p) => p.packageType == PackageType.annual,
        orElse: () => packages.first,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _hero(theme)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _trustStrip(theme)
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 120.ms)
                        .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
                    const SizedBox(height: 24),

                    // Benefit-led outcomes — the reason to upgrade.
                    _sectionTitle(theme, 'Everything you need to stay ahead'),
                    const SizedBox(height: 14),
                    ..._outcomes.asMap().entries.map((e) => _outcomeRow(
                          theme,
                          e.value,
                        ).animate().fadeIn(
                            duration: 320.ms, delay: (90 * e.key).ms)
                        .slideX(begin: 0.08, end: 0, curve: Curves.easeOut)),
                    const SizedBox(height: 26),

                    // Plans.
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
                    else ...[
                      _sectionTitle(theme, 'Choose your plan'),
                      const SizedBox(height: 4),
                      Text('Cancel anytime. Upgrade, downgrade or stop whenever you like.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor)),
                      const SizedBox(height: 14),
                      ..._packages.asMap().entries.map(
                            (e) => _planTile(e.value)
                                .animate()
                                .fadeIn(
                                    duration: 320.ms, delay: (80 * e.key).ms)
                                .slideY(
                                    begin: 0.10,
                                    end: 0,
                                    curve: Curves.easeOut),
                          ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _errorBanner(theme, _error!),
                    ],

                    const SizedBox(height: 22),
                    _everythingIncluded(theme),
                    const SizedBox(height: 18),
                    _guarantee(theme),
                    const SizedBox(height: 16),
                    _legal(theme),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _stickyCta(theme),
    );
  }

  // --- Hero -----------------------------------------------------------------

  Widget _hero(ThemeData theme) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(34),
              bottomRight: Radius.circular(34),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _proBadge(theme),
                  const Spacer(),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                    ),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: const PremiumIllustration(height: 140)
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .scale(
                      begin: const Offset(0.85, 0.85),
                      end: const Offset(1, 1),
                      duration: 500.ms,
                      curve: Curves.easeOutBack,
                    )
                    // Gentle continuous float so the hero feels alive.
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveY(
                      begin: -6,
                      end: 6,
                      duration: 2600.ms,
                      curve: Curves.easeInOut,
                    ),
              ),
              const SizedBox(height: 14),
              Text('Unlock your best\nsemester yet.',
                      style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.12))
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0, curve: Curves.easeOut),
              const SizedBox(height: 10),
              Text(
                'Let AI, smart insights and timely reminders do the heavy '
                'lifting — so you never miss a class, deadline or safe skip.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92), height: 1.4),
              ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
            ],
          ),
        ),
      ],
    );
  }

  Widget _proBadge(ThemeData theme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 15),
            const SizedBox(width: 6),
            Text('CLASSTRACK PRO',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
          ],
        ),
      );

  // --- Trust strip ----------------------------------------------------------

  Widget _trustStrip(ThemeData theme) {
    Widget item(IconData icon, String label) => Expanded(
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(height: 7),
              Text(label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600, height: 1.2)),
            ],
          ),
        );
    return Row(
      children: [
        item(Icons.lock_outline_rounded, 'Secure\ncheckout'),
        const SizedBox(width: 10),
        item(Icons.event_available_rounded, 'Cancel\nanytime'),
        const SizedBox(width: 10),
        item(Icons.flash_on_rounded, 'Instant\nunlock'),
        const SizedBox(width: 10),
        item(Icons.workspace_premium_rounded, 'All future\nupdates'),
      ],
    );
  }

  // --- Outcomes -------------------------------------------------------------

  Widget _sectionTitle(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      );

  Widget _outcomeRow(ThemeData theme, _Outcome o) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.16),
                    AppColors.primaryLight.withValues(alpha: 0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(o.icon, color: AppColors.primary, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700, height: 1.25)),
                  const SizedBox(height: 3),
                  Text(o.text,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );

  // --- Everything included (full feature list, collapsed) ------------------

  Widget _everythingIncluded(ThemeData theme) => Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            leading: const Icon(Icons.checklist_rounded,
                color: AppColors.primary),
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
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700)),
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

  Widget _guarantee(ThemeData theme) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded,
                color: AppColors.success, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No lock-in. Manage or cancel your subscription anytime in your '
                'store account — your data always stays yours.',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
          ],
        ),
      );

  Widget _legal(ThemeData theme) => Column(
        children: [
          Text(
            'Subscriptions renew automatically until cancelled.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => _openUrl(AppConstants.termsUrl),
                child: const Text('Terms'),
              ),
              Text('•',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor)),
              TextButton(
                onPressed: () => _openUrl(AppConstants.privacyPolicyUrl),
                child: const Text('Privacy Policy'),
              ),
            ],
          ),
        ],
      );

  // --- Sticky CTA bar -------------------------------------------------------

  Widget _stickyCta(ThemeData theme) {
    // Nothing actionable to show until plans have loaded.
    if (_loading || !ProConstants.enabled || _packages.isEmpty) {
      return const SizedBox.shrink();
    }
    final sub = _ctaSubcaption();
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, -6),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GradientButton(
                enabled: _canBuy,
                busy: _busy,
                label: _ctaLabel(),
                onTap: _buy,
              ),
              if (sub != null) ...[
                const SizedBox(height: 8),
                Text(sub,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600, color: theme.hintColor)),
              ],
              TextButton(
                onPressed: _busy ? null : _restore,
                child: const Text('Restore purchases'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Plans ----------------------------------------------------------------

  Widget _planTile(Package package) {
    final theme = Theme.of(context);
    final selected = identical(package, _selected) ||
        package.identifier == _selected?.identifier;
    final product = package.storeProduct;
    final popular =
        package.packageType == PackageType.annual && _packages.length > 1;
    final savings = _badgeFor(package);
    final perMonth = _perMonthLabel(package);
    final trial = _freeTrialLabel(product);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
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
            boxShadow: selected
                ? AppColors.softShadow(opacity: 0.10, blur: 20)
                : null,
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
                                        ?.copyWith(
                                            fontWeight: FontWeight.w800)),
                              ),
                              if (trial != null) ...[
                                const SizedBox(width: 8),
                                _pill('FREE TRIAL', AppColors.success, theme),
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
                        Text(product.priceString,
                            style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800, height: 1.05)),
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
    if (perMonth != null) {
      return 'Just $perMonth · billed yearly';
    }
    if (package.packageType == PackageType.lifetime) {
      return 'One-time payment — yours forever';
    }
    if (product.description.isNotEmpty) return product.description;
    return null;
  }

  // --- CTA copy -------------------------------------------------------------

  String _ctaLabel() {
    final p = _selected;
    if (p == null) return 'Continue';
    if (_freeTrialLabel(p.storeProduct) != null) return 'Start my free trial';
    if (p.packageType == PackageType.lifetime) return 'Unlock Pro forever';
    return 'Unlock ClassTrack Pro';
  }

  String? _ctaSubcaption() {
    final p = _selected;
    if (p == null || !ProConstants.enabled) return null;
    final product = p.storeProduct;
    final trial = _freeTrialLabel(product);
    if (trial != null) {
      return 'Free for your $trial, then ${product.priceString} ${_perPeriodWord(p.packageType)}. Cancel anytime.';
    }
    if (p.packageType == PackageType.lifetime) {
      return '${product.priceString} once. No subscription, yours forever.';
    }
    return '${product.priceString} ${_perPeriodWord(p.packageType)} · cancel anytime.';
  }

  // --- Pricing helpers ------------------------------------------------------

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

/// The primary purchase button: a bold gradient CTA with a busy state.
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
          borderRadius: BorderRadius.circular(16),
          onTap: active ? onTap : null,
          child: Ink(
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
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
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 20),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
    // A slow, periodic shimmer sweep on the live CTA keeps the eye drawn to the
    // primary action without being distracting (only when it's actionable).
    if (!active) return button;
    return button
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          delay: 1600.ms,
          duration: 1500.ms,
          color: Colors.white.withValues(alpha: 0.35),
        );
  }
}
