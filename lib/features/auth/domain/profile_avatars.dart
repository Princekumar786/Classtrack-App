/// Catalog of the selectable profile characters bundled under
/// `assets/characters/`.
///
/// The app used to draw a plain letter (the first character of the display
/// name) as every user's avatar. Instead we now ship a set of fun character
/// icons: each account is given a distinct one at sign-up (deterministically,
/// so it's stable across devices) and the student can change it any time from
/// Settings → Edit profile.
///
/// Only the bare file name (e.g. `icons8-batman-144.png`) is ever stored on the
/// user document — [assetPath] turns it into a loadable asset path. Keeping the
/// list here means the picker, the default assignment and every avatar render
/// all draw from the same source of truth.
class ProfileAvatars {
  ProfileAvatars._();

  /// Folder the character PNGs live in (registered in pubspec.yaml).
  static const String assetDir = 'assets/characters';

  /// Every selectable character (static PNGs only — the animated `.apng.png`
  /// variants are intentionally excluded so avatars stay crisp and light).
  static const List<String> all = [
    'icons8-aang-144.png',
    'icons8-adam-savage-144.png',
    'icons8-albus-dumbledore-144.png',
    'icons8-amethyst-universe-144.png',
    'icons8-anonymous-mask-144.png',
    'icons8-aquaman-144.png',
    'icons8-atom-144.png',
    'icons8-badtz-maru-144.png',
    'icons8-batman-144.png',
    'icons8-batman-144-2.png',
    'icons8-bendy-144.png',
    'icons8-bill-cipher-144.png',
    'icons8-bmo-144.png',
    'icons8-brave-144.png',
    'icons8-brutus-144.png',
    'icons8-bt21-chimmy-144.png',
    'icons8-bt21-cooky-144.png',
    'icons8-bt21-mang-144.png',
    'icons8-catwoman-144.png',
    'icons8-cheburashka-144.png',
    'icons8-chewbacca-144.png',
    'icons8-chip-144.png',
    'icons8-chucky-144.png',
    'icons8-cookie-monster-144.png',
    'icons8-cyborg-144.png',
    'icons8-cylon-head-new-144.png',
    'icons8-dale-144.png',
    'icons8-eric-cartman-144.png',
    'icons8-fairy-144.png',
    'icons8-finding-nemo-144.png',
    'icons8-finn-144.png',
    'icons8-fortnite-llama-144.png',
    'icons8-fsociety-mask-144.png',
    'icons8-futurama-amy-wong-144.png',
    'icons8-genie-144.png',
    'icons8-goofy-144.png',
    'icons8-grey-144.png',
    'icons8-grim-adventures-of-billy-and-mandy-144.png',
    'icons8-grinch-144.png',
    'icons8-gunter-144.png',
    'icons8-harley-quinn-dc-144.png',
    'icons8-harley-quinn-suicide-squad-144.png',
    'icons8-hawkgirl-144.png',
    'icons8-hellcat-144.png',
    'icons8-hello-kitty-144.png',
    'icons8-hercules-144.png',
    'icons8-hulk-144.png',
    'icons8-iron-man-144.png',
    'icons8-jake-144.png',
    'icons8-jeffy-144.png',
    'icons8-jerry-144.png',
    'icons8-jetpack-joyride-144.png',
    'icons8-joker-suicide-squad-144.png',
    'icons8-kermit-the-frog-144.png',
    'icons8-keroppi-144.png',
    'icons8-lumpy-space-princess-144.png',
    'icons8-magneto-144.png',
    'icons8-marceline-144.png',
    'icons8-my-melody-144.png',
    'icons8-mystique-144.png',
    'icons8-oggy-144.png',
    'icons8-rogue-144.png',
    'icons8-smurf-144.png',
    'icons8-someity-144.png',
    'icons8-spider-man-head-144.png',
    'icons8-spyro-144.png',
    'icons8-steven-universe-144.png',
    'icons8-storm-marvel-144.png',
    'icons8-super-mario-144.png',
    'icons8-thanos-144.png',
    'icons8-the-coon-144.png',
    'icons8-thor-144.png',
    'icons8-timon-144.png',
    'icons8-venom-head-144.png',
  ];

  /// Full asset path for a stored [fileName], or `null` when it's empty or not
  /// a known character (so callers can fall back gracefully).
  static String? assetPath(String? fileName) {
    if (fileName == null || fileName.isEmpty) return null;
    if (!all.contains(fileName)) return null;
    return '$assetDir/$fileName';
  }

  /// A stable, deterministic default character for a given user id.
  ///
  /// Derived from a simple hash of the uid so a brand-new account starts with a
  /// distinct character (not the same one for everyone) and always resolves to
  /// the same character on every device — without needing a server round-trip.
  static String defaultForUid(String uid) {
    if (all.isEmpty) return '';
    if (uid.isEmpty) return all.first;
    var hash = 0;
    for (final unit in uid.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return all[hash % all.length];
  }

  /// Resolves which character to actually display for a user: their [chosen]
  /// one when it's a known character, otherwise the deterministic default for
  /// [uid]. Guarantees a non-empty, renderable file name for every user.
  static String resolve(String? chosen, String uid) {
    if (chosen != null && all.contains(chosen)) return chosen;
    return defaultForUid(uid);
  }
}
