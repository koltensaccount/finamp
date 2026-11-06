from pathlib import Path
import datetime,json,os,socket,subprocess,tempfile,time,urllib.request
EXPECTED='c928768c5b1da8d02c4245b98b693ab2e1fa2c679efea9519a27d23054f78fbd'
built=json.loads(Path('/tmp/kb-workflows-built-image.json').read_text())
image=built['image']; stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
def docker(*args):return subprocess.check_output(['docker',*args],text=True).strip()
def inspect(name):return json.loads(docker('inspect',name))[0]
old=inspect('kb-music-web');assert old['Id']==EXPECTED,'Concurrent deployment: preserve it and re-audit'
host=old['HostConfig'];config=old['Config']
assert host['NetworkMode']=='host' and not host['Privileged']
assert not host.get('PortBindings') and not host.get('Tmpfs') and not host.get('Mounts')
assert not host.get('PidMode') and config['Cmd']==['node','server.js']
assert not config.get('Healthcheck'),'Unexpected custom healthcheck'
assert inspect(image)['Config']['Entrypoint']==config['Entrypoint']
metadata=Path('/tmp/kb-web-rollback-metadata-'+stamp+'.json')
fd=os.open(metadata,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as f:json.dump(old,f)
envpaths=[]
def create(name,port,loopback=False,restart=None):
 env=dict(item.split('=',1) for item in config['Env'])
 env['PORT']=str(port)
 if loopback:env['HOSTNAME']='127.0.0.1'
 assert all('\n' not in k+v for k,v in env.items())
 fd,path=tempfile.mkstemp(prefix='kb-web-env-',dir='/tmp');envpaths.append(Path(path))
 with os.fdopen(fd,'w') as f:f.write(''.join(k+'='+v+'\n' for k,v in env.items()))
 args=['docker','create','--name',name,'--network','host','--env-file',path,'--restart',restart or 'no']
 if config.get('User'):args+=['--user',config['User']]
 if config.get('WorkingDir'):args+=['--workdir',config['WorkingDir']]
 for bind in host.get('Binds') or []:args+=['--volume',bind]
 for option in host.get('SecurityOpt') or []:args+=['--security-opt',option]
 for cap in host.get('CapDrop') or []:args+=['--cap-drop',cap]
 for cap in host.get('CapAdd') or []:args+=['--cap-add',cap]
 if host.get('ReadonlyRootfs'):args+=['--read-only']
 if host.get('Memory'):args+=['--memory',str(host['Memory'])]
 if host.get('NanoCpus'):args+=['--cpus',str(host['NanoCpus']/1e9)]
 if host.get('Init'):args+=['--init']
 log=host.get('LogConfig') or {}
 if log.get('Type'):args+=['--log-driver',log['Type']]
 for k,v in (log.get('Config') or {}).items():args+=['--log-opt',k+'='+v]
 for k,v in (config.get('Labels') or {}).items():
  if k!='org.opencontainers.image.revision':args+=['--label',k+'='+v]
 args += [image,*config['Cmd']]
 return subprocess.check_output(args,text=True).strip()
def healthy(name,port):
 for _ in range(25):
  if inspect(name)['State']['Running']:
   try:
    with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/',timeout=2) as r:
     assert r.status==200 and b'KB Music' in r.read()
    with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/manifest.json',timeout=2) as r:
     assert json.loads(r.read())['name']=='KB Music'
    with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/sw.js',timeout=2) as r:
     assert b'kb-music-v2-workflows' in r.read()
    return
   except Exception:pass
  time.sleep(1)
 raise RuntimeError('Health check failed for '+name)
canary='kb-music-web-workflow-canary-'+stamp
backup='kb-music-web-before-workflows-'+stamp
created=False;stopped=False;renamed=False;new_created=False
try:
 with socket.socket() as s:s.bind(('127.0.0.1',13300))
 create(canary,13300,loopback=True);created=True;docker('start',canary);healthy(canary,13300)
 print('Loopback canary passed: root, manifest and updated service worker',flush=True)
 docker('stop','--time','10',canary);docker('rm',canary);created=False
 assert inspect('kb-music-web')['Id']==EXPECTED,'Concurrent deployment before promotion'
 docker('stop','--time','15','kb-music-web');stopped=True
 docker('rename','kb-music-web',backup);renamed=True
 create('kb-music-web',3300,restart=host['RestartPolicy']['Name'] or 'no');new_created=True
 docker('start','kb-music-web');healthy('kb-music-web',3300)
 current=inspect('kb-music-web');assert current['Image']==image
 assert current['HostConfig']['Binds']==host['Binds']
 receipt={'previous_container':EXPECTED,'rollback_container':backup,'new_container':current['Id'],'image':image,'source_revision':built['revision'],'health':'pass','account_media_mounts':'unchanged','credentials':'unchanged','time_utc':stamp}
 Path('/tmp/kb-web-rollout-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print(json.dumps(receipt),flush=True)
except Exception:
 if new_created:
  subprocess.run(['docker','stop','--time','10','kb-music-web'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  subprocess.run(['docker','rm','kb-music-web'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 if renamed:docker('rename',backup,'kb-music-web')
 if stopped:docker('start','kb-music-web')
 raise
finally:
 if created:
  subprocess.run(['docker','stop','--time','10',canary],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  subprocess.run(['docker','rm',canary],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 for path in envpaths:path.unlink(missing_ok=True)
