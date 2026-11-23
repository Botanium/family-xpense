/// Invite codes (DATA_MODEL 2.15, D-27): 10 base32 characters, shown to
/// people and typed by them, stored only as a SHA-256.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Crockford's base32 alphabet: digits and capitals without I, L, O and U,
/// so a code read aloud or copied by hand cannot be mistaken.
const inviteAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Characters in a code: 50 bits, about 10^15 codes.
const inviteCodeLength = 10;

/// A new random code from [random], which must be cryptographically secure
/// outside tests (`Random.secure()`).
String generateInviteCode(Random random) => String.fromCharCodes([
  for (var i = 0; i < inviteCodeLength; i++)
    inviteAlphabet.codeUnitAt(random.nextInt(inviteAlphabet.length)),
]);

/// The canonical form of a code someone typed or a link carried, or null
/// when it cannot be a code.
///
/// Spaces and dashes are dropped and letters upper-cased. Crockford's
/// decoding rules map the look-alikes: `O` reads as `0`, `I` and `L` as `1`.
/// `U` is not in the alphabet, so a code with it is refused.
String? normalizeInviteCode(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.toUpperCase().runes) {
    final char = String.fromCharCode(rune);
    if (char == ' ' || char == '-') continue;
    final mapped = switch (char) {
      'O' => '0',
      'I' || 'L' => '1',
      _ => char,
    };
    if (!inviteAlphabet.contains(mapped) || mapped.length != 1) return null;
    buffer.write(mapped);
    if (buffer.length > inviteCodeLength) return null;
  }
  final code = buffer.toString();
  return code.length == inviteCodeLength ? code : null;
}

/// The id of the `invites` document for a canonical [code]: its SHA-256 in
/// lower-case hex. The code itself is never stored.
String inviteCodeHash(String code) =>
    sha256.convert(utf8.encode(code)).toString();

/// The link that opens the join screen with [code] filled in
/// (`xpense://join?code=…`, ARCHITECTURE 3.3).
String inviteLink(String code) => Uri(
  scheme: 'xpense',
  host: 'join',
  queryParameters: {'code': code},
).toString();
