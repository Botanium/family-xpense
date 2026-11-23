// "Today" and "Yesterday" on entry detail compare calendar dates, never
// elapsed local time (Codex review, PR #39): across a daylight-saving
// change a local day lasts 23 or 25 hours.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/features/activity/detail/entry_days.dart';
import 'package:xpense_app/features/activity/detail/entry_labels.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  test('days ago, here', () {
    final now = DateTime(2026, 11, 22, 9);
    expect(entryDaysAgo(DateTime(2026, 11, 22, 0, 5), now), 0);
    expect(entryDaysAgo(DateTime(2026, 11, 21, 23, 55), now), 1);
    expect(entryDaysAgo(DateTime(2025, 11, 22, 12), now), 365);
  });

  test('the labels use the calendar day', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final now = DateTime(2026, 11, 22, 9);
    expect(
      l10n.entryWhen(DateTime(2026, 11, 21, 20), now, 'en'),
      'Yesterday 20:00',
    );
    expect(l10n.entryWhen(DateTime(2026, 11, 22, 8), now, 'en'), 'Today 08:00');
    expect(
      l10n.entryWhen(DateTime(2026, 11, 20, 8), now, 'en'),
      'Nov 20 08:00',
    );
  });

  test(
    'across daylight saving in America/New_York, last night is yesterday',
    () async {
      final result = await Process.run(
        'dart',
        ['run', 'test/activity/entry_days_dst_probe.dart'],
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
      expect(probe['lastNight'], 1);
      expect(probe['thisMorning'], 0);
      expect(probe['twoDaysAgo'], 2);
      expect(probe['utcLastNight'], 1);
      expect(probe['autumnYesterday'], 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
