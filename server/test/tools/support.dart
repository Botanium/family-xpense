// Shared set-up for the tool tests: the demo household on a fixed day.
import 'package:clock/clock.dart';

import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/runtime/demo_household.dart';
import 'package:xpense_agent/tools/in_memory_reader.dart';
import 'package:xpense_agent/tools/tool_deps.dart';

/// 2026-11-22 09:00 in Baghdad.
final fixedClock = Clock.fixed(DateTime.utc(2026, 11, 22, 6));

/// The demo member's context.
final dara = XpenseContext.of(demoContext);

/// The partner's context.
const shilan = XpenseContext(
  uid: demoPartnerUid,
  hid: demoHid,
  locale: 'en',
  privacyMode: PrivacyMode.smart,
  tz: 'Asia/Baghdad',
);

/// Tool dependencies over the demo household.
ToolDeps demoDeps({
  List<String> texts = const [],
  EntryClassifier? classifier,
  Map<String, double> thresholds = const {},
  InMemoryHouseholdReader? reader,
}) => ToolDeps(
  reader: reader ?? demoReader('2026-11-22'),
  classifier: classifier ?? FakeEntryClassifier(),
  thresholds: () async => thresholds,
  turnText: () => texts,
  clock: fixedClock,
);
