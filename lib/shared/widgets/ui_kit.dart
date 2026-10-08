import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';

/// Staggered entrance for list rows that stays smooth on long lists.
///
/// Only the first [maxAnimated] rows animate (the ones visible when the screen
/// opens), with a capped delay. Rows further down render immediately — before,
/// row 40 waited ~2s to appear and every lazily-built row replayed its fade as
/// it scrolled in, which read as scroll lag.
extension ListEntrance on Widget {
  Widget listEntrance(int index,
      {int stepMs = 40, int maxAnimated = 8, double slide = 0.06}) {
    if (index >= maxAnimated) return this;
    return animate()
        .fadeIn(delay: (index * stepMs).ms, duration: 280.ms)
        .slideY(begin: slide, curve: Curves.easeOutCubic);
  }
}

/// Soft, shadowed card decoration used across the redesigned screens.
BoxDecoration softCard(
  BuildContext context, {
  Color? color,
  double radius = 26,
  bool shadow = true,
}) {
  final theme = Theme.of(context);
  return BoxDecoration(
    color: color ?? theme.cardColor,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: shadow && theme.brightness == Brightness.light
        ? AppColors.softShadow(opacity: 0.05, blur: 14)
        : null,
  );
}

/// The message currently on screen via [showQuickFeedback], used to collapse
/// repeats. Deliberately module-level: the messenger is app-wide, so the
/// de-duplication must be too (the same confirmation is raised from several
/// screens/tiles). Cleared when that bar closes.
String? _visibleQuickFeedback;

/// Shows a short confirmation snackbar, collapsing a REPEAT of the same message
/// while that message is still on screen. Returns true when a bar was shown and
/// false when the call was absorbed as a repeat.
///
/// Why: the quick attendance-mark buttons used to do
/// `removeCurrentSnackBar()` + `showSnackBar()` on every tap.
/// `removeCurrentSnackBar` tears the bar down instantly (no settle animation),
/// so tapping Present a few times in a row — or marking several classes —
/// made the confirmation visibly flash in and out ("the notification blinks
/// many times"). Re-showing an identical message adds no information, so the
/// existing bar is left to ride instead. A *different* message still replaces
/// the current one immediately, which is what users expect.
///
/// The suppression window is the bar's ACTUAL lifetime (tracked via
/// [ScaffoldFeatureController.closed]) rather than a wall-clock timer, so it
/// stays exact regardless of the configured [duration] or animation speed.
bool showQuickFeedback(
  BuildContext context,
  String message, {
  Color? background,
  Duration duration = const Duration(milliseconds: 1400),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return false;
  if (message == _visibleQuickFeedback) return false; // already on screen
  messenger.removeCurrentSnackBar();
  _visibleQuickFeedback = message;
  messenger
      .showSnackBar(SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
      ))
      .closed
      .then((_) {
    // Only clear if a newer message hasn't already taken over.
    if (_visibleQuickFeedback == message) _visibleQuickFeedback = null;
  });
  return true;
}

/// Test-only reset for the [showQuickFeedback] de-duplication state.
@visibleForTesting
void resetQuickFeedbackForTest() => _visibleQuickFeedback = null;

/// A branded, selectable pill for filter bars (single-select categories or
/// multi-toggle quick filters). Filled with [accent] (or primary) when
/// selected; bordered otherwise. Consistent across feeds/editors.
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? accent;
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? AppColors.primary;
    return Material(
      color: selected ? color : theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
            color: selected ? color : theme.dividerColor, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: selected ? Colors.white : color),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? Colors.white
                          : theme.textTheme.bodyMedium?.color,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Body wrapper for editor forms: centres the content and caps its width, while
/// giving the (scrolling) child an explicit, bounded height.
///
/// A greedy `ListView` wrapped only in `Center`/`Align` can collapse to zero
/// height under the loose constraints a `Scaffold` passes its body when a
/// `bottomNavigationBar` is present — which blanks the whole form. Forcing the
/// height here makes the layout robust regardless of the surrounding chrome.
class CmsFormBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const CmsFormBody({super.key, required this.child, this.maxWidth = 760});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth < maxWidth ? c.maxWidth : maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: w,
            height: c.maxHeight.isFinite ? c.maxHeight : null,
            child: child,
          ),
        );
      },
    );
  }
}

/// A sticky bottom action bar for editor screens (Cancel + primary Save).
///
/// Pinned via `Scaffold.bottomNavigationBar` so the primary action stays
/// reachable no matter how long the form is — critical on mobile where a
/// top-app-bar-only Save scrolls out of reach.
class CmsSaveBar extends StatelessWidget {
  final bool saving;
  final bool isNew;

  /// Lower-case noun used in the button label, e.g. "resource" → "Create resource".
  final String label;
  final VoidCallback? onSave;

  const CmsSaveBar({
    super.key,
    required this.saving,
    required this.isNew,
    required this.label,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          // heightFactor: 1 → the bar hugs its content height (centering only
          // horizontally). Without it, Center is greedy vertically and, as a
          // bottomNavigationBar, expands to fill the screen — squeezing the
          // form body to zero height.
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      onPressed: onSave,
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded),
                      label: Text(saving
                          ? 'Saving…'
                          : (isNew ? 'Create $label' : 'Save changes')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular icon button used in headers (settings, notifications, back).
///
/// Icon-only controls are invisible to screen readers unless labelled, so
/// prefer passing a [semanticLabel] (e.g. "Settings", "Notifications"). It is
/// also surfaced as a long-press [tooltip] for sighted users.
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? background;
  final Color? iconColor;
  final double size;
  final String? semanticLabel;

  const RoundIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.background,
    this.iconColor,
    this.size = 44,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget button = Material(
      color: background ?? theme.cardColor,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon,
              size: 21,
              color: iconColor ?? theme.textTheme.titleLarge?.color),
        ),
      ),
    );
    if (semanticLabel != null && semanticLabel!.isNotEmpty) {
      button = Tooltip(
        message: semanticLabel!,
        child: Semantics(
          button: true,
          label: semanticLabel,
          child: ExcludeSemantics(child: button),
        ),
      );
    }
    return button;
  }
}

/// A small dark/tinted pill label (e.g. "Today", "1h 30m").
class PillTag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  const PillTag({
    super.key,
    required this.label,
    this.background = AppColors.ink,
    this.foreground = Colors.white,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon != null ? 12 : 16, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A section header row: a bold title with an optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: theme.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
