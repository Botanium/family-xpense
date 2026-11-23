// Day labels compare calendar dates, never elapsed local time (Codex
// review, PR #38): across a daylight-saving change a local day lasts 23 or
// 25 hours.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/features/activity/activity_dates.dart';

void main() {
  test('days before today, here', () {
    final now = DateTime(2026, 11, 22, 9);
    expect(daysBefore('2026-11-22', now), 0);
    expect(daysBefore('2026-11-21', now), 1);
    expect(daysBefore('2025-11-22', now), 365);
    expect(daysBefore('not a day', now), isNull);
    expect(dayBefore(now, 1), '2026-11-21');
    expect(dayBefore(DateTime(2026, 3, 2), 2), '2026-02-28');
  });

  test(
    'across daylight saving in America/New_York, yesterday stays yesterday',
    () async {
      final result = await Process.run(
        'dart',
        ['run', 'test/activity/dst_probe.dart'],
        environment: {'TZ': 'America/New_York'},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final probe = jsonDecode(
        const LineSplitter()
            .convert('${result.stdout}')
            .lastWhere((l) => l.startsWith('{')),
      ) as Map<String, Object?>;
      // The probe really ran in New York: 8 March 2026 lasted 23 hours.
      expect(probe['localDayHours'], 23);
      expect(probe['today'], 0);
      expect(probe['yesterday'], 1);
      expect(probe['autumnYesterday'], 1);
      expect(probe['dayBefore1'], '2026-03-08');
      expect(probe['dayBefore2'], '2026-03-07');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
