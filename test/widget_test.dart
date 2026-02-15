import 'package:flutter_test/flutter_test.dart';
import 'package:fineglaze_app/main.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FineGlazeApp());

    // Verify that the app title is present.
    expect(find.text('FineGlaze'), findsOneWidget);

    // Verify that the login button is present.
    expect(find.text('Login'), findsOneWidget);
    
    // Verify input fields are present.
    expect(find.text('Email or Phone'), findsOneWidget);
    expect(find.text('Password/OTP'), findsOneWidget);
  });
}
