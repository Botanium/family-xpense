import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/settings_privacy/lock/app_lock_controller.dart';

/// Covers the whole app while the Face ID lock is closed, and while the app
/// is in the app switcher (DESIGN_SYSTEM screen 21, BACKLOG S1.2).
///
/// Mounted once, above the router, by `MaterialApp.builder`. While covered,
/// the app below is hidden from VoiceOver, cannot be tapped or focused,
/// and its animations stop.
class AppLockGate extends ConsumerStatefulWidget {
  /// Wraps [child], the app's navigator.
  const new({required this.child, super.key});

  /// The app's navigator.
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  @override
  void initState() {
    super.initState();
    // A cold start with the lock on asks for Face ID once the first frame
    // is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptIfRequested());
  }

  void _promptIfRequested() {
    if (!mounted) return;
    // iOS shows the prompt only to an active app. If the app is not active
    // yet, the controller asks again when it is.
    final lifecycle = SchedulerBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    ref
        .read(appLockControllerProvider.notifier)
        .promptIfRequested(reason: context.l10n.lockReason);
  }

  void _unlock() => ref
      .read(appLockControllerProvider.notifier)
      .unlock(reason: context.l10n.lockReason);

  @override
  Widget build(BuildContext context) {
    ref.listen(
      appLockControllerProvider.select((s) => s.promptRequest),
      (_, _) => _promptIfRequested(),
    );
    final lock = ref.watch(appLockControllerProvider);
    final covered = lock.locked || lock.obscured;
    return Stack(
      children: [
        ExcludeSemantics(
          excluding: covered,
          child: ExcludeFocus(
            excluding: covered,
            child: IgnorePointer(
              ignoring: covered,
              child: TickerMode(enabled: !covered, child: widget.child),
            ),
          ),
        ),
        // The gate sits above the navigator, outside any Scaffold; the
        // transparent Material gives its text the theme's default style.
        if (lock.locked)
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: _LockScreen(
                notice: lock.notice,
                onUnlock: lock.authenticating ? null : _unlock,
              ),
            ),
          )
        else if (lock.obscured)
          const Positioned.fill(child: _PrivacyCover()),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const new({required this.notice, required this.onUnlock});

  final LockNotice? notice;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final message = switch (notice) {
      LockNotice.lockedOut => l10n.lockLockedOut,
      LockNotice.failed => l10n.lockFailed,
      null => null,
    };
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.lockLockedLabel,
      child: Stack(
        children: [
          Positioned.fill(
            child: LockOverlay(
              unlockLabel: l10n.lockUnlockButton,
              // The overlay needs a callback; while a prompt is up a second
              // tap is ignored by the controller anyway.
              onUnlock: onUnlock ?? () {},
            ),
          ),
          if (message != null)
            PositionedDirectional(
              start: XpSpace.screenMargin,
              end: XpSpace.screenMargin,
              bottom:
                  MediaQuery.paddingOf(context).bottom +
                  XpSpace.screenMargin +
                  XpSpace.buttonHeight +
                  XpSpace.s16,
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: type.meta.copyWith(color: colors.inkSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What the app switcher shows while the lock is on: the canvas, blurred
/// like the lock screen, with nothing readable.
class _PrivacyCover extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final blur = XpGlass.of(context).recipe(GlassVariant.sheet).blur;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: ColoredBox(
          color: XpColors.of(context).canvas
              .withValues(alpha: XpOpacity.lockCanvas),
        ),
      ),
    );
  }
}
