import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The Decisions proxy, `POST /decide` (ARCHITECTURE 5.2, AI_PIPELINE 7).
///
/// Wrapped because the Decisions API is in beta and may be swapped. The key
/// stays on the server; the phone sends only the message and question keys.
abstract interface class DecisionsClient {
  /// Asks the closed-set questions in [request]. Never throws.
  ///
  /// The server's `{unavailable: true}` (input blocked, classifier down,
  /// another language) comes back as [ServiceUnavailable], so callers have
  /// one path to on-device classification or local pickers. Answers from
  /// the uncalibrated fallback are `Ok` with `calibrated: false`; the caller
  /// caps their confidences at `conf_on_device_cap`.
  Future<Result<DecideResponse, ServiceFailure>> decide(DecideRequest request);
}

/// The [DecisionsClient] for this run. Throws until the composition root
/// sets it.
final decisionsClientProvider = Provider<DecisionsClient>(
  (ref) =>
      throw UnimplementedError('decisionsClientProvider is set in bootstrap()'),
  name: 'decisionsClientProvider',
);

/// One HTTP response: status and body text.
typedef DecideHttpResponse = ({int status, String body});

/// Posts [body] to [url] with [headers]. Throws [SocketException],
/// [HttpException] or [TimeoutException] when no response arrives.
typedef DecideTransport = Future<DecideHttpResponse> Function(
  Uri url,
  Map<String, String> headers,
  String body,
);

/// [DecisionsClient] over HTTPS to `xpense-agent`'s `/v1/decide`.
///
/// Sends the Firebase ID token and the App Check token, which the server's
/// context provider verifies, wrapped in Genkit's `{data}` envelope, and
/// maps every failure to a [ServiceFailure].
final class HttpDecisionsClient implements DecisionsClient {
  /// Creates the client. [baseUrl] is the service origin (the `/v1/decide`
  /// path is added). `idToken` and `appCheckToken` return the current
  /// tokens, or null when there is none.
  new({
    required this.baseUrl,
    required this._idToken,
    required this._appCheckToken,
    required this.timeout,
    DecideTransport? transport,
  }) : _transport = transport ?? _ioTransport;

  /// The service origin, such as `https://xpense-agent-….run.app`.
  final Uri baseUrl;

  /// The whole call's limit, tokens included. About 10 s: the API answers
  /// in 0.3 s (p50) and the phone's on-device path is the alternative.
  final Duration timeout;

  final Future<String?> Function() _idToken;
  final Future<String?> Function() _appCheckToken;
  final DecideTransport _transport;

  /// The endpoint.
  Uri get endpoint => baseUrl.resolve('/v1/decide');

  @override
  Future<Result<DecideResponse, ServiceFailure>> decide(
    DecideRequest request,
  ) async {
    try {
      return await _decide(request).timeout(timeout);
    } on TimeoutException {
      return const Err(ServiceOffline());
    } on SocketException {
      return const Err(ServiceOffline());
    } on HttpException {
      return const Err(ServiceOffline());
    } on Exception catch (e) {
      // A token plugin failure or similar: report the type only, since a
      // message could hold a token.
      debugPrint('DecisionsClient: ${e.runtimeType}');
      return Err(ServiceError('decide.${e.runtimeType}'));
    }
  }

  Future<Result<DecideResponse, ServiceFailure>> _decide(
    DecideRequest request,
  ) async {
    final idToken = await _idToken();
    if (idToken == null || idToken.isEmpty) {
      return const Err(ServiceError('decide.no_id_token'));
    }
    final appCheck = await _appCheckToken();
    final response = await _transport(endpoint, {
      'content-type': 'application/json',
      'authorization': 'Bearer $idToken',
      if (appCheck != null && appCheck.isNotEmpty)
        'x-firebase-appcheck': appCheck,
    }, jsonEncode({'data': request.toJson()}));
    return await parseDecideResponse(response.status, response.body);
  }
}

/// Maps the proxy's HTTP response to a result.
///
/// - 200 `{result}`: the answers, or [ServiceUnavailable] when the result
///   says `unavailable`.
/// - 429 `over_limit`: [ServiceRateLimited].
/// - 403 `on_device_mode`: [ServiceUnavailable] (the privacy mode keeps AI
///   on the phone).
/// - 503 and other 5xx: [ServiceOffline].
/// - anything else, including 401 and 400: [ServiceError] with
///   `decide.<status>.<code>`.
@visibleForTesting
Future<Result<DecideResponse, ServiceFailure>> parseDecideResponse(
  int status,
  String body,
) async {
  final json = _decode(body);
  if (status == 200) {
    final result = json?['result'];
    if (result is! Map) {
      return const Err(ServiceError('decide.bad_response'));
    }
    final map = result.cast<String, dynamic>();
    // Schemantic reads fields lazily, so check the shape up front: a
    // malformed answer fails here, not later in a caller.
    if ((await DecideResponse.$schema.validate(map)).isNotEmpty) {
      return const Err(ServiceError('decide.bad_response'));
    }
    final response = DecideResponse.fromJson(map);
    if (response.unavailable ?? false) return const Err(ServiceUnavailable());
    return Ok(response);
  }
  final code = json?['message'] is String ? json!['message']! as String : '';
  return Err(switch ((status, code)) {
    (429, _) => const ServiceRateLimited(),
    (403, 'on_device_mode') => const ServiceUnavailable(),
    (>= 500, _) => const ServiceOffline(),
    _ => ServiceError('decide.$status${code.isEmpty ? '' : '.$code'}'),
  });
}

Map<String, Object?>? _decode(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  } on FormatException {
    return null;
  }
}

Future<DecideHttpResponse> _ioTransport(
  Uri url,
  Map<String, String> headers,
  String body,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(url);
    headers.forEach(request.headers.set);
    request.add(utf8.encode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: text);
  } finally {
    client.close(force: true);
  }
}
