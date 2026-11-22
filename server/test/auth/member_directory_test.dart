import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/auth/auth_failure.dart';
import 'package:xpense_agent/auth/member_directory.dart';
import 'package:xpense_agent/auth/xpense_context.dart';

import '../support/fakes.dart';

void main() {
  late FakeDocumentStore docs;
  late DateTime now;
  late MemberDirectory directory;

  setUp(() {
    docs = FakeDocumentStore()
      ..seedMember(uid: 'u1', hid: 'h1', privacyMode: 'cloud');
    now = DateTime.utc(2026, 11, 22);
    directory = MemberDirectory(docs, clock: Clock(() => now), maxEntries: 2);
  });

  test('reads user, household and member documents', () async {
    final record = await directory.lookup('u1');
    expect(record.hid, 'h1');
    expect(record.privacyMode, PrivacyMode.cloud);
    expect(docs.reads, {
      'users/u1',
      'households/h1',
      'households/h1/members/u1',
    });
  });

  test('concurrent lookups share one read', () async {
    final records = await Future.wait([
      directory.lookup('u1'),
      directory.lookup('u1'),
      directory.lookup('u1'),
    ]);
    expect(records.toSet(), hasLength(1));
    expect(docs.readsOf('users/u1'), 1);
  });

  test('entries expire after the ttl', () async {
    await directory.lookup('u1');
    now = now.add(const Duration(seconds: 60));
    await directory.lookup('u1');
    expect(docs.readsOf('users/u1'), 2);
  });

  test('invalidate drops the entry', () async {
    await directory.lookup('u1');
    directory.invalidate('u1');
    await directory.lookup('u1');
    expect(docs.readsOf('users/u1'), 2);
  });

  test('failures are not cached', () async {
    docs.failingPaths.add('users/u1');
    await expectLater(directory.lookup('u1'), throwsA(anything));
    docs.failingPaths.clear();
    expect((await directory.lookup('u1')).hid, 'h1');
  });

  test('rejections carry the typed failure', () async {
    await expectLater(
      directory.lookup('ghost'),
      throwsA(
        isA<AuthRejection>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.noHousehold,
        ),
      ),
    );
  });

  test('the cache is bounded; the oldest entry goes first', () async {
    docs
      ..seedMember(uid: 'u2', hid: 'h2')
      ..seedMember(uid: 'u3', hid: 'h3');
    await directory.lookup('u1');
    await directory.lookup('u2');
    await directory.lookup('u3');
    await directory.lookup('u3');
    await directory.lookup('u1');
    expect(docs.readsOf('users/u3'), 1);
    expect(docs.readsOf('users/u1'), 2);
  });

  test('isDocumentId accepts ids and refuses paths', () {
    for (final id in ['u1', 'aZ09_-', '0193a1b2-7c3d-7e4f-8a9b-0c1d2e3f4a5b']) {
      expect(isDocumentId(id), isTrue, reason: id);
    }
    for (final id in ['', 'a/b', '..', 'a b', 'x' * 129, 'é']) {
      expect(isDocumentId(id), isFalse, reason: id);
    }
  });
}
