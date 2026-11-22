import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Text recognition for receipts (ARCHITECTURE 3.2, 5.5). Wraps
/// `google_mlkit_text_recognition` (Latin script), which only
/// `lib/services/` may import. An interface so an Arabic-script engine
/// (Apple Vision) can be added with the deferred languages (D-08).
abstract interface class OcrEngine {
  /// Reads the text lines of the image at [imagePath], with their boxes
  /// when the engine gives them, ready for `parseReceipt`. Never throws.
  Future<Result<List<OcrLine>, ServiceFailure>> recognize(String imagePath);
}

/// The [OcrEngine] for this run. Throws until the composition root sets it.
final ocrEngineProvider = Provider<OcrEngine>(
  (ref) => throw UnimplementedError('ocrEngineProvider is set in bootstrap()'),
  name: 'ocrEngineProvider',
);
