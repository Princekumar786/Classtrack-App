/// Aggregate user-base counts for notification recipient estimates, read from
/// `audienceCounts/summary`. Pure and unit-testable.
class AudienceCounts {
  final int total;
  final Map<String, int> byCountry;
  const AudienceCounts({this.total = 0, this.byCountry = const {}});

  factory AudienceCounts.fromMap(Map<String, dynamic> m) {
    final country = <String, int>{};
    final raw = m['country'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final n = (v as num?)?.toInt() ?? 0;
        if (n != 0) country[k.toString()] = n;
      });
    }
    return AudienceCounts(
      total: (m['total'] as num?)?.toInt() ?? 0,
      byCountry: country,
    );
  }

  /// Estimated recipients for a broadcast target. [country] null = everyone.
  /// Country estimates count users whose targeting country (profile choice,
  /// else auto-detected from their phone) is that country.
  int estimate({String? country}) {
    if (country == null || country.isEmpty) return total;
    return byCountry[country] ?? 0;
  }
}
