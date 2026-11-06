# Repeated macOS Keychain prompts

The user confirmed the dialogs were macOS login-Keychain prompts, not KB Music
password errors. The screenshot names KB Music and the shared default Flutter
service. Earlier direct `security find-generic-password` diagnostics also can
request per-item access. Do not repeat them. A token returned by that diagnostic
is not proof of the token used by the running app.

## Fix

- Use a KB-specific macOS Keychain service. Leave all previous entries and app
  data untouched; no broad deleteAll. No automatic access to old unsigned items.
  A one-time KB account login may be needed in the new secure namespace.
- Background storage requests use Apple's noninteractive authentication-failure
  constant, passed through the installed Flutter plugin. Denial fails visibly on
  credential writes and cannot fall back to plaintext preferences on macOS.
  Existing iOS storage namespace/behavior remains unchanged.
- Replace per-build ad-hoc identity with a persistent, dedicated local preview
  certificate/private key. The app requirement pins bundle ID and certificate.
  No system trust, Gatekeeper, login-Keychain ACL or Apple account changes.
  This is a local preview signer, not an Apple Developer ID or notarization.
- Signing material lives only in a mode700 local signing directory; dedicated
  keychain and password file are private. Never commit/export private material.
  The creation script refuses to replace an existing identity. Packaging uses
  it explicitly, preserving the normal keychain search list.

## Evidence

A fixture using its own temporary Keychain was compiled twice with different
executable bytes, signed with the same local identity, and successfully read
its fixture item without authentication UI. It used no real app credentials.
`python3 scripts/check_macos_signing_continuity.py` repeats this isolated check.
Storage regressions cover namespace/noninteractive options and denied account
and catalog writes. Runtime app startup and real account reconnection remain
separate gates; no claim based solely on a successful build.

## Official sources

- [Apple: code requirements and identity changes](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Apple: self-signed code-signing identities](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)
- [Apple: noninteractive Keychain queries](https://developer.apple.com/documentation/security/ksecuseauthenticationuifail)

The plugin currently exposes the older authentication-UI option; Apple recommends
LAContext.interactionNotAllowed for new native integrations. The exact constant
value was verified against the installed Security framework, not guessed.
