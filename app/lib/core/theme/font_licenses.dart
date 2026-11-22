import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset path of the SIL Open Font License shipped with Geist and Geist Mono.
const String fontLicenseAsset = 'assets/fonts/OFL.txt';

/// Registers the bundled fonts' licence with [LicenseRegistry], so it shows
/// on the licences page. Call once before `runApp`.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(fontLicenseAsset);
    yield LicenseEntryWithLineBreaks(const ['Geist', 'Geist Mono'], text);
  });
}
