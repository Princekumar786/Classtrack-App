import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/flashcard.dart';

/// A flip-card study session over a note's flashcards. Tap the card to flip
/// between question and answer, then mark whether you knew it. Ends with a
/// score summary and the option to review just the ones you missed.
class FlashcardStudyScreen extends StatefulWidget {
  final List<Flashcard> cards;
  final String title;

  const FlashcardStudyScreen({
    super.key,
    required this.cards,
    this.title = 'Study',
  });

  @override
  State<FlashcardStudyScreen> createState() => _FlashcardStudyScreenState();
}

class _FlashcardStudyScreenState extends State<FlashcardStudyScreen>
    with SingleTickerProviderStateMixin {
  late List<Flashcard> _deck;
  late final AnimationController _flip;
  int _index = 0;
  bool _showingAnswer = false;

  /// Ids the user marked as known this session.
  final Set<String> _known = {};

  /// Ids the user marked as needing review.
  final Set<String> _missed = {};

  bool get _finished => _index >= _deck.length;

  @override
  void initState() {
    super.initState();
    _deck = List.of(widget.cards);
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    HapticFeedback.selectionClick();
    if (_showingAnswer) {
      _flip.reverse();
    } else {
      _flip.forward();
    }
    setState(() => _showingAnswer = !_showingAnswer);
  }

  void _mark({required bool known}) {
    final card = _deck[_index];
    setState(() {
      if (known) {
        _known.add(card.id);
        _missed.remove(card.id);
      } else {
        _missed.add(card.id);
        _known.remove(card.id);
      }
      _index++;
      _showingAnswer = false;
      _flip.value = 0;
    });
  }

  void _restart(List<Flashcard> deck) {
    setState(() {
      _deck = deck;
      _index = 0;
      _showingAnswer = false;
      _flip.value = 0;
      _known.clear();
      _missed.clear();
    });
  }

  void _shuffle() {
    setState(() {
      _deck = List.of(_deck)..shuffle(math.Random());
      _index = 0;
      _showingAnswer = false;
      _flip.value = 0;
      _known.clear();
      _missed.clear();
    });
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    if (_deck.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: Text('No flashcards to study yet.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (!_finished)
            IconButton(
              tooltip: 'Shuffle',
              icon: const Icon(Icons.shuffle_rounded),
              onPressed: _shuffle,
            ),
        ],
      ),
      body: _finished ? _summary(context) : _studyView(context),
    );
  }

  Widget _studyView(BuildContext context) {
    final theme = Theme.of(context);
    final card = _deck[_index];
    final progress = _index / _deck.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Card ${_index + 1} of ${_deck.length}',
                      style: theme.textTheme.labelLarge),
                  const Spacer(),
                  Text('${_known.length} known',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: AppColors.success)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: AppColors.lavenderTint,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _FlipCard(
              animation: _flip,
              onTap: _toggleFlip,
              front: _face(
                context,
                label: 'QUESTION',
                text: card.question,
                gradient: const [AppColors.primaryLight, AppColors.primary],
                hint: 'Tap to reveal answer',
              ),
              back: _face(
                context,
                label: 'ANSWER',
                text: card.answer,
                gradient: const [Color(0xFF14B8A6), AppColors.success],
                hint: 'Tap to see question',
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _mark(known: false),
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.coral),
                  label: const Text('Review again'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.coral,
                    side: const BorderSide(color: AppColors.coral),
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _mark(known: true),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Got it'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _face(
    BuildContext context, {
    required String label,
    required String text,
    required List<Color> gradient,
    required String hint,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                )),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Text(
                  text.trim().isEmpty ? '—' : text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_rounded,
                  size: 16, color: Colors.white.withValues(alpha: 0.85)),
              const SizedBox(width: 6),
              Text(hint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    final total = _deck.length;
    final knew = _known.length;
    final pct = total == 0 ? 0 : (knew / total * 100).round();
    final missedCards =
        _deck.where((c) => _missed.contains(c.id)).toList();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pct >= 80 ? '🎉' : (pct >= 50 ? '💪' : '📚'),
                style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text('Session complete', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'You knew $knew of $total cards ($pct%).',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),
            if (missedCards.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _restart(missedCards),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text('Review ${missedCards.length} missed'),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _restart(List.of(widget.cards)),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Study all again'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card that flips around its Y axis between [front] and [back] driven by
/// [animation] (0 → front, 1 → back).
class _FlipCard extends StatelessWidget {
  final Animation<double> animation;
  final Widget front;
  final Widget back;
  final VoidCallback onTap;

  const _FlipCard({
    required this.animation,
    required this.front,
    required this.back,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final angle = animation.value * math.pi;
          final showBack = angle > math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: back,
                  )
                : front,
          );
        },
      ),
    );
  }
}

/// Full-screen, zoomable viewer for an attached image.
class NoteImageViewer extends StatelessWidget {
  final String url;
  final String? name;

  const NoteImageViewer({super.key, required this.url, this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: name == null
            ? null
            : Text(name!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            // Cap the decoded bitmap size so full-resolution camera photos
            // (12MP+) don't blow up memory — addresses the Play "bitmap
            // downsampling" recommendation. 1600px stays crisp even when the
            // InteractiveViewer is zoomed in on a phone screen.
            cacheWidth: 1600,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const CircularProgressIndicator(color: Colors.white);
            },
            errorBuilder: (context, _, __) => const Icon(
                Icons.broken_image_rounded, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}
