import '../../opportunities/domain/resource.dart';
import '../../opportunities/domain/resource_status.dart';
import '../../opportunities/domain/resource_type.dart';

/// Aggregate content metrics for the CMS dashboard.
///
/// Computed purely from a snapshot of [Resource]s so it can be unit-tested and
/// reused anywhere (no Flutter/Firestore dependency).
class CmsContentMetrics {
  /// Total resources of any status (incl. drafts/archived).
  final int total;

  /// Effective status buckets (date-driven lifecycle applied).
  final int active;
  final int openingSoon;
  final int closedOrExpired;

  /// Stored-status buckets (admin-driven).
  final int drafts;
  final int archived;

  /// Active resources whose deadline falls within [expiringWindowDays].
  final int expiringSoon;

  final int sponsored;

  /// Count per [ResourceType], highest first when iterated via [topTypes].
  final Map<ResourceType, int> byType;

  const CmsContentMetrics({
    required this.total,
    required this.active,
    required this.openingSoon,
    required this.closedOrExpired,
    required this.drafts,
    required this.archived,
    required this.expiringSoon,
    required this.sponsored,
    required this.byType,
  });

  /// Visible in the student feed right now (active or opening soon).
  int get published => active + openingSoon;

  /// Types sorted by count descending (ties broken by enum order).
  List<MapEntry<ResourceType, int>> get topTypes {
    final entries = byType.entries.toList()
      ..sort(
        (a, b) => b.value != a.value
            ? b.value.compareTo(a.value)
            : a.key.index.compareTo(b.key.index),
      );
    return entries;
  }
}

/// Computes [CmsContentMetrics] from [resources]. [now] is injectable so the
/// date-driven lifecycle (and "expiring soon") is deterministic in tests.
CmsContentMetrics computeContentMetrics(
  List<Resource> resources, {
  DateTime? now,
  int expiringWindowDays = 7,
}) {
  final t = now ?? DateTime.now();
  var active = 0,
      openingSoon = 0,
      closedOrExpired = 0,
      drafts = 0,
      archived = 0,
      expiringSoon = 0,
      sponsored = 0;
  final byType = <ResourceType, int>{};

  for (final r in resources) {
    final eff = resolveResourceStatus(
      stored: r.status,
      startDate: r.startDate,
      deadline: r.deadline,
      now: t,
    );
    switch (eff) {
      case ResourceStatus.active:
        active++;
        break;
      case ResourceStatus.openingSoon:
        openingSoon++;
        break;
      case ResourceStatus.applicationsClosed:
      case ResourceStatus.expired:
        closedOrExpired++;
        break;
      default:
        break;
    }

    if (r.status == ResourceStatus.draft) drafts++;
    if (r.status == ResourceStatus.archived) archived++;
    if (r.sponsored) sponsored++;
    byType[r.type] = (byType[r.type] ?? 0) + 1;

    final dl = r.deadline;
    if (eff == ResourceStatus.active && dl != null) {
      final diff = dl.difference(t);
      if (!diff.isNegative && diff.inDays <= expiringWindowDays) {
        expiringSoon++;
      }
    }
  }

  return CmsContentMetrics(
    total: resources.length,
    active: active,
    openingSoon: openingSoon,
    closedOrExpired: closedOrExpired,
    drafts: drafts,
    archived: archived,
    expiringSoon: expiringSoon,
    sponsored: sponsored,
    byType: byType,
  );
}

/// Converts a human title into a URL-safe SEO slug, e.g.
/// `"Google Summer of Code 2026!"` → `"google-summer-of-code-2026"`.
///
/// Lower-cases, keeps only `[a-z0-9]`, collapses any run of other characters
/// into a single hyphen, and trims leading/trailing hyphens.
String slugify(String input) {
  final lower = input.trim().toLowerCase();
  final buf = StringBuffer();
  var pendingDash = false;
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final isAlphaNum =
        (ch.codeUnitAt(0) >= 0x61 && ch.codeUnitAt(0) <= 0x7A) ||
        (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39);
    if (isAlphaNum) {
      if (pendingDash && buf.isNotEmpty) buf.write('-');
      pendingDash = false;
      buf.write(ch);
    } else {
      pendingDash = true;
    }
  }
  return buf.toString();
}

/// Whether [value] is a syntactically valid absolute http(s) URL — used to
/// gate live image previews and to validate link fields as the user types.
bool isValidHttpUrl(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  final uri = Uri.tryParse(v);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
