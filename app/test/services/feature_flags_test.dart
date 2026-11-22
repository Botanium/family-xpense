import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/services/feature_flags.dart';
import 'package:xpense_app/services/feature_flags_fake.dart';

void main() {
  group('featureFlagsProvider', () {
    test('starts from the source and follows its changes', () async {
      final source = FakeFeatureFlags();
      final container = ProviderContainer.test(
        overrides: [featureFlagSourceProvider.overrideWithValue(source)],
      );
      final seen = <bool>[];
      container.listen(
        featureFlagsProvider.select((f) => f.appleSignInEnabled),
        (_, next) => seen.add(next),
        fireImmediately: true,
      );

      source
        ..set(const FeatureFlags(appleSignInEnabled: true))
        ..set(FeatureFlags.defaults);

      expect(seen, [false, true, false]);
    });

    test('a source that starts on (fetched on an earlier launch) is on', () {
      final container = ProviderContainer.test(
        overrides: [
          featureFlagSourceProvider.overrideWithValue(
            FakeFeatureFlags(const FeatureFlags(appleSignInEnabled: true)),
          ),
        ],
      );
      expect(container.read(featureFlagsProvider).appleSignInEnabled, isTrue);
    });
  });

  test('FeatureFlags compares by value', () {
    expect(
      const FeatureFlags(appleSignInEnabled: true),
      const FeatureFlags(appleSignInEnabled: true),
    );
    expect(
      FeatureFlags.defaults,
      isNot(const FeatureFlags(appleSignInEnabled: true)),
    );
  });
}
