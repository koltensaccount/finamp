import 'dart:io';

import 'package:finamp/services/catalog_credential_store.dart';
import 'package:finamp/services/kb_account_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class DeniedReadStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw PlatformException(code: 'interaction_not_allowed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'macOS Keychain denial does not masquerade as an unconfigured catalog',
    () async {
      final store = SecureCatalogCredentialStore(storage: DeniedReadStorage());
      await expectLater(store.read(), throwsA(isA<StateError>()));
      final account = KBAccountService(storage: DeniedReadStorage());
      expect(await account.init(), isFalse);
    },
    skip: !Platform.isMacOS,
  );
}
