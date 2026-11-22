import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/buttons.dart';
import 'package:xpense_app/core/ui/xp_icon.dart';

/// Two overlapping initials: the user in ink, the partner in white
/// (DESIGN_SYSTEM 8.2, Home artboard).
class AvatarPair extends StatelessWidget {
  /// Creates the pair.
  const new({
    required this.first,
    required this.second,
    required this.semanticLabel,
    super.key,
  });

  /// The user's initial.
  final String first;

  /// The partner's initial; empty before they join.
  final String second;

  /// Spoken label, such as "You and Sam".
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    Widget avatar(String initial, Color fill, Color text) => Container(
      width: XpSpace.avatar,
      height: XpSpace.avatar,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: colors.canvas, width: XpSpace.avatarRing),
      ),
      child: Text(
        initial,
        style: type.meta.copyWith(fontWeight: FontWeight.w600, color: text),
      ),
    );
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar(first, colors.ink, colors.canvas),
          if (second.isNotEmpty)
            Transform.translate(
              offset: Offset(
                Directionality.of(context) == TextDirection.rtl
                    ? XpSpace.avatarOverlap
                    : -XpSpace.avatarOverlap,
                0,
              ),
              child: avatar(second, colors.surface, colors.ink),
            ),
        ],
      ),
    );
  }
}

/// Four orange corner brackets marking where the receipt should be
/// (DESIGN_SYSTEM 8.2). A "live" mark, so orange is allowed.
class ScanFrame extends StatelessWidget {
  /// Creates a scan frame that fills its parent.
  const new({this.semanticLabel, super.key});

  /// Spoken hint, such as "Fit the receipt inside the frame".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: CustomPaint(
      painter: _BracketPainter(color: XpColors.of(context).accent),
      child: const SizedBox.expand(),
    ),
  );
}

class _BracketPainter extends CustomPainter {
  const new({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const arm = XpSpace.scanBracket;
    const s = XpSpace.scanStroke;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s
      ..strokeCap = StrokeCap.butt;
    final w = size.width;
    final h = size.height;
    const o = s / 2;
    canvas
      ..drawPath(
        Path()
          ..moveTo(o, arm)
          ..lineTo(o, o)
          ..lineTo(arm, o),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(w - arm, o)
          ..lineTo(w - o, o)
          ..lineTo(w - o, arm),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(o, h - arm)
          ..lineTo(o, h - o)
          ..lineTo(arm, h - o),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(w - arm, h - o)
          ..lineTo(w - o, h - o)
          ..lineTo(w - o, h - arm),
        paint,
      );
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.color != color;
}

/// Legibility scrim under the top controls on the camera screen: black from
/// 35 % to clear over 120 pt (DESIGN_SYSTEM 6.2).
class CameraScrim extends StatelessWidget {
  /// Creates the scrim.
  const new({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox(
      height: XpSpace.cameraScrim + MediaQuery.paddingOf(context).top,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              XpElevation.scrim.withValues(alpha: XpOpacity.cameraScrim),
              XpElevation.scrim.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The app lock: blurred canvas, app mark and a Face ID button
/// (DESIGN_SYSTEM 8.2).
class LockOverlay extends StatelessWidget {
  /// Creates the lock overlay.
  const new({
    required this.unlockLabel,
    required this.onUnlock,
    this.mark,
    super.key,
  });

  /// "Unlock with Face ID".
  final String unlockLabel;

  /// Starts authentication.
  final VoidCallback onUnlock;

  /// The app mark; defaults to the Ask sparkle in an ink tile.
  final Widget? mark;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final blur = XpGlass.of(context).recipe(GlassVariant.sheet).blur;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: ColoredBox(
          color: colors.canvas.withValues(alpha: XpOpacity.lockCanvas),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.all(XpSpace.screenMargin),
              child: Column(
                children: [
                  const Spacer(),
                  mark ??
                      SizedBox.square(
                        dimension: XpSpace.askButton,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: colors.primaryFill,
                            shape: const RoundedSuperellipseBorder(
                              borderRadius: XpRadius.dockAll,
                            ),
                          ),
                          child: Center(
                            child: XpIcon(
                              XpGlyph.sparkle,
                              size: XpSpace.iconAsk,
                              color: colors.onPrimaryFill,
                            ),
                          ),
                        ),
                      ),
                  const Spacer(),
                  XpButton.secondary(
                    label: unlockLabel,
                    glyph: XpGlyph.faceId,
                    onPressed: onUnlock,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
