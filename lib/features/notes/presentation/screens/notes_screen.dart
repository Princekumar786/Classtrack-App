import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/checklist_item.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/url_launcher_util.dart';
import '../../../../shared/widgets/feature_tip_banner.dart';
import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../subjects/domain/subject.dart';
import '../../../exams/domain/exam.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../domain/note.dart';
import '../../domain/flashcard.dart';
import '../../domain/note_attachment.dart';
import '../../domain/note_formatting.dart';
import '../../data/note_importer.dart';
import '../providers/note_providers.dart';
import 'flashcard_study_screen.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  static void _openEditor(
    BuildContext context, {
    Note? note,
    String? draftTitle,
    String? draftBody,
  }) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NoteEditorScreen(
        initial: note,
        draftTitle: draftTitle,
        draftBody: draftBody,
      ),
    ));
  }

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notesAsync = ref.watch(notesStreamProvider);
    final q = _query.trim().toLowerCase();
    final total = notesAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: back + title/count + import + new.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Row(
                children: [
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Notes',
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          total == 0
                              ? 'Capture ideas & lectures'
                              : '$total ${total == 1 ? 'note' : 'notes'}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  RoundIconButton(
                    icon: Icons.upload_file_rounded,
                    onTap: _import,
                  ),
                  const SizedBox(width: 10),
                  _AddButton(onTap: () => NotesScreen._openEditor(context)),
                ],
              ),
            ),
            const FeatureTipBanner(
              prefsKey: AppConstants.prefsTipNotes,
              message: 'You can create flashcards from your notes.',
            ),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search notes',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() => _query = ''),
                          ),
                  ),
                ),
              ),
            Expanded(
              child: notesAsync.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(notesStreamProvider)),
                data: (notes) {
                  if (notes.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                      children: [_empty(context)],
                    );
                  }
                  final filtered = q.isEmpty
                      ? notes
                      : notes
                          .where((n) =>
                              n.title.toLowerCase().contains(q) ||
                              n.body.toLowerCase().contains(q))
                          .toList();
                  if (filtered.isEmpty) {
                    return _noMatch(theme);
                  }
                  final pinned = filtered.where((n) => n.pinned).toList();
                  final others = filtered.where((n) => !n.pinned).toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        _sectionLabel(theme, 'Pinned',
                            icon: Icons.push_pin_rounded),
                        for (var i = 0; i < pinned.length; i++)
                          _cardTile(pinned[i], i),
                      ],
                      if (others.isNotEmpty) ...[
                        if (pinned.isNotEmpty) _sectionLabel(theme, 'Others'),
                        for (var i = 0; i < others.length; i++)
                          _cardTile(others[i], i),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: theme.hintColor),
            const SizedBox(width: 6),
          ],
          Text(text.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.hintColor,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  /// A single full-width note card with a subtle entrance animation.
  Widget _cardTile(Note note, int i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _NoteCard(note: note).listEntrance(i, stepMs: 30, slide: 0.05),
    );
  }

  Widget _noMatch(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 44, color: theme.hintColor),
            const SizedBox(height: 12),
            Text('No notes match “$_query”',
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Future<void> _import() async {
    List<ImportedNote> imported;
    try {
      imported = await NoteImporter.pickAndExtract();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
      return;
    }
    if (!mounted || imported.isEmpty) return;

    // A single file opens the editor prefilled so the user can review before
    // saving. Multiple files are imported straight into the notes list.
    if (imported.length == 1) {
      final note = imported.first;
      NotesScreen._openEditor(
        context,
        draftTitle: note.title,
        draftBody: note.body,
      );
      return;
    }

    final ctrl = ref.read(noteControllerProvider);
    var count = 0;
    for (final note in imported) {
      if (note.isEmpty) continue;
      await ctrl.add(Note(
        id: 'new',
        title: note.title,
        body: note.body,
        updatedAt: DateTime.now(),
      ));
      count++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $count note(s).')),
      );
    }
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.edit_note_rounded,
              size: 44, color: AppColors.primary),
        ),
        const SizedBox(height: 18),
        Text('Your notes live here', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Write lecture notes, add headings and lists, attach images or PDFs, '
          'and build flashcards to study from.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () => NotesScreen._openEditor(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create your first note'),
          style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _import,
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: const Text('Import from file'),
        ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_rounded, size: 20, color: Colors.white),
              SizedBox(width: 6),
              Text('New note',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends ConsumerWidget {
  final Note note;
  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final byId = ref.watch(subjectsByIdProvider);
    final subject = note.subjectId != null ? byId[note.subjectId] : null;
    final hasAccent = subject != null || note.colorHex != null;
    final accent = subject != null
        ? Color(subject.colorHex)
        : (note.colorHex != null ? Color(note.colorHex!) : AppColors.primary);
    final images = note.imageAttachments;

    // Resolve a linked exam/event (set via the AI "link note" action).
    Exam? linkedExam;
    if (note.linkedExamId != null) {
      final exams = ref.watch(examsStreamProvider).valueOrNull ?? const [];
      for (final e in exams) {
        if (e.id == note.linkedExamId) {
          linkedExam = e;
          break;
        }
      }
    }
    final hasPills = note.hasFlashcards ||
        note.pdfAttachments.isNotEmpty ||
        linkedExam != null;

    return Container(
      decoration: softCard(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => NotesScreen._openEditor(context, note: note),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (images.isNotEmpty) _cover(images),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasAccent) ...[
                        Container(
                          margin: const EdgeInsets.only(top: 5, right: 8),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: accent, shape: BoxShape.circle),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          note.title.trim().isEmpty
                              ? 'Untitled note'
                              : note.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700, height: 1.2),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            ref.read(noteControllerProvider).togglePin(note),
                        child: Icon(
                          note.pinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          size: 17,
                          color:
                              note.pinned ? AppColors.primary : theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                  if (note.body.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(note.preview,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodySmall?.color,
                            height: 1.35),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (note.hasChecklist) ...[
                    const SizedBox(height: 10),
                    _checklistBar(theme, accent),
                  ],
                  if (hasPills) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (note.hasFlashcards)
                          _metaPill(
                            context,
                            icon: Icons.style_rounded,
                            label:
                                '${note.flashcardCount} card${note.flashcardCount == 1 ? '' : 's'}',
                            color: AppColors.primary,
                            onTap: () =>
                                Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => FlashcardStudyScreen(
                                          cards: note.flashcards,
                                          title: note.title.trim().isEmpty
                                              ? 'Study'
                                              : note.title.trim(),
                                        ))),
                          ),
                        if (note.pdfAttachments.isNotEmpty)
                          _metaPill(
                            context,
                            icon: Icons.picture_as_pdf_rounded,
                            label:
                                '${note.pdfAttachments.length} PDF${note.pdfAttachments.length == 1 ? '' : 's'}',
                            color: AppColors.danger,
                          ),
                        if (linkedExam != null)
                          _metaPill(
                            context,
                            icon: Icons.event_note_rounded,
                            label: _short(linkedExam.title),
                            color: AppColors.info,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (subject != null)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(subject.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      if (subject != null) const Spacer(),
                      if (note.updatedAt != null)
                        Text(DateUtilsX.prettyDate(note.updatedAt!),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checklistBar(ThemeData theme, Color accent) {
    final done = note.checklistDone;
    final total = note.checklist.length;
    final progress = total == 0 ? 0.0 : done / total;
    return Row(
      children: [
        Icon(Icons.checklist_rounded, size: 14, color: accent),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: theme.dividerColor,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$done/$total',
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  /// Full-width cover built from the first image, with a "+N" badge for more.
  /// A fixed-height [SizedBox] + [StackFit.expand] gives the image a bounded
  /// size from the card's width without ever using `double.infinity`, so it
  /// can't force an unbounded width in any layout context.
  Widget _cover(List<NoteAttachment> images) {
    final extra = images.length - 1;
    return SizedBox(
      height: 118,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            images.first.url,
            fit: BoxFit.cover,
            cacheWidth: 500,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Container(color: AppColors.lavenderTint),
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.lavenderTint,
              child: const Icon(Icons.broken_image_rounded),
            ),
          ),
          if (extra > 0)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_library_rounded,
                        size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('+$extra',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _short(String s) => s.length > 16 ? '${s.substring(0, 15)}…' : s;

  Widget _metaPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          if (onTap != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.play_arrow_rounded, size: 13, color: color),
          ],
        ],
      ),
    );
    if (onTap == null) return pill;
    return GestureDetector(onTap: onTap, child: pill);
  }
}

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
                      onTap: () async {
                        await _persist();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const Spacer(),
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
                            hintText: 'Start writing…',
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
