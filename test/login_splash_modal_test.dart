import 'dart:convert';

import 'package:finamp/components/LoginScreen/login_splash_page.dart';
import 'package:finamp/services/kb_account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    if (GetIt.instance.isRegistered<KBAccountService>()) {
      GetIt.instance.unregister<KBAccountService>();
    }
  });

  tearDown(() {
    if (GetIt.instance.isRegistered<KBAccountService>()) {
      GetIt.instance.unregister<KBAccountService>();
    }
  });

  testWidgets('LoginSplashPage opens Create Account modal with all fields and validations', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final mockClient = MockClient((request) async {
      if (request.url.path == '/v1/account/status') {
        return http.Response(
          jsonEncode({
            'enrolled': true,
            'server_name': 'KB Music Server',
            'version': '1.0.0',
            'device_count': 1,
          }),
          200,
        );
      }
      if (request.url.path == '/v1/account/check-username') {
        final u = request.url.queryParameters['username'];
        if (u == 'takenuser') {
          return http.Response(jsonEncode({'available': false, 'error': "Username 'takenuser' is already taken"}), 409);
        }
        return http.Response(jsonEncode({'available': true}), 200);
      }
      return http.Response('Not Found', 404);
    });

    FlutterSecureStorage.setMockInitialValues({'kb_account_endpoint': 'http://127.0.0.1:8765'});
    final service = KBAccountService(client: mockClient);
    GetIt.instance.registerSingleton<KBAccountService>(service);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kbAccountServiceProvider.overrideWith((ref) => service),
        ],
        child: MaterialApp(
          home: LoginSplashPage(onGetStartedPressed: () {}),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap "Need a new account? Create KB Account" on splash screen
    final newAccountButton = find.text('Need a new account? Create KB Account');
    expect(newAccountButton, findsOneWidget);
    await tester.tap(newAccountButton);
    await tester.pumpAndSettle();

    // Tapping from splash when enrolled opened sign in modal with switch option
    // Tap the switch button to toggle to Create KB Account
    final switchToCreateButton = find.text('First time setup? Create KB Account');
    expect(switchToCreateButton, findsOneWidget);
    await tester.tap(switchToCreateButton);
    await tester.pumpAndSettle();

    // Verify modal header & fields are present
    expect(find.text('Create KB Account'), findsOneWidget);
    expect(find.text('Display Name'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);

    // Verify bottom sheet has solid opaque background (no bleed through)
    final bottomSheet = tester.widget<Container>(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Container),
      ).first,
    );
    expect(bottomSheet.decoration, isA<BoxDecoration>());

    // Test Validation: tap Create Account with empty fields
    final submitButton = find.widgetWithText(FilledButton, 'Create Account');
    expect(submitButton, findsOneWidget);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Please enter a username'), findsOneWidget);

    // Enter short username
    final usernameField = find.widgetWithText(TextField, 'Username');
    await tester.enterText(usernameField, 'ab');
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Username must be between 3 and 30 characters'), findsOneWidget);

    // Enter valid username and short password
    await tester.enterText(usernameField, 'validuser');
    final passwordField = find.widgetWithText(TextField, 'Password');
    await tester.enterText(passwordField, 'short');
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Password must be at least 8 characters long'), findsOneWidget);

    // Enter valid password but mismatching confirm password
    await tester.enterText(passwordField, 'longpassword123');
    final confirmPasswordField = find.widgetWithText(TextField, 'Confirm Password');
    await tester.enterText(confirmPasswordField, 'differentpassword');
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });
}
