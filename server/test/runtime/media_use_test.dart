// The media a member's message spends (PR #30 review: media allowances).
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:xpense_agent/runtime/media_use.dart';

/// A minimal MP4 header: `ftyp`, then `moov` holding an `mvhd` box.
Uint8List _m4a({required int timescale, required int duration, int v = 0}) {
  final body = ByteData(v == 1 ? 32 : 20)..setUint8(0, v);
  if (v == 1) {
    body
      ..setUint32(20, timescale)
      ..setUint64(24, duration);
  } else {
    body
      ..setUint32(12, timescale)
      ..setUint32(16, duration);
  }
  return Uint8List.fromList([
    ...ascii.encode('\x00\x00\x00\x10ftypM4A \x00\x00\x00\x00'),
    ...ascii.encode('\x00\x00\x00\x00moov\x00\x00\x00\x00mvhd'),
    ...body.buffer.asUint8List(),
  ]);
}

Map<String, dynamic> _message(List<Map<String, dynamic>> media) => {
  'role': 'user',
  'content': [
    for (final m in media) {'media': m},
    {'text': 'hi'},
  ],
};

String _data(String type, Uint8List bytes) =>
    'data:$type;base64,${base64Encode(bytes)}';

void main() {
  test('counts image parts and reads the clip length', () {
    final use = mediaUse(
      _message([
        {'url': 'data:image/jpeg;base64,AAAA', 'contentType': 'image/jpeg'},
        {'url': 'data:image/png;base64,AAAA'},
        {
          'url': _data('audio/mp4', _m4a(timescale: 44100, duration: 198450)),
          'contentType': 'audio/mp4',
        },
      ]),
    );
    // 198450 / 44100 = 4.5 s, charged as 5.
    expect(use, (images: 2, audioSeconds: 5));
  });

  test('reads 64-bit movie headers', () {
    expect(
      mp4Duration(_m4a(timescale: 1000, duration: 12000, v: 1)),
      const Duration(seconds: 12),
    );
  });

  test('an unreadable clip is charged the longest recording', () {
    expect(
      mediaUse(
        _message([
          {'url': 'data:audio/wav;base64,AAAA', 'contentType': 'audio/wav'},
          {'url': 'gs://bucket/clip.m4a', 'contentType': 'audio/mp4'},
        ]),
      ),
      (images: 0, audioSeconds: 2 * maxClipSeconds),
    );
  });

  test('a text message spends nothing', () {
    expect(mediaUse(_message(const [])), (images: 0, audioSeconds: 0));
  });
}
