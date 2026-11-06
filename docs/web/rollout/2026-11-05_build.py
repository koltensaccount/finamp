from pathlib import Path
import hashlib,json,shutil,subprocess,tempfile
root=Path.home()/'kb-music-web'
revision=Path('/tmp/kb-workflows-source-revision.txt').read_text().strip()
tag='kb-music-web:workflow-'+revision[:8]
initial=json.loads(Path('/tmp/kb-audit-initial-source-hashes.json').read_text())
changes=json.loads(Path('/tmp/kb-final-playback-hashes.json').read_text())
for name,digest in initial.items():
 expected=changes[name]['after'] if name in changes else digest
 assert hashlib.sha256((root/name).read_bytes()).hexdigest()==expected,f'Unexpected concurrent source change: {name}'
context=Path(tempfile.mkdtemp(prefix='kb-workflows-build-',dir='/tmp'))
for name in ('src','public'):shutil.copytree(root/name,context/name)
for name in ('package.json','package-lock.json','next.config.ts','tsconfig.json','next-env.d.ts','postcss.config.mjs','eslint.config.mjs','Dockerfile'):
 shutil.copyfile(root/name,context/name)
assert not (context/'.env.local').exists()
for name,values in changes.items():assert hashlib.sha256((context/name).read_bytes()).hexdigest()==values['after'],name
log=Path('/tmp/kb-workflows-docker-build-13fd50ef.txt')
with log.open('w') as output:
 subprocess.run(['docker','build','-t',tag,'--label','org.opencontainers.image.revision='+revision,str(context)],stdout=output,stderr=subprocess.STDOUT,check=True)
image=subprocess.check_output(['docker','image','inspect',tag,'--format','{{.Id}}'],text=True).strip()
Path('/tmp/kb-workflows-built-image.json').write_text(json.dumps({'image':image,'tag':tag,'revision':revision}))
print('Built guarded web image:',image,'revision:',revision)
print('No runtime container changed')
