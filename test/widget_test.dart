import 'package:flutter_test/flutter_test.dart';
import 'package:broker_module/main.dart';

void main() {
  testWidgets('Rubika Discount App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const RubikaDiscountApp());

    // Verify that the title widget is displayed.
    expect(find.text('ماژول تخفیف و صورتحساب‌های روبیکا'), findsOneWidget);
  });
}
