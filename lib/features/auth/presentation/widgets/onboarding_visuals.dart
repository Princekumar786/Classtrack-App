import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/character_avatar.dart';
import '../../../../shared/widgets/sweep_shimmer.dart';
import '../../domain/onboarding_profile.dart';

/// Visual building blocks for the personalised onboarding.
///
/// Everything here honours the OS "reduce motion" setting via [motionOn]:
/// looping/decorative motion is switched off and entrances become instant, so
/// the flow stays comfortable (and widget tests can `pumpAndSettle`).

bool motionOn(BuildContext context) => !MediaQuery.of(context).disableAnimations;

/// Step-change duration in the onboarding (keep in sync with OnboardingScreen).
const int kOnboardingSwitchMs = 300;

/// Card entrances wait until the page slide is mostly done.
const int _afterSwitchMs = 140;

/// Time-of-day greeting used on the plan preview ("Good evening, Priya").
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 5) return 'Up late';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

extension OnboardingMotion on Widget {
  /// Staggered entrance (fade + rise). No-op under reduce motion.
  ///
  /// The child is cached in a RepaintBoundary so the fade/slide only
  /// re-composites a layer each frame instead of repainting its shadows and
  /// text. Entrances start just after the step transition (+[_afterSwitchMs])
  /// so the page slide and the card entrances don't fight for the same frames.
  Widget enter(BuildContext context, {int delayMs = 0, double dy = 0.12}) {
    if (!motionOn(context)) return this;
    return RepaintBoundary(child: this)
        .animate()
        .fadeIn(delay: (delayMs + _afterSwitchMs).ms, duration: 360.ms, curve: Curves.easeOut)
        .slideY(begin: dy * 0.6, curve: Curves.easeOutCubic, duration: 420.ms);
  }

  /// Soft pop-in for "objects" (cards, stickers). No-op under reduce motion.
  /// A small, non-bouncy scale (0.9 → 1) on a cached layer: the old 0.6 →
  /// overshoot spring re-rasterised blurred shadows every frame and read as
  /// jittery on mid-range phones.
  Widget pop(BuildContext context, {int delayMs = 0}) {
    if (!motionOn(context)) return this;
    return RepaintBoundary(child: this)
        .animate()
        .fadeIn(delay: delayMs.ms, duration: 280.ms, curve: Curves.easeOut)
        .scaleXY(begin: 0.9, delay: delayMs.ms, duration: 420.ms, curve: Curves.easeOutCubic);
  }

  /// Gentle idle bob. No-op under reduce motion. The child is isolated in a
  /// RepaintBoundary so each frame only re-composites a cached layer instead
  /// of repainting the child (shadows, text, images) at its new offset.
  Widget float(BuildContext context, {double dy = 6, int ms = 2800, int delayMs = 0}) {
    if (!motionOn(context)) return this;
    return RepaintBoundary(child: this)
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .moveY(begin: -dy, end: dy, delay: delayMs.ms, duration: ms.ms, curve: Curves.easeInOut);
  }
}

// ─── Mascot ────────────────────────────────────────────────────────────────

/// Expressions cut from `assets/mascot/ai_mascot_poses.png`.
enum MascotPose {
  wave,
  think,
  excited,
  talk,
  celebrate;

  String get asset => 'assets/mascot/mascot_$name.png';
}

/// The mascot, switching expressions with a springy swap and an idle float.
class Mascot extends StatelessWidget {
  const Mascot({super.key, required this.pose, this.size = 96});

  final MascotPose pose;
  final double size;

  @override
  Widget build(BuildContext context) {
    final motion = motionOn(context);
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedSwitcher(
        duration: motion ? const Duration(milliseconds: 380) : Duration.zero,
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, a) => ScaleTransition(
          scale: Tween(begin: 0.7, end: 1.0).animate(a),
          child: FadeTransition(opacity: a, child: child),
        ),
        child: Image.asset(
          pose.asset,
          key: ValueKey(pose),
          width: size,
          height: size,
          // Decode at display size, not the 512px source.
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
      ),
    ).float(context, dy: size * 0.04, ms: 2400);
  }
}

/// Mascot + speech bubble. The bubble carries the mascot's *reaction* to the
/// student's last answer; the screen title still carries the question.
class MascotGuide extends StatelessWidget {
  const MascotGuide({
    super.key,
    required this.pose,
    required this.message,
    this.size = 84,
  });

  final MascotPose pose;
  final String message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Mascot(pose: pose, size: size),
        const SizedBox(width: 4),
        Flexible(
          child: CustomPaint(
            painter: _BubbleTailPainter(bubbleColor),
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppColors.softShadow(opacity: 0.08, blur: 18),
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topLeft,
                child: TypewriterText(
                  message,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  _BubbleTailPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final path = Path()
      ..moveTo(0, y)
      ..lineTo(10, y - 8)
      ..lineTo(10, y + 8)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter old) => old.color != color;
}

/// Types its text out character-by-character (restarts when the text changes).
/// Layout is reserved for the full string so nothing jumps, and screen readers
/// get the full text at once.
class TypewriterText extends StatefulWidget {
  const TypewriterText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restart();
  }

  @override
  void didUpdateWidget(TypewriterText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _restart();
  }

  void _restart() {
    if (!motionOn(context)) {
      _c.value = 1;
      return;
    }
    final ms = (widget.text.characters.length * 22).clamp(250, 1200);
    _c
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters;
    return Semantics(
      label: widget.text,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Stack(
          children: [
            // Invisible full text reserves the final size.
            Text(widget.text,
                style: widget.style?.copyWith(color: Colors.transparent)),
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Text(
                chars.take((chars.length * _c.value).ceil()).toString(),
                style: widget.style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Backdrop ──────────────────────────────────────────────────────────────

/// Soft "aurora" background: an accent wash plus three slowly drifting glow
/// blobs. Radial gradients (no blur filters) keep it cheap on low-end phones.
class OnboardingBackdrop extends StatelessWidget {
  const OnboardingBackdrop({super.key, required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;

    Widget blob(Color c, double size) => AnimatedContainer(
          duration: const Duration(milliseconds: 700),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [c.withValues(alpha: 0.28), c.withValues(alpha: 0)],
            ),
          ),
        );

    // The backdrop is STATIC between steps (it only cross-fades its accent on
    // a step change). Continuously drifting full-screen gradients forced the
    // GPU to repaint ~70% of the screen every frame — the main onboarding lag.
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 700),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color.lerp(bg, accent, 0.10)!, bg],
                        ),
                      ),
                    ),
                  ),
                  Positioned(top: -90, right: -70, child: blob(accent, 300)),
                  Positioned(top: 220, left: -110, child: blob(AppColors.coral, 240)),
                  Positioned(bottom: -100, right: -40, child: blob(AppColors.info, 260)),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

// ─── Welcome hero ──────────────────────────────────────────────────────────

/// The welcome collage: the waving mascot inside pulsing halos, surrounded by
/// floating "your semester" cards (attendance, next class, task, CGPA). Drawn
/// on a fixed 360×340 canvas and scaled to fit, so it composes identically on
/// every screen size.
class WelcomeHero extends StatelessWidget {
  const WelcomeHero({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion = motionOn(context);

    Widget halo(double size, double alpha, int delay) {
      final w = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary.withValues(alpha: alpha),
        ),
      );
      return motion
          ? RepaintBoundary(child: w)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 0.94, end: 1.06, delay: delay.ms, duration: 2600.ms, curve: Curves.easeInOut)
          : w;
    }

    Widget sparkle(double size, Color c, int delay) {
      final w = Icon(Icons.auto_awesome, size: size, color: c);
      return motion
          ? RepaintBoundary(child: w)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fade(begin: 0.25, end: 1, delay: delay.ms, duration: 1400.ms)
              .scaleXY(begin: 0.8, end: 1.1, duration: 1400.ms)
          : w;
    }

    return Semantics(
      image: true,
      label: 'ClassTrack assistant surrounded by study streak, timetable, task and grade cards',
      child: ExcludeSemantics(
        // Isolate the hero's continuous motion from the rest of the page.
        child: RepaintBoundary(
        child: FittedBox(
          child: SizedBox(
            width: 360,
            height: 340,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                halo(250, 0.06, 0),
                halo(190, 0.08, 400),
                const Mascot(pose: MascotPose.wave, size: 170).pop(context),
                Positioned(top: 18, left: 0, child: const _StreakChip().pop(context, delayMs: 250).float(context, dy: 5, ms: 3000)),
                Positioned(top: 4, right: 0, child: const _ClassChip().pop(context, delayMs: 380).float(context, dy: 6, ms: 3400, delayMs: 300)),
                Positioned(bottom: 22, left: 6, child: const _TaskChip().pop(context, delayMs: 510).float(context, dy: 5, ms: 3200, delayMs: 600)),
                Positioned(bottom: 6, right: 4, child: const _GpaChip().pop(context, delayMs: 640).float(context, dy: 6, ms: 2900, delayMs: 200)),
                Positioned(top: 120, right: 30, child: sparkle(18, AppColors.accent, 0)),
                Positioned(top: 96, left: 44, child: sparkle(14, scheme.primary, 600)),
                Positioned(bottom: 108, right: 70, child: sparkle(12, AppColors.coral, 900)),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.08)),
        boxShadow: AppColors.softShadow(opacity: 0.14, blur: 22),
      ),
      child: child,
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _HeroCard(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Color(0xFFFDBA74), Color(0xFFF97316)]),
          ),
          child: const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('5-day streak', style: t.titleMedium?.copyWith(color: const Color(0xFFF97316))),
          Text('2h 10m focused', style: t.bodySmall),
        ]),
      ]),
    );
  }
}

class _ClassChip extends StatelessWidget {
  const _ClassChip();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _HeroCard(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 4, height: 34, decoration: BoxDecoration(color: AppColors.info, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Data Structures', style: t.labelLarge),
          Text('10:00 · Room 204', style: t.bodySmall),
        ]),
      ]),
    );
  }
}

class _TaskChip extends StatelessWidget {
  const _TaskChip();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _HeroCard(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.coral, size: 22),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Lab report', style: t.labelLarge),
          Text('Due tomorrow', style: t.bodySmall?.copyWith(color: AppColors.coral)),
        ]),
      ]),
    );
  }
}

class _GpaChip extends StatelessWidget {
  const _GpaChip();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _HeroCard(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.trending_up_rounded, color: AppColors.accent, size: 18),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('CGPA 8.7', style: t.labelLarge),
          Text('+0.3 this sem', style: t.bodySmall?.copyWith(color: AppColors.success)),
        ]),
      ]),
    );
  }
}

// ─── Student ID card ───────────────────────────────────────────────────────

/// A live "student ID" that fills in as the student answers — name as they
/// type, then their avatar. Gives the questions a tangible, growing outcome.
class StudentIdCard extends StatelessWidget {
  const StudentIdCard({
    super.key,
    required this.name,
    this.avatarCharacter,
    this.rhythm,
  });

  final String name;
  final String? avatarCharacter;

  /// Shown as a small badge on the card once picked (e.g. "Night owl").
  final StudyRhythm? rhythm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final motion = motionOn(context);
    final hasName = name.trim().isNotEmpty;
    final year = DateTime.now().year;

    Widget card = Container(
      height: 172,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primary, AppColors.primaryDark],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Decorative rings.
          Positioned(right: -40, top: -50, child: _ring(170, 0.10)),
          Positioned(right: 40, bottom: -70, child: _ring(140, 0.07)),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.school_rounded, color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('CLASSTRACK · STUDENT',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(color: Colors.white70, letterSpacing: 1.4)),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: motion ? const Duration(milliseconds: 380) : Duration.zero,
                    transitionBuilder: (c, a) => ScaleTransition(
                      scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                      child: c,
                    ),
                    child: rhythm == null
                        ? Text('$year',
                            key: const ValueKey('year'),
                            style: theme.textTheme.labelMedium?.copyWith(color: Colors.white70))
                        : Container(
                            key: ValueKey(rhythm),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(rhythm!.icon, size: 14, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(rhythm!.label,
                                  style: theme.textTheme.labelMedium?.copyWith(color: Colors.white)),
                            ]),
                          ),
                  ),
                ]),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AnimatedSwitcher(
                      duration: motion ? const Duration(milliseconds: 420) : Duration.zero,
                      transitionBuilder: (c, a) => ScaleTransition(
                        scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                        child: c,
                      ),
                      child: avatarCharacter == null
                          ? Container(
                              key: const ValueKey('empty'),
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.18),
                                border: Border.all(color: Colors.white38, width: 1.5),
                              ),
                              alignment: Alignment.center,
                              child: hasName
                                  ? Text(name.trim()[0].toUpperCase(),
                                      style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white))
                                  : const Icon(Icons.person_rounded, color: Colors.white70, size: 32),
                            )
                          : CharacterAvatar(
                              key: ValueKey(avatarCharacter),
                              uid: 'onboarding',
                              character: avatarCharacter,
                              size: 64,
                              backgroundColor: Colors.white.withValues(alpha: 0.22),
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
                              color: hasName ? Colors.white : Colors.white54,
                            ),
                            child: Text(hasName ? name.trim() : 'Your name',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            rhythm == null ? 'Member since $year' : '${rhythm!.label} · Member since $year',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const _Barcode(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (motion) {
      // An occasional glossy sweep sells the "card" material. SweepShimmer
      // only applies its mask during the sweep itself (see its docs). The
      // card content is cached so the sweep doesn't repaint text/avatar.
      card = SweepShimmer(
        delay: const Duration(milliseconds: 1600),
        every: const Duration(seconds: 6),
        duration: const Duration(milliseconds: 1300),
        color: Colors.white.withValues(alpha: 0.35),
        child: card,
      );
    }
    // The blurred shadow sits OUTSIDE the shimmer, so each sweep frame never
    // re-rasterises it (a 28px blur was the card's main jank).
    card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 14)),
        ],
      ),
      child: card,
    );
    return Semantics(
      label: 'Your student card: ${hasName ? name.trim() : 'no name yet'}',
      child: ExcludeSemantics(child: RepaintBoundary(child: card)),
    );
  }

  static Widget _ring(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: alpha), width: 18),
        ),
      );
}

class _Barcode extends StatelessWidget {
  const _Barcode();
  @override
  Widget build(BuildContext context) {
    const widths = [2.0, 1.0, 3.0, 1.0, 2.0, 1.0, 1.0, 3.0, 2.0, 1.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final w in widths)
          Container(width: w, height: 30, margin: const EdgeInsets.only(left: 2), color: Colors.white54),
      ],
    );
  }
}

// ─── Study rhythm ──────────────────────────────────────────────────────────

/// Look & feel for each [StudyRhythm] (kept out of the domain layer).
extension StudyRhythmLook on StudyRhythm {
  IconData get icon => switch (this) {
        StudyRhythm.earlyBird => Icons.wb_twilight_rounded,
        StudyRhythm.daytime => Icons.wb_sunny_rounded,
        StudyRhythm.nightOwl => Icons.bedtime_rounded,
      };

  Color get color => switch (this) {
        StudyRhythm.earlyBird => const Color(0xFFF97316),
        StudyRhythm.daytime => AppColors.info,
        StudyRhythm.nightOwl => const Color(0xFF6366F1),
      };

  List<Color> get sky => switch (this) {
        StudyRhythm.earlyBird => const [Color(0xFF8B7FEC), Color(0xFFFF9A8B), Color(0xFFFFD3A5)],
        StudyRhythm.daytime => const [Color(0xFF38BDF8), Color(0xFF7DD3FC), Color(0xFFE0F2FE)],
        StudyRhythm.nightOwl => const [Color(0xFF0B0C22), Color(0xFF1B1C34), Color(0xFF3B3A7A)],
      };
}

/// A little sky that changes with the student's answer: the sun rises for
/// early birds, sits high for daytime, and swaps for a moon and stars for
/// night owls. Pure implicit animations, so it's cheap and settles instantly
/// under reduce motion.
class RhythmSky extends StatelessWidget {
  const RhythmSky({super.key, required this.rhythm});

  final StudyRhythm? rhythm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final motion = motionOn(context);
    final d = motion ? const Duration(milliseconds: 650) : Duration.zero;
    const curve = Curves.easeInOutCubic;
    final r = rhythm;
    final night = r == StudyRhythm.nightOwl;

    final sky = r?.sky ?? const [AppColors.primaryLight, Color(0xFFB9B0F3), AppColors.lavender];
    final orbAlign = switch (r) {
      StudyRhythm.earlyBird => const Alignment(-0.68, 0.35),
      StudyRhythm.daytime => const Alignment(0.05, -0.62),
      StudyRhythm.nightOwl => const Alignment(0.62, -0.5),
      null => const Alignment(0, 1.6), // below the horizon
    };
    final hillBack = switch (r) {
      StudyRhythm.earlyBird => const Color(0xFFE88B6E),
      StudyRhythm.daytime => const Color(0xFF86EFAC),
      StudyRhythm.nightOwl => const Color(0xFF2A2C4A),
      null => Colors.white.withValues(alpha: 0.45),
    };
    final hillFront = switch (r) {
      StudyRhythm.earlyBird => const Color(0xFFC2603F),
      StudyRhythm.daytime => const Color(0xFF22C55E),
      StudyRhythm.nightOwl => const Color(0xFF1B1C34),
      null => Colors.white.withValues(alpha: 0.7),
    };

    Widget hill(Color c, double w, double h) => AnimatedContainer(
          duration: d,
          curve: curve,
          width: w,
          height: h,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.all(Radius.elliptical(w / 2, h / 2))),
        );

    // Fixed star field; only its opacity animates.
    const stars = [
      (0.08, 0.14, 3.0), (0.22, 0.30, 2.0), (0.34, 0.10, 2.5), (0.47, 0.26, 2.0),
      (0.58, 0.08, 3.0), (0.86, 0.20, 2.0), (0.93, 0.40, 2.5), (0.15, 0.48, 2.0),
      (0.40, 0.44, 1.8), (0.72, 0.36, 2.2),
    ];

    final orb = AnimatedSwitcher(
      duration: d,
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: a, child: c)),
      child: night
          ? Container(
              key: const ValueKey('moon'),
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF8FAFC),
                boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.45), blurRadius: 26)],
              ),
              // A sky-coloured disc offset over the moon carves the crescent.
              child: Align(
                alignment: const Alignment(0.9, -0.7),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1B1C34)),
                ),
              ),
            )
          : Container(
              key: const ValueKey('sun'),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(colors: [Color(0xFFFFF7CC), Color(0xFFFDE047), Color(0xFFF59E0B)]),
                boxShadow: [BoxShadow(color: const Color(0xFFFDE047).withValues(alpha: 0.6), blurRadius: 30)],
              ),
            ),
    );

    return Semantics(
      label: r == null ? 'Sky scene. Pick when you study best.' : 'Sky scene: ${r.label}, peak focus ${r.window}',
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedContainer(
            duration: d,
            curve: curve,
            height: 176,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sky),
              boxShadow: [
                BoxShadow(
                  color: (r?.color ?? AppColors.primary).withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (final (i, (x, y, s)) in stars.indexed)
                    Positioned(
                      left: x * w,
                      top: y * 176,
                      child: AnimatedOpacity(
                        duration: d,
                        opacity: night ? 1 : 0,
                        child: Container(
                          width: s,
                          height: s,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        ),
                      ).twinkle(context, delayMs: i * 230, active: night),
                    ),
                  // Clouds drift in for daytime.
                  AnimatedPositioned(
                    duration: d,
                    curve: curve,
                    left: r == StudyRhythm.daytime ? w * 0.08 : -90,
                    top: 34,
                    child: Icon(Icons.cloud_rounded, size: 52, color: Colors.white.withValues(alpha: 0.9)),
                  ),
                  AnimatedPositioned(
                    duration: d,
                    curve: curve,
                    right: r == StudyRhythm.daytime ? w * 0.12 : -90,
                    top: 70,
                    child: Icon(Icons.cloud_rounded, size: 36, color: Colors.white.withValues(alpha: 0.75)),
                  ),
                  Positioned.fill(
                    child: AnimatedAlign(duration: d, curve: Curves.easeOutBack, alignment: orbAlign, child: orb),
                  ),
                  Positioned(left: -w * 0.2, bottom: -70, child: hill(hillBack, w * 0.9, 150)),
                  Positioned(right: -w * 0.25, bottom: -80, child: hill(hillFront, w * 1.0, 150)),
                  Positioned(
                    left: 18,
                    bottom: 14,
                    right: 18,
                    child: AnimatedSwitcher(
                      duration: motion ? const Duration(milliseconds: 260) : Duration.zero,
                      child: Column(
                        key: ValueKey(r),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            r == null ? 'YOUR PEAK HOURS' : 'PEAK FOCUS',
                            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70, letterSpacing: 1.4),
                          ),
                          Text(
                            r?.window ?? 'Pick one below',
                            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

extension _Twinkle on Widget {
  /// Slow opacity pulse for stars; off under reduce motion or when hidden.
  Widget twinkle(BuildContext context, {int delayMs = 0, required bool active}) {
    if (!active || !motionOn(context)) return this;
    return animate(onPlay: (c) => c.repeat(reverse: true))
        .fade(begin: 1, end: 0.3, delay: delayMs.ms, duration: 1400.ms, curve: Curves.easeInOut);
  }
}

/// A 24-hour strip with the student's peak window highlighted (wraps past
/// midnight for night owls). Used on the plan preview.
class FocusWindowBar extends StatelessWidget {
  const FocusWindowBar({super.key, required this.rhythm});

  final StudyRhythm rhythm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (start, end) = rhythm.hours;
    // Split into ≤2 segments on a 0–24 track.
    final segments = end <= 24 ? [(start, end)] : [(start, 24), (0, end - 24)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 12,
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return Stack(children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              for (final (s, e) in segments)
                Positioned(
                  left: w * s / 24,
                  width: w * (e - s) / 24,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [rhythm.color.withValues(alpha: 0.75), rhythm.color]),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [BoxShadow(color: rhythm.color.withValues(alpha: 0.5), blurRadius: 10)],
                    ),
                  ),
                ),
            ]);
          }),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final l in const ['12a', '6a', '12p', '6p', '12a'])
              Text(l, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white38)),
          ],
        ),
      ],
    );
  }
}

// ─── Perks hero ────────────────────────────────────────────────────────────

/// The perks reveal: a locked "student perks" pass unlocks with a sparkle
/// burst, then deal stickers fly out from behind it and settle into a gentle
/// float. Drawn on a fixed 360×300 canvas and scaled to fit, like
/// [WelcomeHero]. Under reduce motion it renders already unlocked and still.
class PerksHero extends StatefulWidget {
  const PerksHero({super.key});

  @override
  State<PerksHero> createState() => _PerksHeroState();
}

class _PerksHeroState extends State<PerksHero> {
  /// The pass unlocks once the page slide and its own pop-in have finished.
  static const _unlockMs = 700;

  Timer? _timer;
  bool _started = false;
  bool _unlocked = false;

  static const _stickers = [
    _PerkSticker(Icons.laptop_mac_rounded, 'Laptops', AppColors.info, Alignment(-1, -0.92), -0.07),
    _PerkSticker(Icons.apps_rounded, 'Software', AppColors.primary, Alignment(1, -1), 0.06),
    _PerkSticker(Icons.shopping_bag_rounded, 'Shopping', Color(0xFFEC4899), Alignment(-0.92, 1), 0.06),
    _PerkSticker(Icons.movie_rounded, 'Streaming', AppColors.coral, Alignment(1, 0.92), -0.06),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!motionOn(context)) {
      _unlocked = true;
      return;
    }
    _timer = Timer(const Duration(milliseconds: _unlockMs), () {
      if (mounted) setState(() => _unlocked = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = motionOn(context);
    const pink = Color(0xFFEC4899);

    Widget halo(double size, Color c, double alpha, int delay) {
      final w = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: alpha)),
      );
      return motion
          ? RepaintBoundary(child: w)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 0.92, end: 1.06, delay: delay.ms, duration: 2400.ms, curve: Curves.easeInOut)
          : w;
    }

    Widget sparkle(double size, Color c, int delay) {
      final w = Icon(Icons.auto_awesome, size: size, color: c);
      return motion
          ? RepaintBoundary(child: w)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fade(begin: 0.2, end: 1, delay: delay.ms, duration: 1300.ms)
              .scaleXY(begin: 0.8, end: 1.15, duration: 1300.ms)
          : w;
    }

    /// Flies out from the pass (the canvas centre) with a little spin, then
    /// bobs. Only translation/scale of a cached layer, so it stays cheap.
    Widget dealt(Widget child, Alignment at, int i, {double spin = 0.1}) {
      if (!motion) return Align(alignment: at, child: child);
      final delay = _unlockMs + 80 + 90 * i;
      final flown = RepaintBoundary(child: child)
          .animate()
          .fadeIn(delay: delay.ms, duration: 180.ms)
          .move(
            delay: delay.ms,
            begin: Offset(-at.x * 130, -at.y * 100),
            end: Offset.zero,
            duration: 640.ms,
            curve: Curves.easeOutBack,
          )
          .scaleXY(delay: delay.ms, begin: 0.3, end: 1, duration: 520.ms, curve: Curves.easeOutCubic)
          .rotate(delay: delay.ms, begin: i.isEven ? -spin : spin, end: 0, duration: 640.ms, curve: Curves.easeOutCubic);
      return Align(
        alignment: at,
        child: flown.float(context, dy: 4 + (i % 2) * 1.5, ms: 2600 + 300 * i),
      );
    }

    return Semantics(
      image: true,
      label: 'Student perks pass, unlocked, surrounded by student prices on laptops, software, shopping and streaming',
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: FittedBox(
            child: SizedBox(
              width: 360,
              height: 300,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  halo(260, pink, 0.06, 0),
                  halo(200, AppColors.primary, 0.07, 500),
                  // Stickers sit behind the pass so they appear to slide out of it.
                  for (final (i, s) in _stickers.indexed)
                    dealt(Transform.rotate(angle: s.tilt, child: _PerkStickerChip(sticker: s)), s.at, i),
                  dealt(const _PerkBubble(icon: Icons.school_rounded, color: AppColors.primary), const Alignment(-1, 0.05), 4,
                      spin: 0.2),
                  dealt(const _PerkBubble(icon: Icons.work_outline_rounded, color: AppColors.success), const Alignment(1, -0.05), 5,
                      spin: 0.2),
                  _PerksPass(unlocked: _unlocked).pop(context, delayMs: 60),
                  SparkleBurst(trigger: _unlocked ? 'perks' : null, radius: 130),
                  Positioned(top: 52, left: 120, child: sparkle(14, AppColors.accent, 0)),
                  Positioned(bottom: 50, right: 116, child: sparkle(16, pink, 500)),
                  Positioned(top: 70, right: 96, child: sparkle(11, AppColors.primaryLight, 900)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PerkSticker {
  const _PerkSticker(this.icon, this.label, this.color, this.at, this.tilt);
  final IconData icon;
  final String label;
  final Color color;
  final Alignment at;

  /// Resting tilt in radians, so the stickers look hand-placed.
  final double tilt;
}

class _PerkStickerChip extends StatelessWidget {
  const _PerkStickerChip({required this.sticker});
  final _PerkSticker sticker;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = sticker.color;
    return _HeroCard(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Color.lerp(c, Colors.white, 0.3)!, c]),
          ),
          child: Icon(sticker.icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(sticker.label, style: t.labelLarge),
          // The theme's success green is too light for small text on white.
          Text('Student price',
              style: t.bodySmall?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark ? AppColors.success : const Color(0xFF15803D),
                fontWeight: FontWeight.w600,
              )),
        ]),
      ]),
    );
  }
}

/// A round icon-only sticker for the non-deal perks (scholarships, internships).
class _PerkBubble extends StatelessWidget {
  const _PerkBubble({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
        boxShadow: AppColors.softShadow(opacity: 0.14, blur: 18),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// The coupon-style "student perks" pass in the middle of [PerksHero]. It
/// flips from "Unlocking…" to "Unlocked" when [unlocked] turns true.
class _PerksPass extends StatelessWidget {
  const _PerksPass({required this.unlocked});
  final bool unlocked;

  static const _w = 244.0;
  static const _h = 140.0;

  /// Height of the perforation line (and the side notches) from the top.
  static const _tearY = 98.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final motion = motionOn(context);

    Widget gift = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.2)),
      child: const Icon(Icons.redeem_rounded, color: Colors.white, size: 19),
    );
    if (motion && unlocked) {
      // A little "there's something in here" wiggle every few seconds.
      gift = RepaintBoundary(child: gift)
          .animate(onPlay: (c) => c.repeat())
          .shake(delay: 2400.ms, duration: 650.ms, hz: 4, rotation: 0.14);
    }

    Widget face = Container(
      width: _w,
      height: _h,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF472B6), AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: Stack(children: [
        Positioned(right: -36, top: -46, child: StudentIdCard._ring(140, 0.10)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                gift,
                const SizedBox(width: 8),
                Flexible(
                  child: Text('STUDENT PERKS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(color: Colors.white70, letterSpacing: 1.4)),
                ),
              ]),
              const SizedBox(height: 10),
              // "Unlocking…" rolls up and out as "Unlocked" rolls in from below.
              ClipRect(
                child: AnimatedSwitcher(
                  duration: motion ? const Duration(milliseconds: 460) : Duration.zero,
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, if (current != null) current],
                  ),
                  transitionBuilder: (c, a) {
                    final incoming = c.key == ValueKey(unlocked);
                    return SlideTransition(
                      position: Tween(begin: Offset(0, incoming ? 0.9 : -0.9), end: Offset.zero).animate(a),
                      child: FadeTransition(opacity: a, child: c),
                    );
                  },
                  child: Row(
                    key: ValueKey(unlocked),
                    children: [
                      Icon(unlocked ? Icons.lock_open_rounded : Icons.lock_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 6),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(unlocked ? 'Unlocked' : 'Unlocking…',
                              style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Perforation.
              Row(children: [
                for (var i = 0; i < 16; i++)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
              ]),
              SizedBox(
                height: _h - _tearY - 1,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Deals · Scholarships · Internships',
                        maxLines: 1,
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ]),
    );

    if (motion) {
      face = SweepShimmer(
        delay: const Duration(milliseconds: 1500),
        every: const Duration(seconds: 6),
        duration: const Duration(milliseconds: 1200),
        color: Colors.white.withValues(alpha: 0.35),
        child: face,
      );
    }

    // The shadow is painted from the same ticket path, so it follows the
    // notches (and looks the same in tests, unlike PhysicalShape).
    const clipper = _TicketClipper(radius: 22, notch: 11, notchY: _tearY);
    return RepaintBoundary(
      child: CustomPaint(
        painter: const _TicketShadowPainter(clipper),
        child: ClipPath(clipper: clipper, child: face),
      ),
    );
  }
}

class _TicketShadowPainter extends CustomPainter {
  const _TicketShadowPainter(this.clipper);
  final _TicketClipper clipper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawShadow(clipper.getClip(size), AppColors.primary.withValues(alpha: 0.7), 12, false);
  }

  @override
  bool shouldRepaint(_TicketShadowPainter old) => old.clipper.shouldReclip(clipper);
}

/// A rounded rectangle with a half-circle bitten out of each side at [notchY].
class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper({required this.radius, required this.notch, required this.notchY});
  final double radius;
  final double notch;
  final double notchY;

  @override
  Path getClip(Size size) {
    final card = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    final bites = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, notchY), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(size.width, notchY), radius: notch));
    return Path.combine(PathOperation.difference, card, bites);
  }

  @override
  bool shouldReclip(_TicketClipper old) => old.radius != radius || old.notch != notch || old.notchY != notchY;
}

// ─── Sparkle burst ─────────────────────────────────────────────────────────

/// A one-shot ring of sparkles that bursts outward and fades. Change [trigger]
/// to fire again (e.g. on each avatar pick).
class SparkleBurst extends StatelessWidget {
  const SparkleBurst({super.key, required this.trigger, this.radius = 70});

  final Object? trigger;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (!motionOn(context) || trigger == null) return const SizedBox.shrink();
    const colors = [AppColors.accent, AppColors.coral, AppColors.primaryLight, AppColors.success];
    return IgnorePointer(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Stack(
          key: ValueKey(trigger),
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 8; i++)
              Icon(Icons.auto_awesome, size: 14 + (i % 3) * 3.0, color: colors[i % colors.length])
                  .animate()
                  .move(
                    begin: Offset.zero,
                    end: Offset(math.cos(i * math.pi / 4) * radius, math.sin(i * math.pi / 4) * radius),
                    duration: 600.ms,
                    curve: Curves.easeOutCubic,
                  )
                  .scaleXY(begin: 0.3, end: 1, duration: 300.ms)
                  .then()
                  .fadeOut(duration: 300.ms),
          ],
        ),
      ),
    );
  }
}

// ─── Press feedback ────────────────────────────────────────────────────────

/// Subtle scale-down while pressed — tactile feedback for big CTAs and cards.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});
  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down && motionOn(context) ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}
