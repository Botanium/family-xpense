import Flutter
import UIKit

/// Reports platform flags Flutter does not expose (DESIGN_SYSTEM 6.2):
/// Reduce Transparency, Low Power Mode and the device model. The Dart side
/// is `lib/core/ui/glass/accessibility_flags.dart`; channel names must match.
final class AccessibilityFlagsPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static let methodChannelName = "xpense/accessibility"
  static let eventChannelName = "xpense/accessibility/changes"

  private var sink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AccessibilityFlagsPlugin()
    let methods = FlutterMethodChannel(
      name: methodChannelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(
      name: eventChannelName, binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "snapshot":
      result(Self.snapshot())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    let center = NotificationCenter.default
    let names: [Notification.Name] = [
      UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      Notification.Name.NSProcessInfoPowerStateDidChange,
    ]
    observers = names.map { name in
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.sink?(Self.snapshot())
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    sink = nil
    return nil
  }

  static func snapshot() -> [String: Any] {
    [
      "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
      "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
      "deviceModel": deviceModel(),
    ]
  }

  /// Hardware identifier such as "iPhone16,2"; the simulated model on the
  /// simulator.
  static func deviceModel() -> String {
    if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
      return simulated
    }
    var info = utsname()
    uname(&info)
    return withUnsafePointer(to: &info.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
  }
}
