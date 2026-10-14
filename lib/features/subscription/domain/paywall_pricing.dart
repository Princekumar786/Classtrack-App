/// Small, dependency-free pricing math for the paywall so the discount logic
/// can be unit-tested without constructing store SDK objects.
class PaywallPricing {
  PaywallPricing._();

  /// Whole-number percent saved when going from [original] to [discounted]
  /// (e.g. original 1000, discounted 500 → 50).
  ///
  /// Returns null when the inputs don't describe a real saving — invalid
  /// numbers, a non-discount (discounted >= original), or a rounded saving
  /// below 1% — so callers can treat "no meaningful discount" uniformly.
  static int? percentOff(double original, double discounted) {
    if (!original.isFinite || !discounted.isFinite) return null;
    if (original <= 0 || discounted < 0) return null;
    if (discounted >= original) return null;
    final pct = ((1 - discounted / original) * 100).round();
    return pct >= 1 ? pct : null;
  }

  /// The "compare at" price for a multi-month plan: what the same time would
  /// cost on the monthly plan ([monthlyPrice] × [months]). Shown struck out
  /// next to the real [planPrice] (e.g. ₹399 × 3 = ₹1,197 → ₹999).
  ///
  /// Null when it isn't a real saving — no monthly price, a 1-month (or
  /// unknown) plan, bad numbers, or a saving below 1%.
  static double? compareAtPrice({
    required double? monthlyPrice,
    required int? months,
    required double planPrice,
  }) {
    if (monthlyPrice == null || months == null || months < 2) return null;
    final full = monthlyPrice * months;
    return percentOff(full, planPrice) == null ? null : full;
  }
}
