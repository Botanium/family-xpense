/// What a member's message spends of the daily media allowances
/// (`config/runtime` limits `images` and `audioSeconds`, ARCHITECTURE 4.5).
///
/// Gemini's usage reports no per-modality figures, so the server counts the
/// media itself: one image per image part, and the seconds of each audio
/// clip read from its MP4 (`.m4a`, AAC) header. A clip whose length cannot
/// be read (another container, a URL instead of inline data) is charged the
/// longest clip the phone records, 60 seconds (ARCHITECTURE, voice capture).
library;

import 'dart:convert';
import 'dart:typed_data';

/// The longest clip the phone records, charged when a length is unknown.
const maxClipSeconds = 60;

/// Images and audio seconds in [message] (a message's JSON form).
({int images, int audioSeconds}) mediaUse(Map<String, dynamic> message) {
  var images = 0;
  var audioSeconds = 0;
  final content = message['content'];
  for (final part in content is List ? content : const <Object?>[]) {
    if (part is! Map || part['media'] is! Map) continue;
    final media = part['media'] as Map;
    final url = '${media['url'] ?? ''}';
    final type = '${media['contentType'] ?? _dataUriType(url) ?? ''}';
    if (type.startsWith('image/')) {
      images += 1;
    } else if (type.startsWith('audio/')) {
      audioSeconds += _clipSeconds(url) ?? maxClipSeconds;
    }
  }
  return (images: images, audioSeconds: audioSeconds);
}

String? _dataUriType(String url) {
  final m = RegExp('^data:([^;,]+)').firstMatch(url);
  return m?.group(1);
}

/// The whole seconds (rounded up, at least 1) of an inline MP4 clip, or
/// null when [url] is not one.
int? _clipSeconds(String url) {
  final comma = url.indexOf(',');
  if (!url.startsWith('data:') || comma < 0) return null;
  if (!url.substring(0, comma).endsWith(';base64')) return null;
  final Uint8List bytes;
  try {
    bytes = base64Decode(url.substring(comma + 1));
  } on FormatException {
    return null;
  }
  final duration = mp4Duration(bytes);
  if (duration == null) return null;
  final seconds = (duration.inMilliseconds + 999) ~/ 1000;
  return seconds < 1 ? 1 : seconds;
}

/// The duration in an MP4 movie header (`mvhd`), or null.
Duration? mp4Duration(Uint8List bytes) {
  final at = _find(bytes, const [0x6d, 0x76, 0x68, 0x64]); // "mvhd"
  if (at < 0) return null;
  final data = ByteData.sublistView(bytes);
  var i = at + 4;
  if (i + 4 > bytes.length) return null;
  final version = bytes[i];
  i += 4; // version and flags
  final int timescale;
  final int duration;
  if (version == 1) {
    if (i + 28 > bytes.length) return null;
    timescale = data.getUint32(i + 16);
    duration = data.getUint64(i + 20);
  } else {
    if (i + 16 > bytes.length) return null;
    timescale = data.getUint32(i + 8);
    duration = data.getUint32(i + 12);
  }
  // An absurd length (over a day) is not a voice note: charged as unknown.
  if (timescale == 0 || duration < 0 || duration ~/ timescale > 86400) {
    return null;
  }
  return Duration(microseconds: duration * 1000000 ~/ timescale);
}

int _find(Uint8List bytes, List<int> tag) {
  for (var i = 0; i + tag.length <= bytes.length; i++) {
    var hit = true;
    for (var j = 0; j < tag.length; j++) {
      if (bytes[i + j] != tag[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return i;
  }
  return -1;
}
