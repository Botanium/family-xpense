import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the system share sheet with [text].
typedef ShareText = Future<void> Function(String text);

/// How household setup shares the invite. Tests override it.
///
/// The default is the share sheet that Flutter's iOS engine already
/// presents for the text-selection "Share…" item (`Share.invoke` on the
/// platform channel), so sharing needs no plugin. If another feature needs
/// sharing, this moves behind a service in `lib/services/`.
final shareTextProvider = Provider<ShareText>(
  (ref) => systemShareText,
  name: 'shareTextProvider',
);

/// Shares [text] through the platform's share sheet. A platform that does
/// not support it reports the error and shares nothing.
Future<void> systemShareText(String text) async {
  try {
    await SystemChannels.platform.invokeMethod<void>('Share.invoke', text);
  } on PlatformException catch (error, stack) {
    _report(error, stack);
  } on MissingPluginException catch (error, stack) {
    _report(error, stack);
  }
}

void _report(Object error, StackTrace stack) => FlutterError.reportError(
  FlutterErrorDetails(
    exception: error,
    stack: stack,
    library: 'household',
    context: ErrorDescription('while opening the share sheet'),
  ),
);
