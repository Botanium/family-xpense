/// What the agent tools depend on, injected by the runtime.
library;

import 'package:clock/clock.dart';

import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_agent/tools/household_snapshot.dart';
import 'package:xpense_agent/tools/turn_evidence.dart';

/// The confidence thresholds of AI_PIPELINE 9, from `config/runtime`.
typedef Thresholds = Map<String, double>;

/// The tools' collaborators.
final class ToolDeps {
  /// Creates the dependencies.
  ///
  /// [turnText] returns the text of the user messages of the current agent
  /// turn and its history, oldest first. The runtime reads them from the
  /// agent session; `prepareEntries` checks every amount against them.
  new({
    required this.reader,
    required this.classifier,
    required this.thresholds,
    required this.turnText,
    HouseholdSnapshots? snapshots,
    Clock? clock,
    TurnEvidence? Function()? evidence,
    Future<bool> Function(String hid)? decisionsLeft,
  }) : decisionsLeft = decisionsLeft ?? _always,
       evidence = evidence ?? (() => TurnEvidence.current),
       clock = clock ?? const Clock(),
       snapshots = snapshots ?? HouseholdSnapshots(reader, clock: clock);

  /// Household data.
  final HouseholdReader reader;

  /// Cached household views.
  final HouseholdSnapshots snapshots;

  /// The classification step (WP-33).
  final EntryClassifier classifier;

  /// The current confidence thresholds.
  final Future<Thresholds> Function() thresholds;

  /// The user texts of the conversation, oldest first.
  final List<String> Function() turnText;

  /// The running turn's media evidence (tests inject one).
  final TurnEvidence? Function() evidence;

  /// The wall clock.
  final Clock clock;

  /// Whether household `hid` has `decisions` allowance left today; checked
  /// before each classifier call, which counts against it like `/decide`.
  final Future<bool> Function(String hid) decisionsLeft;

  static Future<bool> _always(String _) async => true;
}

/// Reads a threshold with its documented default.
double threshold(Thresholds t, String key) =>
    t[key] ??
    const {
      'conf_high': 0.85,
      'conf_low': 0.55,
      'conf_intent_min': 0.90,
      'conf_on_device_cap': 0.80,
      'dup_warn': 0.80,
      'recurring_offer': 0.75,
    }[key]!;
