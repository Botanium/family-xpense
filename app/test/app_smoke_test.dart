import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/main.dart';

void main() {
  testWidgets('placeholder app builds', (tester) async {
    await tester.pumpWidget(const XpenseApp());
    expect(find.byType(XpenseApp), findsOneWidget);
  });
}
