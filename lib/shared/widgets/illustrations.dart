import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';

/// Gentle looping vertical float used by the decorative illustration pieces.
/// Kept small and few in number so it stays perfectly smooth; the child is
/// isolated in a RepaintBoundary so each frame only moves a cached layer.
Widget _float(Widget child,
    {double dy = 6, int ms = 2600, int delayMs = 0}) {
  return RepaintBoundary(child: child)
      .animate(onPlay: (c) => c.repeat(reverse: true))
      .moveY(
        begin: -dy,
        end: dy,
        duration: ms.ms,
        curve: Curves.easeInOut,
        delay: delayMs.ms,
      );
}

Widget _chip({
  required IconData icon,
  required Color color,
  double size = 44,
}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(size * 0.32),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.28),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Icon(icon, color: color, size: size * 0.5),
  );
}

/// A friendly, on-brand illustrated header for the auth screens — a central
/// brand tile surrounded by softly floating "student life" chips (calendar,
/// grade, streak, tasks) over a soft lavender backdrop. Pure widgets, so it's
/// crisp at any size and needs no image assets.
class AuthIllustration extends StatelessWidget {
  final double height;
  const AuthIllustration({super.key, this.height = 190});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft backdrop blobs.
          Container(
            width: 168,
            height: 168,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.lavender, AppColors.lavenderTint],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            right: 44,
            top: 8,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.25),
              ),
            ),
          ),
          Positioned(
            left: 40,
            bottom: 10,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.coral.withValues(alpha: 0.3),
              ),
            ),
          ),
          // Central brand tile.
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryLight, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.42),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: const Icon(Icons.calendar_month_rounded,
                size: 46, color: Colors.white),
          )
              .animate()
              .scale(
                  begin: const Offset(0.7, 0.7),
                  end: const Offset(1, 1),
                  duration: 450.ms,
                  curve: Curves.easeOutBack)
              .fadeIn(duration: 320.ms),
          // Floating chips (kept to two for a light, smooth first frame).
          Positioned(
            left: 26,
            top: 30,
            child: _float(
                _chip(icon: Icons.check_circle_rounded, color: AppColors.success),
                dy: 6, ms: 2600),
          ),
          Positioned(
            right: 30,
            bottom: 24,
            child: _float(
                _chip(icon: Icons.school_rounded, color: AppColors.accent, size: 40),
                dy: 5, ms: 2800, delayMs: 400),
          ),
        ],
      ),
    ),
    );
  }
}

/// A friendly, animated illustration for empty states: the given [icon] in a
/// gradient medallion over soft halos, with a couple of gently floating accent
/// dots. Used by the shared `EmptyState` so every empty screen feels alive.
///
/// Only two tiny elements float, so it stays perfectly smooth on any screen.
class EmptyIllustration extends StatelessWidget {
  final IconData icon;
  final Color color;
  const EmptyIllustration({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    Widget dot(double size, double opacity) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: opacity),
          ),
        );

    return SizedBox(
      height: 138,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.07),
            ),
          ),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
          ),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.82), color],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.32),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 38),
          )
              .animate()
              .scale(
                  begin: const Offset(0.7, 0.7),
                  end: const Offset(1, 1),
                  duration: 460.ms,
                  curve: Curves.easeOutBack)
              .fadeIn(duration: 320.ms),
          Positioned(
            left: 44,
            top: 20,
            child: _float(dot(11, 0.35), dy: 5, ms: 2600),
          ),
          Positioned(
            right: 46,
            bottom: 22,
            child: _float(dot(8, 0.28), dy: 6, ms: 3000, delayMs: 300),
          ),
        ],
      ),
    );
  }
}

/// A serene, calming header for the Pro paywall: a soft set of concentric
/// halos that gently "breathe" in and out, with a quiet lotus mark at the
/// centre and a few slowly drifting dots. Designed for a dark gradient
/// backdrop. Deliberately slow and low-contrast (no sharp sparkles or trophy)
/// so the screen feels reassuring and relaxed rather than pushy.
class CalmIllustration extends StatelessWidget {
  final double height;
  const CalmIllustration({super.key, this.height = 150});

  @override
  Widget build(BuildContext context) {
    Widget dot(double size, double opacity) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: opacity),
          ),
        );

    // A soft halo that slowly breathes in and out — the heart of the calm feel.
    Widget breathingHalo(double size, double opacity,
            {int ms = 4200, int delayMs = 0}) =>
        RepaintBoundary(
          child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: opacity),
          ),
        ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(
              begin: 0.94,
              end: 1.06,
              duration: ms.ms,
              delay: delayMs.ms,
              curve: Curves.easeInOut,
            );

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          breathingHalo(132, 0.08),
          breathingHalo(100, 0.12, ms: 4600, delayMs: 300),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.spa_rounded,
                color: AppColors.primary, size: 36),
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(
                begin: const Offset(0.85, 0.85),
                end: const Offset(1, 1),
                duration: 600.ms,
                curve: Curves.easeOut,
              )
              // A gentle, slow float so it feels alive but never busy.
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(
                  begin: -4, end: 4, duration: 3200.ms, curve: Curves.easeInOut),
          Positioned(
              left: 46, top: 26, child: _float(dot(9, 0.45), dy: 4, ms: 3200)),
          Positioned(
              right: 50,
              top: 40,
              child: _float(dot(6, 0.35), dy: 5, ms: 3600, delayMs: 300)),
          Positioned(
              right: 64,
              bottom: 26,
              child: _float(dot(10, 0.4), dy: 4, ms: 3400, delayMs: 500)),
        ],
      ),
    );
  }
}
