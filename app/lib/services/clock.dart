import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:clock/clock.dart' show Clock;

/// "Now" for everything that depends on time (ARCHITECTURE 3.2).
///
/// Code reads `ref.read(clockProvider).now()` instead of the system time,
/// so tests can pin time with `Clock.fixed`. The composition root overrides
/// this with `const Clock()`; until then it throws, so a missing wiring
/// fails loudly.
final clockProvider = Provider<Clock>(
  (ref) => throw UnimplementedError('clockProvider is set in bootstrap()'),
  name: 'clockProvider',
);
