import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform flags Flutter does not expose: Reduce Transparency, Low Power
/// Mode and the device model, read from iOS through a small channel
/// (`ios/Runner/AccessibilityFlagsPlugin.swift`, DESIGN_SYSTEM 6.2).
@immutable
class AccessibilityFlags {
  /// Creates a flag snapshot.
  const new({
    this.reduceTransparency = false,
    this.lowPowerMode = false,
    this.deviceModel = '',
  });

  /// Reads a snapshot from the channel's map, tolerating missing keys.
  factory fromMap(Map<Object?, Object?> map) => AccessibilityFlags(
    reduceTransparency: map['reduceTransparency'] == true,
    lowPowerMode: map['lowPowerMode'] == true,
    deviceModel: map['deviceModel'] is String
        ? map['deviceModel']! as String
        : '',
  );

  /// The flags assumed before the platform answers, or where there is no
  /// channel (tests, Android until it gets an implementation).
  static const AccessibilityFlags unknown = AccessibilityFlags();

  /// iOS Settings → Accessibility → Display → Reduce Transparency.
  final bool reduceTransparency;

  /// iOS Low Power Mode.
  final bool lowPowerMode;

  /// Hardware model identifier such as `iPhone16,2`; on the simulator, the
  /// simulated model. Empty when unknown.
  final String deviceModel;

  @override
  bool operator ==(Object other) =>
      other is AccessibilityFlags &&
      other.reduceTransparency == reduceTransparency &&
      other.lowPowerMode == lowPowerMode &&
      other.deviceModel == deviceModel;

  @override
  int get hashCode =>
      Object.hash(reduceTransparency, lowPowerMode, deviceModel);

  @override
  String toString() =>
      'AccessibilityFlags(reduceTransparency: $reduceTransparency, '
      'lowPowerMode: $lowPowerMode, deviceModel: $deviceModel)';
}

/// Reads [AccessibilityFlags] from the platform and reports changes.
class AccessibilityFlagsChannel {
  /// Creates the channel pair; the names match the Swift plugin.
  const new({
    this.methods = const MethodChannel(methodChannelName),
    this.events = const EventChannel(eventChannelName),
  });

  /// Method channel name, shared with `AccessibilityFlagsPlugin.swift`.
  static const String methodChannelName = 'xpense/accessibility';

  /// Event channel name, shared with `AccessibilityFlagsPlugin.swift`.
  static const String eventChannelName = 'xpense/accessibility/changes';

  /// Channel for the one-off snapshot.
  final MethodChannel methods;

  /// Channel that pushes a fresh snapshot whenever a flag changes.
  final EventChannel events;

  /// Returns the current flags, or [AccessibilityFlags.unknown] when the
  /// platform has no implementation.
  Future<AccessibilityFlags> read() async {
    try {
      final map = await methods.invokeMapMethod<Object?, Object?>('snapshot');
      return map == null
          ? AccessibilityFlags.unknown
          : AccessibilityFlags.fromMap(map);
    } on MissingPluginException {
      return AccessibilityFlags.unknown;
    } on PlatformException {
      return AccessibilityFlags.unknown;
    }
  }

  /// Emits a snapshot each time Reduce Transparency or Low Power Mode
  /// changes. Errors and a missing implementation end the stream quietly.
  Stream<AccessibilityFlags> changes() => events
      .receiveBroadcastStream()
      .where((event) => event is Map<Object?, Object?>)
      .map(
        (event) => AccessibilityFlags.fromMap(event as Map<Object?, Object?>),
      )
      .handleError((Object _) {}, test: (e) => e is PlatformException)
      .handleError((Object _) {}, test: (e) => e is MissingPluginException);
}
