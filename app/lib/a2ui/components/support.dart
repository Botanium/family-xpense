/// Helpers shared by the component implementations.
library;

import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The event name of the action prop [key] as written in the message, or
/// null when the component has none.
String? actionNameOf(ComponentNode<ComponentImplementation> node, String key) {
  final raw = node.context?.componentModel.properties[key];
  return switch (raw) {
    {'event': {'name': final String name}} => name,
    {'name': final String name} => name,
    _ => null,
  };
}

/// Whether an action named [name] would start an agent turn: not local and
/// not the dummy `click` the router drops.
bool reachesAgent(String? name) =>
    name != null && !isLocalActionName(name) && name != dummyActionName;

/// A tap handler that fires the action prop [key], or null when there is
/// none, or when it would reach the agent while a turn is streaming.
VoidCallback? actionHandler(
  XpenseScope scope,
  ComponentNode<ComponentImplementation> node,
  ComponentProps props,
  String key,
) {
  final action = props.action(key);
  if (action == null) return null;
  if (scope.busy && reachesAgent(actionNameOf(node, key))) return null;
  return () => fire(action);
}

/// Runs [action] without waiting; a failure is reported, never swallowed.
void fire(NodeAction action) => unawaited(
  action().catchError((Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'xpense a2ui',
        context: ErrorDescription('while dispatching an A2UI action'),
      ),
    );
  }),
);

/// The surface's data model, for components that keep their own state in
/// it (`/ui/status`, `/ui/saved`).
DataModel? dataModelOf(ComponentNode<ComponentImplementation> node) =>
    node.context?.surface.dataModel;
