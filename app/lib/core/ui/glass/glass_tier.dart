import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:xpense_app/core/theme/xp_motion.dart';
import 'package:xpense_app/core/ui/glass/accessibility_flags.dart';

/// How glass is rendered (DESIGN_SYSTEM 6.2). Lower tiers are cheaper.
enum GlassTier {
  /// Tier 0: opaque `surface` fill and a `hairline` border, same shape and
  /// shadow. Reduce Transparency, Low Power Mode, or a failed probe.
  solid,

  /// Tier 1: `BackdropFilter` blur, tint, border and highlight (the glass
  /// package's minimal quality). Older devices, glass over a platform view,
  /// or frame time over budget.
  blur,

  /// Tier 2: the glass package's standard (lightweight shader) quality.
  standard,

  /// Tier 3: the glass package's premium Impeller shader.
  premium,
}

/// Picks the starting tier from the device model.
///
/// The table is provisional: WP-S2 measures tiers on the household's
/// iPhone 15 Pro Max and iPhone 17 Pro before it is locked. Until then the
/// A17 Pro and newer iPhones start at premium, other recent iPhones at
/// standard, and older iPhones at blur until one can be measured.
abstract final class GlassTierPolicy {
  /// Model prefixes that start at [GlassTier.premium].
  static const List<String> premiumModels = [
    'iPhone16,1', // iPhone 15 Pro
    'iPhone16,2', // iPhone 15 Pro Max (household phone)
    'iPhone17,', // iPhone 16 family
    'iPhone18,', // iPhone 17 family, including the household iPhone 17 Pro
  ];

  /// Oldest iPhone major model number that starts at [GlassTier.standard]
  /// (`iPhone14,x` is the iPhone 13 and 14 generation).
  static const int standardFromMajor = 14;

  /// Returns the starting tier for [deviceModel].
  static GlassTier initialTierFor(String deviceModel) {
    if (deviceModel.isEmpty) return GlassTier.standard;
    if (premiumModels.any(deviceModel.startsWith)) return GlassTier.premium;
    final iphone = RegExp(r'^iPhone(\d+),').firstMatch(deviceModel);
    if (iphone == null) return GlassTier.standard;
    final major = int.parse(iphone.group(1)!);
    return major >= standardFromMajor ? GlassTier.standard : GlassTier.blur;
  }
}

/// Holds the glass tier for the session.
///
/// The tier starts from [GlassTierPolicy] and can only step down at runtime,
/// never up (DESIGN_SYSTEM 6.2). Reduce Transparency, Low Power Mode or a
/// failed probe force [GlassTier.solid] while they last.
class GlassController extends ChangeNotifier {
  /// Creates a controller starting at [deviceTier].
  new({required this.deviceTier, this._flags = AccessibilityFlags.unknown})
    : _cap = deviceTier;

  /// The tier the device table chose at startup.
  final GlassTier deviceTier;

  GlassTier _cap;
  AccessibilityFlags _flags;
  bool _probeFailed = false;
  StreamSubscription<AccessibilityFlags>? _subscription;

  /// Reads the platform flags, picks the starting tier and keeps listening
  /// for Reduce Transparency and Low Power Mode changes.
  static Future<GlassController> start({
    AccessibilityFlagsChannel channel = const AccessibilityFlagsChannel(),
  }) async {
    final flags = await channel.read();
    final controller = GlassController(
      deviceTier: GlassTierPolicy.initialTierFor(flags.deviceModel),
      flags: flags,
    );
    controller._subscription = channel.changes().listen(controller.updateFlags);
    return controller;
  }

  /// The current platform flags.
  AccessibilityFlags get flags => _flags;

  /// The tier glass renders at right now.
  GlassTier get tier =>
      _flags.reduceTransparency || _flags.lowPowerMode || _probeFailed
      ? GlassTier.solid
      : _cap;

  /// Replaces the platform flags, for example after Reduce Transparency is
  /// switched in Settings.
  void updateFlags(AccessibilityFlags flags) {
    if (flags == _flags) return;
    final before = tier;
    _flags = flags;
    if (tier != before) notifyListeners();
  }

  /// Steps one tier down, stopping at [GlassTier.blur]. Called when frame
  /// time is over budget; there is no way back up within a session.
  void stepDown() {
    if (_cap.index <= GlassTier.blur.index) return;
    final before = tier;
    _cap = GlassTier.values[_cap.index - 1];
    if (tier != before) notifyListeners();
  }

  /// Marks the shader probe as failed, which drops glass to solid.
  void markProbeFailed() {
    if (_probeFailed) return;
    final before = tier;
    _probeFailed = true;
    if (tier != before) notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

/// Watches raster frame times and steps a [GlassController] down when glass
/// keeps the frame over budget.
class GlassFrameBudget {
  /// Creates a watcher; call [attach] to start.
  new(
    this.controller, {
    this.budget = XpMotion.frameBudget,
    this.framesOverBudget = 30,
  });

  /// The controller to step down.
  final GlassController controller;

  /// Raster time per frame above which a frame counts as slow.
  final Duration budget;

  /// Consecutive slow frames before stepping down.
  final int framesOverBudget;

  int _slow = 0;

  /// Starts listening to frame timings.
  void attach() => SchedulerBinding.instance.addTimingsCallback(_onTimings);

  /// Stops listening.
  void detach() => SchedulerBinding.instance.removeTimingsCallback(_onTimings);

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _slow = timing.rasterDuration > budget ? _slow + 1 : 0;
      if (_slow >= framesOverBudget) {
        _slow = 0;
        controller.stepDown();
      }
    }
  }
}

/// Makes a [GlassController] available to every `GlassSurface` below.
class GlassScope extends InheritedNotifier<GlassController> {
  /// Provides [controller] to [child].
  const new({
    required GlassController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The tier used when there is no [GlassScope] above: the spec's default.
  static const GlassTier defaultTier = GlassTier.standard;

  /// Returns the current tier for [context].
  static GlassTier tierOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlassScope>()
          ?.notifier
          ?.tier ??
      defaultTier;
}
