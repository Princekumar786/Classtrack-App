import 'package:classtrack/features/chat/domain/chat_actions_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSpendStatement', () {

  group('bestMatchIndex', () {
    final tasks = [
      'Microsoft Fabric end-to-end tutorial',
      'OS assignment: process scheduling',
      'Networks lab record',
    ];
    test('"the microsoft fabric video" finds the Fabric task', () {
      expect(bestMatchIndex(tasks, 'microsoft fabric video'), 0);
      expect(bestMatchIndex(tasks, 'the Microsoft Fabric video task'), 0);
      expect(bestMatchIndex(tasks, 'fabric'), 0);
    });
    test('exact and contains still win', () {
      expect(bestMatchIndex(tasks, 'networks lab record'), 2);
      expect(bestMatchIndex(tasks, 'OS assignment'), 1);
    });
    test('ambiguous or unrelated → null (ask instead of guessing)', () {
      expect(bestMatchIndex(['Maths quiz 1', 'Maths quiz 2'], 'maths quiz'), isNull);
      expect(bestMatchIndex(tasks, 'chemistry homework'), isNull);
      expect(bestMatchIndex(tasks, 'the video'), isNull);
    });
    test('expenses by item name', () {
      expect(bestMatchIndex(['Samosa', 'Aws', 'Uber'], 'the aws spend'), 1);
      expect(bestMatchIndex(['Samosa', 'AWS credits', 'Uber'], 'aws'), 1);
    });
  });

  group('normalizeUpdateAction / updateRequestsChange', () {
    test('"completed": true and friends become done: true', () {
      expect(normalizeUpdateAction({'completed': true})['done'], isTrue);
      expect(normalizeUpdateAction({'done': 'true'})['done'], isTrue);
      expect(normalizeUpdateAction({'status': 'completed'})['done'], isTrue);
      expect(normalizeUpdateAction({'isDone': 'no'})['done'], isFalse);
    });
    test('an update that changes nothing is detected', () {
      expect(updateRequestsChange({'match': 'x'}), isFalse);
      expect(updateRequestsChange(normalizeUpdateAction({'match': 'x', 'completed': true})), isTrue);
      expect(updateRequestsChange({'match': 'x', 'newTitle': ''}), isFalse);
    });
  });

  group('claimsDataChange', () {
    test('catches confident claims', () {
      for (final s in [
        'Done — deleted the AWS expense.',
        "I've marked the Microsoft Fabric video as complete!",
        'Got it, I removed it for you.',
        'Your task has been marked completed.',
        'The task is now marked done.',
        'All set — updated your exam to Friday.',
      ]) {
        expect(claimsDataChange(s), isTrue, reason: s);
      }
    });
    test('ignores questions, info and offers', () {
      for (final s in [
        'Which task do you mean — the Fabric video or the OS assignment?',
        'You spent ₹120 on AWS this month.',
        'You have 3 tasks due this week.',
        'Want me to mark it as done?',
        'To mark a task done, tap the circle next to it.',
      ]) {
        expect(claimsDataChange(s), isFalse, reason: s);
      }
    });
  });

    void expectSpend(String msg, double amount, String title, String category) {
      final p = parseSpendStatement(msg);
      expect(p, isNotNull, reason: msg);
      expect(p!.amount, amount, reason: msg);
      expect(p.title, title, reason: msg);
      expect(p.category, category, reason: msg);
    }

    test('the reported failures now log', () {
      expectSpend('spent 120 on aws', 120, 'Aws', 'other');
      expectSpend('I spent 20 on samosa', 20, 'Samosa', 'food');
    });

    test('common phrasings, currencies and categories', () {
      expectSpend('paid ₹49 for Spotify', 49, 'Spotify', 'other');
      expectSpend('Spent rs 250 on uber today', 250, 'Uber', 'transport');
      expectSpend('bought a notebook for 60', 60, 'Notebook', 'books');
      expectSpend('I spent \$12.50 on Netflix', 12.5, 'Netflix', 'fun');
      expectSpend('paid 4500 for hostel rent', 4500, 'Hostel rent', 'rent');
      expectSpend('spent 300 on medicines', 300, 'Medicines', 'health');
      expectSpend('Spent 80 rupees on chai and maggi', 80, 'Chai and maggi', 'food');
    });

    test('leaves ambiguous messages to the model', () {
      for (final m in [
        'how much did I spend on food?',
        'should I spend 500 on a course',
        'set my budget to 5000',
        'delete the 20 rupees food expense',
        'spent 20 on tea and 30 on samosa', // two amounts
        'I spent a lot this month', // no amount
        'what is my schedule tomorrow',
        'I got a refund of 200',
        'I spent 300 on aws last month?',
      ]) {
        expect(parseSpendStatement(m), isNull, reason: m);
      }
    });
  });

  group('fixAmEnteredClassTime', () {
    test('afternoon classes entered as AM move to PM', () {
      expect(fixAmEnteredClassTime('01:40', '02:30'), ('13:40', '14:30'));
      expect(fixAmEnteredClassTime('02:30', '03:20'), ('14:30', '15:20'));
      expect(fixAmEnteredClassTime('03:20', '04:00'), ('15:20', '16:00'));
    });

    test('a class crossing noon entered without PM fixes only the end', () {
      expect(fixAmEnteredClassTime('11:30', '01:00'), ('11:30', '13:00'));
      expect(fixAmEnteredClassTime('12:00', '12:50'), isNull); // already fine
    });

    test('real morning, afternoon and evening classes are untouched', () {
      expect(fixAmEnteredClassTime('09:30', '10:20'), isNull);
      expect(fixAmEnteredClassTime('07:30', '08:20'), isNull);
      expect(fixAmEnteredClassTime('13:40', '14:30'), isNull);
      expect(fixAmEnteredClassTime('18:00', '19:00'), isNull);
    });

    test('garbage input is ignored', () {
      expect(fixAmEnteredClassTime('', '10:00'), isNull);
      expect(fixAmEnteredClassTime('25:00', '26:00'), isNull);
    });
  });

  group('categorizeExpense', () {
    test('unknown services fall back to other', () {
      expect(categorizeExpense('aws'), 'other');
      expect(categorizeExpense('github copilot'), 'other');
      expect(categorizeExpense('canteen lunch'), 'food');
    });
  });

  group('parseConfirmationReply', () {
    test('yes-type answers confirm', () {
      for (final s in ['yes', 'Yes!', 'yes delete it', 'ok', 'Sure', 'confirm', 'go ahead', 'haan']) {
        expect(parseConfirmationReply(s), isTrue, reason: s);
      }
    });
    test('no-type answers cancel', () {
      for (final s in ['no', 'No.', 'cancel', "don't", 'wait', 'keep it']) {
        expect(parseConfirmationReply(s), isFalse, reason: s);
      }
    });
    test('new requests and long messages go to the AI', () {
      for (final s in ['', 'what is my attendance in Maths', 'add a physics exam tomorrow',
          'yes and also add a Maths exam for next friday please']) {
        expect(parseConfirmationReply(s), isNull, reason: s);
      }
    });
  });
}
