import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'raw_value_gate.dart';

void main() {
  test('app/lib holds no raw design values outside lib/core/theme/', () {
    final violations = checkRawValues(Directory('lib'));
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  group('gate', () {
    List<String> rules(String path, String source) =>
        checkSource(path, source).map((v) => v.rule).toList();

    test('catches each kind of raw value in a feature', () {
      const path = 'features/home/home_screen.dart';
      expect(rules(path, 'final c = Color(0xFF123456);'), ['raw colour']);
      expect(rules(path, 'Color.fromRGBO(1, 2, 3, 1)'), ['raw colour']);
      expect(rules(path, 'Colors.red'), ['Material colour constant']);
      expect(rules(path, 'CupertinoColors.systemRed'), [
        'Cupertino colour constant',
      ]);
      expect(rules(path, 'BorderRadius.circular(12)'), ['raw radius']);
      expect(rules(path, 'Radius.circular(8)'), ['raw radius']);
      expect(rules(path, 'Duration(milliseconds: 200)'), ['raw duration']);
      expect(rules(path, 'curve: Curves.easeIn'), ['raw curve']);
      expect(rules(path, 'TextStyle(fontSize: 14)'), ['raw font size']);
      expect(rules(path, 'EdgeInsets.only(left: 4)'), [
        'non-directional insets',
      ]);
      expect(rules(path, 'Alignment.centerLeft'), [
        'non-directional alignment',
      ]);
      expect(rules(path, 'TextAlign.right'), [
        'non-directional text alignment',
      ]);
      expect(rules(path, 'Positioned(left: 0, child: x)'), [
        'non-directional Positioned',
      ]);
      expect(rules(path, 'ColorScheme.fromSeed(seedColor: c)'), [
        'seeded colour scheme',
      ]);
    });

    test('allows tokens and directional layout', () {
      const path = 'core/ui/x.dart';
      expect(rules(path, 'Radius.circular(XpRadius.slip)'), isEmpty);
      expect(rules(path, 'duration: motion.fast'), isEmpty);
      expect(rules(path, 'EdgeInsetsDirectional.only(start: 4)'), isEmpty);
      expect(rules(path, 'EdgeInsets.symmetric(vertical: 4)'), isEmpty);
      expect(rules(path, 'AlignmentDirectional.centerStart'), isEmpty);
      expect(rules(path, 'Alignment.center'), isEmpty);
      expect(rules(path, 'TextAlign.end'), isEmpty);
      expect(rules(path, '// Colors.red in a comment'), isEmpty);
    });

    test('lets lib/core/theme/ hold raw values but not break layout rules', () {
      expect(rules('core/theme/primitives.dart', 'Color(0xFF0B0B0C)'), isEmpty);
      expect(
        rules('core/theme/xp_motion.dart', 'Duration(milliseconds: 120)'),
        isEmpty,
      );
      expect(rules('core/theme/app_theme.dart', 'EdgeInsets.only(left: 1)'), [
        'non-directional insets',
      ]);
    });
  });
}
