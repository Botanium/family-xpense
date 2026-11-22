/// `outputGuard`: the generate middleware that checks every surface the
/// agent emits (AI_PIPELINE 8 and 10).
///
/// It is listed after `householdContext` and before `a2ui()` in the agent's
/// `use`, so it wraps `a2ui()` and sees the A2UI data parts that `a2ui()`
/// compiled from the model's Express, both the streamed chunks and the final
/// message. Drafts that fail [GuardFacts.reject] are removed from the data
/// model and from the part's Express source (which is what the model sees of
/// the surface on later turns), and the removal is logged without content.
library;

import 'package:genkit/genkit.dart';
import 'package:logging/logging.dart';

import 'package:xpense_agent/safety/draft_guard.dart';

final _log = Logger('xpense.safety.outputGuard');

/// The middleware's registry name.
const outputGuardName = 'outputGuard';

/// Registers `outputGuard` on [ai]. [onViolation] observes removals (tests,
/// counters).
GenerateMiddlewareDef<void> defineOutputGuard(
  Genkit ai, {
  void Function(GuardViolation violation)? onViolation,
}) => ai.defineGenerateMiddleware<void>(
  name: outputGuardName,
  create: (config, ctx) => OutputGuardMiddleware(onViolation: onViolation),
);

/// The middleware instance (one per generate call).
final class OutputGuardMiddleware extends GenerateMiddleware {
  /// Creates the middleware.
  new({this.onViolation});

  /// Observes removals.
  final void Function(GuardViolation violation)? onViolation;

  @override
  Future<ModelResponse> model(
    ModelRequest request,
    ActionFnArg<ModelResponseChunk, ModelRequest, void> ctx,
    Future<ModelResponse> Function(
      ModelRequest request,
      ActionFnArg<ModelResponseChunk, ModelRequest, void> ctx,
    )
    next,
  ) async {
    final facts = GuardFacts.fromMessages([
      for (final m in request.messages) m.toJson(),
    ]);
    final guarded = ActionFnArg<ModelResponseChunk, ModelRequest, void>(
      streamingRequested: ctx.streamingRequested,
      sendChunk: (chunk) => ctx.sendChunk(_guardChunk(chunk, facts)),
      context: ctx.context,
      inputStream: ctx.inputStream,
      init: ctx.init,
      cancel: ctx.cancel,
    );
    final response = await next(request, guarded);
    final json = response.toJson();
    final message = json['message'];
    if (message is! Map) return response;
    final content = _contentOf(message);
    if (content == null) return response;
    final result = guardParts(content, facts);
    _report(result.violations);
    if (!result.changed) return response;
    return ModelResponse.fromJson({
      ...json,
      'message': <String, dynamic>{
        ...message.cast<String, dynamic>(),
        'content': result.parts,
      },
    });
  }

  ModelResponseChunk _guardChunk(ModelResponseChunk chunk, GuardFacts facts) {
    final json = chunk.toJson();
    final content = _contentOf(json);
    if (content == null) return chunk;
    final result = guardParts(content, facts);
    // Chunk violations are reported again on the final message; log once.
    if (!result.changed) return chunk;
    return ModelResponseChunk.fromJson({...json, 'content': result.parts});
  }

  void _report(List<GuardViolation> violations) {
    for (final v in violations) {
      _log.warning({
        'message': 'outputGuard removed agent output',
        'surfaceId': v.surfaceId,
        'reason': v.reason,
      });
      onViolation?.call(v);
    }
  }

  static List<Map<String, dynamic>>? _contentOf(Map<dynamic, dynamic> json) {
    final content = json['content'];
    if (content is! List) return null;
    return [
      for (final p in content)
        if (p is Map) p.cast<String, dynamic>(),
    ];
  }
}
