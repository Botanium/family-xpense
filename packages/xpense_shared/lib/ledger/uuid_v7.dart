/// Client-generated document ids (DATA_MODEL 2): UUID v7, so an entry
/// created offline keeps its id when the queued write is retried, and ids
/// sort by creation time.
library;

import 'dart:math';

/// A UUID v7 (RFC 9562) for [now]: 48 bits of Unix milliseconds, then 74
/// random bits from [random], with the version and variant bits set.
String uuidV7(DateTime now, Random random) {
  final ms = now.millisecondsSinceEpoch;
  final bytes = [
    for (var i = 5; i >= 0; i--) (ms >> (8 * i)) & 0xff,
    for (var i = 0; i < 10; i++) random.nextInt(256),
  ];
  bytes[6] = (bytes[6] & 0x0f) | 0x70; // version 7
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
