/// A minimal REST client for `POST /v1beta/decisions` (no Dart SDK exists).
///
/// The API key is read once from the environment and only ever placed in
/// the `x-goog-api-key` header. Nothing here prints, logs or stores it, and
/// no outcome carries it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

final Uri decisionsEndpoint = Uri.parse(
  'https://generativelanguage.googleapis.com/v1beta/decisions',
);

const String decisionModel = 'gemini-decision-1';

/// The key from `GEMINI_API_KEY`, or a clear error without echoing anything.
String apiKeyFromEnvironment() {
  final key = Platform.environment['GEMINI_API_KEY']?.trim();
  if (key == null || key.isEmpty) {
    stderr.writeln(
      'GEMINI_API_KEY is not set. Run with:\n'
      r'  GEMINI_API_KEY="$(gcloud secrets versions access latest '
      '--secret=GEMINI_API_KEY --project=expense-family-cc6ee '
      '--billing-project=expense-family-cc6ee)" dart run bin/<script>.dart',
    );
    exit(64);
  }
  return key;
}

/// What one call produced.
sealed class DecisionOutcome {
  const new({required this.status, required this.latency, required this.raw});

  /// HTTP status, or 0 when the request never got a response.
  final int status;

  /// Wall time from sending the request to reading the whole body.
  final Duration latency;

  /// The decoded body, or the text when it is not JSON.
  final Object? raw;

  String get kind;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'status': status,
    'latencyMs': latency.inMilliseconds,
    'body': raw,
  };
}

/// HTTP 200 with answers.
final class DecisionAnswered extends DecisionOutcome {
  const new({
    required super.status,
    required super.latency,
    required super.raw,
    required this.answers,
    required this.usage,
  });

  final Map<String, Object?> answers;
  final Map<String, Object?> usage;

  int get inputTokens => (usage['total_input_tokens'] as num?)?.toInt() ?? 0;

  @override
  String get kind => 'answered';
}

/// Blocked by the input filters: either HTTP 400 with an `error.code` from
/// the safety list (guide), or `prompt_feedback.block_reason` with empty
/// answers (API reference). Both are handled because the docs disagree.
final class DecisionBlocked extends DecisionOutcome {
  const new({
    required super.status,
    required super.latency,
    required super.raw,
    required this.reason,
    required this.via,
    this.message,
  });

  final String reason;

  /// `http_400` or `prompt_feedback`.
  final String via;
  final String? message;

  @override
  String get kind => 'blocked';
}

/// Any other HTTP error.
final class DecisionHttpError extends DecisionOutcome {
  const new({
    required super.status,
    required super.latency,
    required super.raw,
    this.code,
    this.statusText,
    this.message,
  });

  /// `error.code` (a number on Google APIs, a string for safety blocks).
  final Object? code;

  /// `error.status`, for example `INVALID_ARGUMENT`.
  final String? statusText;
  final String? message;

  bool get retryable => status == 429 || status >= 500;

  @override
  String get kind => 'http_error';
}

/// No response: timeout, DNS, TLS, reset.
final class DecisionTransportError extends DecisionOutcome {
  const new({required super.latency, required this.error})
    : super(status: 0, raw: null);

  final String error;

  @override
  String get kind => 'transport_error';

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'error': error};
}

const Set<String> safetyCodes = {
  'safety',
  'prohibited_content',
  'blocklist',
  'image_safety',
  'content_blocked',
};

final class DecisionsClient {
  new({
    required this._apiKey,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 20),
  }) : _endpoint = endpoint ?? decisionsEndpoint;

  final String _apiKey;
  final Uri _endpoint;
  final Duration timeout;
  final HttpClient _http = HttpClient();

  /// Sends a request body (without the key) and classifies the result.
  Future<DecisionOutcome> send(
    Map<String, Object?> body, {
    String? apiKeyOverride,
    bool omitKey = false,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final req = await _http.postUrl(_endpoint).timeout(timeout);
      req.headers.contentType = ContentType.json;
      if (!omitKey) {
        req.headers.set('x-goog-api-key', apiKeyOverride ?? _apiKey);
      }
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      watch.stop();
      return classify(res.statusCode, text, watch.elapsed);
    } on Object catch (e) {
      watch.stop();
      return DecisionTransportError(
        latency: watch.elapsed,
        error: e.runtimeType.toString(),
      );
    }
  }

  void close() => _http.close(force: true);
}

/// Turns a status and body into an outcome. Public for the probes.
DecisionOutcome classify(int status, String text, Duration latency) {
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    decoded = text;
  }
  final body = decoded is Map ? decoded.cast<String, Object?>() : null;
  if (status == 200 && body != null) {
    final feedback = (body['prompt_feedback'] as Map?)?.cast<String, Object?>();
    final blockReason = feedback?['block_reason'] as String?;
    if (blockReason != null) {
      return DecisionBlocked(
        status: status,
        latency: latency,
        raw: decoded,
        reason: blockReason,
        via: 'prompt_feedback',
        message: feedback?['block_reason_message'] as String?,
      );
    }
    return DecisionAnswered(
      status: status,
      latency: latency,
      raw: decoded,
      answers: (body['answers'] as Map? ?? {}).cast<String, Object?>(),
      usage: (body['usage'] as Map? ?? {}).cast<String, Object?>(),
    );
  }
  final error = (body?['error'] as Map?)?.cast<String, Object?>();
  final code = error?['code'];
  if (status == 400 && code is String && safetyCodes.contains(code)) {
    return DecisionBlocked(
      status: status,
      latency: latency,
      raw: decoded,
      reason: code,
      via: 'http_400',
      message: error?['message'] as String?,
    );
  }
  return DecisionHttpError(
    status: status,
    latency: latency,
    raw: decoded,
    code: code,
    statusText: error?['status'] as String?,
    message: error?['message'] as String?,
  );
}

/// The request body for one call.
Map<String, Object?> decisionRequest(
  Object input,
  Map<String, Object?> questions,
) => {'model': decisionModel, 'input': input, 'questions': questions};
