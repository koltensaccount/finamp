import 'kb_secure_storage.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/services/catalog_credential_store.dart';
import 'package:finamp/services/finamp_user_helper.dart';
import 'package:finamp/services/jellyfin_api_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _logger = Logger('KBAccountService');

class KBAccountSession {
  const KBAccountSession({
    required this.accountId,
    required this.username,
    required this.displayName,
    required this.deviceId,
    required this.deviceName,
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accountId;
  final String username;
  final String displayName;
  final String deviceId;
  final String deviceName;
  final String token;
  final String refreshToken;
  final int expiresAt;

  bool get isExpired => DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiresAt;
}

class KBAccountService extends ChangeNotifier {
  static const _defaultStorage = kbSecureStorage;

  KBAccountService({FlutterSecureStorage? storage, http.Client? client})
      : _storage = storage ?? _defaultStorage,
        _client = client ?? http.Client();

  final FlutterSecureStorage _storage;
  final http.Client _client;

  Future<void> _storeWrite(String key, String value) async {
    bool secureOk = false;
    try {
      await _storage.write(key: key, value: value);
      secureOk = true;
    } catch (e) {
      if (Platform.isMacOS) {
        throw StateError('Secure login storage is unavailable. Use the installed KB Music app; your existing saved data has not been deleted.');
      }
      _logger.warning('SecureStorage write failed for $key, using SharedPreferences fallback: $e');
    }
    if (!secureOk) {
      try {
        final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
        await prefs.setString('kb_sec_$key', value);
      } catch (e) {
        _logger.warning('SharedPreferences write fallback failed for $key: $e');
      }
    }
  }

  Future<String?> _storeRead(String key) async {
    try {
      final val = await _storage.read(key: key);
      return val;
    } catch (e) {
      if (Platform.isMacOS) return null;
      _logger.warning('SecureStorage read failed for $key, checking SharedPreferences fallback: $e');
      try {
        final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
        return prefs.getString('kb_sec_$key');
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _storeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
      await prefs.remove('kb_sec_$key');
    } catch (_) {}
  }

  Future<void> _storeDeleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
      for (final k in [
        _keyEndpoint,
        _keyToken,
        _keyRefreshToken,
        _keyAccountId,
        _keyUsername,
        _keyDisplayName,
        _keyDeviceId,
        _keyDeviceName,
        _keyExpiresAt,
      ]) {
        await prefs.remove('kb_sec_$k');
      }
    } catch (_) {}
  }

  static const _defaultEndpoint = 'http://100.73.94.105:8765';
  static const _fallbackEndpoint = 'http://koltensserver.tailfa2fff.ts.net:8765';

  static const _keyEndpoint = 'kb_account_endpoint';
  static const _keyToken = 'kb_account_token';
  static const _keyRefreshToken = 'kb_account_refresh_token';
  static const _keyAccountId = 'kb_account_id';
  static const _keyUsername = 'kb_account_username';
  static const _keyDisplayName = 'kb_account_display_name';
  static const _keyDeviceId = 'kb_account_device_id';
  static const _keyDeviceName = 'kb_account_device_name';
  static const _keyExpiresAt = 'kb_account_expires_at';

  KBAccountSession? _currentSession;
  KBAccountSession? get currentSession => _currentSession;
  bool get isSignedIn => _currentSession != null && !_currentSession!.isExpired;

  String? _cachedEndpoint;

  Future<String> get endpoint async {
    if (_cachedEndpoint != null) return _cachedEndpoint!;
    final stored = await _storeRead(_keyEndpoint);
    if (stored != null && stored.isNotEmpty) {
      _cachedEndpoint = stored;
      return stored;
    }
    return _defaultEndpoint;
  }

  Future<void> setEndpoint(String newEndpoint) async {
    _cachedEndpoint = newEndpoint.replaceAll(RegExp(r'/+$'), '');
    await _storeWrite(_keyEndpoint, _cachedEndpoint!);
    notifyListeners();
  }

  /// Resolve platform device name
  Future<String> resolveDeviceName() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isMacOS) {
        final mac = await info.macOsInfo;
        return mac.computerName.isNotEmpty ? mac.computerName : 'MacBook';
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return ios.name.isNotEmpty ? ios.name : 'Apple Device';
      } else if (Platform.isAndroid) {
        final android = await info.androidInfo;
        return '${android.brand} ${android.model}'.trim();
      } else if (Platform.isLinux) {
        final linux = await info.linuxInfo;
        return linux.prettyName.isNotEmpty ? linux.prettyName : 'Linux Device';
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }

  /// Initialize and load saved session
  Future<bool> init() async {
    try {
      final token = await _storeRead(_keyToken);
      final refreshToken = await _storeRead(_keyRefreshToken);
      final accountId = await _storeRead(_keyAccountId);
      final username = await _storeRead(_keyUsername);
      final displayName = await _storeRead(_keyDisplayName);
      final deviceId = await _storeRead(_keyDeviceId);
      final deviceName = await _storeRead(_keyDeviceName);
      final expiresStr = await _storeRead(_keyExpiresAt);

      if (token != null && accountId != null && username != null) {
        final expiresAt = expiresStr != null ? int.tryParse(expiresStr) ?? 0 : 0;
        _currentSession = KBAccountSession(
          accountId: accountId,
          username: username,
          displayName: displayName ?? username,
          deviceId: deviceId ?? 'dev_unknown',
          deviceName: deviceName ?? 'Device',
          token: token,
          refreshToken: refreshToken ?? '',
          expiresAt: expiresAt,
        );

        if (_currentSession!.isExpired && refreshToken != null && refreshToken.isNotEmpty) {
          await refreshSession();
        }

        notifyListeners();
        return true;
      }
    } catch (e) {
      _logger.warning('Failed to initialize KB Account session: $e');
    }
    return false;
  }

  /// Server status
  Future<Map<String, dynamic>> checkStatus() async {
    final ep = await endpoint;
    for (final base in [ep, _fallbackEndpoint, _defaultEndpoint]) {
      try {
        final uri = Uri.parse('$base/v1/account/status');
        final resp = await _client.get(uri).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          if (base != ep) {
            await setEndpoint(base);
          }
          return jsonDecode(resp.body) as Map<String, dynamic>;
        }
      } catch (_) {}
    }
    return {'enrolled': false, 'error': 'Server unreachable'};
  }

  /// Check username availability (returns true if available, false if taken)
  Future<Map<String, dynamic>> checkUsernameAvailability(String username) async {
    final ep = await endpoint;
    try {
      final uri = Uri.parse('$ep/v1/account/check-username').replace(queryParameters: {'username': username.trim()});
      final resp = await _client.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } else {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return {'available': false, 'error': data['error'] ?? 'Username already taken'};
      }
    } catch (e) {
      return {'available': true}; // Allow trying on submit if check network fails
    }
  }

  /// Create / Register Account (handles both owner enrollment and new user account creation)
  Future<Map<String, dynamic>> createAccount({
    required String username,
    required String password,
    required String displayName,
    String? deviceName,
  }) async {
    final ep = await endpoint;
    final dName = deviceName ?? await resolveDeviceName();
    final body = jsonEncode({
      'username': username.trim(),
      'password': password,
      'display_name': displayName.trim().isNotEmpty ? displayName.trim() : username.trim(),
      'device_name': dName,
      'platform': Platform.operatingSystem,
      'client_version': '1.0.0',
    });

    // Try /v1/account/register first; fallback to /v1/account/enroll
    http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse('$ep/v1/account/register'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 404) {
        resp = await _client
            .post(
              Uri.parse('$ep/v1/account/enroll'),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 10));
      }
    } catch (_) {
      resp = await _client
          .post(
            Uri.parse('$ep/v1/account/enroll'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      await applyConfigAndSignIn(data);
      return data;
    } else {
      throw Exception(data['error'] ?? 'Account creation failed with status ${resp.statusCode}');
    }
  }

  /// Enroll owner account
  Future<Map<String, dynamic>> enrollOwner({
    required String username,
    required String password,
    required String displayName,
    String? deviceName,
  }) async {
    return createAccount(
      username: username,
      password: password,
      displayName: displayName,
      deviceName: deviceName,
    );
  }

  /// Sign in with username and password
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    String? deviceName,
  }) async {
    final ep = await endpoint;
    final dName = deviceName ?? await resolveDeviceName();
    final body = jsonEncode({
      'username': username,
      'password': password,
      'device_name': dName,
      'platform': Platform.operatingSystem,
      'client_version': '1.0.0',
    });

    final resp = await _client
        .post(
          Uri.parse('$ep/v1/account/login'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 10));

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      await applyConfigAndSignIn(data);
      return data;
    } else {
      throw Exception(data['error'] ?? 'Invalid username or password');
    }
  }

  /// Refresh active session
  Future<bool>? _refreshInFlight;
  String? _renewedFromToken;

  Future<bool> refreshSession() {
    return _refreshInFlight ??= _refreshSession().whenComplete(() => _refreshInFlight = null);
  }

  /// Only renew this account's token; never replace a manually configured key.
  Future<String?> renewRejectedToken(String rejectedToken) async {
    if (_currentSession == null || !rejectedToken.startsWith('kba_')) return null;
    if (_currentSession!.token != rejectedToken) {
      return _renewedFromToken == rejectedToken ? _currentSession!.token : null;
    }
    return await refreshSession() ? _currentSession?.token : null;
  }

  Future<bool> _refreshSession() async {
    if (_currentSession == null || _currentSession!.refreshToken.isEmpty) return false;
    try {
      final ep = await endpoint;
      final body = jsonEncode({'refresh_token': _currentSession!.refreshToken});
      final resp = await _client
          .post(
            Uri.parse('$ep/v1/account/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final previous = _currentSession!;
        final store = GetIt.instance.isRegistered<CatalogCredentialStore>()
            ? GetIt.instance<CatalogCredentialStore>()
            : SecureCatalogCredentialStore(storage: _storage);
        final catalog = await store.read();
        // Refresh returns session fields, not the full login/bootstrap envelope.
        await applyConfigAndSignIn({
          'account': {'id': previous.accountId, 'username': previous.username, 'display_name': previous.displayName},
          'device': {'id': previous.deviceId, 'name': previous.deviceName},
          'session': data,
          'config': {
            if (catalog != null && catalog.token == previous.token)
              'catalog': {'endpoint': catalog.endpoint.toString()},
          },
        });
        _renewedFromToken = previous.token;
        return true;
      }
    } catch (e) {
      _logger.warning('Failed to refresh KB Account session: $e');
    }
    return false;
  }

  /// Request 6-digit pairing code for this device
  Future<Map<String, dynamic>> createPairingRequest({String? deviceName}) async {
    final ep = await endpoint;
    final dName = deviceName ?? await resolveDeviceName();
    final body = jsonEncode({
      'device_name': dName,
      'platform': Platform.operatingSystem,
      'client_version': '1.0.0',
    });

    final resp = await _client
        .post(
          Uri.parse('$ep/v1/account/pair/request'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 8));

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['error'] ?? 'Could not create pairing code');
    }
  }

  /// Poll pairing status
  Future<Map<String, dynamic>> pollPairing({
    required String code,
    String? pairingId,
    String? pollToken,
  }) async {
    final ep = await endpoint;
    final queryParams = <String, String>{'code': code};
    if (pairingId != null) queryParams['pairing_id'] = pairingId;
    if (pollToken != null) queryParams['poll_token'] = pollToken;

    final uri = Uri.parse('$ep/v1/account/pair/poll').replace(queryParameters: queryParams);
    final resp = await _client.get(uri).timeout(const Duration(seconds: 5));

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      if (data['state'] == 'approved') {
        await applyConfigAndSignIn(data);
      }
      return data;
    } else {
      throw Exception(data['error'] ?? 'Pairing poll failed');
    }
  }

  /// Approve another device using its 6-digit code
  Future<Map<String, dynamic>> approvePairing(String code) async {
    if (!isSignedIn) throw Exception('Not signed into KB Account');
    final ep = await endpoint;
    final body = jsonEncode({'code': code.trim()});

    final resp = await _client
        .post(
          Uri.parse('$ep/v1/account/pair/approve'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${_currentSession!.token}',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 8));

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['error'] ?? 'Failed to approve pairing');
    }
  }

  /// List registered devices
  Future<List<Map<String, dynamic>>> listDevices() async {
    if (!isSignedIn) return [];
    try {
      final ep = await endpoint;
      final resp = await _client
          .get(
            Uri.parse('$ep/v1/account/devices'),
            headers: {'Authorization': 'Bearer ${_currentSession!.token}'},
          )
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final devices = (data['devices'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        return devices;
      }
    } catch (e) {
      _logger.warning('Failed to fetch devices: $e');
    }
    return [];
  }

  /// Rename a device
  Future<bool> renameDevice(String deviceId, String newName) async {
    if (!isSignedIn) return false;
    final ep = await endpoint;
    final resp = await _client
        .post(
          Uri.parse('$ep/v1/account/devices/$deviceId/rename'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${_currentSession!.token}',
          },
          body: jsonEncode({'name': newName.trim()}),
        )
        .timeout(const Duration(seconds: 6));
    return resp.statusCode == 200;
  }

  /// Revoke a device
  Future<bool> revokeDevice(String deviceId) async {
    if (!isSignedIn) return false;
    final ep = await endpoint;
    final resp = await _client
        .post(
          Uri.parse('$ep/v1/account/devices/$deviceId/revoke'),
          headers: {'Authorization': 'Bearer ${_currentSession!.token}'},
        )
        .timeout(const Duration(seconds: 6));
    return resp.statusCode == 200;
  }

  /// Submit a bug report directly to backend BUGS.md
  Future<Map<String, dynamic>> submitBugReport({
    required String title,
    String description = '',
    String category = 'UI/Layout',
    String screen = '',
    String nowPlaying = '',
  }) async {
    final ep = await endpoint;
    final dName = await resolveDeviceName();
    final body = jsonEncode({
      'title': title,
      'description': description,
      'category': category,
      'screen': screen,
      'device_name': dName,
      'platform': Platform.operatingSystem,
      'client_version': '1.0.0',
      'now_playing': nowPlaying,
    });

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (isSignedIn) {
      headers['Authorization'] = 'Bearer ${_currentSession!.token}';
    }

    final resp = await _client
        .post(Uri.parse('$ep/v1/account/bug-reports'), headers: headers, body: body)
        .timeout(const Duration(seconds: 8));

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to submit bug report');
    }
  }

  /// Apply config from server response and sign in
  Future<void> applyConfigAndSignIn(Map<String, dynamic> data) async {
    final account = data['account'] as Map<String, dynamic>? ?? {};
    final device = data['device'] as Map<String, dynamic>? ?? {};
    final session = data['session'] as Map<String, dynamic>? ?? {};
    final config = data['config'] as Map<String, dynamic>? ?? {};

    final token = session['token'] as String? ?? '';
    final refreshToken = session['refresh_token'] as String? ?? '';
    final expiresAt = session['expires_at'] as int? ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30 * 86400);

    final accountId = account['id'] as String? ?? '';
    final username = account['username'] as String? ?? '';
    final displayName = account['display_name'] as String? ?? username;
    final deviceId = device['id'] as String? ?? '';
    final deviceName = device['name'] as String? ?? 'Device';

    if (token.trim().isEmpty || accountId.trim().isEmpty || username.trim().isEmpty) {
      throw const FormatException('Server returned an incomplete account session. Please try signing in again.');
    }

    // 1. Store session securely with automatic SharedPreferences fallback
    await _storeWrite(_keyToken, token);
    await _storeWrite(_keyRefreshToken, refreshToken);
    await _storeWrite(_keyAccountId, accountId);
    await _storeWrite(_keyUsername, username);
    await _storeWrite(_keyDisplayName, displayName);
    await _storeWrite(_keyDeviceId, deviceId);
    await _storeWrite(_keyDeviceName, deviceName);
    await _storeWrite(_keyExpiresAt, expiresAt.toString());

    _currentSession = KBAccountSession(
      accountId: accountId,
      username: username,
      displayName: displayName,
      deviceId: deviceId,
      deviceName: deviceName,
      token: token,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
    );

    // 2. Configure Catalog and Books credentials
    final catalogConf = config['catalog'] as Map<String, dynamic>?;
    if (catalogConf != null && catalogConf['endpoint'] != null) {
      final credStore = GetIt.instance.isRegistered<CatalogCredentialStore>()
          ? GetIt.instance<CatalogCredentialStore>()
          : SecureCatalogCredentialStore(storage: _storage);
      final cUri = Uri.tryParse(catalogConf['endpoint'] as String);
      if (cUri != null) {
        await credStore.save(CatalogCredentials(endpoint: cUri, token: token));
      }
    }

    // 3. Configure Jellyfin User
    final jfConf = config['jellyfin'] as Map<String, dynamic>?;
    if (jfConf != null && GetIt.instance.isRegistered<FinampUserHelper>()) {
      final userHelper = GetIt.instance<FinampUserHelper>();
      final serverUrl = jfConf['server_url'] as String? ?? '';
      final localUrl = jfConf['local_url'] as String? ?? serverUrl;
      final userId = jfConf['user_id'] as String? ?? '';
      final accessToken = jfConf['access_token'] as String? ?? '';
      final serverId = jfConf['server_id'] as String? ?? '';
      final viewIdStr = jfConf['view_id'] as String? ?? '';

      final viewsMap = <BaseItemId, BaseItemDto>{};
      BaseItemId? currentViewId;
      if (viewIdStr.isNotEmpty) {
        currentViewId = BaseItemId(viewIdStr);
        viewsMap[currentViewId] = BaseItemDto(
          id: currentViewId,
          name: 'Music',
          type: 'CollectionFolder',
        );
      }

      final finampUser = FinampUser(
        id: userId,
        publicAddress: serverUrl,
        localAddress: localUrl,
        isLocal: false,
        preferLocalNetwork: false,
        accessToken: accessToken,
        serverId: serverId,
        views: viewsMap,
        currentViewId: currentViewId,
      );

      await userHelper.saveUser(finampUser);

      // Hydrate views from Jellyfin if connected
      if (GetIt.instance.isRegistered<JellyfinApiHelper>()) {
        try {
          final jfHelper = GetIt.instance<JellyfinApiHelper>();
          final views = await jfHelper.getViews();
          if (views.isNotEmpty) {
            userHelper.setCurrentUserViews(views);
          }
        } catch (_) {}
      }
    }

    notifyListeners();
  }

  /// Sign out
  Future<void> logout({bool all = false}) async {
    if (_currentSession != null) {
      try {
        final ep = await endpoint;
        final path = all ? '/v1/account/logout-all' : '/v1/account/logout';
        await _client
            .post(
              Uri.parse('$ep$path'),
              headers: {'Authorization': 'Bearer ${_currentSession!.token}'},
            )
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    await _storeDelete(_keyToken);
    await _storeDelete(_keyRefreshToken);
    await _storeDelete(_keyAccountId);
    await _storeDelete(_keyUsername);
    await _storeDelete(_keyDisplayName);
    await _storeDelete(_keyDeviceId);
    await _storeDelete(_keyDeviceName);
    await _storeDelete(_keyExpiresAt);

    _currentSession = null;
    notifyListeners();
  }
}

final kbAccountServiceProvider = ChangeNotifierProvider<KBAccountService>((ref) {
  if (GetIt.instance.isRegistered<KBAccountService>()) {
    return GetIt.instance<KBAccountService>();
  }
  final service = KBAccountService();
  GetIt.instance.registerSingleton<KBAccountService>(service);
  return service;
});
