import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/metrics_service.dart';

/// Records a feed "impression" for [resourceId] the first time this card is
/// laid out (once per resource per app session — see
/// [MetricsService.recordImpression]). Wrap feed cards with it so sponsors get
/// impressions, reach and feed click-through rate.
///
/// Set [enabled] to false for previews (e.g. CMS "preview as student") so
/// staff browsing doesn't count as student reach.
class ImpressionLogger extends ConsumerStatefulWidget {
  final String resourceId;
  final bool enabled;
  final Widget child;
  const ImpressionLogger({
    super.key,
    required this.resourceId,
    required this.child,
    this.enabled = true,
  });

  @override
  ConsumerState<ImpressionLogger> createState() => _ImpressionLoggerState();
}

class _ImpressionLoggerState extends ConsumerState<ImpressionLogger> {
  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(metricsServiceProvider).recordImpression(widget.resourceId);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
