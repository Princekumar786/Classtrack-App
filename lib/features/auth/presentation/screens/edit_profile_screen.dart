import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/character_avatar.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/app_user.dart';
import '../../domain/profile_avatars.dart';
import '../../domain/profile_options.dart';
import '../providers/auth_providers.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';

/// Settings → Edit profile.
///
/// Progressive profiling: every field is OPTIONAL. Students can fill in as much
/// or as little as they like; the data personalises Opportunities & Discounts
/// but the app works perfectly with an empty profile. Nothing here is forced at
/// sign-up.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _state;
  late final TextEditingController _city;
  late final TextEditingController _university;
  late final TextEditingController _college;
  late final TextEditingController _degree;
  late final TextEditingController _department;
  late final TextEditingController _academicYear;
  late final TextEditingController _semester;
  late final TextEditingController _graduationYear;

  String? _country;
  String? _careerGoal;
  final Set<String> _interests = {};

  String? _uid;
  String? _avatarCharacter;

  bool _saving = false;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _state = TextEditingController();
    _city = TextEditingController();
    _university = TextEditingController();
    _college = TextEditingController();
    _degree = TextEditingController();
    _department = TextEditingController();
    _academicYear = TextEditingController();
    _semester = TextEditingController();
    _graduationYear = TextEditingController();
  }

  /// Seeds the form once from the loaded profile. Guarded by [_initialised] so
  /// later stream rebuilds never clobber the student's in-progress edits.
  void _seed(AppUser user) {
    if (_initialised) return;
    _initialised = true;
    _name.text = user.displayName ?? '';
    _state.text = user.stateRegion ?? '';
    _city.text = user.city ?? '';
    _university.text = user.university ?? '';
    _college.text = user.college ?? '';
    _degree.text = user.degree ?? '';
    _department.text = user.department ?? '';
    _academicYear.text = user.academicYear?.toString() ?? '';
    _semester.text = user.semester?.toString() ?? '';
    _graduationYear.text = user.graduationYear?.toString() ?? '';
    _country = user.country;
    _careerGoal = user.careerGoal;
    _uid = user.uid;
    _avatarCharacter = ProfileAvatars.resolve(user.avatarCharacter, user.uid);
    _interests
      ..clear()
      ..addAll(user.interests);
  }

  @override
  void dispose() {
    _name.dispose();
    _state.dispose();
    _city.dispose();
    _university.dispose();
    _college.dispose();
    _degree.dispose();
    _department.dispose();
    _academicYear.dispose();
    _semester.dispose();
    _graduationYear.dispose();
    super.dispose();
  }

  /// A text value → sanitized string, or [FieldValue.delete] when cleared, so a
  /// single merge-write both sets and removes fields.
  Object _text(String raw) {
    final clean = Validators.sanitizeText(raw, maxLength: 80);
    return clean.isEmpty ? FieldValue.delete() : clean;
  }

  /// An int text value → parsed int (clamped to [min]..[max]) or
  /// [FieldValue.delete] when empty/invalid.
  Object _int(String raw, {int min = 1, int max = 9999}) {
    final v = int.tryParse(raw.trim());
    if (v == null) return FieldValue.delete();
    return v.clamp(min, max);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? true)) return;
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    setState(() => _saving = true);

    final repo = ref.read(authRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Display name also lives on the Firebase Auth user, so it goes through
      // its dedicated path (which updates both Auth + Firestore).
      final newName = Validators.sanitizeName(_name.text);
      if (newName.isNotEmpty) {
        await repo.updateDisplayName(uid, newName);
      }

      await repo.updateProfileDetails(uid, {
        'avatarCharacter':
            (_avatarCharacter == null || _avatarCharacter!.isEmpty)
                ? FieldValue.delete()
                : _avatarCharacter,
        'country':
            (_country == null || _country!.isEmpty) ? FieldValue.delete() : _country,
        'stateRegion': _text(_state.text),
        'city': _text(_city.text),
        'university': _text(_university.text),
        'college': _text(_college.text),
        'degree': _text(_degree.text),
        'department': _text(_department.text),
        'academicYear': _int(_academicYear.text, max: 12),
        'semester': _int(_semester.text, max: 20),
        'graduationYear': _int(_graduationYear.text, min: 1970, max: 2100),
        'careerGoal': (_careerGoal == null || _careerGoal!.isEmpty)
            ? FieldValue.delete()
            : _careerGoal,
        'interests': _interests.toList(),
      });

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Profile saved ✓')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save your profile. Try again.")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    if (profile != null) _seed(profile);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      bottomNavigationBar: _saveBar(theme),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            _headerPreview(theme, profile?.email),
            const SizedBox(height: 16),
            _intro(theme),
            const SizedBox(height: 18),
            _sectionCard(
              theme,
              icon: Icons.badge_rounded,
              title: 'Account',
              children: [
                _input(_name, 'Display name',
                    capitalize: true,
                    icon: Icons.person_rounded,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? null
                        : Validators.name(v)),
              ],
            ),
            const SizedBox(height: 14),
            _sectionCard(
              theme,
              icon: Icons.face_retouching_natural_rounded,
              title: 'Profile character',
              subtitle: 'Pick an avatar that represents you',
              children: [_characterPicker(theme)],
            ),
            const SizedBox(height: 14),
            _sectionCard(
              theme,
              icon: Icons.location_on_rounded,
              title: 'Location',
              subtitle: 'Improves your opportunity & perk matches',
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _country,
                  isExpanded: true,
                  decoration: _decoration(theme, 'Country',
                      icon: Icons.public_rounded),
                  items: [
                    const DropdownMenuItem<String>(
                        value: null, child: Text('Not set')),
                    ...ProfileOptions.countries.map((c) =>
                        DropdownMenuItem<String>(value: c, child: Text(c))),
                  ],
                  onChanged: (v) => setState(() => _country = v),
                ),
                const SizedBox(height: 12),
                _input(_state, 'State / region', icon: Icons.map_rounded),
                const SizedBox(height: 12),
                _input(_city, 'City', icon: Icons.location_city_rounded),
              ],
            ),
            const SizedBox(height: 14),
            _sectionCard(
              theme,
              icon: Icons.school_rounded,
              title: 'Education',
              children: [
                _input(_university, 'University',
                    icon: Icons.account_balance_rounded),
                const SizedBox(height: 12),
                _input(_college, 'College', icon: Icons.apartment_rounded),
                const SizedBox(height: 12),
                _input(_degree, 'Degree (e.g. MBA, B.Tech)',
                    icon: Icons.workspace_premium_rounded),
                const SizedBox(height: 12),
                _input(_department, 'Department / branch',
                    icon: Icons.category_rounded),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _input(_academicYear, 'Year', number: true)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _input(_semester, 'Semester', number: true)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _input(_graduationYear, 'Grad. year',
                            number: true)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _sectionCard(
              theme,
              icon: Icons.flag_rounded,
              title: 'Career goal',
              subtitle: 'Pick the one that fits you best',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in ProfileOptions.careerGoals)
                      _selectChip(g, _careerGoal == g,
                          () => setState(() =>
                              _careerGoal = _careerGoal == g ? null : g)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _sectionCard(
              theme,
              icon: Icons.interests_rounded,
              title: 'Interests',
              subtitle: 'Select all that apply',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final i in ProfileOptions.interests)
                      _selectChip(i, _interests.contains(i), () => setState(() {
                            if (!_interests.remove(i)) _interests.add(i);
                          })),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A gradient identity preview at the top of the form.
  Widget _headerPreview(ThemeData theme, String? email) {
    final name = _name.text.trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.softShadow(opacity: 0.24, blur: 22),
      ),
      child: Row(
        children: [
          CharacterAvatar(
            uid: _uid ?? '',
            character: _avatarCharacter,
            fallbackText: name.isEmpty ? '?' : name,
            size: 58,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'Your name' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: Colors.white)),
                if (email != null && email.isNotEmpty)
                  Text(email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact character summary: shows the current avatar with a "Change"
  /// button that opens the full picker in a bottom sheet — so the form stays
  /// short instead of listing every character inline.
  Widget _characterPicker(ThemeData theme) {
    final selected = ProfileAvatars.resolve(_avatarCharacter, _uid ?? '');
    final baseColor = theme.brightness == Brightness.dark
        ? AppColors.darkSurfaceAlt
        : AppColors.lavenderSoft;
    return Row(
      children: [
        _CharacterChoice(
          path: '${ProfileAvatars.assetDir}/$selected',
          selected: false,
          baseColor: baseColor,
          onTap: _openCharacterSheet,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            ref.watch(isProProvider)
                ? 'Choose from ${ProfileAvatars.all.length} characters'
                : '${ProfileAvatars.freeCount} free · ${ProfileAvatars.all.length} with Pro',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _openCharacterSheet,
          icon: const Icon(Icons.grid_view_rounded, size: 18),
          label: const Text('Change'),
          // The app's outlinedButtonTheme sets minimumSize: Size.fromHeight(54)
          // (infinite width), which is fine inside an Expanded but throws
          // "BoxConstraints forces an infinite width" in this Row. Pin a finite
          // min width so the button sizes to its content instead.
          style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              side: const BorderSide(color: AppColors.primary)),
        ),
      ],
    );
  }

  /// Opens a scrollable grid of every character. Selecting one updates the
  /// live preview; "Save" persists just the avatar immediately (independent of
  /// the rest of the form) and closes the sheet.
  Future<void> _openCharacterSheet() async {
    final theme = Theme.of(context);
    final baseColor = theme.brightness == Brightness.dark
        ? AppColors.darkSurfaceAlt
        : AppColors.lavenderSoft;
    // Remember what was set before, so Cancel can revert the live preview.
    final previous = _avatarCharacter;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (sheetCtx, controller) {
            return StatefulBuilder(
              builder: (sheetCtx, setSheet) {
                final selected =
                    ProfileAvatars.resolve(_avatarCharacter, _uid ?? '');
                return Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.dividerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Choose your character',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700)),
                                if (!ref.read(isProProvider))
                                  Text(
                                    'First ${ProfileAvatars.freeCount} are free · unlock all ${ProfileAvatars.all.length} with Pro',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: theme.hintColor),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 74,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                        ),
                        itemCount: ProfileAvatars.all.length,
                        itemBuilder: (ctx, i) {
                          final file = ProfileAvatars.all[i];
                          final isPro = ref.read(isProProvider);
                          final locked =
                              !isPro && !ProfileAvatars.isFree(file);
                          return Center(
                            child: _CharacterChoice(
                              path: '${ProfileAvatars.assetDir}/$file',
                              selected: file == selected,
                              locked: locked,
                              baseColor: baseColor,
                              onTap: () async {
                                if (locked) {
                                  // Pro-only character: send them to the
                                  // paywall. If they upgrade, unlock the grid
                                  // and select the one they wanted.
                                  final becamePro = await showUpgradePrompt(
                                      ctx, UpgradeReason.avatars);
                                  if (!mounted || !becamePro) return;
                                  setState(() => _avatarCharacter = file);
                                  setSheet(() {});
                                  return;
                                }
                                setState(() => _avatarCharacter = file);
                                setSheet(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(sheetCtx).pop(false),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48)),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    minimumSize: const Size.fromHeight(48)),
                                onPressed: () =>
                                    Navigator.of(sheetCtx).pop(true),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Save'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    if (saved == true) {
      await _persistCharacter();
    } else {
      // Reverted: restore the preview to what it was before opening the sheet.
      if (mounted) setState(() => _avatarCharacter = previous);
    }
  }

  /// Persists only the chosen avatar character (a lightweight merge-write) so
  /// the picker has its own save, separate from the full "Save profile" action.
  Future<void> _persistCharacter() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    final repo = ref.read(authRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.updateProfileDetails(uid, {
        'avatarCharacter': (_avatarCharacter == null || _avatarCharacter!.isEmpty)
            ? FieldValue.delete()
            : _avatarCharacter,
      });
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Character updated ✓')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't update character. Try again.")),
      );
    }
  }


  Widget _saveBar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).maybePop(),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50)),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(50)),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Saving…' : 'Save profile'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro(ThemeData theme) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Everything is optional. The more you share, the better we match '
                'scholarships, internships and student perks to you.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.inkSoft, height: 1.35),
              ),
            ),
          ],
        ),
      );

  /// A titled section wrapped in a soft card with an icon header.
  Widget _sectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: softCard(context, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _decoration(ThemeData theme, String label, {IconData? icon}) {
    final fill = theme.brightness == Brightness.dark
        ? AppColors.darkSurfaceAlt
        : AppColors.lavenderSoft;
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: fill,
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 19, color: theme.hintColor),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    );
  }

  Widget _input(TextEditingController c, String label,
      {bool number = false,
      bool capitalize = false,
      IconData? icon,
      String? Function(String?)? validator}) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters:
          number ? [FilteringTextInputFormatter.digitsOnly] : null,
      textCapitalization: (capitalize && !number)
          ? TextCapitalization.words
          : TextCapitalization.none,
      // Refresh the header preview initial/name as the user types.
      onChanged: c == _name ? (_) => setState(() {}) : null,
      decoration: _decoration(theme, label, icon: icon),
      validator: validator,
    );
  }

  /// A selectable pill that stays visible on any background. Filled primary
  /// when selected.
  Widget _selectChip(String label, bool selected, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? AppColors.primary
          : (theme.brightness == Brightness.dark
              ? AppColors.darkSurfaceAlt
              : AppColors.lavenderSoft),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? Colors.white
                          : theme.textTheme.bodyLarge?.color,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}



/// A single tappable character in the picker: the artwork on a soft circular
/// backing, with a primary ring + check badge when it's the selected avatar.
class _CharacterChoice extends StatelessWidget {
  const _CharacterChoice({
    required this.path,
    required this.selected,
    required this.baseColor,
    required this.onTap,
    this.locked = false,
  });

  final String path;
  final bool selected;
  final Color baseColor;
  final VoidCallback onTap;

  /// A Pro-only character the current (free) user can't select yet. Shown
  /// dimmed with a small lock badge; tapping routes to the paywall.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    const size = 58.0;
    return Semantics(
      button: true,
      selected: selected,
      label: locked ? 'Pro character, locked' : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: baseColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2.4,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Opacity(
                  opacity: locked ? 0.4 : 1,
                  child: Image.asset(
                    path,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.person_rounded, color: Colors.white),
                  ),
                ),
              ),
              if (locked)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: const Icon(Icons.lock_rounded,
                        size: 11, color: Colors.white),
                  ),
                )
              else if (selected)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
