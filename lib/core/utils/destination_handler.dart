import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/cms/domain/marketing.dart';
import '../../features/subscription/presentation/providers/subscription_providers.dart';
import '../../features/subscription/presentation/screens/paywall_screen.dart'
    show showPaywall;
import '../../features/subscription/presentation/screens/pro_status_screen.dart';
import '../../services/notification_service.dart';
import '../../services/push_deep_link.dart';
import 'url_launcher_util.dart';

/// True when [destination] points at the in-app Pro paywall (`app://paywall`,
/// `pricing`, `pro`, …).
bool isPaywallDestination(String? destination) =>
    PushDeepLink.parse(destination) is PaywallDeepLink;

/// Pure rule for which banners a user sees. When [hideProOnly] is true (the
/// user is Pro, or Pro status is still loading) we drop:
///  • "upgrade" banners (destination = paywall) — always, and
///  • banners the CMS marked "Show to Pro users: off".
/// Free users see everything. Unit tested.
List<CmsBanner> filterBannersForPro(
  List<CmsBanner> banners, {
  required bool hideProOnly,
}) {
  if (!hideProOnly) return banners;
  return banners
      .where((b) => b.showToPro && !isPaywallDestination(b.destination))
      .toList();
}

/// Applies [filterBannersForPro] for the signed-in user. Treats "Pro status
/// still loading" as Pro, so a Pro user never sees a flash of a free-only
/// banner such as "Upgrade Now".
List<CmsBanner> visibleBannersFor(WidgetRef ref, List<CmsBanner> banners) {
  final pro = ref.watch(serverProProvider);
  return filterBannersForPro(
    banners,
    hideProOnly: pro.isLoading || (pro.valueOrNull ?? false),
  );
}

/// Opens the pricing page for free users. Pro users get their subscription
/// page instead, so they're never asked to buy what they already own.
Future<void> openPaywallOrProStatus(BuildContext context, WidgetRef ref) async {
  if (ref.read(isProProvider)) {
    await Navigator.of(context).push(
      MaterialPageRoute(settings: const RouteSettings(name: 'Pro Status'), builder: (_) => const ProStatusScreen()),
    );
    return;
  }
  await showPaywall(context);
}

/// Routes a CMS "destination" string (from a banner tap) to the right place,
/// using the same vocabulary as push notifications ([PushDeepLink]):
///
///  • `app://paywall` / `paywall` / `pro` / `pricing` → in-app Pro paywall
///    (or the Pro status page if the user is already Pro).
///  • `tab:<name>` / `resource:<id>`                  → in-app navigation
///    (handed to HomeShell via [NotificationService.selectedPayload], which
///    already knows how to switch tabs and open resource detail pages).
///  • `http(s)://…` or a bare domain                  → external browser.
///
/// Keeping banners and notifications on one resolver means "send the user
/// anywhere" works the same way wherever the destination is authored.
Future<void> handleDestination(
  BuildContext context,
  WidgetRef ref,
  String? destination,
) async {
  if (destination == null || destination.trim().isEmpty) return;
  final dest = destination.trim();
  final link = PushDeepLink.parse(dest);
  switch (link) {
    case PaywallDeepLink():
      await openPaywallOrProStatus(context, ref);
    case UrlDeepLink(:final url):
      await openUrl(context, url);
    case TabDeepLink():
    case ResourceDeepLink():
      // Reuse HomeShell's notification routing for in-app destinations. The
      // banner always lives inside HomeShell, so its listener picks this up.
      NotificationService.selectedPayload.value = dest;
    case null:
      // Not a recognised token — treat it as a web link (back-compat with the
      // original behaviour, which passed every destination to openUrl).
      await openUrl(context, dest);
  }
}
