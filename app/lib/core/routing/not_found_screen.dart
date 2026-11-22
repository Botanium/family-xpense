import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/app_routes.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// Where a link that matches no screen lands: one line and a way home,
/// never a red error box.
class NotFoundScreen extends StatelessWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: XpColors.of(context).canvas,
      body: SafeArea(
        child: Column(
          children: [
            XpTopBar(title: l10n.routingNotFoundTitle),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: XpSpace.screenMargin,
                ),
                child: Center(
                  child: EmptyState(
                    message: l10n.routingNotFoundMessage,
                    actionLabel: l10n.routingNotFoundAction,
                    onAction: () => context.go(AppRoutes.home),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
