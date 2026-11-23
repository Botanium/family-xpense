// The Firestore store's server-first reads (Codex review, PR #35): the day's
// rate comes from the server when it answers in time, else from the cache,
// so a save never takes an older cached rate while online and never blocks
// offline. The store itself runs against the emulator
// (integration_test/transactions_emulator_test.dart).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/write/firestore_ledger_store.dart';

void main() {
  const timeout = Duration(milliseconds: 50);
  Future<String> cache() async => 'cached older day';

  test('the server answer wins over an older cached one', () async {
    expect(
      await serverThenCache(
        () async => 'server newer day',
        cache,
        timeout: timeout,
      ),
      'server newer day',
    );
  });

  test('offline (the server read fails) uses the cache', () async {
    expect(
      await serverThenCache<String>(
        () async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        ),
        cache,
        timeout: timeout,
      ),
      'cached older day',
    );
  });

  test('a slow server falls back to the cache in time', () async {
    final slow = Completer<String>();
    final watch = Stopwatch()..start();
    expect(
      await serverThenCache(() => slow.future, cache, timeout: timeout),
      'cached older day',
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    slow.complete('too late');
  });

  test('null when neither answers', () async {
    Future<String> fails() async =>
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    expect(await serverThenCache(fails, fails, timeout: timeout), isNull);
  });
}
