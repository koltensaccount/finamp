const fs = require('node:fs');
const vm = require('node:vm');
const {test} = require('node:test');
const assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[2], 'utf8');
function fixture({offline=false}={}) {
 const listeners={}, deleted=[], calls=[];
 const context={URL,Promise,
  self:{addEventListener:(name,fn)=>listeners[name]=fn,skipWaiting:()=>{},clients:{claim:()=>{}}},
  fetch:async()=>{calls.push('network');if(offline)throw new Error('offline');return 'fresh-network-html';},
  caches:{keys:async()=>['kb-music-v1','kb-music-v2-workflows','unrelated-cache'],delete:async name=>deleted.push(name),
   open:async()=>({match:async()=>{calls.push('cache');return 'offline-shell';},addAll:async()=>{}})}
 };
 vm.runInNewContext(source,context);
 return {listeners,deleted,calls};
}
test('Navigation uses fresh HTML ahead of cached HTML',async()=>{
 const f=fixture();let result;f.listeners.fetch({request:{url:'https://example.test/',method:'GET',mode:'navigate'},respondWith:p=>result=p});
 assert.equal(await result,'fresh-network-html');assert.deepEqual(f.calls,['network']);
});
test('Offline navigation falls back to the app shell',async()=>{
 const f=fixture({offline:true});let result;f.listeners.fetch({request:{url:'https://example.test/',method:'GET',mode:'navigate'},respondWith:p=>result=p});
 assert.equal(await result,'offline-shell');
});
test('Activation cleans only old KB Music caches',async()=>{
 const f=fixture();let done;f.listeners.activate({waitUntil:p=>done=p});await done;assert.deepEqual(f.deleted,['kb-music-v1']);
});
test('Media/API requests bypass shell caching',()=>{
 const f=fixture();for(const path of ['/api/books','/api/stream/music/fixture']){
  let intercepted=false;f.listeners.fetch({request:{url:'https://example.test'+path,method:'GET',mode:'cors'},respondWith:()=>intercepted=true});assert.equal(intercepted,false);
 }
});
