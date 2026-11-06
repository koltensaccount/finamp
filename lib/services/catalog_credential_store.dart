import 'dart:io';
import 'kb_secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  SecureCatalogCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? kbSecureStorage;

  static const _endpointKey = 'catalog_api_endpoint';
  static const _tokenKey = 'catalog_api_bearer_token';
  static const _disabledKey = 'catalog_explicitly_disabled';
  static const _envEndpoint = String.fromEnvironment('CATALOG_ENDPOINT', defaultValue: '');
  static const _envToken = String.fromEnvironment('CATALOG_TOKEN', defaultValue: '');
  final FlutterSecureStorage _storage;

  Future<void> _safeWrite(String key, String value) async {
    bool secureOk = false;
    try {
      await _storage.write(key: key, value: value);
      secureOk = true;
    } catch (_) {
      if (Platform.isMacOS) throw StateError('Secure login storage is unavailable. Sign in using the installed KB Music app.');
    }
    if (!secureOk) {
      try {
        final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
        await prefs.setString('kb_sec_$key', value);
      } catch (_) {}
    }
  }

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      if (Platform.isMacOS) {
        throw StateError('macOS Keychain could not read the saved catalog connection. Reconnect in Account settings; your existing credentials have not been deleted.');
      }
      try {
        final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
        return prefs.getString('kb_sec_$key');
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
      await prefs.remove('kb_sec_$key');
    } catch (_) {}
  }

  @override
  Future<CatalogCredentials?> read() async {
    final isDisabled = await _safeRead(_disabledKey);
    if (isDisabled == 'true') {
      return null;
    }

    final endpoint = await _safeRead(_endpointKey);
    final token = await _safeRead(_tokenKey);

    final effectiveEndpoint = (endpoint != null && endpoint.isNotEmpty)
        ? endpoint
        : (_envEndpoint.isNotEmpty ? _envEndpoint : 'http://127.0.0.1:8765');
    final effectiveToken = (token != null && token.isNotEmpty) ? token : _envToken;

    final uri = Uri.tryParse(effectiveEndpoint);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty || effectiveToken.isEmpty) {
      return null;
    }
    return CatalogCredentials(endpoint: uri, token: effectiveToken);
  }

  @override
  Future<void> save(CatalogCredentials credentials) async {
    await _safeDelete(_disabledKey);
    await _safeWrite(_endpointKey, credentials.endpoint.toString());
    await _safeWrite(_tokenKey, credentials.token);
  }

  @override
  Future<void> clear() async {
    await _safeDelete(_endpointKey);
    await _safeDelete(_tokenKey);
    if (_envToken.isNotEmpty) {
      await _safeWrite(_disabledKey, 'true');
    } else {
      await _safeDelete(_disabledKey);
    }
  }
}
