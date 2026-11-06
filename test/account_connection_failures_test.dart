import 'dart:convert';

import 'package:finamp/services/kb_account_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('expired session is not restored when refresh is rejected', () async {
    final expiredAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
    FlutterSecureStorage.setMockInitialValues({
      'kb_account_endpoint': 'https://example.test',
      'kb_account_token': 'kba_expired',
      'kb_account_refresh_token': 'kbr_expired',
      'kb_account_id': 'fixture',
      'kb_account_username': 'fixture',
      'kb_account_expires_at': expiredAt.toString(),
    });
    var refreshCalls = 0;
    final service = KBAccountService(client: MockClient((request) async {
      expect(request.url.path, '/v1/account/refresh');
      refreshCalls++;
      return http.Response(jsonEncode({'error': 'revoked'}), 401);
    }));

    expect(await service.init(), isFalse);
    expect(service.isSignedIn, isFalse);
    expect(service.currentSession?.token, 'kba_expired');
    expect(refreshCalls, 1);
  });

  test('device API errors are not treated as an empty device list', () async {
    final expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    FlutterSecureStorage.setMockInitialValues({
      'kb_account_endpoint': 'https://example.test',
      'kb_account_token': 'kba_active',
      'kb_account_id': 'fixture',
      'kb_account_username': 'fixture',
      'kb_account_expires_at': expiresAt.toString(),
    });
    var code = 401;
    final service = KBAccountService(client: MockClient((request) async {
      expect(request.url.path, '/v1/account/devices');
      if (code == 200) return http.Response('{}', code);
      return http.Response(jsonEncode({'error': 'unavailable'}), code);
    }));
    expect(await service.init(), isTrue);

    await expectLater(service.listDevices(), throwsA(isA<StateError>()));
    code = 503;
    await expectLater(service.listDevices(), throwsA(isA<StateError>()));
    code = 200;
    await expectLater(service.listDevices(), throwsA(isA<FormatException>()));
  });
}
