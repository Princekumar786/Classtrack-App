import 'dart:async';

import 'package:flutter/material.dart';

/// A light sweep across [child] that is only *present* while it's sweeping.
///
/// Why not `flutter_animate`'s `.shimmer()`: that keeps a [ShaderMask] (an
/// offscreen render pass) wrapped around the child for the effect's whole
/// lifetime — including idle delays and after it finishes — so a repeating
/// shimmer costs an extra full-layer render every frame, forever. Here the
/// mask exists only during the ~1s sweep; the rest of the time [child] is
/// drawn directly, and its own repaint is isolated by a [RepaintBoundary].
///
/// Plays once after [delay]; when [every] is set, sweeps again on that period.
/// Does nothing when the OS "reduce motion" setting is on.
class SweepShimmer extends StatefulWidget {
  const SweepShimmer({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 900),
    this.every,
    this.duration = const Duration(milliseconds: 1100),
    this.color = const Color(0x66FFFFFF),
  });

  final Widget child;
  final Duration delay;
  final Duration? every;
  final Duration duration;
  final Color color;

  @override
  State<SweepShimmer> createState() => _SweepShimmerState();
}

class _SweepShimmerState extends State<SweepShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)
        ..addStatusListener((s) {
          // Drop the mask the moment the sweep ends.
          if (s == AnimationStatus.completed && mounted) setState(() {});
        });
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || MediaQuery.of(context).disableAnimations) return;
    _started = true;
    _timer = Timer(widget.delay, _sweep);
  }

  void _sweep() {
    if (!mounted) return;
    setState(() {}); // mount the mask
    _c.forward(from: 0);
    final every = widget.every;
    if (every != null) _timer = Timer(every, _sweep);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = RepaintBoundary(child: widget.child);
    if (!_c.isAnimating) return content;
    return AnimatedBuilder(
      animation: _c,
      child: content,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        // Band travels from off-left to off-right.
        final center = -0.4 + t * 1.8;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.transparent, widget.color, Colors.transparent],
            stops: [
              (center - 0.18).clamp(0.0, 1.0),
              center.clamp(0.0, 1.0),
              (center + 0.18).clamp(0.0, 1.0),
            ],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}
