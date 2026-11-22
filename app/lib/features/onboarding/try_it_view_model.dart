import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_app/services/speech_capture.dart';

/// Where the first message from Try it goes.
///
/// A stub until the capture pipeline can take it: the router and fast
/// parse arrive in WP-34, voice in WP-40. The composition root overrides
/// [tryItCaptureProvider] with the real pipeline then; the screen does not
/// change.
abstract interface class TryItCapture {
  /// Handles [text], typed or transcribed. Saves nothing.
  Future<void> submit(String text);
}

/// The [TryItCapture] until capture exists: accepts the text and does
/// nothing with it.
final class StubTryItCapture implements TryItCapture {
  /// Creates the stub.
  const new();

  @override
  Future<void> submit(String text) async {}
}

/// The [TryItCapture] for this run.
final tryItCaptureProvider = Provider<TryItCapture>(
  (ref) => const StubTryItCapture(),
  name: 'tryItCaptureProvider',
);

/// Why Try it switched from voice to typing.
enum VoiceNotice {
  /// Speech recognition cannot run here (no recogniser, or the fake).
  unavailable,

  /// The person declined microphone or speech permission.
  denied,

  /// Listening stopped for another reason.
  failed,
}

/// The locale Try it listens in; English only for now (DESIGN_SYSTEM 10).
const String tryItLocale = 'en-US';

/// Most waveform levels kept; older ones scroll out of the dock.
const int _maxLevels = 48;

/// What Try it shows (DESIGN_SYSTEM 9, screen 5).
@immutable
final class TryItState {
  /// Creates a state; the default waits for voice.
  const new({
    this.mode = CaptureMode.voice,
    this.listening = false,
    this.levels = const [],
    this.notice,
    this.sending = false,
    this.sent,
  });

  /// Voice or typing in the dock.
  final CaptureMode mode;

  /// Whether the microphone is on.
  final bool listening;

  /// Live waveform levels while listening.
  final List<double> levels;

  /// Why voice gave way to typing, if it did.
  final VoiceNotice? notice;

  /// Whether a message is being handed over.
  final bool sending;

  /// The message the person sent; the screen then offers Home.
  final String? sent;

  /// Returns a copy with the given fields replaced. [notice] and [sent]
  /// are cleared unless given.
  TryItState copyWith({
    CaptureMode? mode,
    bool? listening,
    List<double>? levels,
    VoiceNotice? notice,
    bool? sending,
    String? sent,
  }) => TryItState(
    mode: mode ?? this.mode,
    listening: listening ?? this.listening,
    levels: levels ?? this.levels,
    notice: notice,
    sending: sending ?? this.sending,
    sent: sent ?? this.sent,
  );

  @override
  bool operator ==(Object other) =>
      other is TryItState &&
      other.mode == mode &&
      other.listening == listening &&
      listEquals(other.levels, levels) &&
      other.notice == notice &&
      other.sending == sending &&
      other.sent == sent;

  @override
  int get hashCode => Object.hash(
    mode,
    listening,
    Object.hashAll(levels),
    notice,
    sending,
    sent,
  );
}

/// The view model of Try it: the dock's mode, listening through
/// [SpeechCapture], and handing the message to [TryItCapture].
final class TryItViewModel extends Notifier<TryItState> {
  StreamSubscription<SpeechEvent>? _listening;

  @override
  TryItState build() {
    ref.onDispose(() => unawaited(_listening?.cancel()));
    return const TryItState();
  }

  /// Switches the dock between voice and typing. Switching away while
  /// listening drops what was heard: nothing half-said is sent.
  void setMode(CaptureMode mode) {
    if (state.listening) {
      unawaited(_listening?.cancel());
      _listening = null;
      unawaited(stopListening());
    }
    if (state.mode == mode && !state.listening) return;
    state = state.copyWith(mode: mode, listening: false, levels: const []);
  }

  /// The orange button: starts listening, or stops when listening.
  Future<void> toggleListening() =>
      state.listening ? stopListening() : _startListening();

  /// Stops listening; the recogniser then delivers its final words.
  Future<void> stopListening() => ref.read(speechCaptureProvider).stop();

  Future<void> _startListening() async {
    if (state.sending) return;
    await _listening?.cancel();
    state = state.copyWith(listening: true, levels: const []);
    // Smart mode lets iOS use the network when the phone has no on-device
    // recogniser; the household's privacy mode joins here with WP-40.
    _listening = ref
        .read(speechCaptureProvider)
        .listen(localeId: tryItLocale, onDeviceOnly: false)
        .listen(_onSpeech);
  }

  void _onSpeech(SpeechEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case SpeechLevel(:final level):
        final levels = [...state.levels, level];
        state = state.copyWith(
          levels: levels.length > _maxLevels
              ? levels.sublist(levels.length - _maxLevels)
              : levels,
        );
      case SpeechPartial():
        break;
      case SpeechFinal(:final text):
        state = state.copyWith(listening: false, levels: const []);
        unawaited(submit(text));
      case SpeechFailed(:final failure):
        state = state.copyWith(
          mode: CaptureMode.type,
          listening: false,
          levels: const [],
          notice: switch (failure) {
            ServiceUnavailable() || ServiceOffline() => VoiceNotice.unavailable,
            ServicePermissionDenied() => VoiceNotice.denied,
            ServiceCancelled() => null,
            ServiceRateLimited() || ServiceError() => VoiceNotice.failed,
          },
        );
    }
  }

  /// Hands [text] to [TryItCapture]. Blank text is ignored.
  Future<void> submit(String text) async {
    final message = text.trim();
    if (message.isEmpty || state.sending) return;
    state = state.copyWith(sending: true);
    try {
      await ref.read(tryItCaptureProvider).submit(message);
      if (ref.mounted) state = state.copyWith(sending: false, sent: message);
    } finally {
      // A failure reaches the global error handler; the dock stays usable.
      if (ref.mounted && state.sending) state = state.copyWith(sending: false);
    }
  }
}

/// Try it's view model, disposed with the screen.
final NotifierProvider<TryItViewModel, TryItState> tryItViewModelProvider =
    NotifierProvider.autoDispose<TryItViewModel, TryItState>(
      TryItViewModel.new,
      name: 'tryItViewModelProvider',
    );
