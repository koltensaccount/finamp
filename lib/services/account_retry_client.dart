import 'package:http/http.dart' as http;

/// Retry only read requests after a rejected account token. No write/acquisition
/// request is replayed, and no credentials are sent to a different destination.
class AccountRetryClient extends http.BaseClient {
  AccountRetryClient({required this.renewToken, this.ready, http.Client? inner})
      : _inner = inner ?? http.Client();

  final Future<String?> Function(String rejectedToken) renewToken;
  final http.Client _inner;
  final Future<void>? ready;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await ready;
    final response = await _inner.send(request);
    final authorization = request.headers['Authorization'];
    if (response.statusCode != 401 ||
        !const ['GET', 'HEAD'].contains(request.method) ||
        authorization == null || !authorization.startsWith('Bearer kba_')) {
      return response;
    }
    // Buffer the error so callers still receive it when renewal is unavailable.
    final body = await response.stream.toBytes();
    final rejectedToken = authorization.substring(7);
    String? token;
    try {
      token = await renewToken(rejectedToken);
    } catch (_) {
      // Preserve the server's actionable 401 rather than obscuring it with a
      // transient refresh error. Never replay requests without a new token.
    }
    if (token == null || token.isEmpty || token == rejectedToken) {
      return http.StreamedResponse(Stream.value(body), response.statusCode,
          headers: response.headers, request: request);
    }
    final retry = http.Request(request.method, request.url)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..headers.addAll(request.headers)
      ..headers['Authorization'] = 'Bearer $token';
    return _inner.send(retry);
  }

  @override
  void close() => _inner.close();
}
