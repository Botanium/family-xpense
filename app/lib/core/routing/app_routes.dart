/// Every screen's location (ARCHITECTURE 3.3).
///
/// Call sites build locations here instead of writing paths by hand.
/// Identity always travels in the path or query, never in `extra`, so a
/// cold start from a deep link rebuilds the screen from the URL alone.
abstract final class AppRoutes {
  /// Home tab.
  static const String home = '/home';

  /// Activity tab.
  static const String activity = '/activity';

  /// Goals tab.
  static const String goals = '/goals';

  /// Accounts tab.
  static const String accounts = '/accounts';

  /// Ask, pushed above the shell by the round glass button.
  static const String ask = '/ask';

  /// Settings.
  static const String settings = '/settings';

  /// Join a household from an invite.
  static const String join = '/join';

  /// Household setup (screen 3): name, display name, base currency, invite.
  /// Where a signed-in person without a household goes (WP-12).
  static const String householdSetup = '/household';

  /// Try it (screen 5), the first capture. Household setup and joining
  /// continue here until WP-13 puts Add accounts (screen 4) in between.
  static const String tryIt = '/try-it';

  /// Route pattern of an entry's detail screen.
  static const String entryPattern = '/entries/:$idParam';

  /// Route pattern of a loan or debt's detail screen.
  static const String loanPattern = '/loans/:$idParam';

  /// Where a link that opens nothing lands.
  static const String notFound = '/not-found';

  /// The component gallery, registered in debug builds only. Equal to
  /// `galleryRoutePath` in `core/ui/gallery/`.
  static const String gallery = '/gallery';

  /// Path parameter holding an entity id.
  static const String idParam = 'id';

  /// Query parameter holding text to prefill in Ask.
  static const String textParam = 'text';

  /// Query parameter holding an invite code.
  static const String codeParam = 'code';

  /// Ask, with [text] prefilled in the dock when given.
  static String askWith({String? text}) => _withQuery(ask, textParam, text);

  /// Join, with the invite [code] prefilled.
  static String joinWith({required String code}) =>
      _withQuery(join, codeParam, code);

  /// The detail screen of the entry [id].
  static String entry(String id) => '/entries/${Uri.encodeComponent(id)}';

  /// The detail screen of the loan or debt [id].
  static String loan(String id) => '/loans/${Uri.encodeComponent(id)}';

  static String _withQuery(String path, String key, String? value) =>
      value == null || value.isEmpty
      ? path
      : Uri(path: path, queryParameters: {key: value}).toString();
}
