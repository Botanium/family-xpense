// The router's decision table (AI_PIPELINE 2, story S3.8): one test per
// row, each built so that only its row can match first, plus the edges
// between rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/features/capture/router/capture_router.dart';
import 'package:xpense_shared/xpense_shared.dart';

Signals _signals({
  int amounts = 1,
  bool conjunction = false,
  bool question = false,
  bool command = false,
  bool personTransfer = false,
  List<UnresolvedField> unresolved = const [UnresolvedField.category],
  Attachment attachment = Attachment.none,
}) => Signals(
  amountCount: amounts,
  hasConjunction: conjunction,
  isQuestion: question,
  isCommand: command,
  hasPersonTransfer: personTransfer,
  unresolved: unresolved,
  attachment: attachment,
);

RouteDecision _route(
  Signals signals, {
  CapturePrivacyMode mode = CapturePrivacyMode.smart,
  bool online = true,
  bool model = false,
  bool transcript = true,
  bool noModelUsesDecide = true,
}) => routeCapture(
  RouteInput(
    mode: mode,
    online: online,
    onDeviceModel: model,
    signals: signals,
    onDeviceTranscript: transcript,
    noModelUsesDecide: noModelUsesDecide,
  ),
);

void main() {
  group('decision table, first matching row wins', () {
    test('row 1: On-device only mode is path L, even for a question', () {
      final d = _route(
        _signals(question: true, amounts: 0),
        mode: CapturePrivacyMode.onDevice,
        online: false,
      );
      expect(d.path, CapturePath.local);
      expect(d.reason, RouteReason.onDeviceMode);
      expect(d.reason.row, 1);
      expect(d.offerManualOrQueue, isFalse);
    });

    test('row 2: offline is path L; a simple entry offers nothing more', () {
      final d = _route(_signals(), online: false, model: true);
      expect(d.path, CapturePath.local);
      expect(d.reason, RouteReason.offline);
      expect(d.offerManualOrQueue, isFalse);
    });

    test('row 2: offline, with a message rows 3 to 5 would take to the '
        'agent, offers Finish manually or Queue for later', () {
      for (final s in [
        _signals(attachment: Attachment.audio),
        _signals(question: true),
        _signals(command: true),
        _signals(amounts: 2),
        _signals(conjunction: true),
        _signals(amounts: 0),
      ]) {
        final d = _route(s, online: false, transcript: false);
        expect(d.path, CapturePath.local, reason: '$s');
        expect(d.offerManualOrQueue, isTrue, reason: '$s');
      }
    });

    test('row 3: audio with no on-device transcript is path A', () {
      final d = _route(
        _signals(attachment: Attachment.audio, unresolved: const []),
        transcript: false,
      );
      expect(d.path, CapturePath.agent);
      expect(d.reason, RouteReason.cloudAudio);
    });

    test('row 3 does not apply when the phone transcribed the audio', () {
      final d = _route(
        _signals(attachment: Attachment.audio, unresolved: const []),
      );
      expect(d.reason, RouteReason.resolved);
    });

    test('row 4: a question is path A', () {
      final d = _route(_signals(question: true, unresolved: const []));
      expect(d.path, CapturePath.agent);
      expect(d.reason, RouteReason.questionOrCommand);
    });

    test('row 4: a command is path A', () {
      final d = _route(_signals(command: true, unresolved: const []));
      expect(d.path, CapturePath.agent);
      expect(d.reason, RouteReason.questionOrCommand);
    });

    test('row 5: two or more amounts are path A', () {
      final d = _route(_signals(amounts: 2, unresolved: const []));
      expect(d.path, CapturePath.agent);
      expect(d.reason, RouteReason.complex);
    });

    test('row 5: a conjunction is path A', () {
      final d = _route(_signals(conjunction: true, unresolved: const []));
      expect(d.reason, RouteReason.complex);
    });

    test('row 5: no amount is path A', () {
      final d = _route(_signals(amounts: 0, unresolved: const []));
      expect(d.path, CapturePath.agent);
      expect(d.reason, RouteReason.complex);
    });

    test('row 6: nothing unresolved is path L', () {
      final d = _route(_signals(unresolved: const []), model: true);
      expect(d.path, CapturePath.local);
      expect(d.reason, RouteReason.resolved);
      expect(d.extractOnDevice, isFalse);
    });

    test('row 7: a model in Smart mode extracts on device, then path D', () {
      final d = _route(_signals(), model: true);
      expect(d.path, CapturePath.decide);
      expect(d.reason, RouteReason.onDeviceThenDecide);
      expect(d.extractOnDevice, isTrue);
    });

    test('row 8: one amount and no model is path D with the raw text', () {
      final d = _route(_signals());
      expect(d.path, CapturePath.decide);
      expect(d.reason, RouteReason.decideRawText);
      expect(d.extractOnDevice, isFalse);
    });

    test('row 8: Cloud mode skips extraction, so a model still goes to D '
        'with the raw text', () {
      final d = _route(_signals(), mode: CapturePrivacyMode.cloud, model: true);
      expect(d.path, CapturePath.decide);
      expect(d.reason, RouteReason.decideRawText);
      expect(d.extractOnDevice, isFalse);
    });

    test('row 9: with router_no_model_uses_decide off, row 8 is skipped and '
        'the message goes to the agent', () {
      final d = _route(_signals(), noModelUsesDecide: false);
      expect(d.path, CapturePath.agent);
      expect(d.reason, RouteReason.fallback);
      expect(d.reason.row, 9);
    });
  });

  test('a person transfer alone does not force path A', () {
    final d = _route(_signals(personTransfer: true));
    expect(d.path, CapturePath.decide);
  });

  test('every reason has a distinct code and row', () {
    expect(RouteReason.values.map((r) => r.code).toSet(), hasLength(9));
    expect(RouteReason.values.map((r) => r.row), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
  });

  test('decisions compare by value', () {
    expect(
      _route(_signals()),
      const RouteDecision(
        path: CapturePath.decide,
        reason: RouteReason.decideRawText,
      ),
    );
  });
}
