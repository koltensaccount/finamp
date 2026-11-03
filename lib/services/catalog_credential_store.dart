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
  final FlutterSecureStorage _storage;

  @override
  Future<CatalogCredentials?> read() async {
    final endpoint = await _storage.read(key: _endpointKey);
    final token = await _storage.read(key: _tokenKey);
    final uri = endpoint == null ? null : Uri.tryParse(endpoint);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return CatalogCredentials(endpoint: uri, token: token);
  }

  @override
  Future<void> save(CatalogCredentials credentials) async {
    await _storage.write(key: _endpointKey, value: credentials.endpoint.toString());
    await _storage.write(key: _tokenKey, value: credentials.token);
  }

  @override
  Future<void> clear() => _storage.deleteAll();
}
