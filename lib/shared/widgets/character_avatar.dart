import 'package:flutter/material.dart';

import '../../features/auth/domain/profile_avatars.dart';

/// A circular profile avatar that renders the user's chosen character icon.
///
/// Replaces the old "first letter of the name" avatar used across the app
/// (dashboard header, settings header, edit-profile preview). Resolution order:
///   1. the user's [character] (when it's a known asset),
///   2. a deterministic default derived from [uid] (so every account still gets
///      a distinct character even before they pick one),
///   3. an initial letter from [fallbackText] if the image can't be loaded.
///
/// The character art has a transparent background, so the widget draws it on a
/// circular backing — either a [gradient] or a solid [backgroundColor] — to
/// preserve the look of the surfaces it replaces.
class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar({
    super.key,
    required this.uid,
    this.character,
    this.fallbackText,
    this.size = 46,
    this.gradient,
    this.backgroundColor,
    this.padding,
  });

  /// The user's uid — used to pick a stable default when [character] is unset.
  final String uid;

  /// The stored character file name (e.g. `icons8-batman-144.png`), if any.
  final String? character;

  /// Text whose first letter is shown if the image fails to load (usually the
  /// display name).
  final String? fallbackText;

  /// Rendered diameter in logical pixels.
  final double size;

  /// Optional gradient backing (takes precedence over [backgroundColor]).
  final Gradient? gradient;

  /// Optional solid backing colour. Defaults to a translucent white, matching
  /// the avatar wells on the app's gradient headers.
  final Color? backgroundColor;

  /// Inset around the character art. Defaults to ~14% of [size].
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final file = ProfileAvatars.resolve(character, uid);
    final path = ProfileAvatars.assetPath(file);
    final pad = padding ?? EdgeInsets.all(size * 0.14);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null
            ? (backgroundColor ?? Colors.white.withValues(alpha: 0.22))
            : null,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: path == null
          ? _letter()
          : Padding(
              padding: pad,
              child: Image.asset(
                path,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => _letter(),
              ),
            ),
    );
  }

  Widget _letter() {
    final source = (fallbackText != null && fallbackText!.trim().isNotEmpty)
        ? fallbackText!.trim()
        : '?';
    return Text(
      source[0].toUpperCase(),
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
