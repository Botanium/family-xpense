/// Step 0 of the pipeline: the capture router (AI_PIPELINE 2, story S3.8).
///
/// Pure Dart, no I/O. [routeCapture] reads the privacy mode, connectivity,
/// device capability and the fast parser's complexity signals, and returns
/// the path a message takes with a reason code. The reason is logged
/// without the message's content.
library;

import 'package:flutter/foundation.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The household's privacy mode (ARCHITECTURE 6).
enum CapturePrivacyMode {
  /// Nothing leaves the phone for AI processing.
  onDevice,

  /// The default: on-device first, Decisions API and the agent in the cloud.
  smart,

  /// Cloud processing allowed for everything.
  cloud,
}

/// The three capture paths (ARCHITECTURE 5).
enum CapturePath {
  /// Path L: on the phone only.
  local,

  /// Path D: the Decisions API through `/v1/decide`.
  decide,

  /// Path A: the Genkit agent.
  agent,
}

/// Why the router chose a path: one code per row of the decision table
/// (AI_PIPELINE 2). Logged, never shown.
enum RouteReason {
  /// Row 1: the mode is On-device only.
  onDeviceMode('on_device_mode', 1),

  /// Row 2: the phone is offline.
  offline('offline', 2),

  /// Row 3: audio with no on-device transcript.
  cloudAudio('cloud_audio', 3),

  /// Row 4: a question or a command.
  questionOrCommand('question_or_command', 4),

  /// Row 5: several amounts, a conjunction, or no amount.
  complex('complex', 5),

  /// Row 6: rules and explicit words settled every required field.
  resolved('resolved', 6),

  /// Row 7: extract on device, then classify what is still uncertain.
  onDeviceThenDecide('on_device_then_decide', 7),

  /// Row 8: one amount and no on-device extraction: classify the raw text.
  decideRawText('decide_raw_text', 8),

  /// Row 9: anything else.
  fallback('fallback', 9);

  new(this.code, this.row);

  /// The logged code.
  final String code;

  /// The decision-table row.
  final int row;
}

/// What the router knows about one message and the phone.
@immutable
final class RouteInput {
  /// Creates the input.
  const new({
    required this.mode,
    required this.online,
    required this.onDeviceModel,
    required this.signals,
    this.onDeviceTranscript = true,
    this.noModelUsesDecide = true,
  });

  /// The household's privacy mode.
  final CapturePrivacyMode mode;

  /// Whether the phone believes it can reach the backend.
  final bool online;

  /// Whether an on-device model that can extract an entry is available.
  final bool onDeviceModel;

  /// The fast parser's complexity signals.
  final Signals signals;

  /// For an audio attachment: whether the phone transcribed it itself.
  final bool onDeviceTranscript;

  /// Remote Config `router_no_model_uses_decide` (default true): row 8.
  final bool noModelUsesDecide;
}

/// The router's answer.
@immutable
final class RouteDecision {
  /// Creates a decision.
  const new({
    required this.path,
    required this.reason,
    this.extractOnDevice = false,
    this.offerManualOrQueue = false,
  });

  /// The path the message takes.
  final CapturePath path;

  /// Which row decided it.
  final RouteReason reason;

  /// Row 7: run on-device extraction before calling `/decide`.
  final bool extractOnDevice;

  /// Row 2: the message needs the cloud (rows 3 to 5 would apply), so the
  /// thread offers "Finish manually" or "Queue for later".
  final bool offerManualOrQueue;

  @override
  bool operator ==(Object other) =>
      other is RouteDecision &&
      other.path == path &&
      other.reason == reason &&
      other.extractOnDevice == extractOnDevice &&
      other.offerManualOrQueue == offerManualOrQueue;

  @override
  int get hashCode =>
      Object.hash(path, reason, extractOnDevice, offerManualOrQueue);

  @override
  String toString() =>
      'RouteDecision(${path.name}, ${reason.code}'
      '${extractOnDevice ? ', extract' : ''}'
      '${offerManualOrQueue ? ', offer manual or queue' : ''})';
}

/// Picks the path for one message: the first matching row of the decision
/// table in AI_PIPELINE 2 wins.
///
/// Row 8's "no on-device model" also covers Cloud mode, where on-device
/// extraction is skipped (ARCHITECTURE 6), so a single entry in Cloud mode
/// goes to `/decide` with the raw text rather than to the agent.
RouteDecision routeCapture(RouteInput input) {
  final s = input.signals;
  final needsAgent =
      (s.attachment == Attachment.audio && !input.onDeviceTranscript) ||
      s.isQuestion ||
      s.isCommand ||
      _isComplex(s);

  // Row 1.
  if (input.mode == CapturePrivacyMode.onDevice) {
    return const RouteDecision(
      path: CapturePath.local,
      reason: RouteReason.onDeviceMode,
    );
  }
  // Row 2.
  if (!input.online) {
    return RouteDecision(
      path: CapturePath.local,
      reason: RouteReason.offline,
      offerManualOrQueue: needsAgent,
    );
  }
  // Row 3.
  if (s.attachment == Attachment.audio && !input.onDeviceTranscript) {
    return const RouteDecision(
      path: CapturePath.agent,
      reason: RouteReason.cloudAudio,
    );
  }
  // Row 4.
  if (s.isQuestion || s.isCommand) {
    return const RouteDecision(
      path: CapturePath.agent,
      reason: RouteReason.questionOrCommand,
    );
  }
  // Row 5.
  if (_isComplex(s)) {
    return const RouteDecision(
      path: CapturePath.agent,
      reason: RouteReason.complex,
    );
  }
  // Row 6.
  if (s.unresolved.isEmpty) {
    return const RouteDecision(
      path: CapturePath.local,
      reason: RouteReason.resolved,
    );
  }
  // Row 7.
  if (input.onDeviceModel && input.mode == CapturePrivacyMode.smart) {
    return const RouteDecision(
      path: CapturePath.decide,
      reason: RouteReason.onDeviceThenDecide,
      extractOnDevice: true,
    );
  }
  // Row 8 (rows 5 and 6 leave exactly one amount here).
  final extractionSkipped =
      !input.onDeviceModel || input.mode == CapturePrivacyMode.cloud;
  if (s.amountCount == 1 && extractionSkipped && input.noModelUsesDecide) {
    return const RouteDecision(
      path: CapturePath.decide,
      reason: RouteReason.decideRawText,
    );
  }
  // Row 9.
  return const RouteDecision(
    path: CapturePath.agent,
    reason: RouteReason.fallback,
  );
}

bool _isComplex(Signals s) =>
    s.amountCount >= 2 || s.hasConjunction || s.amountCount == 0;
