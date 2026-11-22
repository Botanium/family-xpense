/// REST client for `POST /v1beta/decisions` (no Dart SDK or Genkit plugin).
///
/// Turns every response into a [DecisionOutcome]. WP-S4 found two error
/// shapes, and they must not be confused:
///
/// - the Decisions API's own validation errors: HTTP 400 with a **string**
///   `error.code` (`invalid_request`, `not_found`); safety blocks use the
///   same shape with a code from [safetyCodes];
/// - Google's usual errors for the key and quota: a **numeric** `code` plus
///   `status` (`INVALID_ARGUMENT`, `PERMISSION_DENIED`,
///   `RESOURCE_EXHAUSTED`).
///
/// A block is also recognised as HTTP 200 with `prompt_feedback.block_reason`
/// (the API reference's shape; the guide and the reference disagree).
///
/// The key is only ever placed in the `x-goog-api-key` header. Nothing here
/// logs, prints or stores it, and no outcome carries it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// The endpoint.
final Uri decisionsEndpoint = Uri.parse(
  'https://generativelanguage.googleapis.com/v1beta/decisions',
);

/// `error.code` values that mean the input was blocked (the guide's list).
const Set<String> safetyCodes = {
  'safety',
  'prohibited_content',
  'blocklist',
  'image_safety',
  'content_blocked',
};

/// What one call produced.
@immutable
sealed class DecisionOutcome {
  const new({required this.status});

  /// HTTP status, or 0 when no response arrived.
  final int status;
}

/// HTTP 200 with answers.
final class DecisionAnswered extends DecisionOutcome {
  /// Creates the outcome.
  const new({required this.answers, required this.inputTokens})
    : super(status: 200);

  /// `answers`, keyed by question key.
  final Map<String, Object?> answers;

  /// `usage.total_input_tokens` (the only billed count; output is 0).
  final int inputTokens;
}

/// The input was blocked by the safety filters. Not retried, no fallback.
final class DecisionBlocked extends DecisionOutcome {
  /// Creates the outcome.
  const new({required super.status, required this.reason});

  /// The block code or `block_reason`.
  final String reason;
}

/// The API rejected the request itself (HTTP 400 `invalid_request`, 404
/// `not_found`): a proxy bug or a wrong model id, never the user's message.
final class DecisionRequestRejected extends DecisionOutcome {
  /// Creates the outcome.
  const new({required super.status, required this.code, this.message});

  /// The string `error.code`.
  final String code;

  /// The API's message (names the rule broken; never holds the key).
  final String? message;
}

/// The key was refused: Google's numeric shape with `INVALID_ARGUMENT`
/// "API key not valid", or HTTP 401 or 403.
final class DecisionKeyRejected extends DecisionOutcome {
  /// Creates the outcome.
  const new({required super.status, this.statusText});

  /// `error.status`, such as `PERMISSION_DENIED`.
  final String? statusText;
}

/// Worth one retry: HTTP 429, 5xx, or no response at all.
final class DecisionTransient extends DecisionOutcome {
  /// Creates the outcome. [status] is 0 for a transport error.
  const new({required super.status, required this.detail});

  /// `RESOURCE_EXHAUSTED`, `UNAVAILABLE`, `timeout`, `transport`, ...
  final String detail;
}

/// Any other response, including a 200 whose body is not the documented
/// shape.
final class DecisionUnexpected extends DecisionOutcome {
  /// Creates the outcome.
  const new({required super.status, required this.detail});

  /// What was wrong, for logs.
  final String detail;
}

/// Where the API key comes from.
abstract interface class ApiKeySource {
  /// The key to use now.
  FutureOr<String> current();

  /// Re-reads the key after a key error (a rotation may have happened).
  /// Returns the new key, or null when it cannot be re-read.
  FutureOr<String?> refresh();
}

/// A fixed key, such as `GEMINI_API_KEY` from the environment. On Cloud Run
/// the secret is resolved to `latest` when an instance starts, so a refresh
/// cannot see a newer version; the error is alerted and the fallback runs.
final class FixedApiKey implements ApiKeySource {
  /// Wraps [_key].
  new(this._key);

  final String _key;

  @override
  String current() => _key;

  @override
  String? refresh() => null;

  @override
  String toString() => 'FixedApiKey(***)';
}

/// Calls the Decisions API.
final class DecisionsApi {
  /// Creates a client over [_http]; [endpoint] is overridable for tests.
  new({
    required this._http,
    required this._keys,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 8),
  }) : _endpoint = endpoint ?? decisionsEndpoint;

  final http.Client _http;
  final ApiKeySource _keys;
  final Uri _endpoint;

  /// Per-call timeout. The p95 measured in WP-S4 was 0.5 s.
  final Duration timeout;

  /// Sends [body] once. On a key error, re-reads the key once and sends
  /// again with the new key.
  Future<DecisionOutcome> send(Map<String, Object?> body) async {
    final encoded = jsonEncode(body);
    final outcome = await _send(encoded, await _keys.current());
    if (outcome is DecisionKeyRejected) {
      final fresh = await _keys.refresh();
      if (fresh != null) return await _send(encoded, fresh);
    }
    return outcome;
  }

  Future<DecisionOutcome> _send(String body, String key) async {
    try {
      final response = await _http
          .post(
            _endpoint,
            headers: {
              'content-type': 'application/json',
              'x-goog-api-key': key,
            },
            body: body,
          )
          .timeout(timeout);
      return classifyResponse(response.statusCode, response.body);
    } on TimeoutException {
      return const DecisionTransient(status: 0, detail: 'timeout');
    } on http.ClientException {
      return const DecisionTransient(status: 0, detail: 'transport');
    }
  }
}

/// Turns a status and body into an outcome.
DecisionOutcome classifyResponse(int status, String text) {
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    decoded = null;
  }
  final body = decoded is Map ? decoded.cast<String, Object?>() : null;

  if (status == 200) {
    if (body == null) {
      return const DecisionUnexpected(status: 200, detail: 'body not JSON');
    }
    if (body['prompt_feedback'] case {'block_reason': final String reason}
        when reason.isNotEmpty) {
      return DecisionBlocked(status: 200, reason: reason);
    }
    final answers = body['answers'];
    if (answers is! Map) {
      return const DecisionUnexpected(status: 200, detail: 'no answers');
    }
    final tokens = switch (body['usage']) {
      {'total_input_tokens': final num n} => n.toInt(),
      _ => 0,
    };
    return DecisionAnswered(
      answers: answers.cast<String, Object?>(),
      inputTokens: tokens,
    );
  }

  final error = switch (body?['error']) {
    final Map<Object?, Object?> e => e.cast<String, Object?>(),
    _ => const <String, Object?>{},
  };
  final code = error['code'];
  final statusText = error['status'] is String
      ? error['status']! as String
      : null;
  final message = error['message'] is String
      ? error['message']! as String
      : null;

  // The Decisions API's own shape: a string code.
  if (code is String) {
    if (safetyCodes.contains(code)) {
      return DecisionBlocked(status: status, reason: code);
    }
    if (status == 429 || status >= 500) {
      return DecisionTransient(status: status, detail: code);
    }
    return DecisionRequestRejected(
      status: status,
      code: code,
      message: message,
    );
  }

  // Google's shape: a numeric code and a status.
  if (status == 429 || status >= 500) {
    return DecisionTransient(status: status, detail: statusText ?? 'http');
  }
  if (status == 401 ||
      status == 403 ||
      (status == 400 &&
          (message ?? '').contains('API key') &&
          statusText == 'INVALID_ARGUMENT')) {
    return DecisionKeyRejected(status: status, statusText: statusText);
  }
  return DecisionUnexpected(
    status: status,
    detail: statusText ?? (code == null ? 'no error body' : 'code $code'),
  );
}
