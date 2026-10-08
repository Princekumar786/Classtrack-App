/// Deep-link payloads carried by CMS push notifications (FCM `data.payload`).
///
/// Supported forms (case-insensitive prefix, whitespace trimmed):
///  • `resource:<id>`     → open that opportunity / discount detail page.
///    Aliases: `opportunity:<id>`, `discount:<id>`, `perk:<id>`.
///  • `tab:<name>`        → switch HomeShell to a tab:
///    `home`, `schedule`, `explore` (alias `opportunities`), `planner`.
///
/// Pure and dependency-free so it can be unit tested and shared by the CMS
/// composer (which builds payloads) and HomeShell (which consumes them).
sealed class PushDeepLink {
  const PushDeepLink();

  /// Prefix the CMS writes for a resource link.
  static const String resourcePrefix = 'resource:';

  /// Builds the canonical payload for a resource id.
  static String forResource(String id) => '$resourcePrefix${id.trim()}';

  static const _resourceAliases = {
    'resource',
    'opportunity',
    'discount',
    'perk',
  };

  /// HomeShell tab indices (must match `_HomeShellState._screens`).
  static const Map<String, int> tabIndex = {
    'home': 0,
    'schedule': 1,
    'explore': 2,
    'opportunities': 2,
    'planner': 3,
  };

  /// Parses [payload], or returns null if it isn't a push deep link (e.g. a
  /// local-reminder payload like `daily_agenda`).
  static PushDeepLink? parse(String? payload) {
    if (payload == null) return null;
    final p = payload.trim();
    final i = p.indexOf(':');
    if (i <= 0) return null;
    final scheme = p.substring(0, i).trim().toLowerCase();
    final value = p.substring(i + 1).trim();
    if (value.isEmpty) return null;

    if (_resourceAliases.contains(scheme)) {
      // Firestore doc ids can't contain '/'; reject anything path-like.
      if (value.contains('/')) return null;
      return ResourceDeepLink(value);
    }
    if (scheme == 'tab') {
      final idx = tabIndex[value.toLowerCase()];
      return idx == null ? null : TabDeepLink(idx);
    }
    return null;
  }
}

/// Open a specific resource's detail page.
class ResourceDeepLink extends PushDeepLink {
  final String resourceId;
  const ResourceDeepLink(this.resourceId);

  @override
  bool operator ==(Object other) =>
      other is ResourceDeepLink && other.resourceId == resourceId;
  @override
  int get hashCode => resourceId.hashCode;
}

/// Switch HomeShell to a tab.
class TabDeepLink extends PushDeepLink {
  final int index;
  const TabDeepLink(this.index);

  @override
  bool operator ==(Object other) => other is TabDeepLink && other.index == index;
  @override
  int get hashCode => index.hashCode;
}
