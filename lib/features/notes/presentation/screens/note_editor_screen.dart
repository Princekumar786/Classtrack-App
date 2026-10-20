import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/models/checklist_item.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/url_launcher_util.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../subjects/domain/subject.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';
import '../../domain/flashcard.dart';
import '../../domain/note.dart';
import '../../domain/note_attachment.dart';
import '../../domain/note_formatting.dart';
import '../providers/note_providers.dart';
import 'flashcard_study_screen.dart';

/// Full-screen note editor. Saves on close if the note is not empty.
class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note? initial;

  /// Optional prefilled content for a brand-new note (e.g. imported from a
  /// file). Ignored when [initial] is provided.
  final String? draftTitle;
  final String? draftBody;

  const NoteEditorScreen({
    super.key,
    this.initial,
    this.draftTitle,
    this.draftBody,
  });

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  static const _uuid = Uuid();

  late final TextEditingController _title;
  late final TextEditingController _body;
  String? _subjectId;
  late bool _pinned;
  int? _color;
  final List<_NoteCheckField> _checklist = [];
  final List<_FlashcardField> _flashcards = [];
  final List<NoteAttachment> _attachments = [];
  bool _uploading = false;
  bool _saved = false;

  // Slash-command menu state.
  int _lastBodyLen = 0;
  bool _slashMenuOpen = false;
  bool _programmaticEdit = false;
  int _slashIndex = -1;
  final FocusNode _bodyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final n = widget.initial;
    _title = TextEditingController(text: n?.title ?? widget.draftTitle ?? '');
    _body = TextEditingController(text: n?.body ?? widget.draftBody ?? '');
    _subjectId = n?.subjectId;
    _pinned = n?.pinned ?? false;
    _color = n?.colorHex;
    _checklist.addAll((n?.checklist ?? const [])
        .map((c) => _NoteCheckField(text: c.text, done: c.done)));
    _flashcards.addAll((n?.flashcards ?? const []).map((f) =>
        _FlashcardField(id: f.id, question: f.question, answer: f.answer)));
    _attachments.addAll(n?.attachments ?? const []);
    _lastBodyLen = _body.text.length;
    _body.addListener(_onBodyChanged);
  }

  @override
  void dispose() {
    _body.removeListener(_onBodyChanged);
    _bodyFocus.dispose();
    _title.dispose();
    _body.dispose();
    for (final c in _checklist) {
      c.dispose();
    }
    for (final f in _flashcards) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _isPro => ref.read(isProProvider);

  /// Ensures the user is Pro before running a smart-notes action; otherwise
  /// opens the paywall. Returns true when the caller may proceed.
  Future<bool> _ensurePro() async {
    if (_isPro) return true;
    return showUpgradePrompt(context, UpgradeReason.smartNotes);
  }

  List<ChecklistItem> _buildChecklist() => _checklist
      .where((c) => c.controller.text.trim().isNotEmpty)
      .map((c) => ChecklistItem(text: c.controller.text.trim(), done: c.done))
      .toList();

  List<Flashcard> _buildFlashcards() => _flashcards
      .map((f) => Flashcard(
            id: f.id,
            question: f.question.text.trim(),
            answer: f.answer.text.trim(),
          ))
      .where((f) => !f.isEmpty)
      .toList();

  void _addCheck() => setState(() {
        _saved = false;
        _checklist.add(_NoteCheckField());
      });

  Widget _checklistSection() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_checklist.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _checklist.length,
                itemBuilder: (_, i) => _checkRow(i, _checklist[i]),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addCheck,
              icon: const Icon(Icons.add_task_rounded, size: 18),
              label: Text(_checklist.isEmpty ? 'Add checklist' : 'Add item'),
              style: TextButton.styleFrom(foregroundColor: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkRow(int i, _NoteCheckField c) {
    final theme = Theme.of(context);
    return Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => c.done = !c.done),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: c.done ? AppColors.primary : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                  color: c.done ? AppColors.primary : theme.dividerColor,
                  width: 2),
            ),
            child: c.done
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: c.controller,
            textCapitalization: TextCapitalization.sentences,
            style: c.done
                ? TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: theme.hintColor)
                : null,
            decoration: const InputDecoration(
              hintText: 'List item',
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close_rounded, size: 18, color: theme.hintColor),
          onPressed: () => setState(() {
            c.dispose();
            _checklist.removeAt(i);
          }),
        ),
      ],
    );
  }

  Future<void> _persist() async {
    if (_saved) return;
    _saved = true;
    final title = _title.text.trim();
    final body = _body.text.trim();
    final checklist = _buildChecklist();
    final flashcards = _buildFlashcards();
    final ctrl = ref.read(noteControllerProvider);
    if (title.isEmpty &&
        body.isEmpty &&
        checklist.isEmpty &&
        flashcards.isEmpty &&
        _attachments.isEmpty) {
      // Nothing to save; delete if it was an existing empty note.
      if (widget.initial != null) await ctrl.delete(widget.initial!.id);
      return;
    }
    if (widget.initial == null) {
      await ctrl.add(Note(
        id: 'new',
        title: title,
        body: body,
        subjectId: _subjectId,
        colorHex: _color,
        pinned: _pinned,
        checklist: checklist,
        flashcards: flashcards,
        attachments: _attachments,
        updatedAt: DateTime.now(),
      ));
    } else {
      await ctrl.update(widget.initial!.copyWith(
        title: title,
        body: body,
        subjectId: _subjectId,
        clearSubject: _subjectId == null,
        colorHex: _color,
        clearColor: _color == null,
        pinned: _pinned,
        checklist: checklist,
        flashcards: flashcards,
        attachments: _attachments,
        updatedAt: DateTime.now(),
      ));
    }
  }

  // ── Slash-command insert menu ───────────────────────────────────────────
  /// Detects a freshly-typed "/" at the start of a line (or after a space) and
  /// pops the insert menu. Ignores slashes inside words like "12/07".
  void _onBodyChanged() {
    final text = _body.text;
    final grew = text.length == _lastBodyLen + 1;
    _lastBodyLen = text.length;
    if (_programmaticEdit || _slashMenuOpen || !grew) return;
    final sel = _body.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final pos = sel.baseOffset;
    if (pos <= 0 || pos > text.length) return;
    if (text[pos - 1] != '/') return;
    if (pos >= 2) {
      final before = text[pos - 2];
      if (before != '\n' && before != ' ') return;
    }
    _slashIndex = pos - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openSlashMenu());
  }

  Future<void> _openSlashMenu() async {
    if (_slashMenuOpen || !mounted) return;
    _slashMenuOpen = true;
    FocusScope.of(context).unfocus();
    final cmd = await showModalBottomSheet<_SlashCmd>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _SlashMenuSheet(isPro: _isPro),
    );
    _slashMenuOpen = false;
    if (!mounted || cmd == null) return;
    // Only link / image / pdf / flashcard require Pro. Text formatting is free.
    if (cmd.pro && !_isPro) {
      final unlocked =
          await showUpgradePrompt(context, UpgradeReason.smartNotes);
      if (!unlocked || !mounted) return;
    }
    _applySlash(cmd);
  }

  void _applySlash(_SlashCmd cmd) {
    final stripped =
        SlashFormatting.stripSlash(_body.text, _slashIndex, _cursorOffset());
    final base = stripped.text;
    final pos = stripped.pos;

    switch (cmd.kind) {
      case _SlashKind.h1:
        _applyLinePrefix(base, pos, '# ');
        break;
      case _SlashKind.h2:
        _applyLinePrefix(base, pos, '## ');
        break;
      case _SlashKind.h3:
        _applyLinePrefix(base, pos, '### ');
        break;
      case _SlashKind.bullet:
        _applyLinePrefix(base, pos, '- ');
        break;
      case _SlashKind.numbered:
        _applyLinePrefix(base, pos, '1. ');
        break;
      case _SlashKind.quote:
        _applyLinePrefix(base, pos, '> ');
        break;
      case _SlashKind.divider:
        _insertBlock(base, pos, '\n---\n');
        break;
      case _SlashKind.checklist:
        _setBody(base, pos);
        _addCheck();
        break;
      case _SlashKind.link:
        _setBody(base, pos);
        _insertLink(pos);
        break;
      case _SlashKind.image:
        _setBody(base, pos);
        _pickImages(camera: false);
        break;
      case _SlashKind.pdf:
        _setBody(base, pos);
        _pickPdfs();
        break;
      case _SlashKind.flashcard:
        _setBody(base, pos);
        _addFlashcard();
        break;
    }
  }

  int _cursorOffset() {
    final sel = _body.selection;
    return sel.isValid ? sel.baseOffset : _body.text.length;
  }

  /// Runs a formatting/insert command from the toolbar (no "/" to strip).
  Future<void> _runToolbar(_SlashCmd cmd) async {
    if (cmd.pro && !_isPro) {
      final unlocked =
          await showUpgradePrompt(context, UpgradeReason.smartNotes);
      if (!unlocked || !mounted) return;
    }
    _slashIndex = -1;
    _applySlash(cmd);
  }

  /// Formatting bar pinned under the editor (sits right above the keyboard).
  Widget _toolbar(ThemeData theme) {
    _SlashCmd cmd(_SlashKind k) => _slashCommands.firstWhere((c) => c.kind == k);
    Widget btn(_SlashKind k, IconData icon, String tip) {
      final c = cmd(k);
      final locked = c.pro && !ref.watch(isProProvider);
      return Tooltip(
        message: locked ? '$tip (Pro)' : tip,
        child: InkResponse(
          onTap: () => _runToolbar(c),
          radius: 22,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 21, color: theme.iconTheme.color),
                if (locked)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Icon(Icons.lock_rounded,
                        size: 10, color: theme.hintColor),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              btn(_SlashKind.h1, Icons.title_rounded, 'Heading'),
              btn(_SlashKind.bullet, Icons.format_list_bulleted_rounded,
                  'Bullet list'),
              btn(_SlashKind.numbered, Icons.format_list_numbered_rounded,
                  'Numbered list'),
              btn(_SlashKind.checklist, Icons.checklist_rounded, 'Checklist'),
              btn(_SlashKind.quote, Icons.format_quote_rounded, 'Quote'),
              btn(_SlashKind.divider, Icons.horizontal_rule_rounded,
                  'Divider'),
              VerticalDivider(
                  width: 16, indent: 12, endIndent: 12,
                  color: theme.dividerColor),
              btn(_SlashKind.link, Icons.link_rounded, 'Link'),
              btn(_SlashKind.image, Icons.image_outlined, 'Image'),
              btn(_SlashKind.pdf, Icons.picture_as_pdf_outlined, 'PDF'),
              btn(_SlashKind.flashcard, Icons.style_outlined, 'Flashcard'),
            ],
          ),
        ),
      ),
    );
  }

  void _applyLinePrefix(String base, int pos, String prefix) {
    final r = SlashFormatting.linePrefix(base, pos, prefix);
    _setBody(r.text, r.cursor);
  }

  void _insertBlock(String base, int pos, String block) {
    final r = SlashFormatting.insertBlock(base, pos, block);
    _setBody(r.text, r.cursor);
  }

  void _setBody(String text, int cursor) {
    _programmaticEdit = true;
    _body.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor.clamp(0, text.length)),
    );
    _lastBodyLen = text.length;
    _programmaticEdit = false;
    _saved = false;
    _bodyFocus.requestFocus();
  }

  /// Prompts for link text + URL and inserts a Markdown link `[text](url)` at
  /// [pos].
  Future<void> _insertLink(int pos) async {
    final result = await showDialog<_LinkResult>(
      context: context,
      builder: (_) => const _LinkDialog(),
    );
    if (result == null || !mounted) return;
    final url = result.url.trim();
    if (url.isEmpty) return;
    final label = result.label.trim().isEmpty ? url : result.label.trim();
    final md = '[$label]($url)';
    final base = _body.text;
    final at = pos.clamp(0, base.length);
    _setBody(base.replaceRange(at, at, md), at + md.length);
  }

  // ── Attachments (images + PDFs) ─────────────────────────────────────────
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _errText(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _pickImages({required bool camera}) async {
    if (!await _ensurePro()) return;
    final service = ref.read(noteAttachmentServiceProvider);
    if (service == null) return;
    setState(() => _uploading = true);
    try {
      final added = camera
          ? await service.pickAndUploadCameraImage()
          : await service.pickAndUploadGalleryImages();
      if (added.isNotEmpty) {
        setState(() {
          _saved = false;
          _attachments.addAll(added);
        });
      }
    } catch (e) {
      _snack('Upload failed: ${_errText(e)}');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickPdfs() async {
    if (!await _ensurePro()) return;
    final service = ref.read(noteAttachmentServiceProvider);
    if (service == null) return;
    setState(() => _uploading = true);
    try {
      final added = await service.pickAndUploadPdfs();
      if (added.isNotEmpty) {
        setState(() {
          _saved = false;
          _attachments.addAll(added);
        });
      }
    } catch (e) {
      _snack('Upload failed: ${_errText(e)}');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeAttachment(NoteAttachment a) async {
    setState(() {
      _saved = false;
      _attachments.remove(a);
    });
    await ref.read(noteAttachmentServiceProvider)?.deleteByPath(a.storagePath);
  }

  Widget _attachmentsSection() {
    final theme = Theme.of(context);
    final images = _attachments.where((a) => a.isImage).toList();
    final pdfs = _attachments.where((a) => a.isPdf).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file_rounded, size: 18, color: theme.hintColor),
              const SizedBox(width: 8),
              Text('Attachments', style: theme.textTheme.titleSmall),
              if (!ref.watch(isProProvider)) ...[
                const SizedBox(width: 8),
                _proTag(theme),
              ],
              const Spacer(),
              if (_uploading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _addChip(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: _uploading ? null : () => _pickImages(camera: false)),
              _addChip(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  onTap: _uploading ? null : () => _pickImages(camera: true)),
              _addChip(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'PDF',
                  onTap: _uploading ? null : _pickPdfs),
            ],
          ),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final a in images) _imageThumb(a)],
            ),
          ],
          if (pdfs.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final a in pdfs) _pdfRow(a),
          ],
        ],
      ),
    );
  }

  Widget _proTag(ThemeData theme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text('PRO',
            style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.primary, fontWeight: FontWeight.w700)),
      );

  Widget _addChip(
      {required IconData icon,
      required String label,
      required VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(label,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageThumb(NoteAttachment a) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          settings: const RouteSettings(name: 'Note Image'),
          builder: (_) => NoteImageViewer(url: a.url, name: a.name))),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              a.url,
              width: 92,
              height: 92,
              fit: BoxFit.cover,
              // Decode at the tile's pixel size (not full camera resolution) to
              // slash bitmap memory — addresses the Play "bitmap downsampling"
              // recommendation. 276 ≈ 92dp × 3 (max sensible DPR).
              cacheWidth: 276,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : Container(
                      width: 92,
                      height: 92,
                      color: AppColors.lavenderTint,
                      child: const Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                    ),
              errorBuilder: (_, __, ___) => Container(
                width: 92,
                height: 92,
                color: AppColors.lavenderTint,
                child: const Icon(Icons.broken_image_rounded),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: _removeBadge(() => _removeAttachment(a)),
          ),
        ],
      ),
    );
  }

  Widget _pdfRow(NoteAttachment a) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf_rounded, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => openUrl(context, a.url),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                      a.prettySize.isEmpty
                          ? 'Tap to open'
                          : '${a.prettySize} · Tap to open',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: theme.hintColor),
            onPressed: () => _removeAttachment(a),
          ),
        ],
      ),
    );
  }

  Widget _removeBadge(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close_rounded, size: 15, color: Colors.white),
      ),
    );
  }

  // ── Flashcards ──────────────────────────────────────────────────────────
  Future<void> _addFlashcard() async {
    if (!await _ensurePro()) return;
    if (!mounted) return;
    setState(() {
      _saved = false;
      _flashcards.add(_FlashcardField(id: _uuid.v4()));
    });
  }

  void _openStudy() {
    final cards = _buildFlashcards();
    if (cards.isEmpty) {
      _snack('Add a question and answer to a flashcard first.');
      return;
    }
    final title = _title.text.trim().isEmpty ? 'Study' : _title.text.trim();
    Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'Flashcard Study'),
        builder: (_) => FlashcardStudyScreen(cards: cards, title: title)));
  }

  Widget _flashcardsSection() {
    final theme = Theme.of(context);
    final ready = _buildFlashcards().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.style_rounded, size: 18, color: theme.hintColor),
              const SizedBox(width: 8),
              Text('Flashcards', style: theme.textTheme.titleSmall),
              if (!ref.watch(isProProvider)) ...[
                const SizedBox(width: 8),
                _proTag(theme),
              ],
              if (ready > 0) ...[
                const SizedBox(width: 6),
                Text('($ready)', style: theme.textTheme.bodySmall),
              ],
              const Spacer(),
              if (ready > 0)
                TextButton.icon(
                  onPressed: _openStudy,
                  icon: const Icon(Icons.school_rounded, size: 18),
                  label: const Text('Study'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < _flashcards.length; i++)
            _flashcardRow(i, _flashcards[i]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addFlashcard,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                  _flashcards.isEmpty ? 'Add flashcard' : 'Add another card'),
              style: TextButton.styleFrom(foregroundColor: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _flashcardRow(int i, _FlashcardField f) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('Card ${i + 1}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.primary, letterSpacing: 1)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon:
                    Icon(Icons.close_rounded, size: 18, color: theme.hintColor),
                onPressed: () => setState(() {
                  f.dispose();
                  _flashcards.removeAt(i);
                  _saved = false;
                }),
              ),
            ],
          ),
          TextField(
            controller: f.question,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => _saved = false,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              hintText: 'Question',
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          Divider(color: theme.dividerColor, height: 8),
          TextField(
            controller: f.answer,
            textCapitalization: TextCapitalization.sentences,
            maxLines: null,
            onChanged: (_) => _saved = false,
            style: theme.textTheme.bodyMedium,
            decoration: const InputDecoration(
              hintText: 'Answer',
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }

  String _subjectName(List<Subject> subjects) {
    if (_subjectId == null) return 'No subject';
    for (final s in subjects) {
      if (s.id == _subjectId) return s.name;
    }
    return 'No subject';
  }

  Widget _metaChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.brightness == Brightness.light
          ? AppColors.lavenderSoft
          : theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: theme.hintColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 18, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorChip(VoidCallback onTap) {
    final theme = Theme.of(context);
    final color = _color != null ? Color(_color!) : null;
    return Material(
      color: theme.brightness == Brightness.light
          ? AppColors.lavenderSoft
          : theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color ?? Colors.transparent,
                  shape: BoxShape.circle,
                  border: color == null
                      ? Border.all(color: theme.dividerColor, width: 1.5)
                      : null,
                ),
                child: color == null
                    ? Icon(Icons.palette_outlined,
                        size: 11, color: theme.hintColor)
                    : null,
              ),
              const SizedBox(width: 8),
              Text('Color', style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSubjectPicker(List<Subject> subjects) async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(4)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Subject', style: theme.textTheme.titleLarge),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    ListTile(
                      leading:
                          Icon(Icons.block_rounded, color: theme.hintColor),
                      title: const Text('No subject'),
                      trailing: _subjectId == null
                          ? const Icon(Icons.check_rounded,
                              color: AppColors.primary)
                          : null,
                      onTap: () {
                        setState(() => _subjectId = null);
                        Navigator.pop(ctx);
                      },
                    ),
                    for (final s in subjects)
                      ListTile(
                        leading: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                              color: Color(s.colorHex), shape: BoxShape.circle),
                        ),
                        title: Text(s.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: _subjectId == s.id
                            ? const Icon(Icons.check_rounded,
                                color: AppColors.primary)
                            : null,
                        onTap: () {
                          setState(() => _subjectId = s.id);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openColorPicker() async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        Widget dot(int? hex) {
          final selected = _color == hex;
          return GestureDetector(
            onTap: () {
              setState(() => _color = hex);
              Navigator.pop(ctx);
            },
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: hex == null ? Colors.transparent : Color(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : (hex == null ? theme.dividerColor : Colors.transparent),
                  width: selected ? 3 : (hex == null ? 1.5 : 0),
                ),
              ),
              child: hex == null
                  ? Icon(Icons.not_interested_rounded, color: theme.hintColor)
                  : (selected
                      ? const Icon(Icons.check_rounded, color: Colors.white)
                      : null),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                        color: theme.dividerColor,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                Text('Note color', style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    dot(null),
                    for (final c in AppColors.subjectPalette) dot(c.toARGB32()),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) => _persist(),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      semanticLabel: 'Save and close',
                      onTap: () async {
                        await _persist();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _body,
                        builder: (_, v, __) {
                          final words = RegExp(r'\S+')
                              .allMatches(v.text)
                              .length;
                          final edited = widget.initial?.updatedAt;
                          return Text(
                            [
                              '$words ${words == 1 ? 'word' : 'words'}',
                              if (edited != null)
                                'Edited ${DateUtilsX.prettyDate(edited)}',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.hintColor),
                          );
                        },
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _pinned = !_pinned),
                      icon: Icon(
                        _pinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        color: _pinned ? AppColors.primary : theme.hintColor,
                      ),
                    ),
                    if (widget.initial != null)
                      IconButton(
                        onPressed: () async {
                          _saved = true; // prevent re-save on pop
                          await ref.read(noteControllerProvider).deleteNote(
                              widget.initial!
                                  .copyWith(attachments: _attachments));
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: AppColors.danger),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _metaChip(
                        icon: Icons.folder_open_rounded,
                        label: _subjectName(subjects),
                        onTap: () => _openSubjectPicker(subjects),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _colorChip(() => _openColorPicker()),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: TextField(
                          controller: _body,
                          focusNode: _bodyFocus,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: null,
                          minLines: 8,
                          keyboardType: TextInputType.multiline,
                          style:
                              theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                          decoration: const InputDecoration(
                            hintText:
                                'Start writing… type / for headings, lists & more',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ),
                      _checklistSection(),
                      _attachmentsSection(),
                      _flashcardsSection(),
                    ],
                  ),
                ),
              ),
              _toolbar(theme),
            ],
          ),
        ),
      ),
    );
  }
}

/// Editable checklist row backing for notes (text field + done flag).
class _NoteCheckField {
  final TextEditingController controller;
  bool done;
  _NoteCheckField({String text = '', this.done = false})
      : controller = TextEditingController(text: text);
  void dispose() => controller.dispose();
}

/// Editable flashcard row backing (question + answer controllers + stable id).
class _FlashcardField {
  final String id;
  final TextEditingController question;
  final TextEditingController answer;
  _FlashcardField({required this.id, String question = '', String answer = ''})
      : question = TextEditingController(text: question),
        answer = TextEditingController(text: answer);
  void dispose() {
    question.dispose();
    answer.dispose();
  }
}

/// The kinds of things the "/" insert menu can add to a note.
enum _SlashKind {
  h1,
  h2,
  h3,
  bullet,
  numbered,
  quote,
  divider,
  checklist,
  link,
  image,
  pdf,
  flashcard,
}

class _SlashCmd {
  final _SlashKind kind;
  final IconData icon;
  final String title;
  final String subtitle;

  /// Whether this command requires ClassTrack Pro. Text formatting is free;
  /// links, media and flashcards are Pro.
  final bool pro;

  const _SlashCmd(this.kind, this.icon, this.title, this.subtitle,
      {this.pro = false});
}

const List<_SlashCmd> _slashCommands = [
  _SlashCmd(_SlashKind.h1, Icons.title_rounded, 'Heading', 'Big section title'),
  _SlashCmd(
      _SlashKind.h2, Icons.title_rounded, 'Heading 2', 'Medium subheading'),
  _SlashCmd(
      _SlashKind.h3, Icons.title_rounded, 'Heading 3', 'Small subheading'),
  _SlashCmd(_SlashKind.bullet, Icons.format_list_bulleted_rounded,
      'Bullet list', 'Start a bulleted item'),
  _SlashCmd(_SlashKind.numbered, Icons.format_list_numbered_rounded,
      'Numbered list', 'Start a numbered item'),
  _SlashCmd(_SlashKind.quote, Icons.format_quote_rounded, 'Quote',
      'Highlight a passage'),
  _SlashCmd(_SlashKind.divider, Icons.horizontal_rule_rounded, 'Divider',
      'Separate sections'),
  _SlashCmd(_SlashKind.checklist, Icons.checklist_rounded, 'Checklist item',
      'Add a to-do checkbox'),
  _SlashCmd(_SlashKind.link, Icons.link_rounded, 'Link', 'Insert a web link',
      pro: true),
  _SlashCmd(_SlashKind.image, Icons.image_rounded, 'Image', 'Attach a photo',
      pro: true),
  _SlashCmd(_SlashKind.pdf, Icons.picture_as_pdf_rounded, 'PDF', 'Attach a PDF',
      pro: true),
  _SlashCmd(_SlashKind.flashcard, Icons.style_rounded, 'Flashcard',
      'Add a study card',
      pro: true),
];

/// Bottom-sheet list of slash commands. Text formatting is free; link / image
/// / pdf / flashcard show a small lock for non-Pro users. Returns the chosen
/// [_SlashCmd] via Navigator.pop; the caller handles the paywall. Kept simple —
/// no search box, so the keyboard never pops up over the list.
class _SlashMenuSheet extends StatelessWidget {
  final bool isPro;
  const _SlashMenuSheet({required this.isPro});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final free = _slashCommands.where((c) => !c.pro).toList();
    final pro = _slashCommands.where((c) => c.pro).toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  if (free.isNotEmpty) _groupLabel(theme, 'FORMAT'),
                  for (final c in free) _tile(context, c),
                  if (pro.isNotEmpty) _groupLabel(theme, 'INSERT'),
                  for (final c in pro) _tile(context, c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupLabel(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Text(text,
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700)),
      );

  Widget _tile(BuildContext context, _SlashCmd c) {
    final locked = c.pro && !isPro;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(c.icon, color: AppColors.primary, size: 20),
      ),
      title: Text(c.title),
      subtitle: Text(c.subtitle),
      trailing: locked
          ? const Icon(Icons.lock_outline_rounded, size: 18)
          : (c.pro ? null : const Icon(Icons.chevron_right_rounded, size: 18)),
      onTap: () => Navigator.pop(context, c),
    );
  }
}

/// Result of the link dialog: a display [label] and destination [url].
class _LinkResult {
  final String label;
  final String url;
  const _LinkResult(this.label, this.url);
}

/// Small dialog that collects link text + URL for the "/link" command.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog();

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _label = TextEditingController();
  final _url = TextEditingController();
  bool _touched = false;

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  bool get _valid => _url.text.trim().isNotEmpty;

  void _submit() {
    setState(() => _touched = true);
    if (!_valid) return;
    Navigator.of(context).pop(_LinkResult(_label.text, _url.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Insert link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Text (optional)',
              hintText: 'e.g. Lecture slides',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'URL',
              hintText: 'https://…',
              errorText: _touched && !_valid ? 'Enter a link URL' : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: const Text('Insert'),
        ),
      ],
    );
  }
}
