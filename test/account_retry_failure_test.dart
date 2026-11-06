import 'package:finamp/services/account_retry_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('failed refresh preserves original unauthorized response', () async {
    var sends = 0;
    final client = AccountRetryClient(
      renewToken: (_) async => throw StateError('offline'),
      inner: MockClient((_) async {
        sends++;
        return http.Response('Sign in required', 401);
      }),
    );

    final response = await client.get(
      Uri.parse('https://example.test/v1/books'),
      headers: {'Authorization': 'Bearer kba_expired'},
    );
    expect(response.statusCode, 401);
    expect(response.body, 'Sign in required');
    expect(sends, 1);
  });

  test('unchanged token does not cause a duplicate API request', () async {
    var sends = 0;
    final client = AccountRetryClient(
      renewToken: (token) async => token,
      inner: MockClient((_) async {
        sends++;
        return http.Response('Sign in required', 401);
      }),
    );

    final response = await client.get(
      Uri.parse('https://example.test/v1/books'),
      headers: {'Authorization': 'Bearer kba_expired'},
    );
    expect(response.statusCode, 401);
    expect(sends, 1);
  });
}
