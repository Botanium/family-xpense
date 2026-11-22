import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/telemetry/structured_log.dart';

void main() {
  Map<String, Object?> format(LogRecord record) =>
      jsonDecode(formatLogRecord(record)) as Map<String, Object?>;

  test('plain message', () {
    final entry = format(LogRecord(Level.INFO, 'hello', 'xpense.test'));
    expect(entry['severity'], 'INFO');
    expect(entry['message'], 'hello');
    expect(entry['logger'], 'xpense.test');
    expect(entry['time'], isA<String>());
  });

  test('map messages become structured fields', () {
    final entry = format(
      LogRecord(Level.WARNING, 'ignored', 'xpense.http', null, null, null, {
        'message': 'POST /v1/ping 401',
        'httpRequest': {'status': 401},
      }),
    );
    expect(entry['severity'], 'WARNING');
    expect(entry['message'], 'POST /v1/ping 401');
    expect(entry['httpRequest'], {'status': 401});
  });

  test('severity mapping', () {
    expect(severityOf(Level.FINE), 'DEBUG');
    expect(severityOf(Level.INFO), 'INFO');
    expect(severityOf(Level.WARNING), 'WARNING');
    expect(severityOf(Level.SEVERE), 'ERROR');
    expect(severityOf(Level.SHOUT), 'ALERT');
  });

  test('stack traces only from SEVERE up', () {
    final warning = format(
      LogRecord(
        Level.WARNING,
        'w',
        'x',
        StateError('boom'),
        StackTrace.current,
      ),
    );
    expect(warning['error'], contains('boom'));
    expect(warning.containsKey('stack_trace'), isFalse);
    final severe = format(
      LogRecord(Level.SEVERE, 's', 'x', 'e', StackTrace.current),
    );
    expect(severe['stack_trace'], isA<String>());
  });
}
