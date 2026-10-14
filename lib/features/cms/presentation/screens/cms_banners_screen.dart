import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../services/push_deep_link.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/marketing.dart';
import '../providers/cms_marketing_providers.dart';

/// True when a banner destination opens the Pro pricing page. Same rule the
/// app uses to always hide such banners from Pro users.
bool _isPaywall(String? destination) =>
    PushDeepLink.parse(destination) is PaywallDeepLink;

class CmsBannersScreen extends ConsumerWidget {
  const CmsBannersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(cmsBannersProvider);

    void openEditor(CmsBanner? b) => Navigator.of(context).push(
      MaterialPageRoute(settings: const RouteSettings(name: 'Cms Banner Editor'), builder: (_) => CmsBannerEditorScreen(existing: b)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
          // Wrap (not Row+Spacer) so the action button drops below the title on
          // narrow/mobile widths instead of overflowing off the right edge.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Text('Banners', style: theme.textTheme.headlineSmall),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () => openEditor(null),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New banner'),
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) =>
                Center(child: Text('Failed to load banners.\n$e')),
            data: (banners) {
              if (banners.isEmpty) {
                return Center(
                  child: Text(
                    'No banners yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
                itemCount: banners.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final b = banners[i];
                  return InkWell(
                    onTap: () => openEditor(b),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: softCard(context),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.view_carousel_rounded,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${Placements.label(b.placement)}'
                                  '${b.isLive() ? ' · live' : ''}'
                                  '${b.showToPro && !_isPaywall(b.destination) ? '' : ' · free users only'}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.hintColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (b.sponsored)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: AppColors.accent,
                              ),
                            ),
                          Text(
                            b.published ? 'Published' : 'Draft',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: b.published
                                  ? AppColors.success
                                  : theme.hintColor,
                            ),
                          ),
                          Switch(
                            value: b.published,
                            onChanged: (v) => ref
                                .read(cmsMarketingRepositoryProvider)
                                ?.setBannerPublished(b.id, v),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              final ok = await _confirm(context, b.title);
                              if (ok) {
                                await ref
                                    .read(cmsMarketingRepositoryProvider)
                                    ?.deleteBanner(b.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<bool> _confirm(BuildContext context, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete banner?'),
        content: Text('Delete "$title"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

class CmsBannerEditorScreen extends ConsumerStatefulWidget {
  final CmsBanner? existing;
  const CmsBannerEditorScreen({super.key, this.existing});

  @override
  ConsumerState<CmsBannerEditorScreen> createState() =>
      _CmsBannerEditorScreenState();
}

class _CmsBannerEditorScreenState extends ConsumerState<CmsBannerEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _imageUrl = TextEditingController();
  final _cta = TextEditingController();
  final _destination = TextEditingController();
  final _category = TextEditingController();
  final _countries = TextEditingController();
  final _priority = TextEditingController(text: '0');
  String _placement = Placements.home;
  bool _sponsored = false;
  bool _published = false;
  bool _showToPro = true;
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _title.text = b.title;
      _imageUrl.text = b.imageUrl ?? '';
      _cta.text = b.ctaLabel ?? '';
      _destination.text = b.destination ?? '';
      _category.text = b.category ?? '';
      _countries.text = b.countries.join(', ');
      _priority.text = b.priority.toString();
      _placement = b.placement;
      _sponsored = b.sponsored;
      _published = b.published;
      _showToPro = b.showToPro;
      _start = b.startDate;
      _end = b.endDate;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _imageUrl,
      _cta,
      _destination,
      _category,
      _countries,
      _priority,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(cmsMarketingRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await repo.saveBanner(
        CmsBanner(
          id: widget.existing?.id ?? '',
          title: _title.text.trim(),
          imageUrl: _nn(_imageUrl.text),
          ctaLabel: _nn(_cta.text),
          destination: _nn(_destination.text),
          category: _nn(_category.text),
          countries: _list(_countries.text),
          priority: int.tryParse(_priority.text.trim()) ?? 0,
          placement: _placement,
          sponsored: _sponsored,
          published: _published,
          showToPro: _showToPro,
          startDate: _start,
          endDate: _end,
          createdAt: widget.existing?.createdAt,
        ),
      );
      messenger.showSnackBar(const SnackBar(content: Text('Saved ✓')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nn(String s) => s.trim().isEmpty ? null : s.trim();
  List<String> _list(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  /// Allowed raster image types, matching the Storage rules for `cms/media/**`
  /// (png/jpeg/jpg/webp/gif, under 5 MB). SVG is intentionally excluded.
  static const int _maxImageBytes = 5 * 1024 * 1024;

  /// Picks an image from the gallery, uploads it to Firebase Storage under
  /// `cms/media/banners/`, and fills the Image URL field with its public
  /// download URL. The manual Image URL field still works for external images.
  Future<void> _pickAndUploadImage() async {
    final messenger = ScaffoldMessenger.of(context);
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2000,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxImageBytes) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Image must be under 5 MB.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    final ext = _imageExt(file.name);
    final contentType = _imageContentType(ext);
    setState(() => _uploadingImage = true);
    try {
      final path = 'cms/media/banners/${const Uuid().v4()}.$ext';
      final storageRef = ref.read(firebaseStorageProvider).ref().child(path);
      await storageRef.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );
      final url = await storageRef.getDownloadURL();
      if (!mounted) return;
      setState(() => _imageUrl.text = url);
      messenger.showSnackBar(const SnackBar(content: Text('Image uploaded ✓')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  /// A Storage-rules-safe extension for [name]; defaults to jpg when unknown.
  static String _imageExt(String name) {
    final match = RegExp(r'\.([^.]+)$').firstMatch(name);
    final ext = match?.group(1)?.toLowerCase();
    const allowed = {'png', 'jpg', 'jpeg', 'webp', 'gif'};
    return (ext != null && allowed.contains(ext)) ? ext : 'jpg';
  }

  static String _imageContentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New banner' : 'Edit banner'),
      ),
      bottomNavigationBar: CmsSaveBar(
        saving: _saving,
        isNew: widget.existing == null,
        label: 'banner',
        onSave: _saving ? null : _save,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _imageUrl,
                  decoration: const InputDecoration(
                    labelText: 'Image URL',
                    helperText: 'Paste a URL or upload an image below.',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _uploadingImage ? null : _pickAndUploadImage,
                    icon: _uploadingImage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_rounded, size: 18),
                    label: Text(
                      _uploadingImage ? 'Uploading…' : 'Upload image',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cta,
                  decoration: const InputDecoration(labelText: 'CTA label'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _destination,
                  // Refresh the "Show to Pro users" hint as the link changes.
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Destination (URL or route)',
                    helperText: 'Web link, or app://paywall for the Pro page.',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _destination.text = PushDeepLink.paywall,
                    ),
                    icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                    label: const Text('Use pricing page'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _placement,
                  decoration: const InputDecoration(labelText: 'Placement'),
                  items: [
                    for (final p in Placements.all)
                      DropdownMenuItem(
                        value: p,
                        child: Text(Placements.label(p)),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _placement = v ?? _placement),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _countries,
                  decoration: const InputDecoration(
                    labelText: 'Countries (comma-separated; "Global" = all)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priority,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Priority'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DateTile(
                        label: 'Start',
                        value: _start,
                        onPick: (d) => setState(() => _start = d),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateTile(
                        label: 'End',
                        value: _end,
                        onPick: (d) => setState(() => _end = d),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sponsored'),
                  value: _sponsored,
                  onChanged: (v) => setState(() => _sponsored = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show to Pro users'),
                  subtitle: Text(
                    _isPaywall(_destination.text)
                        ? 'Pricing-page banners are always hidden from Pro users.'
                        : _showToPro
                            ? 'Everyone sees this banner.'
                            : 'Only free users see this banner.',
                  ),
                  value: _showToPro &&
                      !_isPaywall(_destination.text),
                  onChanged: _isPaywall(_destination.text)
                      ? null
                      : (v) => setState(() => _showToPro = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Published'),
                  subtitle: const Text('Visible in the app when live'),
                  value: _published,
                  onChanged: (v) => setState(() => _published = v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A reusable date-picker tile used by the marketing editors.
class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;
  const _DateTile({
    required this.label,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_rounded, size: 18)
              : IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () => onPick(null),
                ),
        ),
        child: Text(
          value == null
              ? 'Not set'
              : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }
}
