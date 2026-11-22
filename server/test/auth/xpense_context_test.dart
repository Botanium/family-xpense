import 'package:genkit/genkit.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/auth/xpense_context.dart';

void main() {
  const context = XpenseContext(
    uid: 'u1',
    hid: 'h1',
    locale: 'en',
    privacyMode: PrivacyMode.smart,
    tz: 'Asia/Baghdad',
  );

  test('round-trips through the context map', () {
    expect(XpenseContext.of(context.toMap()), context);
  });

  test('the map holds ids and settings only', () {
    expect(context.toMap().keys, {'uid', 'hid', 'locale', 'privacyMode', 'tz'});
  });

  test('missing or partial context is unauthenticated', () {
    for (final map in [
      null,
      <String, dynamic>{},
      {...context.toMap()}..remove('hid'),
      {...context.toMap(), 'uid': 42},
    ]) {
      expect(
        () => XpenseContext.of(map),
        throwsA(
          isA<GenkitException>().having(
            (e) => e.status,
            'status',
            StatusCode.unauthenticated,
          ),
        ),
      );
    }
  });

  group('PrivacyMode.parse', () {
    test('known values', () {
      expect(PrivacyMode.parse('on_device'), PrivacyMode.onDevice);
      expect(PrivacyMode.parse('smart'), PrivacyMode.smart);
      expect(PrivacyMode.parse('cloud'), PrivacyMode.cloud);
    });

    test('missing is Smart, the documented default', () {
      expect(PrivacyMode.parse(null), PrivacyMode.smart);
    });

    test('anything else fails closed to On-device', () {
      for (final value in ['Cloud', '', 'onDevice', 3, true]) {
        expect(
          PrivacyMode.parse(value),
          PrivacyMode.onDevice,
          reason: '$value',
        );
      }
    });
  });
}
