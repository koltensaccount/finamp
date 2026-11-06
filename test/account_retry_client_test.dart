import 'dart:async';
import 'package:finamp/services/account_retry_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('API waits for account initialization without starting a request early', () async {
    final ready = Completer<void>();
    var sent = false;
    final client = AccountRetryClient(ready: ready.future, renewToken: (_) async => null,
      inner: MockClient((_) async { sent = true; return http.Response('{}', 200); }));
    final pending = client.get(Uri.parse('https://example.test/v1/books'));
    await Future<void>.delayed(Duration.zero);
    expect(sent, isFalse);
    ready.complete();
    expect((await pending).statusCode, 200);
    expect(sent, isTrue);
  });
  test('401 GET renews once and retries same destination with replacement token', () async {
    var requests = 0;
    final client = AccountRetryClient(
      renewToken: (token) async { expect(token, 'kba_old'); return 'kba_new'; },
      inner: MockClient((request) async {
        expect(request.url.toString(), 'https://example.test/v1/books');
        requests++;
        expect(request.headers['Authorization'], requests == 1 ? 'Bearer kba_old' : 'Bearer kba_new');
        return http.Response('{}', requests == 1 ? 401 : 200);
      }),
    );
    expect((await client.get(Uri.parse('https://example.test/v1/books'), headers: {'Authorization': 'Bearer kba_old'})).statusCode, 200);
    expect(requests, 2);
  });
  test('failed renewal preserves error; repeated 401 retries only once', () async {
    for (final replacement in <String?>[null, 'kba_new']) {
      var requests = 0;
      final client = AccountRetryClient(renewToken: (_) async => replacement,
        inner: MockClient((_) async { requests++; return http.Response('Sign in required', 401); }));
      final response = await client.get(Uri.parse('https://example.test/v1/books'), headers: {'Authorization': 'Bearer kba_old'});
      expect(response.statusCode, 401);
      expect(response.body, 'Sign in required');
      expect(requests, replacement == null ? 1 : 2);
    }
  });
  test('never replays write requests or renews manual API keys', () async {
    final client = AccountRetryClient(renewToken: (_) async => fail('Must not renew'), inner: MockClient((_) async => http.Response('{}', 401)));
    expect((await client.post(Uri.parse('https://example.test/v1/requests'), headers: {'Authorization': 'Bearer kba_old'})).statusCode, 401);
    expect((await client.get(Uri.parse('https://example.test/v1/books'), headers: {'Authorization': 'Bearer manual-key'})).statusCode, 401);
  });
}
