import 'package:material_ui/material_ui.dart';

/// Placeholder entry point.
///
/// The real startup order (ARCHITECTURE 3.3: error handlers, Firebase,
/// App Check, theme restore, then `runApp`) is built in WP-10.
void main() => runApp(const XpenseApp());

/// Root widget placeholder until WP-10 builds the app shell.
class XpenseApp extends StatelessWidget {
  /// Creates the placeholder root widget.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: SizedBox.shrink());
}
