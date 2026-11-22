import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/core/routing/routing.dart';

void main() {
  DeepLink? parse(String link) => DeepLink.parse(Uri.parse(link));

  group('DeepLink.parse', () {
    test('reads the four links of ARCHITECTURE 3.3', () {
      expect(
        parse('xpense://ask?text=lunch%2010000'),
        const AskLink(text: 'lunch 10000'),
      );
      expect(
        parse('xpense://join?code=ABCDE23456'),
        const JoinLink('ABCDE23456'),
      );
      expect(parse('xpense://txn/AbC_12-x'), const EntryLink('AbC_12-x'));
      expect(parse('xpense://loan/L1'), const LoanLink('L1'));
    });

    test('accepts the target as a path and in any case', () {
      expect(parse('xpense:///ask'), const AskLink());
      expect(parse('xpense:ask?text=hi'), const AskLink(text: 'hi'));
      expect(parse('XPENSE://ASK'), const AskLink());
      expect(parse('xpense:///txn/t1'), const EntryLink('t1'));
      expect(parse('xpense://loan/L1/'), const LoanLink('L1'));
    });

    test('Ask text is trimmed, empty is none, long is cut', () {
      expect(parse('xpense://ask?text=%20%20'), const AskLink());
      expect(parse('xpense://ask?text=%20hi%20'), const AskLink(text: 'hi'));
      final long = 'a' * (DeepLink.maxAskText + 20);
      final link = parse('xpense://ask?text=$long')! as AskLink;
      expect(link.text, hasLength(DeepLink.maxAskText));
    });

    test('invite codes drop spaces and dashes and are upper-cased', () {
      expect(
        parse('xpense://join?code=abcde-23456'),
        const JoinLink('ABCDE23456'),
      );
      expect(
        parse('xpense://join?code=abcde%2023456'),
        const JoinLink('ABCDE23456'),
      );
    });

    test('returns null for anything else, never throws', () {
      for (final link in [
        'https://example.com/ask',
        'mailto:someone',
        'xpense://',
        'xpense://unknown',
        'xpense://ask/extra',
        'xpense://join',
        'xpense://join?code=',
        'xpense://join?code=%24%24%24',
        'xpense://txn',
        'xpense://txn/a/b',
        'xpense://txn/bad%20id',
        'xpense://loan/${'x' * 200}',
        '/home',
      ]) {
        expect(parse(link), isNull, reason: link);
      }
    });

    test('each link opens its in-app location', () {
      expect(const AskLink().location, AppRoutes.ask);
      expect(const AskLink(text: 'a b').location, '/ask?text=a+b');
      expect(const JoinLink('ABCDE23456').location, '/join?code=ABCDE23456');
      expect(const EntryLink('t1').location, '/entries/t1');
      expect(const LoanLink('L1').location, '/loans/L1');
    });
  });

  group('appRedirect', () {
    String? redirect(String location) => appRedirect(Uri.parse(location));

    test('rewrites deep links to their location', () {
      expect(redirect('xpense://ask?text=hi'), '/ask?text=hi');
      expect(redirect('xpense://txn/t1'), '/entries/t1');
    });

    test('sends a link that opens nothing to Not found', () {
      expect(redirect('xpense://nowhere'), AppRoutes.notFound);
    });

    test('sends the root to Home and lets everything else pass', () {
      expect(redirect('/'), AppRoutes.home);
      expect(redirect(''), AppRoutes.home);
      for (final location in [
        AppRoutes.home,
        AppRoutes.activity,
        AppRoutes.ask,
        '/ask?text=hi',
        '/entries/t1',
        AppRoutes.notFound,
        '/no-such-screen',
      ]) {
        expect(redirect(location), isNull, reason: location);
      }
    });

    test('never redirects to a location it would rewrite again', () {
      for (final link in [
        'xpense://ask?text=hi',
        'xpense://join?code=ABCDE23456',
        'xpense://txn/t1',
        'xpense://loan/L1',
        'xpense://nowhere',
        '/',
      ]) {
        final first = redirect(link)!;
        expect(redirect(first), isNull, reason: link);
      }
    });
  });
}
