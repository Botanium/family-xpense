/// Production telemetry: Genkit spans and GenAI metrics over OTLP (D-29).
///
/// There is no Genkit Monitoring plugin for Dart; `genkit_otel` maps Genkit
/// actions to OpenTelemetry GenAI spans and metrics, and the
/// `dartastic_opentelemetry` SDK exports them over OTLP. Content capture is
/// off and cannot be turned on from the environment: prompts, replies and
/// transaction text never leave the process (ARCHITECTURE 4.6).
///
/// Under `genkit start` Genkit injects its own development instrumentation,
/// so traces reach the Developer UI without this module.
library;

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:genkit/telemetry.dart';
import 'package:genkit_otel/genkit_otel.dart';
import 'package:logging/logging.dart';

final _log = Logger('xpense.telemetry');

/// Builds the Genkit instrumentation with every content option off.
///
/// The explicit [ContentCapturingMode.noContent] overrides the
/// `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT` environment variable,
/// and `captureActionIO: false` keeps raw flow and tool payloads (which hold
/// user text) off every span.
GenAiInstrumentation buildInstrumentation() => GenAiInstrumentation(
  contentCapturingMode: ContentCapturingMode.noContent,
  // Tool spans carry only names and timings once content is off; they keep
  // the trace tree readable.
  emitToolSpans: true,
);

/// A started telemetry pipeline.
final class Telemetry {
  new _(this.enabled);

  /// Whether spans and metrics are exported.
  final bool enabled;

  /// Flushes and stops exporting. Call once, at shutdown.
  Future<void> shutdown() async {
    if (enabled) await OTel.shutdown();
  }
}

/// Starts OTLP export when [otlpEndpoint] is set; otherwise does nothing (the
/// local default, so a run without a collector does not log export errors).
///
/// Endpoint, headers and protocol also follow the standard `OTEL_*`
/// environment variables; Cloud Trace and Cloud Monitoring need the
/// exporter's Google authentication set up by WP-83.
Future<Telemetry> startTelemetry({
  required String? otlpEndpoint,
  required String serviceName,
  required String serviceVersion,
}) async {
  if (otlpEndpoint == null || otlpEndpoint.isEmpty) {
    _log.info('telemetry export off (no OTLP endpoint)');
    return Telemetry._(false);
  }
  await OTel.initialize(
    endpoint: otlpEndpoint,
    serviceName: serviceName,
    serviceVersion: serviceVersion,
    // Logs are written to stdout for Cloud Logging, not exported over OTLP.
    enableLogs: false,
  );
  configureInstrumentation(buildInstrumentation());
  _log.info('telemetry export on: $otlpEndpoint (content capture off)');
  return Telemetry._(true);
}
