import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CatalogCredentials {
  const CatalogCredentials({required this.endpoint, required this.token});

  final Uri endpoint;
  final String token;
}

abstract class CatalogCredentialStore {
  Future<CatalogCredentials?> read();
  Future<void> save(CatalogCredentials credentials);
  Future<void> clear();
}

class SecureCatalogCredentialStore implements CatalogCredentialStore {
  SecureCatalogCredentialStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _endpointKey = 'catalog_api_endpoint';
  static const _tokenKey = 'catalog_api_bearer_token';
  static const _disabledKey = 'catalog_explicitly_disabled';
  static const _envEndpoint = String.fromEnvironment('CATALOG_ENDPOINT', defaultValue: '');
  static const _envToken = String.fromEnvironment('CATALOG_TOKEN', defaultValue: '');
  final FlutterSecureStorage _storage;

  @override
  Future<CatalogCredentials?> read() async {
    final isDisabled = await _storage.read(key: _disabledKey);
    if (isDisabled == 'true') {
      return null;
    }

    final endpoint = await _storage.read(key: _endpointKey);
    final token = await _storage.read(key: _tokenKey);

    final effectiveEndpoint = (endpoint != null && endpoint.isNotEmpty)
        ? endpoint
        : (_envEndpoint.isNotEmpty ? _envEndpoint : 'http://127.0.0.1:8765');
    final effectiveToken = (token != null && token.isNotEmpty)
        ? token
        : _envToken;

    final uri = Uri.tryParse(effectiveEndpoint);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty || effectiveToken.isEmpty) {
      return null;
    }
    return CatalogCredentials(endpoint: uri, token: effectiveToken);
  }

  @override
  Future<void> save(CatalogCredentials credentials) async {
    await _storage.delete(key: _disabledKey);
    await _storage.write(key: _endpointKey, value: credentials.endpoint.toString());
    await _storage.write(key: _tokenKey, value: credentials.token);
  }

  @override
  Future<void> clear() async {
    await _storage.deleteAll();
    if (_envToken.isNotEmpty) {
      await _storage.write(key: _disabledKey, value: 'true');
    }
  }
}
