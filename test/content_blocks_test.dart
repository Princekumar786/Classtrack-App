import 'package:classtrack/features/opportunities/domain/content_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseContentBlocks', () {
    test('numbered redeem steps → one StepsBlock', () {
      const raw = '1. Open the official Wix student page.\n'
          '2. Sign in or create an account.\n'
          '3) Verify that you are a student.\n'
          'Step 4: Apply the student price at checkout.';
      expect(parseContentBlocks(raw), [
        const StepsBlock([
          'Open the official Wix student page.',
          'Sign in or create an account.',
          'Verify that you are a student.',
          'Apply the student price at checkout.',
        ]),
      ]);
    });

    test('emoji benefit lines → BulletsBlock keeping the emoji', () {
      const raw = '💰 \$30,000 total cash prize pool\n'
          '☁️ Build with Google Cloud AI technologies\n'
          '🧠 Solve real-world business challenges';
      final blocks = parseContentBlocks(raw);
      expect(blocks, hasLength(1));
      final items = (blocks.single as BulletsBlock).items;
      expect(items.map((i) => i.text), [
        '\$30,000 total cash prize pool',
        'Build with Google Cloud AI technologies',
        'Solve real-world business challenges',
      ]);
      expect(items.first.leading, '💰');
      expect(items[1].leading, startsWith('☁'));
    });

    test('dash / dot bullets → BulletsBlock without emoji', () {
      final blocks = parseContentBlocks('- One\n• Two\n* Three');
      expect(blocks, [
        const BulletsBlock(
            [BulletItem('One'), BulletItem('Two'), BulletItem('Three')]),
      ]);
    });

    test('blank lines split paragraphs; wrapped prose reflows', () {
      const raw = 'Wix offers an exclusive\nstudent discount.\n\n'
          'The exact plan varies by country.';
      expect(parseContentBlocks(raw), const [
        ParagraphBlock('Wix offers an exclusive student discount.'),
        ParagraphBlock('The exact plan varies by country.'),
      ]);
    });

    test('mixed prose then steps then prose', () {
      const raw = 'Follow these steps:\n1. Do A\n2. Do B\nGood luck!';
      expect(parseContentBlocks(raw), const [
        ParagraphBlock('Follow these steps:'),
        StepsBlock(['Do A', 'Do B']),
        ParagraphBlock('Good luck!'),
      ]);
    });

    test('lowercase line continues the previous step', () {
      expect(parseContentBlocks('1. Open the page\nlinked on this listing.'),
          const [StepsBlock(['Open the page linked on this listing.'])]);
    });

    test('a year or number inside prose is not a step', () {
      expect(parseContentBlocks('Google Cloud AI Builder Cup 2026 is here.'),
          const [ParagraphBlock('Google Cloud AI Builder Cup 2026 is here.')]);
    });

    test('empty / whitespace → no blocks', () {
      expect(parseContentBlocks(''), isEmpty);
      expect(parseContentBlocks('  \n \n'), isEmpty);
    });
  });
}
