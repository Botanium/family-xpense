/// The HTTP surface: a Shelf pipeline around the Genkit routers.
///
/// `GenkitRouter` serves the actions; Shelf adds request logging and the
/// health route, and mounts the public router under `/v1` (ARCHITECTURE 4.3,
/// D-32). CORS is off: the only client is the iOS app, and no browser origin
/// may call the service.
library;

import 'dart:async';
import 'dart:convert';

import 'package:genkit/io.dart';
import 'package:genkit_shelf/genkit_shelf.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/http/routes.dart';

final _log = Logger('xpense.http');

/// Health routes. `/healthz` is the documented name (ARCHITECTURE 4.1);
/// Cloud Run's front end reserves some paths ending in `z` and answers them
/// itself with 404, so `/health` is served too for checks from outside.
const healthPaths = {'/healthz', '/health'};

/// Builds the request handler for [role].
///
/// - `GET /healthz`, `GET /health`: `{"status":"ok","role":...}`, no auth.
/// - agent role: [public] under `/v1` (each route has its context provider).
/// - jobs role: [events] by exact path (Eventarc posts CloudEvents, not
///   Genkit's `{data}` envelope), then [jobs] at `/jobs/*` and `/events/*`.
/// - anything else: 404.
Handler buildHandler({
  required XpenseRole role,
  required GenkitRouter public,
  required GenkitRouter jobs,
  Map<String, Handler> events = const {},
  String? projectId,
}) {
  final publicHandler = public.asShelfHandler();
  final jobsHandler = jobs.asShelfHandler();
  final prefix = publicPrefix.substring(1);

  FutureOr<Response> route(Request request) {
    final path = '/${request.url.path}';
    if (healthPaths.contains(path)) return _health(request, role);
    switch (role) {
      case XpenseRole.agent:
        if (request.url.pathSegments.firstOrNull == prefix) {
          return publicHandler(request.change(path: prefix));
        }
      case XpenseRole.jobs:
        final event = events[path];
        if (event != null) return event(request);
        if (path.startsWith('/jobs/') || path.startsWith('/events/')) {
          return jobsHandler(request);
        }
    }
    return Response.notFound('Not found');
  }

  return const Pipeline()
      .addMiddleware(accessLog(projectId: projectId))
      .addHandler(route);
}

Response _health(Request request, XpenseRole role) {
  if (request.method != 'GET' && request.method != 'HEAD') {
    return Response(405, headers: {'allow': 'GET, HEAD'});
  }
  return Response.ok(
    jsonEncode({'status': 'ok', 'role': role.name}),
    headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
  );
}

/// Logs one structured line per request: method, path (no query), status,
/// latency and the Cloud Trace id. Never headers or bodies, which hold tokens
/// and user text (ARCHITECTURE 4.6).
Middleware accessLog({String? projectId}) =>
    (inner) => (request) async {
      final watch = Stopwatch()..start();
      final response = await inner(request);
      final status = response.statusCode;
      final trace = _traceId(request.headers);
      final entry = <String, Object?>{
        'message': '${request.method} /${request.url.path} $status',
        'httpRequest': {
          'requestMethod': request.method,
          'requestUrl': '/${request.url.path}',
          'status': status,
          'latency': '${(watch.elapsedMicroseconds / 1e6).toStringAsFixed(3)}s',
        },
        if (trace != null && projectId != null)
          'logging.googleapis.com/trace': 'projects/$projectId/traces/$trace',
      };
      if (status >= 500) {
        _log.severe(entry);
      } else if (status >= 400) {
        _log.warning(entry);
      } else {
        _log.info(entry);
      }
      return response;
    };

/// The trace id from `traceparent` (W3C) or `x-cloud-trace-context`.
String? _traceId(Map<String, String> headers) {
  final traceparent = headers['traceparent'];
  if (traceparent != null) {
    final parts = traceparent.split('-');
    if (parts.length >= 2 && parts[1].length == 32) return parts[1];
  }
  final cloud = headers['x-cloud-trace-context'];
  if (cloud != null) {
    final id = cloud.split('/').first;
    if (RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return id;
  }
  return null;
}
