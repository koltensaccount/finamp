from pathlib import Path
import subprocess,tempfile,json,secrets,hashlib
identity=json.loads((Path.home()/'.local/share/kb-music/signing/identity.json').read_text())
swift='''import Foundation
import Security
let path = CommandLine.arguments[1]
var keychain: SecKeychain?
guard SecKeychainOpen(path, &keychain) == errSecSuccess else { exit(10) }
let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
 kSecAttrService as String:"KB signing fixture", kSecAttrAccount as String:"fixture",
 kSecUseKeychain as String:keychain!, kSecUseAuthenticationUI as String:kSecUseAuthenticationUIFail]
if CommandLine.arguments[2] == "write" {
 var add = query; add[kSecValueData as String] = Data("nonsecret-fixture".utf8)
 guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { exit(11) }
} else {
 var read = query; read[kSecMatchSearchList as String] = [keychain!]
 read[kSecReturnData as String] = true
 var item: CFTypeRef?
 let status = SecItemCopyMatching(read as CFDictionary, &item)
 guard status == errSecSuccess, item as? Data == Data("nonsecret-fixture".utf8) else { print("fixture status", status); exit(12) }
}
print("fixture ok")
'''
def run(args):
 r=subprocess.run(args,capture_output=True,text=True)
 if r.returncode:raise RuntimeError(r.stdout+r.stderr[-700:])
 return r.stdout
with tempfile.TemporaryDirectory(prefix='kb-keychain-fixture-') as tmp:
 t=Path(tmp);keychain=t/'fixture.keychain-db';password=secrets.token_urlsafe(32)
 run(['security','create-keychain','-p',password,str(keychain)])
 try:
  run(['security','unlock-keychain','-p',password,str(keychain)])
  src=t/'fixture.swift';exe=t/'fixture'
  previous_hash=None
  for version in [1,2]:
   src.write_text(swift.replace('fixture ok', 'fixture ok '+str(version)))
   run(['swiftc',str(src),'-o',str(exe)])
   req='=designated => identifier "kb.music.signing.fixture" and certificate leaf = H"'+identity['sha1']+'"'
   run(['codesign','--force','--sign',identity['sha1'],'--keychain',identity['keychain'],'--identifier','kb.music.signing.fixture','--requirements',req,'--timestamp=none',str(exe)])
   current_hash=hashlib.sha256(exe.read_bytes()).hexdigest()
   assert current_hash!=previous_hash
   previous_hash=current_hash
   if version==1:run([str(exe),str(keychain),'write'])
   run([str(exe),str(keychain),'read'])
  print('PASS: separately rebuilt/signed fixture reads its own dedicated test Keychain item without UI; no app credentials accessed.')
 finally:
  run(['security','delete-keychain',str(keychain)])
