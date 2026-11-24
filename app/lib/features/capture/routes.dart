import 'package:go_router/go_router.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/capture/manual/sheet_launcher.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Routes of the Capture feature: Add manually and the entry edit sheet
/// (WP-21). WP-40, WP-41 and WP-80 add voice, receipt scan and quick
/// capture.
///
/// Both are sheets over whatever is showing: the route is a transparent
/// page that presents the sheet and closes itself when the sheet does, so
/// another feature can open them by location (features do not import each
/// other).
/// Add this feature's screens here, never in the central router.
FeatureRoutes captureRoutes() => FeatureRoutes(
  routes: [
    GoRoute(
      path: AppRoutes.addEntry,
      pageBuilder: (context, state) => sheetLauncherPage(
        state,
        AddManuallyLauncher(
          draft: switch (state.extra) {
            final EntryDraft draft => draft,
            final FormRequest request => request.draft,
            _ => null,
          },
          quiet: switch (state.extra) {
            final FormRequest request => request.quiet,
            _ => false,
          },
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.entryEditPattern,
      pageBuilder: (context, state) => sheetLauncherPage(
        state,
        EditEntryLauncher(
          txnId: state.pathParameters[AppRoutes.idParam] ?? '',
          field: state.uri.queryParameters[AppRoutes.fieldParam],
        ),
      ),
    ),
  ],
);
