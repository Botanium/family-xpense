import 'package:flutter/foundation.dart';
import 'package:xpense_app/features/capture/router/capture_router.dart';

/// One row of the Ask thread (DESIGN_SYSTEM screen 7).
@immutable
sealed class ThreadItem {
  const new(this.key);

  /// Stable within the thread, for widget keys.
  final String key;
}

/// What the member typed, shown as a quote.
final class QuoteItem extends ThreadItem {
  /// Creates a quote.
  const new(super.key, this.text);

  /// The words.
  final String text;
}

/// Prose from the agent, such as an answer or a follow-up question.
final class ReplyItem extends ThreadItem {
  /// Creates a reply.
  const new(super.key, this.text);

  /// The text so far; it grows while the turn streams.
  final String text;

  /// A copy with [more] appended.
  ReplyItem append(String more) => ReplyItem(key, text + more);
}

/// An A2UI surface rendered by the thread's surface host.
final class SurfaceItem extends ThreadItem {
  /// Creates the row for [surfaceId].
  const new(this.surfaceId) : super(surfaceId);

  /// The surface.
  final String surfaceId;
}

/// Why a message could not take its path.
enum AskNoticeKind {
  /// No connection: the message needed the cloud.
  offline,

  /// The household's daily limit for the cloud was reached.
  limit,

  /// The cloud refused because the household is in On-device mode.
  privacy,

  /// Anything else.
  error,
}

/// A notice in the thread, with what the member can do next.
final class NoticeItem extends ThreadItem {
  /// Creates a notice about the message [text].
  const new(
    super.key, {
    required this.kind,
    required this.text,
    this.canRetry = true,
    this.canFinishManually = false,
  });

  /// What went wrong.
  final AskNoticeKind kind;

  /// The message it is about, for Retry and Finish manually.
  final String text;

  /// Whether to offer Retry.
  final bool canRetry;

  /// Whether to offer Finish manually (a local slip with pickers).
  final bool canFinishManually;
}

/// The state of the Ask screen.
@immutable
final class AskState {
  /// Creates a state.
  const new({
    this.items = const [],
    this.busy = false,
    this.offline = false,
    this.lastRoute,
    this.traceIds = const [],
  });

  /// The thread, oldest first.
  final List<ThreadItem> items;

  /// Whether a cloud call (Decisions or an agent turn) is running.
  final bool busy;

  /// Whether the last cloud call found no connection. Cleared by the next
  /// call that gets an answer.
  final bool offline;

  /// The route of the latest message, for the mode chip and logs.
  final RouteDecision? lastRoute;

  /// Trace ids of the agent turns, oldest first. Not shown; kept for
  /// support and tests.
  final List<String> traceIds;

  /// A copy with the given fields replaced.
  AskState copyWith({
    List<ThreadItem>? items,
    bool? busy,
    bool? offline,
    RouteDecision? lastRoute,
    List<String>? traceIds,
  }) => AskState(
    items: items ?? this.items,
    busy: busy ?? this.busy,
    offline: offline ?? this.offline,
    lastRoute: lastRoute ?? this.lastRoute,
    traceIds: traceIds ?? this.traceIds,
  );
}
