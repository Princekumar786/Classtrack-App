import 'package:classtrack/shared/widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the reported bug "when user marks present the present
/// notification in the app blinks many times".
///
/// Cause: the quick-mark buttons called `removeCurrentSnackBar()` immediately
/// followed by `showSnackBar()` on EVERY tap. `removeCurrentSnackBar` tears the
/// bar down with no settle animation, so repeated taps (or marking several
/// classes in a row) re-created the same confirmation over and over — a visible
/// flash/blink. [showQuickFeedback] absorbs a repeat of the same message while
/// it is still on screen.
void main() {
  setUp(resetQuickFeedbackForTest);

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          captured = context;
          return const SizedBox.expand();
        }),
      ),
    ));
    return captured;
  }

  testWidgets('the first mark shows one confirmation', (tester) async {
    final context = await pumpHost(tester);
    expect(showQuickFeedback(context, 'Present · Maths'), isTrue);
    await tester.pump();
    expect(find.text('Present · Maths'), findsOneWidget);
  });

  testWidgets('5 rapid identical marks show the bar only ONCE (no blinking)',
      (tester) async {
    final context = await pumpHost(tester);
    final shown = <bool>[];
    for (var i = 0; i < 5; i++) {
      shown.add(showQuickFeedback(context, 'Present · Maths'));
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Exactly one insertion; the other four are absorbed instead of
    // tearing down and re-inserting the bar.
    expect(shown.where((s) => s).length, 1);
    expect(shown, [true, false, false, false, false]);
    expect(find.text('Present · Maths'), findsOneWidget);
  });

  testWidgets('a different message replaces the bar immediately',
      (tester) async {
    final context = await pumpHost(tester);
    expect(showQuickFeedback(context, 'Present · Maths'), isTrue);
    await tester.pump(const Duration(milliseconds: 50));
    // Marking a different subject is new information, so it must show.
    expect(showQuickFeedback(context, 'Absent · Physics'), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Absent · Physics'), findsOneWidget);
    expect(find.text('Present · Maths'), findsNothing);
  });

  testWidgets('the same message shows again once the previous bar has gone',
      (tester) async {
    final context = await pumpHost(tester);
    expect(showQuickFeedback(context, 'Present · Maths'), isTrue);
    await tester.pump();
    expect(find.text('Present · Maths'), findsOneWidget);
    // Advancing the clock takes two steps: the first frame completes the
    // entrance animation (which is when ScaffoldMessenger *schedules* the
    // auto-dismiss timer), the second crosses that timer. pumpAndSettle alone
    // returns as soon as animations are idle and never fires the timer.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Present · Maths'), findsNothing,
        reason: 'the bar must be gone before the repeat window reopens');
    // The bar is no longer on screen, so a genuine later mark is confirmed.
    expect(showQuickFeedback(context, 'Present · Maths'), isTrue);
    await tester.pump();
    expect(find.text('Present · Maths'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('alternating statuses on the same class each confirm',
      (tester) async {
    final context = await pumpHost(tester);
    // Correcting Present -> Absent -> Present are all real changes.
    expect(showQuickFeedback(context, 'Present · Maths'), isTrue);
    await tester.pump(const Duration(milliseconds: 30));
    expect(showQuickFeedback(context, 'Absent · Maths'), isTrue);
    await tester.pump(const Duration(milliseconds: 30));
    expect(showQuickFeedback(context, 'Present · Maths'), isTrue);
    await tester.pumpAndSettle();
  });
}
