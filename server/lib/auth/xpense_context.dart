/// The verified request context every flow, agent turn and tool reads.
library;

import 'package:genkit/genkit.dart';
import 'package:meta/meta.dart';

/// A member's privacy mode (`members/{uid}.privacyMode`, DATA_MODEL 2.3).
enum PrivacyMode {
  /// No AI processing leaves the phone. The server refuses AI routes.
  onDevice('on_device'),

  /// Classification in the cloud, the rest on the phone. The default.
  smart('smart'),

  /// Cloud AI for everything.
  cloud('cloud');

  new(this.wire);

  /// The value stored in Firestore and sent in the context.
  final String wire;

  /// Parses a stored value. A missing value is the documented default,
  /// [smart]; an unrecognised one fails closed to [onDevice], so a corrupt or
  /// future value never sends data to cloud AI.
  static PrivacyMode parse(Object? value) {
    if (value == null) return smart;
    for (final mode in values) {
      if (mode.wire == value) return mode;
    }
    return onDevice;
  }
}

/// The context the provider returns: `{uid, hid, locale, privacyMode, tz}`.
///
/// It holds ids and settings only, never names or text: Genkit records the
/// context map in trace spans (WP-S1).
@immutable
final class XpenseContext {
  /// Creates a context.
  const new({
    required this.uid,
    required this.hid,
    required this.locale,
    required this.privacyMode,
    required this.tz,
  });

  /// Reads the context of a running action (`ctx.context`).
  ///
  /// Throws an unauthenticated [GenkitException] when the action was invoked
  /// without the provider (for example from the Developer UI with no
  /// context), so a flow can never run on made-up ids.
  factory of(Map<String, dynamic>? context) {
    final uid = context?[_uid];
    final hid = context?[_hid];
    final locale = context?[_locale];
    final mode = context?[_privacyMode];
    final tz = context?[_tz];
    if (uid is! String ||
        hid is! String ||
        locale is! String ||
        mode is! String ||
        tz is! String) {
      throw GenkitException(
        'missing_context',
        status: StatusCode.unauthenticated,
      );
    }
    return XpenseContext(
      uid: uid,
      hid: hid,
      locale: locale,
      privacyMode: PrivacyMode.parse(mode),
      tz: tz,
    );
  }

  static const _uid = 'uid';
  static const _hid = 'hid';
  static const _locale = 'locale';
  static const _privacyMode = 'privacyMode';
  static const _tz = 'tz';

  /// Firebase Auth user id of the caller.
  final String uid;

  /// The caller's household id.
  final String hid;

  /// UI language (`users/{uid}.locale`), `en` for now (D-36).
  final String locale;

  /// The caller's privacy mode.
  final PrivacyMode privacyMode;

  /// The household's IANA time zone (`households/{hid}.timeZone`).
  final String tz;

  /// The map handed to Genkit as the action context.
  Map<String, dynamic> toMap() => {
    _uid: uid,
    _hid: hid,
    _locale: locale,
    _privacyMode: privacyMode.wire,
    _tz: tz,
  };

  @override
  bool operator ==(Object other) =>
      other is XpenseContext &&
      other.uid == uid &&
      other.hid == hid &&
      other.locale == locale &&
      other.privacyMode == privacyMode &&
      other.tz == tz;

  @override
  int get hashCode => Object.hash(uid, hid, locale, privacyMode, tz);

  @override
  String toString() =>
      'XpenseContext(uid: $uid, hid: $hid, locale: $locale, '
      'privacyMode: ${privacyMode.wire}, tz: $tz)';
}
