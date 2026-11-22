import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xpense_app/services/service_failure.dart';

/// One thing the recogniser reports while listening (ARCHITECTURE 5.4).
@immutable
sealed class SpeechEvent {
  const new();
}

/// The words so far; replaced by the next partial or the final result.
final class SpeechPartial extends SpeechEvent {
  /// Wraps [text].
  const new(this.text);

  /// The words so far.
  final String text;
}

/// The final transcript. Ends the session.
final class SpeechFinal extends SpeechEvent {
  /// Wraps [text].
  const new(this.text);

  /// The transcript.
  final String text;
}

/// The input level for the live waveform.
final class SpeechLevel extends SpeechEvent {
  /// Wraps [level].
  const new(this.level);

  /// Input level from 0 (silence) to 1 (loudest).
  final double level;
}

/// Listening stopped with [failure]. Ends the session.
final class SpeechFailed extends SpeechEvent {
  /// Wraps [failure].
  const new(this.failure);

  /// Why listening stopped.
  final ServiceFailure failure;
}

/// Speech to text (ARCHITECTURE 3.2). Wraps `speech_to_text` with the
/// on-device flag, and `record` for raw audio, which only
/// `lib/services/` may import. On-device recognition differs by phone.
abstract interface class SpeechCapture {
  /// Whether this phone can recognise [localeId] without the network.
  Future<bool> supportsOnDevice(String localeId);

  /// Starts listening. The stream ends after [SpeechFinal] or
  /// [SpeechFailed] and never emits an error. With [onDeviceOnly], audio
  /// never leaves the phone.
  Stream<SpeechEvent> listen({
    required String localeId,
    required bool onDeviceOnly,
  });

  /// Stops listening; the stream then delivers its [SpeechFinal].
  Future<void> stop();
}

/// The [SpeechCapture] for this run. Throws until the composition root
/// sets it.
final speechCaptureProvider = Provider<SpeechCapture>(
  (ref) =>
      throw UnimplementedError('speechCaptureProvider is set in bootstrap()'),
  name: 'speechCaptureProvider',
);
