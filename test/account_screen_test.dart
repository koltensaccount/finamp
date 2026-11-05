import 'dart:convert';

import 'package:finamp/screens/account_screen.dart';
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

  testWidgets('AccountScreen displays user details and registered devices', (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/v1/account/devices') {
        return http.Response(
          jsonEncode({
            'devices': [
              {'id': 'dev_1', 'device_name': 'MacBook Pro', 'platform': 'macos', 'is_current': true},
              {'id': 'dev_2', 'device_name': 'iPad Pro', 'platform': 'ios', 'is_current': false},
            ]
          }),
          200,
        );
      }
      return http.Response('Not Found', 404);
    });

    FlutterSecureStorage.setMockInitialValues({
      'kb_account_endpoint': 'http://127.0.0.1:8765',
      'kb_account_token': 'kba_master_session',
      'kb_account_id': 'usr_1',
      'kb_account_username': 'kolten',
      'kb_account_display_name': 'Kolten Bendickson',
      'kb_account_expires_at': '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}',
    });

    final service = KBAccountService(client: mockClient);
    await service.init();
    GetIt.instance.registerSingleton<KBAccountService>(service);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kbAccountServiceProvider.overrideWith((ref) => service),
        ],
        child: const MaterialApp(
          home: AccountScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('KB Account'), findsOneWidget);
    expect(find.text('Kolten Bendickson'), findsOneWidget);
    expect(find.text('@kolten'), findsOneWidget);
    expect(find.text('Connected to KB Server'), findsOneWidget);
    expect(find.text('MacBook Pro'), findsOneWidget);
    expect(find.text('This Device'), findsOneWidget);
    expect(find.text('iPad Pro'), findsOneWidget);
  });

  testWidgets('Pair New Device button opens 6-digit code dialog', (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/v1/account/devices') {
        return http.Response(jsonEncode({'devices': []}), 200);
      }
      return http.Response('Not Found', 404);
    });

    FlutterSecureStorage.setMockInitialValues({
      'kb_account_endpoint': 'http://127.0.0.1:8765',
      'kb_account_token': 'kba_master_session',
      'kb_account_id': 'usr_1',
      'kb_account_username': 'kolten',
      'kb_account_expires_at': '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}',
    });

    final service = KBAccountService(client: mockClient);
    await service.init();
    GetIt.instance.registerSingleton<KBAccountService>(service);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kbAccountServiceProvider.overrideWith((ref) => service),
        ],
        child: const MaterialApp(
          home: AccountScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Pair New Device (Enter 6-Digit Code)'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Pair New Device'), findsWidgets);
    expect(find.text('Enter the 6-digit code shown on your other device to connect it instantly to your KB Account.'), findsOneWidget);
  });
}
