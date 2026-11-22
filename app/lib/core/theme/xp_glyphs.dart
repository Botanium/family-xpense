import 'dart:ui';

/// The Signal line icons, drawn from the prototype's 24 × 24 SVG paths so
/// the app needs no icon font.
enum XpGlyph {
  /// Home tab.
  home(1.7),

  /// Activity tab (bulleted list).
  activity(1.7),

  /// Goals tab (target).
  goals(1.7),

  /// Accounts tab (wallet).
  accounts(1.7),

  /// Ask (four-point sparkle).
  sparkle(1.8),

  /// Notifications.
  bell(1.6),

  /// Back; mirrors in right-to-left layouts.
  back(1.8, directional: true),

  /// Forward chevron for disclosure rows; mirrors in right-to-left layouts.
  forward(1.8, directional: true),

  /// Down chevron for menus.
  chevronDown(1.8),

  /// Close.
  close(1.9),

  /// Lock (on-device mode).
  lock(2),

  /// Keyboard (type instead).
  keyboard(1.6),

  /// Camera (scan a receipt).
  camera(1.6),

  /// Microphone (talk).
  mic(1.8),

  /// Stop (filled rounded square).
  stop(0, filled: true),

  /// Add.
  plus(1.8),

  /// Done.
  check(1.9),

  /// Search.
  search(1.7),

  /// Face ID.
  faceId(1.6),

  /// More actions.
  more(2.6),

  /// Restore an earlier version.
  restore(1.7),

  /// Offline (cloud with a slash).
  offline(1.6);

  new(this.strokeWidth, {this.directional = false, this.filled = false});

  /// Stroke width on the 24-unit grid.
  final double strokeWidth;

  /// Whether the glyph mirrors in right-to-left layouts.
  final bool directional;

  /// Whether the glyph is filled rather than stroked.
  final bool filled;
}

Path _dots(List<Offset> points) {
  final path = Path();
  for (final p in points) {
    path
      ..moveTo(p.dx, p.dy)
      ..lineTo(p.dx + 0.01, p.dy);
  }
  return path;
}

Path _roundRect(double x, double y, double w, double h, double r) =>
    Path()..addRRect(RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(r)));

/// Returns the outline of [glyph] on a 24 × 24 grid.
Path glyphPath(XpGlyph glyph) {
  const r2 = Radius.circular(2);
  return switch (glyph) {
    XpGlyph.home =>
      Path()
        ..moveTo(3, 10.5)
        ..lineTo(12, 3)
        ..lineTo(21, 10.5)
        ..moveTo(5, 9.5)
        ..lineTo(5, 21)
        ..lineTo(19, 21)
        ..lineTo(19, 9.5),
    XpGlyph.activity =>
      Path()
        ..moveTo(9, 6)
        ..lineTo(21, 6)
        ..moveTo(9, 12)
        ..lineTo(21, 12)
        ..moveTo(9, 18)
        ..lineTo(21, 18)
        ..addPath(
          _dots(const [Offset(4, 6), Offset(4, 12), Offset(4, 18)]),
          Offset.zero,
        ),
    XpGlyph.goals =>
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9))
        ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 5)),
    XpGlyph.accounts =>
      Path()
        ..moveTo(3, 7)
        ..arcToPoint(const Offset(5, 5), radius: r2)
        ..lineTo(18, 5)
        ..lineTo(18, 9)
        ..moveTo(3, 7)
        ..lineTo(3, 18)
        ..arcToPoint(const Offset(5, 20), radius: r2, clockwise: false)
        ..lineTo(21, 20)
        ..lineTo(21, 9)
        ..lineTo(5, 9)
        ..arcToPoint(const Offset(3, 7), radius: r2)
        ..close(),
    XpGlyph.sparkle =>
      Path()
        ..moveTo(12, 3)
        ..lineTo(13.8, 8.2)
        ..lineTo(19, 10)
        ..lineTo(13.8, 11.8)
        ..lineTo(12, 17)
        ..lineTo(10.2, 11.8)
        ..lineTo(5, 10)
        ..lineTo(10.2, 8.2)
        ..close(),
    XpGlyph.bell =>
      Path()
        ..moveTo(6, 16)
        ..lineTo(6, 11)
        ..arcToPoint(const Offset(18, 11), radius: const Radius.circular(6))
        ..lineTo(18, 16)
        ..lineTo(19.5, 18)
        ..lineTo(4.5, 18)
        ..close()
        ..moveTo(10, 20.5)
        ..arcToPoint(const Offset(14, 20.5), radius: r2, clockwise: false),
    XpGlyph.back =>
      Path()
        ..moveTo(15, 5)
        ..lineTo(8, 12)
        ..lineTo(15, 19),
    XpGlyph.forward =>
      Path()
        ..moveTo(9, 5)
        ..lineTo(16, 12)
        ..lineTo(9, 19),
    XpGlyph.chevronDown =>
      Path()
        ..moveTo(6, 9)
        ..lineTo(12, 15)
        ..lineTo(18, 9),
    XpGlyph.close =>
      Path()
        ..moveTo(6, 6)
        ..lineTo(18, 18)
        ..moveTo(18, 6)
        ..lineTo(6, 18),
    XpGlyph.lock =>
      _roundRect(5, 11, 14, 10, 2)
        ..moveTo(8, 11)
        ..lineTo(8, 7)
        ..arcToPoint(const Offset(16, 7), radius: const Radius.circular(4))
        ..lineTo(16, 11),
    XpGlyph.keyboard =>
      _roundRect(3, 6, 18, 12, 2)
        ..addPath(
          _dots(const [Offset(7, 10), Offset(11, 10), Offset(15, 10)]),
          Offset.zero,
        )
        ..moveTo(7, 14)
        ..lineTo(17, 14),
    XpGlyph.camera =>
      Path()
        ..moveTo(4, 8)
        ..lineTo(7, 8)
        ..lineTo(9, 5)
        ..lineTo(15, 5)
        ..lineTo(17, 8)
        ..lineTo(20, 8)
        ..lineTo(20, 19)
        ..lineTo(4, 19)
        ..close()
        ..addOval(Rect.fromCircle(center: const Offset(12, 13), radius: 3.5)),
    XpGlyph.mic =>
      _roundRect(9, 3, 6, 12, 3)
        ..moveTo(5, 11)
        ..arcToPoint(
          const Offset(19, 11),
          radius: const Radius.circular(7),
          clockwise: false,
        )
        ..moveTo(12, 18)
        ..lineTo(12, 21),
    XpGlyph.stop => _roundRect(6, 6, 12, 12, 3),
    XpGlyph.plus =>
      Path()
        ..moveTo(12, 5)
        ..lineTo(12, 19)
        ..moveTo(5, 12)
        ..lineTo(19, 12),
    XpGlyph.check =>
      Path()
        ..moveTo(5, 12.5)
        ..lineTo(9.5, 17)
        ..lineTo(19, 7),
    XpGlyph.search =>
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(11, 11), radius: 6.5))
        ..moveTo(16, 16)
        ..lineTo(20.5, 20.5),
    XpGlyph.faceId =>
      Path()
        ..moveTo(4, 8)
        ..lineTo(4, 6)
        ..arcToPoint(const Offset(6, 4), radius: r2)
        ..lineTo(8, 4)
        ..moveTo(16, 4)
        ..lineTo(18, 4)
        ..arcToPoint(const Offset(20, 6), radius: r2)
        ..lineTo(20, 8)
        ..moveTo(20, 16)
        ..lineTo(20, 18)
        ..arcToPoint(const Offset(18, 20), radius: r2)
        ..lineTo(16, 20)
        ..moveTo(8, 20)
        ..lineTo(6, 20)
        ..arcToPoint(const Offset(4, 18), radius: r2)
        ..lineTo(4, 16)
        ..moveTo(9, 9.5)
        ..lineTo(9, 10.5)
        ..moveTo(15, 9.5)
        ..lineTo(15, 10.5)
        ..moveTo(12, 9.5)
        ..lineTo(12, 13.5)
        ..lineTo(11, 13.5)
        ..moveTo(9, 16)
        ..arcToPoint(
          const Offset(15, 16),
          radius: const Radius.circular(4),
          clockwise: false,
        ),
    XpGlyph.more => _dots(const [
      Offset(6, 12),
      Offset(12, 12),
      Offset(18, 12),
    ]),
    XpGlyph.restore =>
      Path()
        ..moveTo(4.5, 12)
        ..arcToPoint(
          const Offset(6.8, 6.6),
          radius: const Radius.circular(7.5),
          largeArc: true,
          clockwise: false,
        )
        ..moveTo(4, 4)
        ..lineTo(4, 8)
        ..lineTo(8, 8)
        ..moveTo(12, 8)
        ..lineTo(12, 12)
        ..lineTo(15, 14),
    XpGlyph.offline =>
      Path()
        ..moveTo(7, 18)
        ..arcToPoint(const Offset(6.5, 10), radius: const Radius.circular(4))
        ..arcToPoint(
          const Offset(17.5, 10.5),
          radius: const Radius.circular(5.5),
        )
        ..arcToPoint(const Offset(17, 18), radius: const Radius.circular(3.8))
        ..close()
        ..moveTo(4, 4)
        ..lineTo(20, 20),
  };
}
