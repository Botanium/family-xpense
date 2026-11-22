/// One JSON line per log record, in the shape Cloud Logging parses.
library;

import 'dart:convert';

import 'package:logging/logging.dart';

/// Formats [record] as a Cloud Logging structured entry: `severity`,
/// `message`, `logger`, `time`, plus the fields of a map message (for
/// example `httpRequest`). An attached error is reduced to its type and
/// message; stack traces are kept for SEVERE and above.
String formatLogRecord(LogRecord record) {
  final object = record.object;
  final fields = <String, Object?>{
    if (object is Map)
      for (final e in object.entries) e.key.toString(): e.value,
  };
  final message = fields.remove('message') ?? record.message;
  final entry = <String, Object?>{
    'severity': severityOf(record.level),
    'message': message,
    'logger': record.loggerName,
    'time': record.time.toUtc().toIso8601String(),
    ...fields,
    if (record.error != null) 'error': '${record.error}',
    if (record.stackTrace != null && record.level >= Level.SEVERE)
      'stack_trace': '${record.stackTrace}',
  };
  return jsonEncode(entry, toEncodable: (v) => v.toString());
}

/// Maps a `package:logging` level to a Cloud Logging severity.
String severityOf(Level level) {
  if (level >= Level.SHOUT) return 'ALERT';
  if (level >= Level.SEVERE) return 'ERROR';
  if (level >= Level.WARNING) return 'WARNING';
  if (level >= Level.INFO) return 'INFO';
  return 'DEBUG';
}
