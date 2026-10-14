import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Elevated button that shows a spinner while [loading].
class LoadingButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  final IconData? icon;

  const LoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 10),
                ],
                Text(label),
              ],
            ),
    );
  }
}

/// "Continue with Google" button following Google's sign-in branding:
/// the official multi-colour "G" logo, a neutral surface, a hairline border,
/// and medium-weight label. Adapts to light/dark theme.
class GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onPressed;
  const GoogleButton({super.key, required this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Google's recommended neutral button colours.
    final background = dark ? const Color(0xFF131314) : Colors.white;
    final foreground = dark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);
    final border = dark ? const Color(0xFF8E918F) : const Color(0xFF747775);

    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: loading
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(foreground),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The official logo stays full-colour on any background.
                  SvgPicture.asset(
                    'assets/brand/google_g.svg',
                    height: 20,
                    width: 20,
                    semanticsLabel: 'Google logo',
                  ),
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Text(
                      'Continue with Google',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
