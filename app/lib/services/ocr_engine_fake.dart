import 'package:xpense_app/services/ocr_engine.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// An [OcrEngine] that answers with [result], for tests and the simulator.
/// By default it reports recognition as unavailable.
final class FakeOcrEngine implements OcrEngine {
  /// Creates a fake engine.
  new({this.result = const Err(ServiceUnavailable())});

  /// The answer to every image.
  Result<List<OcrLine>, ServiceFailure> result;

  /// The image paths received, in order.
  final List<String> images = [];

  @override
  Future<Result<List<OcrLine>, ServiceFailure>> recognize(
    String imagePath,
  ) async {
    images.add(imagePath);
    return result;
  }
}
