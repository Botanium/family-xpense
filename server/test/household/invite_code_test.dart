import 'dart:math';

import 'package:test/test.dart';
import 'package:xpense_agent/household/invite_code.dart';

void main() {
  group('generateInviteCode', () {
    test('10 characters from the Crockford alphabet', () {
      final random = Random(7);
      for (var i = 0; i < 500; i++) {
        final code = generateInviteCode(random);
        expect(code, hasLength(inviteCodeLength));
        expect(code, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{10}$')));
      }
    });

    test('the alphabet is 32 characters without I, L, O and U', () {
      expect(inviteAlphabet, hasLength(32));
      expect(inviteAlphabet.split('').toSet(), hasLength(32));
      for (final c in ['I', 'L', 'O', 'U']) {
        expect(inviteAlphabet, isNot(contains(c)));
      }
    });

    test('codes from a secure source do not repeat in practice', () {
      final random = Random.secure();
      final codes = {for (var i = 0; i < 2000; i++) generateInviteCode(random)};
      expect(codes, hasLength(2000));
    });
  });

  group('normalizeInviteCode', () {
    const code = 'AB3DE7GH9K';

    final cases = <String, String?>{
      code: code,
      'ab3de7gh9k': code,
      'AB3DE-7GH9K': code,
      ' AB3 DE7 GH9K ': code,
      'AB3DE--7GH9K': code,
      // Look-alikes read the way Crockford decodes them.
      'O0OOOIIILL': '0000011111',
      // U is not in the alphabet; neither is punctuation.
      'AB3DE7GH9U': null,
      'AB3DE7GH9!': null,
      'AB3DE_7GH9K': null,
      // Too short or too long.
      'AB3DE7GH9': null,
      'AB3DE7GH9KK': null,
      '': null,
      // Other scripts are refused, not folded.
      'AB3DE7GH9٣': null,
    };
    for (final MapEntry(key: raw, value: expected) in cases.entries) {
      test('"$raw" -> $expected', () {
        expect(normalizeInviteCode(raw), expected);
      });
    }
  });

  test('the hash is the lower-case hex SHA-256 of the canonical code', () {
    // echo -n 0000000000 | shasum -a 256
    expect(
      inviteCodeHash('0000000000'),
      '84d9c4b849506b6d8f8075a9000e7e0a254be71060ea889fad3c88395988f4fc',
    );
    expect(inviteCodeHash('AB3DE7GH9K'), matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(inviteCodeHash('AB3DE7GH9K'), isNot(contains('AB3DE7GH9K')));
    expect(inviteCodeHash('AB3DE7GH9K'), inviteCodeHash('AB3DE7GH9K'));
    expect(inviteCodeHash('AB3DE7GH9K'), isNot(inviteCodeHash('AB3DE7GH9M')));
  });

  test('the link opens the join screen with the code', () {
    expect(inviteLink('AB3DE7GH9K'), 'xpense://join?code=AB3DE7GH9K');
  });
}
