import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:go_router/go_router.dart';

/// The page for a pushed screen: an iOS slide with the edge back swipe
/// (DESIGN_SYSTEM 12, item 13), or a cut when Reduce Motion is on
/// (DESIGN_SYSTEM 7).
///
/// Feature routes use it as their `pageBuilder`:
/// `pageBuilder: (context, state) => xpPage(context, state, const MyScreen())`.
Page<void> xpPage(BuildContext context, GoRouterState state, Widget child) =>
    MediaQuery.disableAnimationsOf(context)
    ? NoTransitionPage<void>(key: state.pageKey, child: child)
    : CupertinoPage<void>(key: state.pageKey, child: child);
