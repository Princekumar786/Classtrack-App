import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// The ClassTrack AI assistant mascot — a friendly purple chat-bubble bot.
///
/// Renders `assets/mascot/ai_mascot.png` with a gentle, always-on idle
/// animation: a soft up-and-down float combined with a slow "breathing" scale.
/// Set [animate] to `false` for a completely static image (useful for the tiny
/// per-message avatars, where constant motion on every bubble is distracting).
class AiMascot extends StatelessWidget {
  const AiMascot({
    super.key,
    this.size = 96,
    this.animate = true,
    this.blink = false,
    this.tint,
  });

  /// Rendered width/height in logical pixels (the artwork is square).
  final double size;

  /// Whether to run the looping idle float/breathe animation.
  final bool animate;

  /// Whether to add a periodic "blink" — a quick opacity dip and recovery on a
  /// long interval. The artwork is a single still image (no eye frames), so
  /// this fakes a lifelike blink to draw a little attention. Can be combined
  /// with [animate] (float + blink run on independent cadences).
  final bool blink;

  /// When set, the mascot is drawn as a solid silhouette in this colour
  /// (via [BlendMode.srcIn]) instead of its full-colour artwork. Used where the
  /// full art washes out — e.g. on the light lavender header, where a solid
  /// brand-purple bot stays legible with no backing circle.
  final Color? tint;

  static const _asset = 'assets/mascot/ai_mascot.png';

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      _asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // The source art is ~1250px; decode at display size (a 46dp avatar was
      // decoding a ~6 MB bitmap — costly on first frame and in memory).
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      filterQuality: FilterQuality.medium,
      color: tint,
      colorBlendMode: tint != null ? BlendMode.srcIn : BlendMode.srcOver,
    );

    // Isolate the artwork so the float/blink below only re-composite a cached
    // layer each frame instead of repainting the image.
    Widget content = RepaintBoundary(
      child: SizedBox(width: size, height: size, child: image),
    );

    if (animate) {
      content = content
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .moveY(
            begin: -size * 0.045,
            end: size * 0.045,
            duration: 2200.ms,
            curve: Curves.easeInOut,
          )
          .scaleXY(
            begin: 0.98,
            end: 1.02,
            duration: 2200.ms,
            curve: Curves.easeInOut,
          );
    }

    if (blink) {
      // Hold fully visible, then a quick close/open opacity dip — a subtle
      // blink roughly every ~2.8s. Runs on its own controller so it stays
      // independent of the float above.
      content = content
          .animate(onPlay: (c) => c.repeat())
          .fade(begin: 1, end: 1, duration: 2600.ms)
          .then()
          .fade(begin: 1, end: 0.2, duration: 90.ms, curve: Curves.easeOut)
          .then()
          .fade(begin: 0.2, end: 1, duration: 110.ms, curve: Curves.easeIn);
    }

    return content;
  }
}
