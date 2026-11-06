from pathlib import Path
import argparse,hashlib,json,os,plistlib,shutil,subprocess,tempfile
parser=argparse.ArgumentParser(description='Package a personal ad-hoc KB Music preview; never notarizes or changes system security.')
parser.add_argument('--app',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
repo=Path(__file__).resolve().parents[1];outputs=args.output.resolve();outputs.mkdir(parents=True,exist_ok=True)
app=args.app.resolve()
# Ad-hoc libraries have no Team ID. Scope this compatibility exception to this
# personal preview; preserve release entitlements, never change system settings.
entitlements=plistlib.loads((repo/'macos/Runner/Release.entitlements').read_bytes())
entitlements['com.apple.security.cs.disable-library-validation']=True
with tempfile.NamedTemporaryFile(suffix='.plist') as ent:
 ent.write(plistlib.dumps(entitlements));ent.flush()
 subprocess.run(['codesign','--force','--deep','--sign','-','--preserve-metadata=identifier,flags','--entitlements',ent.name,'--timestamp=none',str(app)],check=True)
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleShortVersionString']=='1.0.4',info
assert info['CFBundleIdentifier']=='com.unicornsonlsd.finamp'
executable=app/'Contents/MacOS'/info['CFBundleExecutable']
architectures=subprocess.check_output(['lipo','-archs',str(executable)],text=True).strip().split()
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
revision=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()
dmg=outputs/'KB-Music-1.0.4-Workflow-Preview.dmg'
with tempfile.TemporaryDirectory(prefix='kb-dmg-stage-',dir='/tmp') as temporary:
 stage=Path(temporary)
 subprocess.run(['ditto',str(app),str(stage/'KB Music.app')],check=True)
 (stage/'Applications').symlink_to('/Applications')
 shutil.copyfile(repo/'LICENSE',stage/'LICENSE.txt')
 (stage/'Read Me.txt').write_text(f'''KB Music 1.0.4 ({info['CFBundleVersion']}) — Workflow Preview

Drag KB Music.app to Applications to install this native macOS build.
The macOS bundle identifier remains com.unicornsonlsd.finamp.
It does not automatically migrate data from a separately identified iOS-on-Mac app.

This preview fixes silent account sign-in navigation and adds Previous / Play-Pause / Next compact controls and keeps
Finamp's existing playback, queue, downloads and offline engine.
89 Flutter tests pass, and the macOS release app was built and verified.

The web app has separate source fixes for automatic next, queue selection,
repeat, shuffle, sleep timers and music system controls. This DMG does not
update the web server. Full platform parity and real iPhone control behavior
are not yet certified. See the workflow audit accompanying this download.

This personal preview is ad-hoc signed, not Apple-notarized.
An app-only library-loading exception supports its embedded Flutter/Isar libraries.
System security settings are unchanged.
No account, library, credentials or local media data are bundled in the installer.
MPL-2.0 license: see LICENSE.txt and preserved source notices.
''')
 subprocess.run(['codesign','--verify','--deep','--strict',str(stage/'KB Music.app')],check=True)
 subprocess.run(['hdiutil','create','-volname','KB Music','-srcfolder',str(stage),'-format','UDZO','-ov',str(dmg)],check=True)
subprocess.run(['hdiutil','verify',str(dmg)],check=True)
with tempfile.TemporaryDirectory(prefix='kb-dmg-verify-',dir='/tmp') as mount:
 attached=False
 try:
  subprocess.run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',mount,str(dmg)],check=True);attached=True
  installed=Path(mount)/'KB Music.app';mounted=plistlib.loads((installed/'Contents/Info.plist').read_bytes())
  assert all(mounted[k]==info[k] for k in ('CFBundleIdentifier','CFBundleShortVersionString','CFBundleVersion'))
  subprocess.run(['codesign','--verify','--deep','--strict',str(installed)],check=True)
  assert hashlib.sha256((installed/'Contents/MacOS'/info['CFBundleExecutable']).read_bytes()).digest()==hashlib.sha256(executable.read_bytes()).digest()
  assert os.readlink(Path(mount)/'Applications')=='/Applications'
  assert (Path(mount)/'LICENSE.txt').is_file()
 finally:
  if attached:subprocess.run(['hdiutil','detach',mount],check=True)
sha=hashlib.sha256(dmg.read_bytes()).hexdigest()
(dmg.with_suffix('.dmg.sha256')).write_text(f'{sha}  {dmg.name}\n')
manifest={'name':'KB Music','version':'1.0.4','build':str(info['CFBundleVersion']),'bundle_identifier':info['CFBundleIdentifier'],'minimum_macos':info.get('LSMinimumSystemVersion'),'architectures':architectures,'source_revision':revision,'source_repository':'https://github.com/koltensaccount/finamp','build_mode':'release','signing':'ad-hoc','apple_notarized':False,'preview_library_validation_exception':True,'system_security_settings':'unchanged','dmg':dmg.name,'size_bytes':dmg.stat().st_size,'sha256':sha,'checks':{'flutter_tests':89,'web_player_contract_tests':14,'codesign_deep_strict':'pass','dmg_verify':'pass','mounted_contents_and_binary':'pass','physical_iphone':'not_verified','web_deployment':'separate_guarded_rollout_verified'}}
(outputs/'KB_Music_macOS_Preview_Manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'dmg':str(dmg),'size_bytes':dmg.stat().st_size,'architectures':architectures,'sha256':sha}))
