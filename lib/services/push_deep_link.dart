/// Deep-link payloads carried by CMS push notifications (FCM `data.payload`)
/// and by CMS banner "destination" strings. One shared vocabulary powers both
/// so marketing can send a user to the same places from a push or a banner.
///
/// Supported forms (case-insensitive prefix, whitespace trimmed):
///  • `app://paywall` / `paywall` / `pro` / `pricing` / `upgrade` / `premium`
///                        → open the in-app Pro paywall (pricing page).
///  • `resource:<id>`     → open that opportunity / discount detail page.
///    Aliases: `opportunity:<id>`, `discount:<id>`, `perk:<id>`.
///  • `tab:<name>`        → switch HomeShell to a tab:
///    `home`, `schedule`, `explore` (alias `opportunities`), `planner`.
///  • `http://…` / `https://…` (or `url:<link>`)
///                        → open that web link in the browser.
///
/// Pure and dependency-free so it can be unit tested and shared by the CMS
/// composer (which builds payloads), HomeShell (which consumes push taps) and
/// the banner tap handler (which consumes banner destinations).
sealed class PushDeepLink {
  const PushDeepLink();

  /// Prefix the CMS writes for a resource link.
  static const String resourcePrefix = 'resource:';

  /// Canonical destination string for the in-app Pro paywall. Marketing types
  /// this into a banner's "Destination" field or a push `payload` to send the
  /// user to the pricing page.
  static const String paywall = 'app://paywall';

  /// Builds the canonical payload for a resource id.
  static String forResource(String id) => '$resourcePrefix${id.trim()}';

  static const _resourceAliases = {
    'resource',
    'opportunity',
    'discount',
    'perk',
  };

  /// Bare tokens (or `scheme:` prefixes) that mean "open the Pro paywall".
  static const _paywallAliases = {
    'paywall',
    'pro',
    'pricing',
    'upgrade',
    'premium',
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
    var p = payload.trim();
    if (p.isEmpty) return null;

    // Normalise an `app://` custom-scheme deep link to its bare token so
    // `app://paywall` and `paywall` behave identically.
    if (p.toLowerCase().startsWith('app://')) {
      p = p.substring('app://'.length).trim();
      if (p.isEmpty) return null;
    }

    final lower = p.toLowerCase();

    // Pricing / paywall as a bare token (no colon), e.g. `paywall` or `pro`.
    if (_paywallAliases.contains(lower.replaceAll('/', ''))) {
      return const PaywallDeepLink();
    }

    // External web links open in the browser.
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return UrlDeepLink(p);
    }

    final i = p.indexOf(':');
    if (i <= 0) return null;
    final scheme = p.substring(0, i).trim().toLowerCase();
    final value = p.substring(i + 1).trim();
    if (value.isEmpty) return null;

    if (_paywallAliases.contains(scheme)) return const PaywallDeepLink();

    if (_resourceAliases.contains(scheme)) {
      // Firestore doc ids can't contain '/'; reject anything path-like.
      if (value.contains('/')) return null;
      return ResourceDeepLink(value);
    }
    if (scheme == 'tab') {
      final idx = tabIndex[value.toLowerCase()];
      return idx == null ? null : TabDeepLink(idx);
    }
    if (scheme == 'url') {
      final v = value.toLowerCase();
      if (v.startsWith('http://') || v.startsWith('https://')) {
        return UrlDeepLink(value);
      }
      return null;
    }
    return null;
  }
}

/// Open the in-app Pro paywall (pricing page).
class PaywallDeepLink extends PushDeepLink {
  const PaywallDeepLink();

  @override
  bool operator ==(Object other) => other is PaywallDeepLink;
  @override
  int get hashCode => (PaywallDeepLink).hashCode;
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

/// Open an external web link in the browser.
class UrlDeepLink extends PushDeepLink {
  final String url;
  const UrlDeepLink(this.url);

  @override
  bool operator ==(Object other) => other is UrlDeepLink && other.url == url;
  @override
  int get hashCode => url.hashCode;
}
