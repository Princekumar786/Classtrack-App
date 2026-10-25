import 'dart:async';

import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:classtrack/core/theme/app_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../services/gemini_service.dart' show sniffMimeType;
import '../../../chat/domain/ai_errors.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';
import '../../../tips/domain/discoverable_feature.dart';
import '../../../tips/presentation/providers/tips_providers.dart';
import '../../data/import_draft_store.dart';
import '../../domain/parsed_schedule.dart';
import '../providers/import_providers.dart';
import '../widgets/import_draft_banner.dart';
import 'review_screen.dart';

class ImportScreen extends ConsumerStatefulWidget {
  /// Kept for the import funnel (`source` = attendance_onboarding vs
  /// schedule). Every entry point gets the same 2 free scans, which the server
  /// enforces; this flag no longer changes access.
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
  /// we can map: the free scan allowance (`resource-exhausted`) routes to the
  /// Pro upgrade prompt, a rejected/garbled input shows the inline "not a
  /// timetable" helper, and connectivity blips get a retry hint.
  Future<String> _handleError(Object error) async {
    if (!mounted) return 'unknown';
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'resource-exhausted':
          // Only the free allowance is an "upgrade" moment. The daily safety
          // cap (Pro) or a server rate limit must never show the paywall.
          if (aiErrorReason(error) == 'rate_limit') {
            _fail('You’ve hit today’s import limit. Please try again tomorrow.');
            return 'daily_cap';
          }
          if (aiErrorReason(error) == null) {
            // No quota reason = the server itself was overloaded (Cloud Run).
            _fail('Lots of students are importing right now. Please try again in a minute.');
            return 'busy';
          }
          await _showLimitReached();
          return 'limit_reached';
        case 'unauthenticated':
          _fail('Please sign in to use AI import.');
          return 'unauthenticated';
        case 'invalid-argument':
        case 'failed-precondition':
          if (aiErrorReason(error) == 'email_unverified') {
            _fail('Verify your email address to use free schedule scans.');
            return 'email_unverified';
          }
          _showNotATimetableHint();
          return 'not_a_timetable';
        case 'unavailable':
          _fail(aiErrorReason(error) == 'busy'
              ? 'Lots of students are importing right now. Please try again in a minute.'
              : 'The AI is busy right now — please try again in a moment.');
          return aiErrorReason(error) == 'busy' ? 'busy' : 'unavailable';
        case 'deadline-exceeded':
          _fail('That took too long. Try again, or use a clearer photo or a '
              'smaller PDF.');
          return 'timeout';
      }
      _fail('Import failed. Please try again.');
      return error.code;
    }
    if (error is FirebaseException) {
      // e.g. the large-file upload to Storage failed (offline mid-upload).
      _fail('Couldn’t upload the file — check your connection and try again.');
      return 'upload';
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

  /// The free schedule-scan allowance (a one-time, lifetime allowance — it does
  /// NOT reset monthly) is used up: show the standard upgrade prompt, which
  /// opens the pricing page tailored to scans.
  Future<void> _showLimitReached() async {
    if (!mounted) return;
    await showUpgradePrompt(context, UpgradeReason.timetableScans);
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
    // Free users get 2 AI scans in total. The SERVER counts and enforces them
    // (parseSchedule → enforceFreeAllowance) and answers `free_limit` once
    // they're used, which [_handleError] turns into the upgrade prompt. Do
    // NOT gate on Pro here: an app-side `requirePro` check used to show the
    // upgrade prompt before the first scan, so most new students never got
    // their 2 free scans (only the Attendance/Home entry points skipped it).
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
      // Keep the result safe BEFORE the review opens: if the app is killed or
      // swiped away now, the scan isn't lost and can be resumed.
      await ref.read(importDraftProvider.notifier).save(result);
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(settings: const RouteSettings(name: 'Review'), builder: (_) => ReviewScreen(schedule: result)));
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
    var bytes = picked.bytes;
    // Some Android pickers return a path but no in-memory bytes (notably for
    // larger files) — read from disk instead of failing.
    if ((bytes == null || bytes.isEmpty) && picked.path != null) {
      try {
        bytes = await File(picked.path!).readAsBytes();
      } catch (_) {}
    }
    if (bytes == null || bytes.isEmpty) {
      _fail('Couldn’t read that PDF. Please try another file.');
      return;
    }
    if (sniffMimeType(bytes, '') != 'application/pdf') {
      _fail('That file isn’t a valid PDF. Please pick a PDF timetable.');
      return;
    }
    // The backend caps uploads at 10 MB; reject oversized PDFs up front with a
    // clear message instead of a generic server error.
    const maxBytes = 10 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      _fail('That PDF is too large (max 10 MB). Try exporting a smaller file.');
      return;
    }
    final pdf = bytes;
    await _run(
      'pdf',
      () => ref.read(importRepositoryProvider)!.parsePdf(pdf),
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
                // An unsaved import from before: offer it first, so the
                // student doesn't spend another scan re-doing it.
                const ImportDraftBanner(padding: EdgeInsets.only(bottom: 20)),
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
                          widget.freeAccess || !ref.watch(isProProvider)
                              ? 'Upload a timetable photo, a PDF, or paste text. '
                                    'Your first 2 scans are free. You’ll review '
                                    'everything before it’s saved.'
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
