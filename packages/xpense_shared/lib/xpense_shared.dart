/// Pure Dart core shared by the Family Xpense app and server.
///
/// Money and FX, digit folding, the fast parser, schemantic schemas, the
/// intent taxonomy, the catalog JSON and the local surface builder live here
/// (ARCHITECTURE 2). This library must not depend on Flutter, `dart:io`,
/// Firebase or `a2ui_core`, so that the app and the server can each resolve
/// their own `a2ui_core` (D-05). The modules are added from WP-02 on.
library;
