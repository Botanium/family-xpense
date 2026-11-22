import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The Decisions proxy, `POST /decide` (ARCHITECTURE 5.2, AI_PIPELINE 7).
///
/// Wrapped because the Decisions API is in beta and may be swapped. The key
/// stays on the server; the phone sends only the message and question keys.
abstract interface class DecisionsClient {
  /// Asks the closed-set questions in [request]. Never throws.
  Future<Result<DecideResponse, ServiceFailure>> decide(DecideRequest request);
}

/// The [DecisionsClient] for this run. Throws until the composition root
/// sets it.
final decisionsClientProvider = Provider<DecisionsClient>(
  (ref) =>
      throw UnimplementedError('decisionsClientProvider is set in bootstrap()'),
  name: 'decisionsClientProvider',
);
