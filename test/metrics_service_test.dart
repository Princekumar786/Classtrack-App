import 'package:classtrack/services/metrics_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MetricsService.resetSessionForTest);

  test('impressions are sent once per resource per session', () async {
    final db = FakeFirebaseFirestore();
    final m = MetricsService(db, 'u1');
    await m.recordImpression('r1');
    await m.recordImpression('r1');
    await m.recordImpression('r2');
    final docs = (await db.collection('events').get()).docs;
    expect(docs.length, 2);
    expect(docs.first.data()['event'], 'impression');
    expect(docs.first.data()['uid'], 'u1');
  });

  test('banner impressions dedupe, clicks always count', () async {
    final db = FakeFirebaseFirestore();
    final m = MetricsService(db, 'u1');
    await m.recordBanner('b1', 'impression');
    await m.recordBanner('b1', 'impression');
    await m.recordBanner('b1', 'click');
    await m.recordBanner('b1', 'click');
    final docs = (await db.collection('events').get()).docs;
    expect(docs.length, 3);
    expect(docs.every((d) => d.data()['bannerId'] == 'b1'), isTrue);
    expect(docs.any((d) => d.data().containsKey('resourceId')), isFalse);
  });

  test('signed-out users send nothing', () async {
    final db = FakeFirebaseFirestore();
    await MetricsService(db, null).recordImpression('r1');
    expect((await db.collection('events').get()).docs, isEmpty);
  });
}
