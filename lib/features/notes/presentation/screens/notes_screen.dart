import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/widgets/feature_tip_banner.dart';
import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../exams/domain/exam.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../subjects/domain/subject.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../data/note_importer.dart';
import '../../domain/note.dart';
import '../../domain/note_attachment.dart';
import '../../domain/note_formatting.dart';
import '../providers/note_providers.dart';
import 'flashcard_study_screen.dart';
import 'note_editor_screen.dart';

// Older code imports NoteEditorScreen from this file — keep that working.
export 'note_editor_screen.dart';

/// List filters shown as chips under the search bar.
enum _NoteFilter { all, pinned, flashcards, files }

/// How the notes are ordered.
enum _NoteSort { recent, oldest, title }

extension on _NoteSort {
  String get label => switch (this) {
        _NoteSort.recent => 'Recently edited',
        _NoteSort.oldest => 'Oldest first',
        _NoteSort.title => 'Title A–Z',
      };
  IconData get icon => switch (this) {
        _NoteSort.recent => Icons.update_rounded,
        _NoteSort.oldest => Icons.history_rounded,
        _NoteSort.title => Icons.sort_by_alpha_rounded,
      };
}

/// Notes home.
///
/// Top to bottom: header (count, search, grid/list toggle, sort & import
/// menu), a "Study all flashcards" card when any note has cards, filter chips
/// (All · Pinned · Flashcards · Files · each subject), then Pinned and Notes
/// sections as a two-column masonry grid (or a single list). Long-press a card
/// for Pin / Study / Delete. The "New note" button sits bottom-right.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  static void _openEditor(
    BuildContext context, {
    Note? note,
    String? draftTitle,
    String? draftBody,
  }) {
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: 'Note Editor'),
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
  static const _prefsGridKey = 'notes_grid_view';

  String _query = '';
  bool _searching = false;
  _NoteFilter _filter = _NoteFilter.all;
  String? _subjectFilter;
  _NoteSort _sort = _NoteSort.recent;
  late bool _grid =
      ref.read(sharedPrefsProvider).getBool(_prefsGridKey) ?? true;

  void _toggleGrid() {
    setState(() => _grid = !_grid);
    ref.read(sharedPrefsProvider).setBool(_prefsGridKey, _grid);
  }

  int _compare(Note a, Note b) {
    DateTime t(Note n) =>
        n.updatedAt ?? n.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return switch (_sort) {
      _NoteSort.recent => t(b).compareTo(t(a)),
      _NoteSort.oldest => t(a).compareTo(t(b)),
      _NoteSort.title => _titleOf(a).toLowerCase().compareTo(
          _titleOf(b).toLowerCase()),
    };
  }

  static String _titleOf(Note n) =>
      n.title.trim().isEmpty ? 'Untitled note' : n.title.trim();

  List<Note> _visible(List<Note> notes, Map<String, Subject> subjects) {
    final q = _query.trim().toLowerCase();
    return notes.where((n) {
      final ok = switch (_filter) {
        _NoteFilter.all => true,
        _NoteFilter.pinned => n.pinned,
        _NoteFilter.flashcards => n.hasFlashcards,
        _NoteFilter.files => n.attachments.isNotEmpty,
      };
      if (!ok) return false;
      if (_subjectFilter != null && n.subjectId != _subjectFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      final subject = n.subjectId == null ? null : subjects[n.subjectId];
      return n.title.toLowerCase().contains(q) ||
          n.body.toLowerCase().contains(q) ||
          (subject?.name.toLowerCase().contains(q) ?? false) ||
          n.flashcards.any((f) =>
              f.question.toLowerCase().contains(q) ||
              f.answer.toLowerCase().contains(q));
    }).toList()
      ..sort(_compare);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notesAsync = ref.watch(notesStreamProvider);
    final notes = notesAsync.valueOrNull ?? const <Note>[];
    final subjects = ref.watch(subjectsByIdProvider);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'notes_fab',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => NotesScreen._openEditor(context),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New note'),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, canPop, notes),
            if (_searching) _searchField(),
            Expanded(
              child: notesAsync.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(notesStreamProvider)),
                data: (notes) => notes.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                        children: [_empty(context)],
                      )
                    : _content(theme, notes, subjects),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────
  Widget _header(ThemeData theme, bool canPop, List<Note> notes) {
    final cards = notes.fold<int>(0, (s, n) => s + n.flashcardCount);
    final subtitle = notes.isEmpty
        ? 'Capture lectures, ideas & flashcards'
        : [
            '${notes.length} ${notes.length == 1 ? 'note' : 'notes'}',
            if (cards > 0) '$cards ${cards == 1 ? 'flashcard' : 'flashcards'}',
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          if (canPop) ...[
            RoundIconButton(
              icon: Icons.arrow_back_rounded,
              semanticLabel: 'Back',
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notes',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ],
            ),
          ),
          if (notes.isNotEmpty) ...[
            IconButton(
              tooltip: _searching ? 'Close search' : 'Search',
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) _query = '';
              }),
              icon: Icon(_searching
                  ? Icons.search_off_rounded
                  : Icons.search_rounded),
            ),
            IconButton(
              tooltip: _grid ? 'List view' : 'Grid view',
              onPressed: _toggleGrid,
              icon: Icon(_grid
                  ? Icons.view_agenda_outlined
                  : Icons.grid_view_rounded),
            ),
          ],
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'import') {
                _import();
              } else if (v.startsWith('sort:')) {
                setState(
                    () => _sort = _NoteSort.values.byName(v.substring(5)));
              }
            },
            itemBuilder: (ctx) => [
              if (notes.isNotEmpty) ...[
                const PopupMenuItem<String>(
                    enabled: false, height: 32, child: Text('SORT BY')),
                for (final s in _NoteSort.values)
                  PopupMenuItem<String>(
                    value: 'sort:${s.name}',
                    child: Row(
                      children: [
                        Icon(s.icon,
                            size: 18,
                            color: s == _sort
                                ? AppColors.primary
                                : theme.hintColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(s.label,
                              style: TextStyle(
                                  fontWeight: s == _sort
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color:
                                      s == _sort ? AppColors.primary : null)),
                        ),
                        if (s == _sort)
                          const Icon(Icons.check_rounded,
                              size: 18, color: AppColors.primary),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
              ],
              PopupMenuItem<String>(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.upload_file_rounded,
                        size: 18, color: theme.hintColor),
                    const SizedBox(width: 10),
                    const Text('Import from file'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: TextField(
        autofocus: true,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search titles, text, subjects or flashcards',
          prefixIcon: const Icon(Icons.search_rounded),
          isDense: true,
          suffixIcon: IconButton(
            tooltip: 'Close search',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() {
              _query = '';
              _searching = false;
            }),
          ),
        ),
      ),
    );
  }

  // ── Content ────────────────────────────────────────────────────────────
  Widget _content(
      ThemeData theme, List<Note> notes, Map<String, Subject> subjects) {
    final visible = _visible(notes, subjects);
    final pinned = visible.where((n) => n.pinned).toList();
    final others = visible.where((n) => !n.pinned).toList();
    final allCards = [for (final n in notes) ...n.flashcards];
    final deckCount = notes.where((n) => n.hasFlashcards).length;
    final subjectIds = <String>{
      for (final n in notes)
        if (n.subjectId != null && subjects.containsKey(n.subjectId))
          n.subjectId!,
    }.toList()
      ..sort((a, b) => subjects[a]!
          .name
          .toLowerCase()
          .compareTo(subjects[b]!.name.toLowerCase()));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
      children: [
        const FeatureTipBanner(
          prefsKey: AppConstants.prefsTipNotes,
          message: 'Type / in a note for headings, lists, images and '
              'flashcards.',
        ),
        if (allCards.isNotEmpty && _query.isEmpty) ...[
          const SizedBox(height: 6),
          _StudyCard(
            cards: allCards.length,
            decks: deckCount,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                settings: const RouteSettings(name: 'Flashcard Study'),
                builder: (_) => FlashcardStudyScreen(
                    cards: allCards, title: 'All flashcards'))),
          ),
        ],
        const SizedBox(height: 14),
        _filterRow(notes, subjectIds, subjects),
        const SizedBox(height: 6),
        if (visible.isEmpty)
          _noMatch(theme)
        else ...[
          if (pinned.isNotEmpty) ...[
            _sectionLabel(theme, 'Pinned', pinned.length,
                icon: Icons.push_pin_rounded),
            _layout(pinned),
          ],
          if (others.isNotEmpty) ...[
            if (pinned.isNotEmpty)
              _sectionLabel(theme, 'Notes', others.length),
            _layout(others),
          ],
        ],
      ],
    );
  }

  Widget _filterRow(List<Note> notes, List<String> subjectIds,
      Map<String, Subject> subjects) {
    int count(_NoteFilter f) => switch (f) {
          _NoteFilter.all => notes.length,
          _NoteFilter.pinned => notes.where((n) => n.pinned).length,
          _NoteFilter.flashcards => notes.where((n) => n.hasFlashcards).length,
          _NoteFilter.files =>
            notes.where((n) => n.attachments.isNotEmpty).length,
        };
    Widget pill(_NoteFilter f, String label, IconData icon) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterPill(
            label: f == _NoteFilter.all ? label : '$label  ${count(f)}',
            icon: icon,
            selected: _filter == f && _subjectFilter == null,
            onTap: () => setState(() {
              _filter = f;
              _subjectFilter = null;
            }),
          ),
        );
    final showPinned = count(_NoteFilter.pinned) > 0;
    final showCards = count(_NoteFilter.flashcards) > 0;
    final showFiles = count(_NoteFilter.files) > 0;

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          pill(_NoteFilter.all, 'All', Icons.notes_rounded),
          if (showPinned)
            pill(_NoteFilter.pinned, 'Pinned', Icons.push_pin_rounded),
          if (showCards)
            pill(_NoteFilter.flashcards, 'Flashcards', Icons.style_rounded),
          if (showFiles)
            pill(_NoteFilter.files, 'Files', Icons.attach_file_rounded),
          for (final id in subjectIds)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterPill(
                label: subjects[id]!.name,
                icon: Icons.circle,
                accent: Color(subjects[id]!.colorHex),
                selected: _subjectFilter == id,
                onTap: () => setState(() {
                  _filter = _NoteFilter.all;
                  _subjectFilter = _subjectFilter == id ? null : id;
                }),
              ),
            ),
        ],
      ),
    );
  }

  /// Grid → two-column masonry (each card keeps its natural height, placed
  /// in the shorter column). List → one card per row.
  Widget _layout(List<Note> notes) {
    if (!_grid) {
      return Column(
        children: [
          for (var i = 0; i < notes.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _NoteCard(
                note: notes[i],
                compact: false,
                onLongPress: () => _actions(notes[i]),
              ).listEntrance(i, stepMs: 30, slide: 0.05),
            ),
        ],
      );
    }
    final left = <Widget>[], right = <Widget>[];
    var lh = 0.0, rh = 0.0;
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      final card = Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _NoteCard(
          note: n,
          compact: true,
          onLongPress: () => _actions(n),
        ).listEntrance(i, stepMs: 30, slide: 0.05),
      );
      final h = _estimateHeight(n);
      if (lh <= rh) {
        left.add(card);
        lh += h;
      } else {
        right.add(card);
        rh += h;
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: left)),
        const SizedBox(width: 12),
        Expanded(child: Column(children: right)),
      ],
    );
  }

  /// Rough card height for balancing the two masonry columns.
  static double _estimateHeight(Note n) {
    var h = 70.0;
    if (n.imageAttachments.isNotEmpty) h += 96;
    final previewLen = notePlainPreview(n.body).length;
    h += (previewLen / 22).clamp(0, 7) * 18;
    if (n.hasChecklist) h += 20;
    if (n.hasFlashcards || n.pdfAttachments.isNotEmpty) h += 28;
    return h;
  }

  Widget _sectionLabel(ThemeData theme, String text, int count,
      {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: theme.hintColor),
              const SizedBox(width: 6),
            ],
            Text('${text.toUpperCase()} · $count',
                style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.hintColor,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _noMatch(ThemeData theme) {
    final searching = _query.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(searching ? Icons.search_off_rounded : Icons.filter_alt_off,
              size: 44, color: theme.hintColor),
          const SizedBox(height: 12),
          Text(
              searching
                  ? 'No notes match “${_query.trim()}”'
                  : 'No notes in this filter',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  // ── Long-press actions ─────────────────────────────────────────────────
  Future<void> _actions(Note note) async {
    HapticFeedback.mediumImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(_titleOf(note),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              ListTile(
                leading: Icon(note.pinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded),
                title: Text(note.pinned ? 'Unpin' : 'Pin to top'),
                onTap: () => Navigator.pop(ctx, 'pin'),
              ),
              if (note.hasFlashcards)
                ListTile(
                  leading: const Icon(Icons.school_rounded),
                  title: Text('Study ${note.flashcardCount} '
                      '${note.flashcardCount == 1 ? 'flashcard' : 'flashcards'}'),
                  onTap: () => Navigator.pop(ctx, 'study'),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.danger),
                title: const Text('Delete',
                    style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'pin':
        await ref.read(noteControllerProvider).togglePin(note);
      case 'study':
        await Navigator.of(context).push(MaterialPageRoute(
            settings: const RouteSettings(name: 'Flashcard Study'),
            builder: (_) => FlashcardStudyScreen(
                cards: note.flashcards, title: _titleOf(note))));
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete note?'),
            content: Text(note.attachments.isEmpty
                ? '“${_titleOf(note)}” will be deleted.'
                : '“${_titleOf(note)}” and its attached files will be deleted.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await ref.read(noteControllerProvider).deleteNote(note);
        }
    }
  }

  // ── Import ─────────────────────────────────────────────────────────────
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
    Widget idea(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );
    return Column(
      children: [
        const SizedBox(height: 12),
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
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          decoration: softCard(context, radius: 20),
          child: Column(
            children: [
              idea(Icons.title_rounded,
                  'Type / for headings, lists, quotes and dividers'),
              idea(Icons.folder_open_rounded,
                  'Link a note to a subject to find it fast'),
              idea(Icons.style_rounded,
                  'Turn key points into flashcards and study them'),
              idea(Icons.attach_file_rounded,
                  'Attach photos of the board or PDF slides'),
            ],
          ),
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

/// Gradient call-to-action to study every flashcard across all notes.
class _StudyCard extends StatelessWidget {
  final int cards;
  final int decks;
  final VoidCallback onTap;
  const _StudyCard(
      {required this.cards, required this.decks, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Study all $cards flashcards',
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryLight, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.style_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Study all flashcards',
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800)),
                        Text(
                            '$cards ${cards == 1 ? 'card' : 'cards'} from '
                            '$decks ${decks == 1 ? 'note' : 'notes'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9))),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_rounded,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 2),
                        Text('Start',
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A note card. Tinted with its subject / note colour, with a thin accent bar
/// on top, a clean text preview (no raw Markdown), checklist progress and
/// small pills for flashcards, PDFs and a linked exam.
class _NoteCard extends ConsumerWidget {
  final Note note;
  final bool compact;
  final VoidCallback onLongPress;
  const _NoteCard(
      {required this.note, required this.compact, required this.onLongPress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final byId = ref.watch(subjectsByIdProvider);
    final subject = note.subjectId != null ? byId[note.subjectId] : null;
    final Color? accent = note.colorHex != null
        ? Color(note.colorHex!)
        : (subject != null ? Color(subject.colorHex) : null);
    final images = note.imageAttachments;
    final preview = notePlainPreview(note.body);
    final title = note.title.trim();

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

    final bg = accent == null
        ? theme.cardColor
        : Color.alphaBlend(
            accent.withValues(alpha: dark ? 0.16 : 0.09), theme.cardColor);

    return Semantics(
      button: true,
      label: '${title.isEmpty ? 'Untitled note' : title}. '
          '${note.pinned ? 'Pinned. ' : ''}Long press for options',
      child: Container(
        decoration: softCard(context, color: bg, radius: 20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => NotesScreen._openEditor(context, note: note),
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (accent != null && images.isEmpty)
                Container(height: 4, color: accent),
              if (images.isNotEmpty) _cover(images),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title.isEmpty ? 'Untitled note' : title,
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 14.5 : 15.5,
                                height: 1.2,
                                color: title.isEmpty ? theme.hintColor : null),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _PinButton(note: note),
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(preview,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.72),
                              fontSize: 12.5,
                              height: 1.4),
                          maxLines: compact ? 7 : 3,
                          overflow: TextOverflow.ellipsis),
                    ],
                    if (note.hasChecklist) ...[
                      const SizedBox(height: 10),
                      _checklistBar(theme, accent ?? AppColors.primary),
                    ],
                    if (hasPills) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (note.hasFlashcards)
                            _pill(
                              icon: Icons.style_rounded,
                              label: '${note.flashcardCount}',
                              color: AppColors.primary,
                              tooltip: 'Study flashcards',
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      settings: const RouteSettings(
                                          name: 'Flashcard Study'),
                                      builder: (_) => FlashcardStudyScreen(
                                            cards: note.flashcards,
                                            title: title.isEmpty
                                                ? 'Study'
                                                : title,
                                          ))),
                            ),
                          if (note.pdfAttachments.isNotEmpty)
                            _pill(
                              icon: Icons.picture_as_pdf_rounded,
                              label: '${note.pdfAttachments.length}',
                              color: AppColors.danger,
                              tooltip: 'PDF attachments',
                            ),
                          if (linkedExam != null)
                            _pill(
                              icon: Icons.event_note_rounded,
                              label: linkedExam.title.length > 14
                                  ? '${linkedExam.title.substring(0, 13)}…'
                                  : linkedExam.title,
                              color: AppColors.info,
                              tooltip: 'Linked exam',
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (subject != null)
                          Flexible(
                            child: Text(subject.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: Color(subject.colorHex),
                                    fontWeight: FontWeight.w700)),
                          ),
                        if (subject != null && note.updatedAt != null)
                          Text('  ·  ',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.hintColor)),
                        if (note.updatedAt != null)
                          Flexible(
                            child: Text(DateUtilsX.prettyDate(note.updatedAt!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: theme.hintColor)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
                ?.copyWith(fontWeight: FontWeight.w600, fontSize: 11)),
      ],
    );
  }

  Widget _cover(List<NoteAttachment> images) {
    final extra = images.length - 1;
    return SizedBox(
      height: compact ? 96 : 130,
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
                child: Text('+$extra',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required Color color,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.play_arrow_rounded, size: 13, color: color),
          ],
        ],
      ),
    );
    return Tooltip(
      message: tooltip,
      child: onTap == null ? pill : GestureDetector(onTap: onTap, child: pill),
    );
  }
}

class _PinButton extends ConsumerWidget {
  final Note note;
  const _PinButton({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: note.pinned ? 'Unpin note' : 'Pin note',
      excludeSemantics: true,
      child: InkResponse(
        radius: 18,
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(noteControllerProvider).togglePin(note);
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            note.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            size: 17,
            color: note.pinned ? AppColors.primary : theme.hintColor,
          ),
        ),
      ),
    );
  }
}
