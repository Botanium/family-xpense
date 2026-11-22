import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';

/// Starts the app in the order of ARCHITECTURE 3.3: error handlers, then
/// Firebase and App Check (dev and prod only), then settings, theme and
/// glass restore, then `runApp`. Post-frame work starts in `XpenseApp`.
///
/// `--dart-define=XPENSE_ENV=dev|prod` picks the backend; without it the
/// app runs on fakes and needs no Firebase config.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final errors = ErrorLog();
  installErrorHandlers(errors);

  final app = await bootstrap(environment: AppEnvironment.compiled);

  runApp(
    ProviderScope(
      // Every provider here fails for a local reason (a bug, a missing
      // wiring), so fail at once instead of retrying behind a spinner.
      retry: (_, _) => null,
      overrides: app.overrides,
      child: const XpenseApp(),
    ),
  );
}
