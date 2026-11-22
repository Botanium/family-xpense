import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Which on-device model engine a phone can run (ARCHITECTURE 5.1).
enum OnDeviceEngine {
  /// Apple Foundation Models (iOS 26 and later, Apple Intelligence on).
  appleFoundationModels,

  /// Gemini Nano (Android).
  geminiNano,

  /// A bundled Gemma model through LiteRT-LM.
  gemma,

  /// No engine; single-entry extraction goes to the cloud path.
  none,
}

/// What the startup probe found.
@immutable
final class OnDeviceProbe {
  /// Creates a probe result.
  const new({required this.engine});

  /// No engine available.
  static const OnDeviceProbe unavailable = OnDeviceProbe(
    engine: OnDeviceEngine.none,
  );

  /// The engine this phone can run.
  final OnDeviceEngine engine;

  /// Whether any engine is available.
  bool get isAvailable => engine != OnDeviceEngine.none;

  @override
  bool operator ==(Object other) =>
      other is OnDeviceProbe && other.engine == engine;

  @override
  int get hashCode => engine.hashCode;
}

/// The on-device model for single-entry extraction and, in On-device mode,
/// classification (ARCHITECTURE 3.2). Wraps `flutter_edge_ai` and its
/// engine packages, which only `lib/services/` may import.
abstract interface class OnDeviceLlm {
  /// Finds out which engine this phone can run. Runs after the first frame
  /// (ARCHITECTURE 3.3); never throws.
  Future<OnDeviceProbe> probe();

  /// Turns one single-entry message into a draft. Never throws.
  Future<Result<EntryDraft, ServiceFailure>> extractEntry(String text);
}

/// The [OnDeviceLlm] for this run. Throws until the composition root sets
/// it.
final onDeviceLlmProvider = Provider<OnDeviceLlm>(
  (ref) =>
      throw UnimplementedError('onDeviceLlmProvider is set in bootstrap()'),
  name: 'onDeviceLlmProvider',
);

/// What this phone's on-device model can do, probed once after the first
/// frame (ARCHITECTURE 3.3) and cached for the capture router.
final onDeviceProbeProvider = FutureProvider<OnDeviceProbe>(
  (ref) => ref.watch(onDeviceLlmProvider).probe(),
  name: 'onDeviceProbeProvider',
);
