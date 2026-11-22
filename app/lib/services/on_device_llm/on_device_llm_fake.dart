import 'package:xpense_app/services/on_device_llm/on_device_llm.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// An [OnDeviceLlm] with a scripted [probeResult] and [extraction], for
/// tests and for phones before the real engines are wired. By default it
/// reports no engine, which routes extraction to the cloud path.
final class FakeOnDeviceLlm implements OnDeviceLlm {
  /// Creates a fake model.
  new({
    this.probeResult = OnDeviceProbe.unavailable,
    this.extraction = const Err(ServiceUnavailable()),
  });

  /// What [probe] answers.
  OnDeviceProbe probeResult;

  /// What [extractEntry] answers.
  Result<EntryDraft, ServiceFailure> extraction;

  /// How many times [probe] ran.
  int probes = 0;

  @override
  Future<OnDeviceProbe> probe() async {
    probes++;
    return probeResult;
  }

  @override
  Future<Result<EntryDraft, ServiceFailure>> extractEntry(String text) async =>
      extraction;
}
