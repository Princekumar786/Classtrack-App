import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/character_avatar.dart';
import '../../../../shared/widgets/progress_ring.dart';
import '../../../../shared/widgets/sweep_shimmer.dart';

/// Visual building blocks for the personalised onboarding.
///
/// Everything here honours the OS "reduce motion" setting via [motionOn]:
/// looping/decorative motion is switched off and entrances become instant, so
/// the flow stays comfortable (and widget tests can `pumpAndSettle`).

bool motionOn(BuildContext context) => !MediaQuery.of(context).disableAnimations;

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
  Widget enter(BuildContext context, {int delayMs = 0, double dy = 0.12}) {
    if (!motionOn(context)) return this;
    return animate()
        .fadeIn(delay: delayMs.ms, duration: 420.ms)
        .slideY(begin: dy, curve: Curves.easeOutCubic);
  }

  /// Springy pop-in for "objects" (cards, stickers). No-op under reduce motion.
  Widget pop(BuildContext context, {int delayMs = 0}) {
    if (!motionOn(context)) return this;
    return animate()
        .fadeIn(delay: delayMs.ms, duration: 260.ms)
        .scaleXY(begin: 0.6, delay: delayMs.ms, duration: 520.ms, curve: Curves.easeOutBack);
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
      label: 'ClassTrack assistant surrounded by attendance, timetable, task and grade cards',
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
                Positioned(top: 18, left: 0, child: const _AttendanceChip().pop(context, delayMs: 250).float(context, dy: 5, ms: 3000)),
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

class _AttendanceChip extends StatelessWidget {
  const _AttendanceChip();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _HeroCard(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const AnimatedProgressRing(percent: 92, size: 40, strokeWidth: 5, color: AppColors.success, centerLabel: ''),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('92%', style: t.titleMedium?.copyWith(color: AppColors.success)),
          Text('Safe to skip 2', style: t.bodySmall),
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
    this.targetAttendance,
  });

  final String name;
  final String? avatarCharacter;
  final int? targetAttendance;

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
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 14)),
        ],
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
                  Text('$year', style: theme.textTheme.labelMedium?.copyWith(color: Colors.white70)),
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
                            targetAttendance == null ? 'Member since $year' : 'Target $targetAttendance% · Member since $year',
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
      // only applies its mask during the sweep itself (see its docs).
      card = SweepShimmer(
        delay: const Duration(milliseconds: 1600),
        every: const Duration(seconds: 6),
        duration: const Duration(milliseconds: 1300),
        color: Colors.white.withValues(alpha: 0.35),
        child: card,
      );
    }
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

// ─── Attendance dots ───────────────────────────────────────────────────────

/// A term drawn as dots: filled = classes to attend, outlined coral = classes
/// the student can still skip. Dots recolour in a quick ripple as the target
/// changes, making the percentage physical.
class AttendanceDots extends StatelessWidget {
  const AttendanceDots({super.key, required this.total, required this.skippable});

  final int total;
  final int skippable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attend = total - skippable;
    final motion = motionOn(context);
    return ExcludeSemantics(
      child: LayoutBuilder(builder: (context, c) {
        const perRow = 10;
        const gap = 8.0;
        final d = ((c.maxWidth - gap * (perRow - 1)) / perRow).clamp(10.0, 22.0);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < total; i++)
              AnimatedContainer(
                duration: motion ? Duration(milliseconds: 160 + (i % perRow) * 18) : Duration.zero,
                curve: Curves.easeOutCubic,
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < attend ? scheme.primary : AppColors.coral.withValues(alpha: 0.12),
                  border: Border.all(
                    color: i < attend ? scheme.primary : AppColors.coral,
                    width: 1.6,
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
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
