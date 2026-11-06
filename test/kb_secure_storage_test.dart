import 'package:finamp/services/kb_secure_storage.dart';
import 'package:finamp/services/kb_account_service.dart';
import 'package:finamp/services/catalog_credential_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

class DeniedStorage extends FlutterSecureStorage {
  @override
  Future<void> write({required String key, required String? value,
    AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
    WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    throw PlatformException(code: 'interaction_not_allowed');
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('macOS KB storage is scoped and requests noninteractive Keychain access', () {
    expect(kbSecureStorage.mOptions.accountName, 'com.unicornsonlsd.finamp.kb-music.v1');
    expect(kbSecureStorage.mOptions.authenticationUIBehavior, 'u_AuthUIF');
    expect((kbSecureStorage.mOptions as MacOsOptions).usesDataProtectionKeychain, isFalse);
  });
  test('denied account write remains a visible failure, never signs in', () async {
    final service=KBAccountService(storage: DeniedStorage(),client:MockClient((_)async=>http.Response('{}',200)));
    await expectLater(service.applyConfigAndSignIn({
      'account':{'id':'fixture','username':'fixture'},'session':{'token':'kba_fixture'},
    }),throwsStateError);
    expect(service.currentSession,isNull);
  });
  test('denied catalog write fails rather than reporting a saved connection', () async {
    final store=SecureCatalogCredentialStore(storage:DeniedStorage());
    await expectLater(store.save(CatalogCredentials(endpoint:Uri.parse('https://example.test'),token:'fixture')),throwsStateError);
  });
}
