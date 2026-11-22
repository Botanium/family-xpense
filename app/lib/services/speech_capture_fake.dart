import 'dart:async';

import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_app/services/speech_capture.dart';

/// A [SpeechCapture] that replays [script], for tests and the simulator.
/// With the default empty script, listening fails as unavailable, so the
/// dock offers "Type instead".
final class FakeSpeechCapture implements SpeechCapture {
  /// Creates a fake recogniser.
  new({this.script = const [], this.onDevice = false});

  /// The events each session emits. A session that does not end itself
  /// ends with [SpeechFinal] of the last partial's text.
  List<SpeechEvent> script;

  /// What [supportsOnDevice] answers.
  bool onDevice;

  /// How many times [stop] was called.
  int stops = 0;

  @override
  Future<bool> supportsOnDevice(String localeId) async => onDevice;

  @override
  Stream<SpeechEvent> listen({
    required String localeId,
    required bool onDeviceOnly,
  }) async* {
    if (script.isEmpty || (onDeviceOnly && !onDevice)) {
      yield const SpeechFailed(ServiceUnavailable());
      return;
    }
    yield* Stream.fromIterable(script);
    final last = script.last;
    if (last is! SpeechFinal && last is! SpeechFailed) {
      final words = script.whereType<SpeechPartial>().lastOrNull?.text ?? '';
      yield SpeechFinal(words);
    }
  }

  @override
  Future<void> stop() async => stops++;
}
