/// The A2UI adapter (ARCHITECTURE 7, A2UI_CATALOG 5, story S3.4): the only
/// `a2ui/` file features import. Its public API holds no `a2ui_core` or
/// `a2ui_flutter` types.
///
/// - One [XpenseSurfaceHost] per conversation owns one `MessageProcessor`.
///   Messages from the local builder, the agent stream and notifications go
///   through one ordered queue, so local and agent surfaces share a thread.
/// - Each message is processed on its own: a bad one is skipped and
///   counted, and the rest of the turn renders.
/// - Actions named `xp.local.*` are handled on the phone through
///   [XpenseActions]; the dummy `click` is dropped; anything else goes to
///   the agent as [AgentAction], and is ignored while a turn is streaming.
/// - After a local save, [XpenseSurfaceHost.takeSavedActions] gives the
///   compact `xp.saved` actions to attach to the member's next turn.
library;

import 'dart:collection';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:clock/clock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/catalog/xpense_catalog.dart';
import 'package:xpense_app/a2ui/xpense_actions.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_shared/xpense_shared.dart';

export 'package:xpense_app/a2ui/xpense_actions.dart';

/// The MIME type of an A2UI data part (`genkit_a2ui`).
const String a2uiMimeType = 'application/a2ui+json';

/// A surface action bound for the agent: the next turn's A2UI data part.
final class AgentAction {
  /// Creates an action.
  const new({
    required this.name,
    required this.surfaceId,
    required this.sourceComponentId,
    required this.context,
    required this.payload,
  });

  /// The event name, such as `xp.answer`.
  final String name;

  /// The surface it came from.
  final String surfaceId;

  /// The component that fired it.
  final String sourceComponentId;

  /// The resolved context values.
  final Map<String, Object?> context;

  /// The renderer-to-agent payload (`{messages: [...]}`), to send as a data
  /// part with [a2uiMimeType] before any text part of the same message.
  final Map<String, Object?> payload;
}

/// Something the host skipped: a message that failed, an unknown component,
/// an action it dropped.
final class SurfaceIssue {
  /// Creates an issue.
  const new({required this.code, required this.message, this.surfaceId});

  /// A stable code, such as `UNKNOWN_COMPONENT_TYPE` or `DROPPED_ACTION`.
  final String code;

  /// What happened.
  final String message;

  /// The surface concerned, if any.
  final String? surfaceId;

  @override
  String toString() => 'SurfaceIssue($code, $surfaceId: $message)';
}

/// The surfaces of one conversation, and their message processor.
class XpenseSurfaceHost extends ChangeNotifier {
  /// Creates a host that calls [actions] for local work and [onAgentAction]
  /// for actions bound for the agent.
  new({
    required XpenseActions actions,
    this.onAgentAction,
    this.onIssue,
    String locale = 'en-US',
  }) : _actions = actions {
    _scoped = _RecordingActions(actions, this);
    _processor = MessageProcessor<ComponentImplementation>(
      catalogs: [xpenseCatalog(locale: locale)],
      onAction: _route,
      onError: (error) => _issue(
        SurfaceIssue(
          code: error.code,
          message: error.message,
          surfaceId: error.surfaceId,
        ),
      ),
    );
    _processor.model.onSurfaceCreated.subscribe((surface) {
      if (!_order.contains(surface.id)) _order.add(surface.id);
    });
  }

  final XpenseActions _actions;
  late final _RecordingActions _scoped;
  late final MessageProcessor<ComponentImplementation> _processor;

  /// Called with each action bound for the agent.
  final ValueChanged<AgentAction>? onAgentAction;

  /// Called with each skipped message, component or action.
  final ValueChanged<SurfaceIssue>? onIssue;

  final Queue<Object?> _queue = Queue();
  final List<String> _order = [];
  final List<_Saved> _saved = [];
  bool _draining = false;
  bool _turnInProgress = false;
  bool _disposed = false;

  /// Messages that failed and were skipped.
  int failedMessages = 0;

  /// Everything skipped so far, for logs and tests.
  final List<SurfaceIssue> issues = [];

  /// The surfaces, in the order they first appeared.
  List<String> get surfaceIds => [
    for (final id in _order)
      if (_processor.model.getSurface(id) != null) id,
  ];

  /// Whether an agent turn is streaming. While it is, actions bound for the
  /// agent are ignored and their controls show a busy state.
  bool get turnInProgress => _turnInProgress;

  set turnInProgress(bool value) {
    if (value == _turnInProgress) return;
    _turnInProgress = value;
    notifyListeners();
  }

  /// Adds A2UI v1.0 messages (raw maps from the local builder, the agent
  /// stream or a notification) to the queue, and processes them in order.
  void addMessages(Iterable<Object?> messages) {
    if (_disposed) return;
    _queue.addAll(messages);
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        _process(_queue.removeFirst());
      }
    } finally {
      _draining = false;
    }
    notifyListeners();
  }

  void _process(Object? message) {
    try {
      final errors = _processor.processMessagesWithErrors([message]);
      if (errors.isNotEmpty) failedMessages++;
    } on Object catch (error, stack) {
      // Not an A2UI error: still one message, still skipped.
      failedMessages++;
      _issue(SurfaceIssue(code: 'MESSAGE_FAILED', message: '$error'));
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'xpense a2ui',
          context: ErrorDescription('while processing an A2UI message'),
        ),
      );
    }
  }

  void _issue(SurfaceIssue issue) {
    issues.add(issue);
    onIssue?.call(issue);
  }

  void _route(A2uiRendererAction action) {
    final name = action.name;
    if (name == dummyActionName) {
      _drop(action, 'dummy action');
    } else if (isLocalActionName(name)) {
      _local(name.substring(localActionPrefix.length), action);
    } else if (_turnInProgress) {
      _drop(action, 'a turn is streaming');
    } else {
      onAgentAction?.call(
        AgentAction(
          name: name,
          surfaceId: action.surfaceId,
          sourceComponentId: action.sourceComponentId,
          context: action.context,
          payload: _payload(action),
        ),
      );
    }
  }

  void _drop(A2uiRendererAction action, String why) => _issue(
    SurfaceIssue(
      code: 'DROPPED_ACTION',
      message: '${action.name}: $why',
      surfaceId: action.surfaceId,
    ),
  );

  void _local(String name, A2uiRendererAction action) {
    final c = action.context;
    String text(String key) => c[key] is String ? c[key]! as String : '';
    switch (name) {
      case LocalActionNames.openManualForm:
        _actions.openManualForm(
          c['draft'] is Map
              ? Map<String, Object?>.from(c['draft']! as Map)
              : const {},
        );
      case LocalActionNames.openTransaction:
        _actions.openTransaction(text('txnId'));
      case LocalActionNames.openLoan:
        _actions.openLoan(text('loanId'));
      case LocalActionNames.openGoal:
        _actions.openGoal(text('goalId'));
      case LocalActionNames.sendText:
        _actions.sendText(text('message'));
      case LocalActionNames.retakeReceipt:
        _actions.retakeReceipt();
      case LocalActionNames.retryQueued:
        _actions.retryQueued(text('captureId'));
      default:
        _drop(action, 'unknown local action');
    }
  }

  static Map<String, Object?> _payload(A2uiRendererAction action) =>
      RendererToAgentMessagePayload.of(
        ActionMessage(version: xpenseProtocolVersion, action: action),
      ).toJson();

  /// The `xp.saved` actions for saves since the last call, one per surface:
  /// `{draftIds, txnIds}`. Attach them to the member's next turn, data part
  /// first (A2UI_CATALOG 5.2).
  List<AgentAction> takeSavedActions() {
    final bySurface = <String, List<_Saved>>{};
    for (final s in _saved) {
      bySurface.putIfAbsent(s.surfaceId, () => []).add(s);
    }
    _saved.clear();
    return [
      for (final MapEntry(key: surfaceId, value: saves) in bySurface.entries)
        _savedAction(surfaceId, saves),
    ];
  }

  AgentAction _savedAction(String surfaceId, List<_Saved> saves) {
    final context = <String, Object?>{
      'draftIds': [for (final s in saves) ...s.draftIds],
      'txnIds': [for (final s in saves) ...s.txnIds],
    };
    final action = A2uiRendererAction(
      name: 'xp.saved',
      surfaceId: surfaceId,
      sourceComponentId: 'root',
      timestamp: clock.now().toUtc(),
      context: context,
    );
    return AgentAction(
      name: action.name,
      surfaceId: surfaceId,
      sourceComponentId: action.sourceComponentId,
      context: context,
      payload: _payload(action),
    );
  }

  SurfaceModel<ComponentImplementation>? _surface(String id) =>
      _processor.model.getSurface(id);

  /// The value at [path] in surface [surfaceId]'s data model, for tests.
  @visibleForTesting
  Object? debugDataModel(String surfaceId, String path) =>
      _surface(surfaceId)?.dataModel.get(path);

  @override
  void dispose() {
    _disposed = true;
    _processor.dispose();
    super.dispose();
  }
}

final class _Saved {
  const new(this.surfaceId, this.groupId, this.draftIds, this.txnIds);

  final String surfaceId;
  final String groupId;
  final List<String> draftIds;
  final List<String> txnIds;
}

/// The actions the components get: the app's, with saves and undos
/// recorded for `xp.saved`.
final class _RecordingActions implements XpenseActions {
  const new(this._inner, this._host);

  final XpenseActions _inner;
  final XpenseSurfaceHost _host;

  @override
  XpenseHousehold get household => _inner.household;

  @override
  Future<SaveOutcome> saveDrafts(
    String surfaceId,
    List<EntryDraft> drafts,
  ) async {
    final outcome = await _inner.saveDrafts(surfaceId, drafts);
    if (outcome case DraftsSaved(:final groupId, :final txnIds)) {
      _host._saved.add(
        _Saved(surfaceId, groupId, [for (final d in drafts) d.id], txnIds),
      );
    }
    return outcome;
  }

  @override
  Future<void> undoSave(String groupId) async {
    // Only once the app has deleted the group: a failed undo leaves the
    // entries saved, and the agent should still hear about them.
    await _inner.undoSave(groupId);
    _host._saved.removeWhere((s) => s.groupId == groupId);
  }

  @override
  Future<void> learn(DraftCorrection correction) => _inner.learn(correction);

  @override
  Future<void> setDailyRate(String pairRate) => _inner.setDailyRate(pairRate);

  @override
  Future<void> setRecurring(String draftId, RecurringMode mode) =>
      _inner.setRecurring(draftId, mode);

  @override
  void openTransaction(String txnId) => _inner.openTransaction(txnId);

  @override
  void openLoan(String loanId) => _inner.openLoan(loanId);

  @override
  void openGoal(String goalId) => _inner.openGoal(goalId);

  @override
  void sendText(String message) => _inner.sendText(message);

  @override
  void retakeReceipt() => _inner.retakeReceipt();

  @override
  void openManualForm(Map<String, Object?> draft) =>
      _inner.openManualForm(draft);

  @override
  Future<void> openAddAccount() => _inner.openAddAccount();

  @override
  void retryQueued(String captureId) => _inner.retryQueued(captureId);
}

/// One surface of a [XpenseSurfaceHost], rebuilt as messages arrive. Shows
/// nothing until the surface exists. The surface gets a bounded width, as
/// the renderer gives it unbounded constraints.
class SurfaceView extends StatelessWidget {
  /// Creates a view of [surfaceId].
  const new({required this.host, required this.surfaceId, super.key});

  /// The host.
  final XpenseSurfaceHost host;

  /// The surface.
  final String surfaceId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: host,
    builder: (context, _) {
      final surface = host._surface(surfaceId);
      if (surface == null) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width,
          child: XpenseScope(
            actions: host._scoped,
            surfaceId: surfaceId,
            busy: host.turnInProgress,
            child: A2uiSurface(key: ObjectKey(surface), surface: surface),
          ),
        ),
      );
    },
  );
}

/// Every surface of a [XpenseSurfaceHost] in thread order, one under the
/// other.
class SurfaceThread extends StatelessWidget {
  /// Creates the thread.
  const new({required this.host, super.key});

  /// The host.
  final XpenseSurfaceHost host;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: host,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, id) in host.surfaceIds.indexed) ...[
          if (i > 0) const SizedBox(height: XpSpace.s24),
          SurfaceView(key: ValueKey(id), host: host, surfaceId: id),
        ],
      ],
    ),
  );
}
