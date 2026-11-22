// Debug entry point for the Xpense catalog gallery (WP-31):
//   flutter run -t lib/a2ui/gallery/a2ui_gallery_main.dart
// Local surfaces built with xpense_shared's SurfaceBuilder, rendered by
// XpenseSurfaceHost against FakeXpenseActions, so EntryList and
// ReceiptSummary can be edited and saved before the write path (WP-20)
// exists. Developer-facing: its sample data is not product copy.
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
import 'package:xpense_app/a2ui/widgets/format.dart' show dayString;
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_shared/xpense_shared.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  await GlassSetup.initialize();
  final glass = await GlassController.start();
  final actions = FakeXpenseActions();
  final host = XpenseSurfaceHost(
    actions: actions,
    onAgentAction: (a) => debugPrint('to agent: ${a.name} ${a.context}'),
    onIssue: (i) => debugPrint('skipped: $i'),
  )..addMessages(gallerySurfaces(dayString(DateTime.now())));
  runApp(A2uiGalleryApp(glass: glass, host: host));
}

/// The gallery's surfaces, dated [day].
List<Map<String, Object?>> gallerySurfaces(String day) => [
  ...captureSurface(
    surfaceId: 'loc_demo_capture',
    title: 'I found two things in that:',
    transcript: const TranscriptData(
      text: 'Lunch with the kids, ten thousand dinars, and the rent',
      seconds: 5,
    ),
    drafts: [
      EntryDraft(
        id: 'd1',
        intent: 'expense',
        amountMinor: 10000,
        currency: 'IQD',
        categoryId: 'dining',
        who: 'me',
        occurredOn: day,
        title: 'Lunch with the kids',
        fx: FxQuote(
          pair: 'USD/IQD',
          pairRate: '1705',
          source: 'market',
          asOf: day,
          baseAmountMinor: 587,
        ),
        confidence: DraftConfidence(intent: 0.97, category: 0.94),
        missing: ['accountId'],
        origin: 'decisions',
      ),
      EntryDraft(
        id: 'd2',
        intent: 'expense',
        amountMinor: 140000,
        currency: 'USD',
        categoryId: 'rent',
        accountId: 'acc_chk',
        who: 'joint',
        occurredOn: day,
        title: 'Rent',
        confidence: DraftConfidence(intent: 0.98, category: 0.99, who: 0.62),
        guessed: ['who'],
        origin: 'decisions',
      ),
    ],
  ),
  ...nudgeSurface(
    surfaceId: 'loc_demo_nudge',
    text: 'Internet is usually paid by the 5th.',
    kind: NudgeKind.bill,
    actionLabel: 'Add',
    action: const LocalAction(
      LocalActionNames.sendText,
      context: {'message': 'Paid the internet, 45 dollars'},
    ),
  ),
];

/// Standalone app around the gallery thread.
class A2uiGalleryApp extends StatelessWidget {
  /// Creates the app.
  const new({required this.glass, required this.host, super.key});

  /// Glass tier for the session.
  final GlassController glass;

  /// The surfaces.
  final XpenseSurfaceHost host;

  @override
  Widget build(BuildContext context) => GlassScope(
    controller: glass,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: XpThemes.light,
      darkTheme: XpThemes.dark,
      highContrastTheme: XpThemes.lightHighContrast,
      highContrastDarkTheme: XpThemes.darkHighContrast,
      themeAnimationStyle: xpThemeAnimationStyle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: XpColors.of(context).canvas,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: XpSpace.screenMargin,
                vertical: XpSpace.s16,
              ),
              child: SurfaceThread(host: host),
            ),
          ),
        ),
      ),
    ),
  );
}
