import 'dart:async';

import 'package:xpense_app/services/decisions_client.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// A [DecisionsClient] that answers with [result], for tests and for runs
/// without a backend. By default it reports the proxy as unavailable, so
/// callers take their low-confidence path.
final class FakeDecisionsClient implements DecisionsClient {
  /// Creates a client that answers every request with [result].
  new({this.result = const Err(ServiceUnavailable())});

  /// The answer to every request.
  Result<DecideResponse, ServiceFailure> result;

  /// The requests received, in order.
  final List<DecideRequest> requests = [];

  /// When set, each answer waits for it, so a test can act mid-request.
  Completer<void>? gate;

  @override
  Future<Result<DecideResponse, ServiceFailure>> decide(
    DecideRequest request,
  ) async {
    requests.add(request);
    await gate?.future;
    return result;
  }
}
