/// Reads the Gemini key from Secret Manager at run time.
///
/// `latest` is resolved to a version number first and then that exact
/// version is read, so the version recorded in a report is the one whose
/// key was used. The value lives only in memory: it is never printed,
/// logged or written, and `toString` shows the version only.
library;

import 'dart:io';

const String secretProject = 'expense-family-cc6ee';
const String secretName = 'GEMINI_API_KEY';

const List<String> _projectFlags = [
  '--project=$secretProject',
  '--billing-project=$secretProject',
];

/// A key and the Secret Manager version it came from.
final class ApiKey {
  const new(this.value, this.version);

  final String value;

  /// The version number, for example `2`.
  final String version;

  @override
  String toString() => 'ApiKey(version $version)';
}

/// Reads the newest enabled version of the secret.
Future<ApiKey> readLatestKey() async {
  final describe = await Process.run('gcloud', [
    'secrets',
    'versions',
    'describe',
    'latest',
    '--secret=$secretName',
    ..._projectFlags,
    '--format=value(name)',
  ]);
  if (describe.exitCode != 0) {
    throw StateError('gcloud describe failed: ${describe.stderr}');
  }
  final version = (describe.stdout as String).trim().split('/').last;
  final access = await Process.run('gcloud', [
    'secrets',
    'versions',
    'access',
    version,
    '--secret=$secretName',
    ..._projectFlags,
  ]);
  if (access.exitCode != 0) {
    // stderr never holds the payload; stdout is never shown.
    throw StateError(
      'gcloud access of version $version failed: '
      '${access.stderr}',
    );
  }
  final value = (access.stdout as String).trim();
  if (value.isEmpty) throw StateError('version $version is empty');
  return ApiKey(value, version);
}
