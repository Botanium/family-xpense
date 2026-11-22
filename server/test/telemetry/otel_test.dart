import 'package:genkit_otel/genkit_otel.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/telemetry/otel.dart';

void main() {
  test('content capture is off and raw action I/O is not recorded', () {
    final instrumentation = buildInstrumentation();
    expect(
      instrumentation.contentCapturingMode,
      ContentCapturingMode.noContent,
    );
    expect(instrumentation.captureActionIO, isFalse);
  });

  test('without an OTLP endpoint nothing is exported', () async {
    final telemetry = await startTelemetry(
      otlpEndpoint: null,
      serviceName: 'xpense-agent',
      serviceVersion: 'test',
    );
    expect(telemetry.enabled, isFalse);
    await telemetry.shutdown();
  });
}
