/// Server tunables from the Firestore document `config/runtime`.
///
/// Model ids, per-household daily limits, switches and confidence thresholds
/// (DATA_MODEL 2.15, ARCHITECTURE 4.5, AI_PIPELINE 8 and 9). The document is
/// server-only (rules deny all client access). Every field is optional: a
/// missing or malformed field falls back to its default, so a typo in the
/// console degrades one setting instead of the service.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';

final _log = Logger('xpense.config');

/// The parsed `config/runtime` document.
///
/// ```json
/// {
///   "models": {"agent": "gemini-3.5-flash-lite",
///              "escalation": "gemini-3.8-flash",
///              "decide": "gemini-decision-1",
///              "decideFallback": "gemini-3.5-flash-lite",
///              "monthlyReport": "gemini-3.8-flash"},
///   "limits": {"agentTurns": 150, "decisions": 600,
///              "audioSeconds": 600, "images": 40},
///   "switches": {"agentEnabled": true, "decideEnabled": true,
///                "liteOnly": false},
///   "confidence": {"conf_high": 0.85, "conf_low": 0.55, ...}
/// }
/// ```
@immutable
final class RuntimeConfig {
  /// Creates a config. Use [RuntimeConfig.defaults] or
  /// [RuntimeConfig.fromDocument].
  const new({
    required this.models,
    required this.limits,
    required this.switches,
    required this.confidence,
  });

  /// Parses the document, falling back field by field to [defaults].
  factory fromDocument(Map<String, Object?>? doc) {
    if (doc == null) return defaults;
    return RuntimeConfig(
      models: {
        ...defaults.models,
        ..._entries<String>(doc['models'], (v) => v is String && v.isNotEmpty),
      },
      limits: {
        ...defaults.limits,
        for (final MapEntry(:key, :value) in _entries<int>(
          doc['limits'],
          (v) => v is int && v >= 0,
        ).entries)
          ?UsageCounter.byField(key): value,
      },
      switches: {
        ...defaults.switches,
        ..._entries<bool>(doc['switches'], (v) => v is bool),
      },
      confidence: {
        ...defaults.confidence,
        ..._entries<double>(
          doc['confidence'],
          (v) => v is num && v >= 0 && v <= 1,
          convert: (v) => (v! as num).toDouble(),
        ),
      },
    );
  }

  /// The defaults from the docs; used until `config/runtime` is written.
  static const defaults = RuntimeConfig(
    // D-04: pinned ids, no -latest aliases.
    models: {
      'agent': 'gemini-3.5-flash-lite',
      'escalation': 'gemini-3.8-flash',
      'decide': 'gemini-decision-1',
      'decideFallback': 'gemini-3.5-flash-lite',
      'monthlyReport': 'gemini-3.8-flash',
    },
    // ARCHITECTURE 4.5, per household per day.
    limits: {
      UsageCounter.agentTurns: 150,
      UsageCounter.decisions: 600,
      UsageCounter.audioSeconds: 600,
      UsageCounter.images: 40,
    },
    switches: {
      'agentEnabled': true,
      'decideEnabled': true,
      // The global spend ceiling: when true, /agent uses Flash-Lite only.
      'liteOnly': false,
    },
    // AI_PIPELINE 9, mirrored from Remote Config.
    confidence: {
      'conf_high': 0.85,
      'conf_low': 0.55,
      'conf_intent_min': 0.90,
      'conf_on_device_cap': 0.80,
      'dup_warn': 0.80,
      'recurring_offer': 0.75,
    },
  );

  /// Model id per role (`agent`, `escalation`, `decide`, ...).
  final Map<String, String> models;

  /// Daily limit per metered counter. Counters without an entry are not
  /// limited.
  final Map<UsageCounter, int> limits;

  /// Feature switches.
  final Map<String, bool> switches;

  /// Confidence thresholds, 0 to 1.
  final Map<String, double> confidence;

  /// The model id for [role]. Throws [StateError] for an unknown role, which
  /// is a programming error (defaults cover every role the code uses).
  String model(String role) =>
      models[role] ?? (throw StateError('No model configured for "$role"'));

  /// Whether [name] is on. Unknown switches are off.
  bool isOn(String name) => switches[name] ?? false;

  static Map<String, T> _entries<T>(
    Object? section,
    bool Function(Object? value) valid, {
    T Function(Object? value)? convert,
  }) {
    if (section is! Map) return const {};
    final out = <String, T>{};
    for (final MapEntry(:key, :value) in section.entries) {
      if (key is String && valid(value)) {
        out[key] = convert == null ? value as T : convert(value);
      } else {
        _log.warning('config/runtime: ignoring invalid value for "$key"');
      }
    }
    return out;
  }
}

/// Loads `config/runtime` and keeps it for [ttl].
///
/// If a refresh fails, the last good config stays in use (or the defaults,
/// before the first successful read), so a Firestore blip never blocks
/// requests.
final class RuntimeConfigLoader {
  /// Creates a loader over a [DocumentStore].
  new(
    this._documents, {
    Clock? clock,
    this.ttl = const Duration(seconds: 60),
    this.path = 'config/runtime',
  }) : _clock = clock ?? const Clock();

  final DocumentStore _documents;
  final Clock _clock;

  /// How long a loaded config is reused.
  final Duration ttl;

  /// Document path.
  final String path;

  RuntimeConfig? _current;
  DateTime? _expiresAt;
  Future<RuntimeConfig>? _inFlight;

  /// The current config.
  Future<RuntimeConfig> current() {
    final current = _current;
    final expiresAt = _expiresAt;
    if (current != null &&
        expiresAt != null &&
        _clock.now().isBefore(expiresAt)) {
      return Future.value(current);
    }
    return _inFlight ??= _refresh().whenComplete(() => _inFlight = null);
  }

  Future<RuntimeConfig> _refresh() async {
    try {
      final config = RuntimeConfig.fromDocument(await _documents.read(path));
      _current = config;
      _expiresAt = _clock.now().add(ttl);
      return config;
    } on GatewayUnavailable catch (e) {
      _log.warning('config/runtime: read failed, keeping last good config', e);
      // Retry on the next request rather than hammering a failing backend
      // from every concurrent one.
      _expiresAt = _clock.now().add(const Duration(seconds: 5));
      return _current ??= RuntimeConfig.defaults;
    }
  }
}
