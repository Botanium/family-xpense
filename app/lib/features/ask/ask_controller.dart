import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/data/rules_repository.dart';
import 'package:xpense_app/features/ask/ask_actions.dart';
import 'package:xpense_app/features/ask/ask_state.dart';
import 'package:xpense_app/features/ask/capture/confidence_policy.dart';
import 'package:xpense_app/features/ask/capture/draft_builder.dart';
import 'package:xpense_app/services/agent_client.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_app/services/decisions_client.dart';
import 'package:xpense_app/services/feature_flags.dart';
import 'package:xpense_app/services/on_device_llm/on_device_llm.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// One Ask thread: the router, the three capture paths, and the surfaces
/// they render (ARCHITECTURE 5, stories S3.8 to S3.11).
///
/// Each thread owns one [XpenseSurfaceHost] and one agent conversation;
/// leaving the screen disposes both.
final class AskController extends Notifier<AskState> {
  late XpenseSurfaceHost _host;
  late AgentConversation _conversation;
  late AskActions _actions;
  final Map<String, RuleKind> _ruleKinds = {};
  final Set<String> _shownSurfaces = {};
  StreamSubscription<AgentEvent>? _turn;
  int _next = 0;
  // The running on-device extraction or Decisions call. Stop moves it on,
  // so a late answer from a stopped call is dropped.
  int _operation = 0;

  /// The thread's surface host, for the thread view.
  XpenseSurfaceHost get host => _host;

  @override
  AskState build() {
    _actions = AskActions(
      inner: ref.watch(xpenseActionsProvider),
      // Read when used: a new rules store (the membership changed) must
      // not reset the thread.
      rules: () => ref.read(rulesRepositoryProvider),
      send: (text) => unawaited(send(text)),
      ruleKinds: _ruleKinds,
    );
    _host = XpenseSurfaceHost(
      actions: _actions,
      onAgentAction: (action) => unawaited(_agentAction(action)),
      onIssue: (issue) => debugPrint('ask surface issue: ${issue.code}'),
    );
    _conversation = ref.watch(agentClientProvider).open();
    final host = _host;
    final conversation = _conversation;
    ref.onDispose(() {
      unawaited(_turn?.cancel());
      unawaited(conversation.close());
      host.dispose();
    });
    // Warm the probe so the first message does not wait for it.
    ref.listen(onDeviceProbeProvider, (_, _) {});
    return const AskState();
  }

  String _id(String prefix) => '$prefix${++_next}';

  /// What [text] would do now, for the mode chip. Null for empty text.
  RouteDecision? preview(String text) {
    if (text.trim().isEmpty) return null;
    return routeCapture(_routeInput(_parse(text)));
  }

  /// Sends a typed message through the router.
  Future<void> send(String text) async {
    final raw = text.trim();
    if (raw.isEmpty || state.busy) return;
    _add(QuoteItem(_id('q'), raw));
    await _dispatch(raw);
  }

  /// Sends [text] again after a notice, without repeating its quote.
  Future<void> retry(String text) async {
    if (state.busy) return;
    _removeNoticesFor(text);
    await _dispatch(text);
  }

  /// Builds the slip on the phone for [text], with pickers for what is
  /// missing (offline, limit, or the member's choice).
  void finishManually(String text) {
    _removeNoticesFor(text);
    final parse = _parse(text);
    if (parse.amounts.length != 1) {
      // Several entries need the agent; one slip per amount is a later
      // refinement (offline queue, WP-71).
      _add(NoticeItem(_id('n'), kind: AskNoticeKind.error, text: text));
      return;
    }
    _local(text, parse);
  }

  /// Stops the running agent turn, or the on-device extraction and
  /// Decisions call; what they answer later is dropped.
  Future<void> cancel() async {
    if (!state.busy) return;
    if (_turn != null) {
      await _conversation.cancel();
      return;
    }
    _operation++;
    state = state.copyWith(busy: false);
  }

  FastParse _parse(String raw) => parseText(
    raw,
    parseContextFor(
      _actions.household,
      clock: ref.read(clockProvider),
      rules: ref.read(rulesRepositoryProvider).current,
    ),
  );

  RouteInput _routeInput(FastParse parse, {bool? online}) {
    final flags = ref.read(featureFlagsProvider);
    return RouteInput(
      mode: ref.read(capturePrivacyModeProvider),
      online: online ?? !state.offline,
      onDeviceModel:
          ref.read(onDeviceProbeProvider).value?.isAvailable ?? false,
      signals: parse.signals,
      noModelUsesDecide: flags.routerNoModelUsesDecide,
    );
  }

  ConfidencePolicy get _policy =>
      ConfidencePolicy(ref.read(featureFlagsProvider).thresholds);

  Future<void> _dispatch(String raw) async {
    final parse = _parse(raw);
    // "Offline" is only what the last call found, so a new message tries
    // the network again; when that try finds no connection too, the
    // failure handling below does what row 2 says (the slip on the phone,
    // or Finish manually).
    final decision = routeCapture(_routeInput(parse, online: true));
    // Reason code and path only, never the message (AI_PIPELINE 2).
    debugPrint(
      'capture route: row ${decision.reason.row} ${decision.reason.code} '
      '-> ${decision.path.name}',
    );
    state = state.copyWith(lastRoute: decision);
    switch (decision.path) {
      case CapturePath.local:
        if (parse.amounts.length == 1) {
          _local(raw, parse);
        } else {
          // Row 1 or 2 with a message only the agent can read.
          _add(
            NoticeItem(
              _id('n'),
              kind: decision.reason == RouteReason.onDeviceMode
                  ? AskNoticeKind.privacy
                  : AskNoticeKind.offline,
              text: raw,
              canRetry: decision.reason != RouteReason.onDeviceMode,
            ),
          );
        }
      case CapturePath.decide:
        await _decide(raw, parse, decision);
      case CapturePath.agent:
        await _agentTurn(AgentTurn(text: raw), raw: raw);
    }
  }

  void _local(
    String raw,
    FastParse parse, {
    DecideResponse? decide,
    EntryDraft? extracted,
  }) {
    final surfaceId = '${localSurfacePrefix}cap_${++_next}';
    final draftId = 'd$_next';
    final draft = buildDraft(
      id: draftId,
      raw: raw,
      parse: parse,
      household: _actions.household,
      policy: _policy,
      decide: decide,
      extracted: extracted,
    );
    if (titleOf(raw, parse) case final title?) _ruleKinds[draftId] = title.kind;
    _host.addMessages(captureSurface(surfaceId: surfaceId, drafts: [draft]));
    _syncSurfaces();
  }

  Future<void> _decide(
    String raw,
    FastParse parse,
    RouteDecision decision,
  ) async {
    final operation = ++_operation;
    bool stopped() => !ref.mounted || operation != _operation;
    state = state.copyWith(busy: true);
    try {
      EntryDraft? extracted;
      if (decision.extractOnDevice) {
        final result = await ref.read(onDeviceLlmProvider).extractEntry(raw);
        if (stopped()) return;
        if (result case Ok(:final value)) extracted = value;
      }
      final result = await ref
          .read(decisionsClientProvider)
          .decide(decideRequestFor(raw, parse));
      if (stopped()) return;
      switch (result) {
        case Ok(:final value):
          state = state.copyWith(offline: false);
          // A question, command or other is not an entry: the agent
          // answers it (path A), never a slip.
          if (nonEntryIntent(parse, value, _policy) case final intent?) {
            debugPrint('decide: ${intent.wire} -> agent');
            await _agentTurn(AgentTurn(text: raw), raw: raw);
            return;
          }
          _local(raw, parse, decide: value, extracted: extracted);
        case Err(:final failure):
          // One path for every failure: the slip on the phone, with
          // pickers for what is still missing.
          _local(raw, parse, extracted: extracted);
          switch (failure) {
            case ServiceOffline():
              state = state.copyWith(offline: true);
            case ServiceRateLimited():
              _add(
                NoticeItem(
                  _id('n'),
                  kind: AskNoticeKind.limit,
                  text: raw,
                  canRetry: false,
                ),
              );
            case ServiceUnavailable() ||
                ServiceCancelled() ||
                ServicePermissionDenied() ||
                ServiceError():
              debugPrint('decide failed: ${failure.code}');
          }
      }
    } finally {
      if (!stopped()) state = state.copyWith(busy: false);
    }
  }

  Future<void> _agentAction(AgentAction action) async {
    if (state.busy) return;
    await _agentTurn(AgentTurn(text: '', actions: [action.payload]));
  }

  Future<void> _agentTurn(AgentTurn turn, {String? raw}) async {
    final saved = [for (final a in _host.takeSavedActions()) a.payload];
    final full = AgentTurn(
      text: turn.text,
      actions: [...saved, ...turn.actions],
    );
    state = state.copyWith(busy: true);
    _host.turnInProgress = true;
    ReplyItem? reply;
    final done = Completer<void>();
    _turn = _conversation
        .send(full)
        .listen(
          (event) {
            if (!ref.mounted) return;
            switch (event) {
              case AgentReply(:final text):
                final current = reply;
                if (current == null) {
                  reply = ReplyItem(_id('r'), text);
                  _add(reply!);
                } else {
                  reply = current.append(text);
                  _replace(current, reply!);
                }
              case AgentSurfaceMessages(:final messages):
                _host.addMessages(messages);
                _syncSurfaces();
              case AgentTurnDone(:final traceId):
                state = state.copyWith(
                  offline: false,
                  traceIds: [...state.traceIds, ?traceId],
                );
                if (traceId != null) debugPrint('agent turn trace: $traceId');
              case AgentTurnFailed(:final failure):
                _agentFailed(failure, raw);
            }
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
    await done.future;
    _turn = null;
    if (!ref.mounted) return;
    _host.turnInProgress = false;
    state = state.copyWith(busy: false);
  }

  void _agentFailed(ServiceFailure failure, String? raw) {
    debugPrint('agent turn failed: ${failure.code}');
    final single = raw != null && _parse(raw).amounts.length == 1;
    switch (failure) {
      case ServiceCancelled():
        return;
      case ServiceOffline():
        state = state.copyWith(offline: true);
        if (raw != null) {
          _add(
            NoticeItem(
              _id('n'),
              kind: AskNoticeKind.offline,
              text: raw,
              canFinishManually: single,
            ),
          );
        }
      case ServiceRateLimited():
        _add(
          NoticeItem(
            _id('n'),
            kind: AskNoticeKind.limit,
            text: raw ?? '',
            canRetry: false,
            canFinishManually: single,
          ),
        );
      case ServiceUnavailable():
        _add(
          NoticeItem(
            _id('n'),
            kind: AskNoticeKind.privacy,
            text: raw ?? '',
            canRetry: false,
            canFinishManually: single,
          ),
        );
      case ServicePermissionDenied() || ServiceError():
        _add(
          NoticeItem(
            _id('n'),
            kind: AskNoticeKind.error,
            text: raw ?? '',
            canRetry: raw != null,
            canFinishManually: single,
          ),
        );
    }
  }

  void _add(ThreadItem item) =>
      state = state.copyWith(items: [...state.items, item]);

  void _replace(ThreadItem old, ThreadItem next) => state = state.copyWith(
    items: [
      for (final i in state.items)
        if (identical(i, old)) next else i,
    ],
  );

  void _removeNoticesFor(String text) => state = state.copyWith(
    items: [
      for (final i in state.items)
        if (i is! NoticeItem || i.text != text) i,
    ],
  );

  /// Adds a row for each surface the host shows for the first time, in
  /// the host's order.
  void _syncSurfaces() {
    final fresh = [
      for (final id in _host.surfaceIds)
        if (_shownSurfaces.add(id)) SurfaceItem(id),
    ];
    if (fresh.isNotEmpty) {
      state = state.copyWith(items: [...state.items, ...fresh]);
    }
  }
}

/// The Ask thread. A new one each time the screen opens.
final NotifierProvider<AskController, AskState> askControllerProvider =
    NotifierProvider.autoDispose<AskController, AskState>(
      AskController.new,
      name: 'askControllerProvider',
    );
