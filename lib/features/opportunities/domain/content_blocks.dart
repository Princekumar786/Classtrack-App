/// Turns free-form CMS text (About / Benefits / How to apply / How to redeem)
/// into structured blocks so the detail page can render numbered steps as a
/// timeline and bullet/emoji lines as a scannable list, instead of one wall of
/// text. Pure and dependency-free so it can be unit tested.
sealed class ContentBlock {
  const ContentBlock();
}

/// A normal paragraph of prose.
class ParagraphBlock extends ContentBlock {
  final String text;
  const ParagraphBlock(this.text);

  @override
  bool operator ==(Object other) =>
      other is ParagraphBlock && other.text == text;
  @override
  int get hashCode => text.hashCode;
}

/// An ordered list ("1. …", "2) …", "Step 3: …").
class StepsBlock extends ContentBlock {
  final List<String> steps;
  const StepsBlock(this.steps);

  @override
  bool operator ==(Object other) =>
      other is StepsBlock && _listEq(other.steps, steps);
  @override
  int get hashCode => Object.hashAll(steps);
}

/// One item of a bullet list. [leading] is the emoji the author used (e.g.
/// "💰"), or null for plain "-", "•", "*" bullets.
class BulletItem {
  final String? leading;
  final String text;
  const BulletItem(this.text, {this.leading});

  @override
  bool operator ==(Object other) =>
      other is BulletItem && other.leading == leading && other.text == text;
  @override
  int get hashCode => Object.hash(leading, text);
}

/// An unordered list of [BulletItem]s.
class BulletsBlock extends ContentBlock {
  final List<BulletItem> items;
  const BulletsBlock(this.items);

  @override
  bool operator ==(Object other) =>
      other is BulletsBlock && _listEq(other.items, items);
  @override
  int get hashCode => Object.hashAll(items);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// "1. x", "1) x", "1 - x", "Step 1: x", "Step 1. x"
final _stepRe =
    RegExp(r'^(?:step\s*)?\d{1,2}\s*[.):\-–]\s*(.+)$', caseSensitive: false);
// "- x", "• x", "* x", "· x", "– x"
final _bulletRe = RegExp(r'^[-•*·–]\s+(.+)$');
// A leading emoji / pictograph followed by text, e.g. "💰 $30,000 prize".
final _emojiRe = RegExp(
  r'^((?:[\u{1F000}-\u{1FAFF}]|[\u{2600}-\u{27BF}]|[\u{2B00}-\u{2BFF}])'
  r'[\u{FE0F}\u{200D}\u{1F3FB}-\u{1F3FF}\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]*)'
  r'\s*(.+)$',
  unicode: true,
);

enum _Kind { para, step, bullet }

/// Splits [raw] into blocks. Consecutive lines of the same list kind are
/// grouped; blank lines end a paragraph; prose lines are joined with spaces so
/// hard-wrapped CMS text reflows naturally.
List<ContentBlock> parseContentBlocks(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').split('\n');
  final out = <ContentBlock>[];

  _Kind? current;
  final para = <String>[];
  final steps = <String>[];
  final bullets = <BulletItem>[];

  void flush() {
    switch (current) {
      case _Kind.para:
        if (para.isNotEmpty) out.add(ParagraphBlock(para.join(' ')));
        para.clear();
      case _Kind.step:
        if (steps.isNotEmpty) out.add(StepsBlock(List.of(steps)));
        steps.clear();
      case _Kind.bullet:
        if (bullets.isNotEmpty) out.add(BulletsBlock(List.of(bullets)));
        bullets.clear();
      case null:
        break;
    }
    current = null;
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      flush();
      continue;
    }

    final step = _stepRe.firstMatch(line);
    if (step != null) {
      if (current != _Kind.step) flush();
      current = _Kind.step;
      steps.add(step.group(1)!.trim());
      continue;
    }

    final bullet = _bulletRe.firstMatch(line);
    if (bullet != null) {
      if (current != _Kind.bullet) flush();
      current = _Kind.bullet;
      bullets.add(BulletItem(bullet.group(1)!.trim()));
      continue;
    }

    final emoji = _emojiRe.firstMatch(line);
    if (emoji != null) {
      if (current != _Kind.bullet) flush();
      current = _Kind.bullet;
      bullets.add(BulletItem(emoji.group(2)!.trim(), leading: emoji.group(1)));
      continue;
    }

    // A hard-wrapped continuation of the previous step / bullet. Only lines
    // that clearly continue a sentence (lowercase or bracket start) qualify,
    // so a new sentence after a list becomes its own paragraph.
    final continues = RegExp(r'^[a-z(\[]').hasMatch(line);
    if (continues && current == _Kind.step && steps.isNotEmpty) {
      steps[steps.length - 1] = '${steps.last} $line';
      continue;
    }
    if (continues && current == _Kind.bullet && bullets.isNotEmpty) {
      final last = bullets.removeLast();
      bullets.add(BulletItem('${last.text} $line', leading: last.leading));
      continue;
    }

    if (current != _Kind.para) flush();
    current = _Kind.para;
    para.add(line);
  }
  flush();
  return out;
}
