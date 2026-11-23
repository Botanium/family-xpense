import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/features/ask/ask_screen.dart';

/// Routes of the Ask feature: the full-height screen pushed above the tabs
/// by the round glass button, and opened by `xpense://ask?text=…`.
///
/// Text from a link is only prefilled; it is never sent until the user
/// sends it.
FeatureRoutes askRoutes() => FeatureRoutes(
  routes: [
    GoRoute(
      path: AppRoutes.ask,
      pageBuilder: (context, state) => xpPage(
        context,
        state,
        AskScreen(prefill: state.uri.queryParameters[AppRoutes.textParam]),
      ),
    ),
  ],
);
