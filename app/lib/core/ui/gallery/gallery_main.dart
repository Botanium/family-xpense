// Debug entry point for the component gallery:
//   flutter run -t lib/core/ui/gallery/gallery_main.dart
// The product app reaches the same page at /gallery once WP-10 registers the
// route in debug builds.
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/gallery/gallery_page.dart';
import 'package:xpense_app/core/ui/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  await GlassSetup.initialize();
  final glass = await GlassController.start();
  GlassFrameBudget(glass).attach();
  debugPrint('Gallery glass tier: ${glass.tier} (${glass.flags})');
  runApp(GalleryApp(glass: glass));
}

/// Standalone app around [GalleryPage].
class GalleryApp extends StatelessWidget {
  /// Creates the gallery app.
  const new({required this.glass, super.key});

  /// Glass tier for the session.
  final GlassController glass;

  @override
  Widget build(BuildContext context) => GlassScope(
    controller: glass,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Signal gallery',
      theme: XpThemes.light,
      darkTheme: XpThemes.dark,
      highContrastTheme: XpThemes.lightHighContrast,
      highContrastDarkTheme: XpThemes.darkHighContrast,
      themeAnimationStyle: xpThemeAnimationStyle,
      initialRoute: galleryRoutePath,
      routes: {galleryRoutePath: (_) => const GalleryPage()},
    ),
  );
}
