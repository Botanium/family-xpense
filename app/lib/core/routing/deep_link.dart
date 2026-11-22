import 'package:flutter/foundation.dart';

import 'package:xpense_app/core/routing/app_routes.dart';

/// A link into the app from outside: another app, a notification, a QR
/// code (ARCHITECTURE 3.3).
///
/// [parse] is pure and total: any URI gives a [DeepLink] or null, never an
/// exception. A link only opens a screen; it never saves, sends or changes
/// anything by itself, so text from a link cannot write money data.
@immutable
sealed class DeepLink {
  const new();

  /// The app's URL scheme, registered in `ios/Runner/Info.plist`.
  static const String scheme = 'xpense';

  /// Longest Ask text a link may prefill; longer text is cut.
  static const int maxAskText = 500;

  /// Parses `xpense://ask?text=…`, `xpense://join?code=…`,
  /// `xpense://txn/{id}` and `xpense://loan/{id}`. The target may also be
  /// the first path segment (`xpense:///ask`, `xpense:ask`). Returns null
  /// for another scheme, an unknown target or a malformed id or code.
  static DeepLink? parse(Uri uri) {
    if (uri.scheme.toLowerCase() != scheme) return null;
    final segments = [
      if (uri.host.isNotEmpty) uri.host.toLowerCase(),
      ...uri.pathSegments.where((s) => s.isNotEmpty),
    ];
    if (segments.isEmpty) return null;
    final [target, ...rest] = segments;
    final query = uri.queryParameters;
    return switch ((target.toLowerCase(), rest)) {
      ('ask', []) => AskLink(text: _askText(query[AppRoutes.textParam])),
      ('join', []) => _code(query[AppRoutes.codeParam]).map(JoinLink.new),
      ('txn', [final id]) => _id(id).map(EntryLink.new),
      ('loan', [final id]) => _id(id).map(LoanLink.new),
      _ => null,
    };
  }

  /// The in-app location this link opens.
  String get location;

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static final RegExp _codePattern = RegExp(r'^[A-Za-z0-9]{4,32}$');
  static final RegExp _codeSeparators = RegExp(r'[\s-]');

  static String? _askText(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final runes = text.runes;
    if (runes.length <= maxAskText) return text;
    return String.fromCharCodes(runes.take(maxAskText)).trimRight();
  }

  static String? _id(String raw) => _idPattern.hasMatch(raw) ? raw : null;

  // Codes are shown in groups and may be typed with spaces or dashes; the
  // server checks the code itself (WP-12).
  static String? _code(String? raw) {
    final code = raw?.replaceAll(_codeSeparators, '').toUpperCase() ?? '';
    return _codePattern.hasMatch(code) ? code : null;
  }
}

/// Opens Ask, with [text] prefilled in the dock. The text is never sent
/// until the user sends it.
final class AskLink extends DeepLink {
  /// Creates the link.
  const new({this.text});

  /// Text to prefill, trimmed and at most [DeepLink.maxAskText] characters.
  final String? text;

  @override
  String get location => AppRoutes.askWith(text: text);

  @override
  bool operator ==(Object other) => other is AskLink && other.text == text;

  @override
  int get hashCode => Object.hash(AskLink, text);
}

/// Opens the join screen with an invite [code].
final class JoinLink extends DeepLink {
  /// Creates the link.
  const new(this.code);

  /// The invite code, upper-cased, without separators.
  final String code;

  @override
  String get location => AppRoutes.joinWith(code: code);

  @override
  bool operator ==(Object other) => other is JoinLink && other.code == code;

  @override
  int get hashCode => Object.hash(JoinLink, code);
}

/// Opens an entry's detail screen.
final class EntryLink extends DeepLink {
  /// Creates the link.
  const new(this.id);

  /// The transaction id.
  final String id;

  @override
  String get location => AppRoutes.entry(id);

  @override
  bool operator ==(Object other) => other is EntryLink && other.id == id;

  @override
  int get hashCode => Object.hash(EntryLink, id);
}

/// Opens a loan or debt's detail screen.
final class LoanLink extends DeepLink {
  /// Creates the link.
  const new(this.id);

  /// The loan id.
  final String id;

  @override
  String get location => AppRoutes.loan(id);

  @override
  bool operator ==(Object other) => other is LoanLink && other.id == id;

  @override
  int get hashCode => Object.hash(LoanLink, id);
}

extension on String? {
  DeepLink? map(DeepLink Function(String value) wrap) {
    final value = this;
    return value == null ? null : wrap(value);
  }
}
