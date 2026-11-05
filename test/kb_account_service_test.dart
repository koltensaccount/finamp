import 'dart:convert';

import 'package:finamp/services/kb_account_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KBAccountService Tests', () {
    test('checkStatus returns server status from mock backend', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/account/status');
        return http.Response(
          jsonEncode({
            'enrolled': true,
            'server_name': 'KB Music Server',
            'version': '1.0.0',
            'device_count': 2,
          }),
          200,
        );
      });

      FlutterSecureStorage.setMockInitialValues({'kb_account_endpoint': 'http://127.0.0.1:8765'});
      final service = KBAccountService(client: mockClient);

      final status = await service.checkStatus();
      expect(status['enrolled'], isTrue);
      expect(status['server_name'], equals('KB Music Server'));
    });

    test('login parses session and device config', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/account/login') {
          return http.Response(
            jsonEncode({
              'account': {'id': 'usr_1', 'username': 'kolten', 'display_name': 'Kolten'},
              'device': {'id': 'dev_1', 'name': 'MacBook Pro'},
              'session': {
                'token': 'kba_test_token_12345',
                'refresh_token': 'kbr_test_refresh_12345',
                'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              },
              'config': {
                'server_host': 'koltensserver.tailfa2fff.ts.net',
                'catalog': {'endpoint': 'http://koltensserver:8765', 'token': 'kba_test_token_12345'},
              },
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      FlutterSecureStorage.setMockInitialValues({'kb_account_endpoint': 'http://127.0.0.1:8765'});
      final service = KBAccountService(client: mockClient);

      final res = await service.login(username: 'kolten', password: 'password123', deviceName: 'MacBook Pro');
      expect(res['account']['username'], equals('kolten'));
      expect(service.isSignedIn, isTrue);
      expect(service.currentSession?.token, equals('kba_test_token_12345'));
      expect(service.currentSession?.displayName, equals('Kolten'));
    });

    test('createPairingRequest and pollPairing work with approved response', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/account/pair/request') {
          return http.Response(
            jsonEncode({
              'pairing_id': 'pr_123',
              'code': '849201',
              'poll_token': 'poll_xyz',
              'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300,
            }),
            200,
          );
        } else if (request.url.path == '/v1/account/pair/poll') {
          expect(request.url.queryParameters['code'], '849201');
          return http.Response(
            jsonEncode({
              'state': 'approved',
              'account': {'id': 'usr_1', 'username': 'kolten', 'display_name': 'Kolten'},
              'device': {'id': 'dev_ipad', 'name': 'iPad Pro'},
              'session': {
                'token': 'kba_ipad_token_67890',
                'refresh_token': 'kbr_ipad_refresh_67890',
                'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              },
              'config': {
                'server_host': 'koltensserver.tailfa2fff.ts.net',
                'catalog': {'endpoint': 'http://koltensserver:8765', 'token': 'kba_ipad_token_67890'},
              },
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      FlutterSecureStorage.setMockInitialValues({'kb_account_endpoint': 'http://127.0.0.1:8765'});
      final service = KBAccountService(client: mockClient);

      final req = await service.createPairingRequest(deviceName: 'iPad Pro');
      expect(req['code'], equals('849201'));

      final poll = await service.pollPairing(code: '849201');
      expect(poll['state'], equals('approved'));
      expect(service.isSignedIn, isTrue);
      expect(service.currentSession?.token, equals('kba_ipad_token_67890'));
      expect(service.currentSession?.deviceName, equals('iPad Pro'));
    });

    test('approvePairing sends token and 6-digit code', () async {
      String? sentAuth;
      String? sentCode;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/account/pair/approve') {
          sentAuth = request.headers['Authorization'];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentCode = body['code'];
          return http.Response(
            jsonEncode({
              'status': 'approved',
              'device_id': 'dev_tablet',
              'device_name': 'iPad Pro',
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
        'kb_account_expires_at': '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}',
      });

      final service = KBAccountService(client: mockClient);
      await service.init();
      expect(service.isSignedIn, isTrue);

      final res = await service.approvePairing('123456');
      expect(res['status'], equals('approved'));
      expect(sentAuth, equals('Bearer kba_master_session'));
      expect(sentCode, equals('123456'));
    });

    test('listDevices parses devices and handles revocation', () async {
      var revoked = false;
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
        } else if (request.url.path == '/v1/account/devices/dev_2/revoke') {
          revoked = true;
          return http.Response(jsonEncode({'status': 'revoked'}), 200);
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

      final devices = await service.listDevices();
      expect(devices.length, equals(2));
      expect(devices[0]['device_name'], equals('MacBook Pro'));
      expect(devices[1]['device_name'], equals('iPad Pro'));

      final ok = await service.revokeDevice('dev_2');
      expect(ok, isTrue);
      expect(revoked, isTrue);
    });
  });
}
