import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/settings_privacy/settings_view_model.dart';
import 'package:xpense_app/services/settings_store.dart';

/// Settings (DESIGN_SYSTEM screen 20), skeleton: appearance and the Face
/// ID lock. Later packages add their sections here.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(appSettingsProvider);
    final view = ref.watch(settingsViewModelProvider);
    final model = ref.read(settingsViewModelProvider.notifier);
    return Scaffold(
      backgroundColor: XpColors.of(context).canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            XpTopBar(title: l10n.settingsTitle, leading: const XpBackButton()),
            Expanded(
              child: ListView(
                padding: EdgeInsetsDirectional.only(
                  start: XpSpace.screenMargin,
                  end: XpSpace.screenMargin,
                  top: XpSpace.s16,
                  bottom: XpSpace.bottomControlOffset(context),
                ),
                children: [
                  XpSection(
                    label: l10n.settingsAppearanceSection,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          vertical: XpSpace.s12,
                        ),
                        child: ChoiceChips<AppearanceMode>(
                          options: [
                            ChoiceOption(
                              value: AppearanceMode.system,
                              label: l10n.settingsAppearanceSystem,
                            ),
                            ChoiceOption(
                              value: AppearanceMode.light,
                              label: l10n.settingsAppearanceLight,
                            ),
                            ChoiceOption(
                              value: AppearanceMode.dark,
                              label: l10n.settingsAppearanceDark,
                            ),
                          ],
                          selected: settings.appearance,
                          onSelected: model.setAppearance,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: XpSpace.s24),
                  XpSection(
                    label: l10n.settingsSecuritySection,
                    children: [
                      XpListRow(
                        title: l10n.settingsFaceIdLock,
                        subtitle: l10n.settingsFaceIdLockHint,
                        trailing: XpSwitch(
                          value: settings.faceIdLock,
                          semanticLabel: l10n.settingsFaceIdLock,
                          onChanged: view.confirmingFaceId
                              ? null
                              : (on) => model.setFaceIdLock(
                                  on: on,
                                  reason: l10n.settingsFaceIdReason,
                                ),
                        ),
                      ),
                      if (view.faceIdNotice case final FaceIdNotice notice)
                        _Notice(_noticeText(l10n, notice)),
                    ],
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: XpSpace.s24),
                    XpSection(
                      label: l10n.settingsDeveloperSection,
                      children: [
                        XpDisclosure(
                          title: l10n.settingsGallery,
                          onTap: () => context.push(AppRoutes.gallery),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _noticeText(AppLocalizations l10n, FaceIdNotice notice) =>
      switch (notice) {
        FaceIdNotice.unavailable => l10n.settingsFaceIdUnavailable,
        FaceIdNotice.lockedOut => l10n.settingsFaceIdLockedOut,
        FaceIdNotice.failed => l10n.settingsFaceIdFailed,
      };
}

class _Notice extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.symmetric(vertical: XpSpace.s8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: XpType.of(context).meta
            .copyWith(color: XpColors.of(context).danger),
      ),
    ),
  );
}
