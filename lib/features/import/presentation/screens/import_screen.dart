import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:classtrack/core/theme/app_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../subscription/presentation/screens/paywall_screen.dart';
import '../../../tips/domain/discoverable_feature.dart';
import '../../../tips/presentation/providers/tips_providers.dart';
import '../../domain/parsed_schedule.dart';
import '../providers/import_providers.dart';
import 'review_screen.dart';

class ImportScreen extends ConsumerStatefulWidget {
  /// When true, the AI photo/PDF/text import is offered free of charge and the
  /// Pro paywall is skipped. Used by the Attendance tab, where uploading a
  /// timetable photo is a free onboarding path for new students.
  final bool freeAccess;

  const ImportScreen({super.key, this.freeAccess = false});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _loading = false;
  final _text = TextEditingController();
  final _scrollController = ScrollController();
  final _textFocus = FocusNode();

  /// Inline, recoverable guidance shown when the AI couldn't read a timetable.
  /// Stays on screen (unlike a SnackBar) with concrete fix-it tips and a
  /// one-tap "paste text" fallback, turning a dead-end into a recovery path.
  _ImportHint? _hint;

  /// Where this screen was launched from — logged into the import funnel.
  String get _source =>
      widget.freeAccess ? 'attendance_onboarding' : 'schedule';

  AnalyticsService get _analytics => ref.read(analyticsProvider);

  /// Rotating, friendly status lines shown in the loading overlay so the wait
  /// feels like progress instead of an indefinite spinner.
  static const List<String> _statusMessages = [
    'Uploading your timetable…',
    'Reading it with AI…',
    'Finding your classes…',
    'Almost there…',
  ];
  Timer? _statusTimer;
  int _statusIndex = 0;

  @override
  void initState() {
    super.initState();
    _analytics.importOpened(_source);
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _scrollController.dispose();
    _textFocus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _startStatusRotator() {
    _statusIndex = 0;
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(
        () => _statusIndex = (_statusIndex + 1) % _statusMessages.length,
      );
    });
  }

  void _stopStatusRotator() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  void _fail(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Turns a thrown error into a friendly, actionable outcome — and NEVER
  /// leaks a raw exception/stack trace to the user. Returns a coarse reason
  /// category for the import funnel. Firebase Functions errors carry a `code`
  /// we can map: the monthly AI quota (`resource-exhausted`) routes to the Pro
  /// paywall, a rejected/garbled input shows the inline "not a timetable"
  /// helper, and connectivity blips get a retry hint.
  Future<String> _handleError(Object error) async {
    if (!mounted) return 'unknown';
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'resource-exhausted':
          await _showLimitReached();
          return 'limit_reached';
        case 'unauthenticated':
          _fail('Please sign in to use AI import.');
          return 'unauthenticated';
        case 'invalid-argument':
        case 'failed-precondition':
          _showNotATimetableHint();
          return 'not_a_timetable';
        case 'unavailable':
        case 'deadline-exceeded':
          _fail('Network hiccup — check your connection and try again.');
          return 'network';
      }
      _fail('Import failed. Please try again.');
      return error.code;
    }
    _fail('Import failed. Please try again.');
    return 'unknown';
  }

  /// Shows the inline, recoverable "we couldn't read a timetable" card with
  /// fix-it tips and a "paste text" shortcut, and scrolls it into view.
  void _showNotATimetableHint() {
    if (!mounted) return;
    setState(() {
      _hint = const _ImportHint(
        title: 'We couldn’t read a timetable there',
        message:
            'That didn’t look like a class schedule. Try again with a '
            'clearer image, or paste your timetable as text below.',
        tips: [
          'Make sure every row and column is visible',
          'Avoid glare, blur and steep angles',
          'Good, even lighting helps the AI read it',
        ],
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Clears the inline hint, scrolls to the paste-text field and focuses it.
  void _focusPasteText() {
    setState(() => _hint = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
      _textFocus.requestFocus();
    });
  }

  /// Free monthly AI allowance is used up: offer the Pro upgrade and, if the
  /// user accepts, open the paywall/pricing screen.
  Future<void> _showLimitReached() async {
    if (!mounted) return;
    final upgrade = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.workspace_premium_rounded,
          color: AppColors.primary,
        ),
        title: const Text('You’ve reached your free AI limit'),
        content: const Text(
          'You’ve used all your free AI imports for this month. Upgrade to '
          'ClassTrack Pro for unlimited timetable imports and AI help — or try '
          'again next month.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Upgrade to Pro'),
          ),
        ],
      ),
    );
    if (upgrade == true && mounted) {
      await showPaywall(context);
    }
  }

  Future<void> _run(
    String method,
    Future<ParsedSchedule> Function() task,
  ) async {
    final repo = ref.read(importRepositoryProvider);
    if (repo == null) {
      _fail('Please sign in first.');
      return;
    }
    if (!repo.isConfigured) {
      _fail(
        'The AI assistant isn’t available right now. Please try again later.',
      );
      return;
    }
    // AI photo/PDF/text import is normally a Pro feature. Free users can still
    // build a timetable manually or via the chat assistant's monthly free
    // messages. When [freeAccess] is set (e.g. launched from the Attendance
    // tab) the paywall is skipped so photo upload is free.
    if (!widget.freeAccess && !ref.read(isProProvider)) {
      final becamePro = await showPaywall(context);
      if (!becamePro || !mounted) return;
    }
    setState(() {
      _loading = true;
      _hint = null; // clear any previous recovery hint on a fresh attempt
    });
    _startStatusRotator();
    _analytics.importParseStarted(method);
    try {
      final result = await task();
      if (!mounted) return;
      if (result.isEmpty) {
        _analytics.importParseFailed(method, 'empty');
        _showNotATimetableHint();
        return;
      }
      _analytics.importParseSucceeded(
        method,
        subjects: result.subjects.length,
        confidence: result.confidence,
      );
      // Feature discovery: photo/AI timetable import has now been tried.
      ref.read(featureUsageProvider.notifier).markUsed(FeatureId.photoImport);
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ReviewScreen(schedule: result)));
    } catch (e) {
      final reason = await _handleError(e);
      // Guard: _handleError may await a paywall/dialog, during which the user
      // can leave this screen. Touching `ref` (via _analytics) after that would
      // throw "Cannot use ref after the widget was disposed".
      if (mounted) _analytics.importParseFailed(method, reason);
    } finally {
      _stopStatusRotator();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final method = source == ImageSource.camera ? 'camera' : 'gallery';
    _analytics.importMethodSelected(method);
    final picker = ImagePicker();
    // Downsample at capture/decode time: cap the longest edge and re-encode at
    // 85% quality. This keeps timetable text legible for the AI while slashing
    // memory use (no full-resolution bitmap is decoded), cutting the base64
    // upload size, and removing the jank on lower-end devices. Also addresses
    // the Play Console "bitmap downsampling" recommendation for image loading.
    final file = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _run(
      method,
      () => ref.read(importRepositoryProvider)!.parseImage(bytes),
    );
  }

  Future<void> _pickPdf() async {
    _analytics.importMethodSelected('pdf');
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true, // load bytes in-memory so we can send them to the AI
      );
    } catch (e) {
      _fail('Could not open the file picker: $e');
      return;
    }
    if (result == null || result.files.isEmpty) return; // user cancelled

    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) {
      _fail('Couldn’t read that PDF. Please try another file.');
      return;
    }
    // The backend caps uploads at 10 MB; reject oversized PDFs up front with a
    // clear message instead of a generic server error.
    const maxBytes = 10 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      _fail('That PDF is too large (max 10 MB). Try exporting a smaller file.');
      return;
    }
    await _run(
      'pdf',
      () => ref.read(importRepositoryProvider)!.parsePdf(bytes),
    );
  }

  Future<void> _parseText() async {
    _analytics.importMethodSelected('text');
    if (_text.text.trim().length < 6) {
      _fail('Paste a bit more of your timetable first.');
      return;
    }
    await _run(
      'text',
      () => ref.read(importRepositoryProvider)!.parseText(_text.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('AI schedule import')),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _loading,
            child: ListView(
              controller: _scrollController,
              // Include the bottom system inset so the last control (and the
              // "Parse text" button) never hides behind the Android gesture /
              // navigation bar under edge-to-edge on tall/notched phones.
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                if (_hint != null) ...[
                  _hintCard(theme, _hint!),
                  const SizedBox(height: 20),
                ],
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.freeAccess
                              ? 'Upload a timetable photo, a PDF, or paste text — '
                                    'free. You’ll review everything before it’s saved.'
                              : 'Upload a timetable photo or PDF, or paste text. '
                                    'You’ll review everything before it’s saved.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _option(
                  icon: PhosphorIcons.camera(),
                  title: 'Take a photo',
                  subtitle: 'Snap your printed timetable',
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                _option(
                  icon: PhosphorIcons.image(),
                  title: 'Choose from gallery',
                  subtitle: 'A screenshot or saved image',
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
                _option(
                  icon: PhosphorIcons.filePdf(),
                  title: 'Upload a PDF',
                  subtitle: 'No photo? Import your timetable PDF instead',
                  onTap: _pickPdf,
                ),
                const SizedBox(height: 24),
                Text('Or paste text', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _text,
                  focusNode: _textFocus,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText:
                        'Mon 9-10 DBMS Room 204\nMon 10-11 OS Lab 3\nWed 9-10 DBMS Room 204 ...',
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _parseText,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Parse text'),
                ),
              ],
            ),
          ),
          if (_loading) _loadingOverlay(theme),
        ],
      ),
    );
  }

  /// Full-screen, dimmed overlay shown while the AI is parsing. Gives clear,
  /// centred feedback (with rotating status text) no matter which upload button
  /// the user tapped — instead of a tiny spinner buried at the bottom of the
  /// list that scrolls out of view.
  Widget _loadingOverlay(ThemeData theme) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _statusMessages[_statusIndex],
                    key: ValueKey<int>(_statusIndex),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This can take a few seconds.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Inline, recoverable guidance card (see [_ImportHint]). Unlike a SnackBar
  /// it stays put with concrete fix-it tips and a one-tap "paste text" escape
  /// hatch, so a failed photo becomes a path forward instead of a dead-end.
  Widget _hintCard(ThemeData theme, _ImportHint hint) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.image_not_supported_outlined,
                color: AppColors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(hint.title, style: theme.textTheme.titleMedium),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _hint = null),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(hint.message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          ...hint.tips.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _focusPasteText,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Paste text instead'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _option({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline, recoverable guidance shown on the import screen when the AI couldn't
/// read a timetable — a title, a short message and a few concrete fix-it tips.
class _ImportHint {
  final String title;
  final String message;
  final List<String> tips;
  const _ImportHint({
    required this.title,
    required this.message,
    required this.tips,
  });
}
