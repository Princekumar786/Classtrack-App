import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/media_asset.dart';
import '../providers/cms_media_providers.dart';

String? _contentTypeForExt(String? ext) {
  switch ((ext ?? '').toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'svg':
      return 'image/svg+xml';
    default:
      return null;
  }
}

/// Picks an image file and uploads it to the media library. Returns the new
/// asset's URL, or null if cancelled/failed (a snackbar explains failures).
Future<String?> pickAndUploadMedia(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(mediaRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  if (repo == null) return null;
  final res = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.first;
  final bytes = f.bytes;
  if (bytes == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not read file.')),
    );
    return null;
  }
  try {
    final asset = await repo.upload(
      bytes: bytes,
      filename: f.name,
      contentType: _contentTypeForExt(f.extension),
    );
    messenger.showSnackBar(SnackBar(content: Text('Uploaded ${asset.name} ✓')));
    return asset.url;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Upload failed: $e'),
        backgroundColor: AppColors.danger,
      ),
    );
    return null;
  }
}

/// Opens the media library as a picker; returns the selected asset URL or null.
Future<String?> showMediaPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const FractionallySizedBox(
      heightFactor: 0.85,
      child: _MediaLibraryBody(pickMode: true),
    ),
  );
}

/// The CMS Media library screen (browse + upload + delete).
class CmsMediaScreen extends StatelessWidget {
  const CmsMediaScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _MediaLibraryBody(pickMode: false);
}

class _MediaLibraryBody extends ConsumerStatefulWidget {
  /// When true, tapping a tile returns its URL (picker); actions are hidden.
  final bool pickMode;
  const _MediaLibraryBody({required this.pickMode});

  @override
  ConsumerState<_MediaLibraryBody> createState() => _MediaLibraryBodyState();
}

class _MediaLibraryBodyState extends ConsumerState<_MediaLibraryBody> {
  bool _busy = false;

  Future<void> _upload() async {
    setState(() => _busy = true);
    await pickAndUploadMedia(context, ref);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(cmsMediaProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Text(
                widget.pickMode ? 'Choose media' : 'Media',
                style: theme.textTheme.headlineSmall,
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: _busy ? null : _upload,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_rounded),
                label: Text(_busy ? 'Uploading…' : 'Upload image'),
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) => Center(
              child: Text(
                'Failed to load media.\n$e',
                textAlign: TextAlign.center,
              ),
            ),
            data: (assets) {
              if (assets.isEmpty) {
                return Center(
                  child: Text(
                    'No media yet. Upload an image to get started.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.82,
                ),
                itemCount: assets.length,
                itemBuilder: (_, i) => _MediaTile(
                  asset: assets[i],
                  pickMode: widget.pickMode,
                  onPick: () => Navigator.of(context).pop(assets[i].url),
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: assets[i].url));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('URL copied')));
                  },
                  onDelete: () => _confirmDelete(assets[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(MediaAsset a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete media?'),
        content: Text(
          'Delete "${a.name}"? Resources/banners still using this URL will '
          'show a broken image.',
        ),
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
    if (ok == true) {
      await ref.read(mediaRepositoryProvider)?.delete(a);
    }
  }
}

class _MediaTile extends StatelessWidget {
  final MediaAsset asset;
  final bool pickMode;
  final VoidCallback onPick;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  const _MediaTile({
    required this.asset,
    required this.pickMode,
    required this.onPick,
    required this.onCopy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: pickMode ? onPick : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: softCard(context, radius: 14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: theme.scaffoldBackgroundColor,
                child: Image.network(
                  asset.url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      color: AppColors.danger,
                    ),
                  ),
                  loadingBuilder: (c, child, p) => p == null
                      ? child
                      : const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                        Text(
                          prettyBytes(asset.size),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pickMode)
                    IconButton(
                      tooltip: 'Use this',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      onPressed: onPick,
                    )
                  else ...[
                    IconButton(
                      tooltip: 'Copy URL',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.link_rounded, size: 18),
                      onPressed: onCopy,
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: onDelete,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
