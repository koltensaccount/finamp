from pathlib import Path
import os,subprocess,tempfile,secrets,json,hashlib
root=Path.home()/'.local/share/kb-music/signing';root.mkdir(parents=True,exist_ok=True);root.chmod(0o700)
keychain=root/'preview.keychain-db';password_file=root/'keychain-password'
assert not keychain.exists(),'Keep existing signing identity; never regenerate it silently'
password=secrets.token_urlsafe(48);password_file.write_text(password);password_file.chmod(0o600)
def run(args,**kw):
 r=subprocess.run(args,capture_output=True,**kw)
 if r.returncode: raise RuntimeError(str(args[0:2])+' failed: '+r.stderr.decode(errors='replace')[:500])
 return r.stdout
search=run(['security','list-keychains','-d','user']).decode()
with tempfile.TemporaryDirectory(prefix='kb-signing-',dir=root) as tmp:
 t=Path(tmp);key=t/'private.pem';cert=t/'certificate.pem';bundle=t/'identity.p12';passfile=t/'password';passfile.write_text(password);passfile.chmod(0o600)
 run(['openssl','req','-x509','-newkey','rsa:3072','-nodes','-keyout',str(key),'-out',str(cert),'-days','3650','-subj','/CN=KB Music Local Preview','-addext','basicConstraints=critical,CA:FALSE','-addext','keyUsage=critical,digitalSignature','-addext','extendedKeyUsage=critical,codeSigning'])
 run(['openssl','pkcs12','-export','-inkey',str(key),'-in',str(cert),'-out',str(bundle),'-name','KB Music Local Preview','-passout','file:'+str(passfile),'-legacy'])
 run(['security','create-keychain','-p',password,str(keychain)])
 run(['security','set-keychain-settings','-lut','21600',str(keychain)])
 run(['security','unlock-keychain','-p',password,str(keychain)])
 run(['security','import',str(bundle),'-k',str(keychain),'-P',password,'-T','/usr/bin/codesign'])
 run(['security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,str(keychain)])
 der=run(['openssl','x509','-in',str(cert),'-outform','DER']);fingerprint=hashlib.sha1(der).hexdigest().upper()
 (root/'identity.json').write_text(json.dumps({'name':'KB Music Local Preview','sha1':fingerprint,'keychain':str(keychain),'apple_issued':False,'system_trust_changed':False},indent=2)+'\n')
 # No private key/certificate export is retained outside the dedicated keychain.
# Restore any search-list addition made by create-keychain; use --keychain explicitly.
import shlex
original=shlex.split(search)
run(['security','list-keychains','-d','user','-s',*original])
print('Created dedicated local preview signer; system trust and original keychain search list unchanged.')
