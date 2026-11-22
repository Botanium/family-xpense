/// App Check stand-in for local runs against the Firebase emulators.
library;

import 'package:logging/logging.dart';

import 'package:xpense_agent/admin/admin_gateway.dart';

final _log = Logger('xpense.admin.app_check');

/// Accepts any non-empty App Check token.
///
/// App Check cannot be emulated. Used only when `XPENSE_APP_CHECK=emulator`,
/// which `ServerEnv` allows off Cloud Run with the Auth emulator only. The
/// header stays required, so the phone's request shape is the same as in
/// production.
final class EmulatorAppCheckVerifier implements AppCheckVerifier {
  /// Creates the verifier and logs a warning once.
  new() {
    _log.warning('App Check is NOT verified (XPENSE_APP_CHECK=emulator)');
  }

  @override
  Future<VerifiedApp> verifyAppCheckToken(String token) async {
    if (token.isEmpty) throw const TokenRejected('app-check/empty');
    return const VerifiedApp(appId: 'emulator');
  }
}
