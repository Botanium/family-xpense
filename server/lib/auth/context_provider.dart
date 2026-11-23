/// The context provider for every public route (ARCHITECTURE 4.4).
///
/// 1. `Authorization: Bearer <Firebase ID token>` and
///    `X-Firebase-AppCheck: <App Check token>` are both required.
/// 2. Both tokens are verified through the admin gateway.
/// 3. The member is loaded (60 s cache): household, privacy mode, locale and
///    time zone.
/// 4. On-device members are refused, and so are households at a daily limit
///    for the counters the route consumes.
/// 5. The context `{uid, hid, locale, privacyMode, tz}` is returned.
///
/// Refusals are `GenkitException`s whose message is an [AuthFailure] code, so
/// the phone gets 401, 403, 429 or 503 with a stable code and nothing else.
library;

import 'dart:async';

import 'package:genkit/io.dart';
import 'package:logging/logging.dart';

import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/auth/auth_failure.dart';
import 'package:xpense_agent/auth/member_directory.dart';
import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';

final _log = Logger('xpense.auth');

/// Header carrying the App Check token, as the Firebase client SDKs send it.
const appCheckHeader = 'x-firebase-appcheck';

/// Builds context providers for the public routes.
final class XpenseContextProvider {
  /// Creates the provider.
  new({
    required this._gateway,
    required this._members,
    required this._config,
    required this._usage,
  });

  final AdminGateway _gateway;
  final MemberDirectory _members;
  final RuntimeConfigLoader _config;
  final UsageCounters _usage;

  /// A provider for a route that consumes [meters]. The household is refused
  /// with [AuthFailure.overLimit] when any of them is at its daily limit.
  /// Routes that do no AI work (such as `ping`) pass none, and no usage is
  /// read.
  ///
  /// [allowOnDevice] admits On-device members. Only routes that send no
  /// member text, audio or images to AI (such as `/household/invite`) set it.
  ContextProvider forRoute({
    Set<UsageCounter> meters = const {},
    bool allowOnDevice = false,
  }) =>
      (request) => resolve(
        request.headers,
        meters: meters,
        allowOnDevice: allowOnDevice,
      );

  /// A provider for a route open to any signed-in user, member of a
  /// household or not, such as `/household/join`. Both tokens are verified;
  /// the context is only `{uid}` ([CallerContext]).
  ContextProvider forSignedInUser() =>
      (request) => resolveCaller(request.headers);

  /// Verifies [headers] (lowercased names) and returns the context map.
  Future<Map<String, dynamic>> resolve(
    Map<String, String> headers, {
    Set<UsageCounter> meters = const {},
    bool allowOnDevice = false,
  }) => _guard(() async {
    final context = await _resolve(headers, meters, allowOnDevice);
    return context.toMap();
  });

  /// Verifies [headers] (lowercased names) and returns `{uid}`, without
  /// looking up a household.
  Future<Map<String, dynamic>> resolveCaller(Map<String, String> headers) =>
      _guard(() async {
        final user = await _verifyTokens(headers);
        return CallerContext(uid: user.uid).toMap();
      });

  /// Maps the module's typed refusals to the Genkit errors the phone gets.
  Future<Map<String, dynamic>> _guard(
    Future<Map<String, dynamic>> Function() resolve,
  ) async {
    try {
      return await resolve();
    } on AuthRejection catch (e) {
      _log.info('refused: ${e.failure.code}');
      throw e.failure.toException();
    } on GatewayUnavailable catch (e) {
      _log.warning('refused: backend unavailable (${e.operation})', e.cause);
      throw AuthFailure.unavailable.toException();
    } on Object catch (e, st) {
      // A bug. Genkit answers anything that is not a GenkitException with a
      // bare 403, so the request still fails closed; log it here.
      _log.severe('context provider failed', e, st);
      rethrow;
    }
  }

  Future<XpenseContext> _resolve(
    Map<String, String> headers,
    Set<UsageCounter> meters,
    bool allowOnDevice,
  ) async {
    final verifiedUser = await _verifyTokens(headers);
    final member = await _members.lookup(verifiedUser.uid);
    if (!allowOnDevice && member.privacyMode == PrivacyMode.onDevice) {
      throw const AuthRejection(AuthFailure.onDeviceMode);
    }
    if (meters.isNotEmpty) await _checkLimits(member.hid, meters);

    return XpenseContext(
      uid: member.uid,
      hid: member.hid,
      locale: member.locale,
      privacyMode: member.privacyMode,
      tz: member.timeZone,
    );
  }

  /// Steps 1 and 2: both headers present, both tokens verified.
  Future<VerifiedUser> _verifyTokens(Map<String, String> headers) async {
    final idToken = _bearer(headers['authorization']);
    if (idToken == null) throw const AuthRejection(AuthFailure.missingIdToken);
    final appCheckToken = headers[appCheckHeader]?.trim() ?? '';
    if (appCheckToken.isEmpty) {
      throw const AuthRejection(AuthFailure.missingAppCheck);
    }

    // Both checks run at once; an ID-token failure is reported first. The
    // App Check future is marked handled so its error is not reported as
    // uncaught when the ID token fails first.
    final user = _verify(
      () => _gateway.idTokens.verifyIdToken(idToken),
      AuthFailure.invalidIdToken,
    );
    final app = _verify(
      () => _gateway.appCheck.verifyAppCheckToken(appCheckToken),
      AuthFailure.invalidAppCheck,
    )..ignore();
    final verifiedUser = await user;
    await app;
    return verifiedUser;
  }

  Future<void> _checkLimits(String hid, Set<UsageCounter> meters) async {
    // The loader never throws (it falls back to the last good config).
    final config = _config.current();
    final usage = await _usage.today(hid);
    final over = UsageCounters.overLimit(
      usage: usage,
      limits: (await config).limits,
      meters: meters,
    );
    if (over.isNotEmpty) {
      _log.info('over limit: ${over.map((c) => c.field).join(', ')}');
      throw const AuthRejection(AuthFailure.overLimit);
    }
  }

  /// Runs one token check, mapping a rejection to [failure].
  static Future<T> _verify<T>(
    Future<T> Function() check,
    AuthFailure failure,
  ) async {
    try {
      return await check();
    } on TokenRejected catch (e) {
      _log.info('token rejected: ${e.reason}');
      throw AuthRejection(failure);
    }
  }

  static String? _bearer(String? header) {
    if (header == null) return null;
    final match = _bearerPattern.firstMatch(header.trim());
    final token = match?.group(1);
    return token == null || token.isEmpty ? null : token;
  }

  static final _bearerPattern = RegExp(
    r'^Bearer\s+(\S+)$',
    caseSensitive: false,
  );
}
