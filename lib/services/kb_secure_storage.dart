import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keep KB credentials separate from other Flutter apps and older unsigned
/// previews. Never display OS password dialogs during background API work.
/// u_AuthUIF is Apple's kSecUseAuthenticationUIFail constant, passed through by
/// flutter_secure_storage_darwin. Access denial stays an error, never plaintext.
const kbSecureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  mOptions: MacOsOptions(
    accountName: 'com.unicornsonlsd.finamp.kb-music.v1',
    accessibility: KeychainAccessibility.first_unlock,
    usesDataProtectionKeychain: false,
    authenticationUIBehavior: 'u_AuthUIF',
  ),
);
