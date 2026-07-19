import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/main.dart';

void main() {
  testWidgets('Paisa app launches onboarding', (WidgetTester tester) async {
    await tester.pumpWidget(const PaisaApp(showMain: false));
    await tester.pumpAndSettle();

    expect(find.text('Paisa'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });
}
