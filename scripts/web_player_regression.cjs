#!/usr/bin/env node
// Runs the actual TSX PlayerProvider in an isolated React/audio harness.
// Usage: node kb-player-regression-tests.cjs path/to/player-context.tsx path/to/typescript.js
// No browser, server, account, network, media files, or application writes.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const sourcePath = process.argv[2];
if (!sourcePath) throw new Error('Supply the PlayerProvider TSX source path as the first argument');
const ts = require(process.argv[3] || 'typescript');
const code = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.React, target: ts.ScriptTarget.ES2020 }
}).outputText;
function fixture(options = {}) {
  const handlers = {};
  const mediaSession = {setActionHandler:(name,fn)=>{handlers[name]=fn;},setPositionState:()=>{}};
  const hooks = [], effects = [], timers = [];
  let index = 0, audio;
  const react = {
    createContext: () => ({Provider:'provider'}),
    createElement: (type, props) => ({type, props}),
    useContext: () => ({}),
    useState(initial) {
      const i = index++;
      if (!hooks[i]) hooks[i] = {value:initial};
      return [hooks[i].value, value => { hooks[i].value = typeof value === 'function' ? value(hooks[i].value) : value; }];
    },
    useRef(initial) {
      const i = index++;
      if (!hooks[i]) hooks[i] = {current:initial};
      return hooks[i];
    },
    useCallback(fn) { index++; return fn; },
    useEffect(fn, deps) {
      const i = index++, previous = hooks[i];
      if (!previous || deps.some((d,j) => d !== previous.deps[j])) {
        hooks[i] = {deps}; effects.push(fn);
      }
    }
  };
  react.default = react;
  class AudioStub {
    constructor() { this.listeners={}; this.paused=true; this.currentTime=0; audio=this; }
    addEventListener(name,fn) { this.listeners[name]=fn; }
    removeEventListener() {}
    play() { this.paused=false; this.listeners.play?.(); return Promise.resolve(); }
    pause() { this.paused=true; this.listeners.pause?.(); }
    end() { this.paused=true; this.listeners.ended?.(); }
  }
  const sandbox = {
    exports:{}, console, window:{}, navigator:options.mediaSession ? {mediaSession} : {}, Audio:AudioStub,
    MediaMetadata: class {constructor(data){Object.assign(this,data);}},
    setTimeout: fn => {timers.push(fn); return timers.length;},
    clearTimeout: id => {timers[id-1]=null;},
    require: name => {
      if (name === 'react') return react;
      if (name === './auth-context') return {useAuth:()=>({updatePresence:()=>{}})};
      throw new Error('Unexpected dependency: '+name);
    }
  };
  vm.runInNewContext(code,sandbox,{filename:sourcePath});
  function render() {
    index=0;
    const result=sandbox.exports.PlayerProvider({children:null}).props.value;
    effects.splice(0).forEach(fn=>fn());
    return result;
  }
  const tracks=['A','B','C','D'].map(id=>({id,title:id,artist:'Fixture',album:'Fixture',duration:60,coverUrl:'fixture',streamUrl:'fixture:'+id}));
  let p=render(); p.playTrack(tracks[0],tracks); p=render();
  return {render,tracks,handlers,shuffleTracks:sandbox.exports.shuffleTracks,get audio(){return audio;},timers,get player(){return p;}};
}

test('Explicit Next advances within the current album queue',()=>{
 const f=fixture(); f.player.nextTrack(); assert.equal(f.render().currentTrack.id,'B');
});
test('Natural track completion automatically starts the next queued track',()=>{
 const f=fixture(); f.audio.end(); assert.equal(f.render().currentTrack.id,'B');
});
test('Repeat one restarts the same track after completion',()=>{
 const f=fixture(); f.player.setRepeatMode('one'); f.render(); f.audio.end();
 assert.equal(f.audio.paused,false,'repeat-one must resume the audio element');
});
test('Selecting a queue row updates the cursor before Next',()=>{
 const f=fixture(); f.player.playTrack(f.tracks[2]); f.render().nextTrack();
 assert.equal(f.render().currentTrack.id,'D');
});
test('Canceling the sleep timer prevents its old timeout pausing playback',()=>{
 const f=fixture(); f.player.setSleepTimerDuration(1); f.render().setSleepTimerDuration(null); f.render();
 f.timers.filter(Boolean).forEach(fn=>fn());
 assert.equal(f.audio.paused,false,'canceled timer must not pause playback');
});
test('Favorite toggle updates current local player state',()=>{
 const f=fixture(); f.player.toggleLike('A'); assert.equal(f.render().currentTrack.isLiked,true);
});

test('Music system controls register track skip, not audiobook seek buttons',()=>{
 const f=fixture({mediaSession:true});
 assert.equal(typeof f.handlers.previoustrack,'function');
 assert.equal(typeof f.handlers.nexttrack,'function');
 assert.equal(f.handlers.seekbackward,null);
 assert.equal(f.handlers.seekforward,null);
});
test('Audiobooks retain contextual seek buttons',()=>{
 const f=fixture({mediaSession:true});
 f.player.playBook({id:'book',title:'Fixture book',author:'Fixture'}); f.render();
 assert.equal(typeof f.handlers.seekbackward,'function');
 assert.equal(typeof f.handlers.seekforward,'function');
});
test('Repeat all wraps to the first queue item',()=>{
 const f=fixture(); f.player.setRepeatMode('all'); f.render().playTrack(f.tracks[3]);
 f.render(); f.audio.end(); assert.equal(f.render().currentTrack.id,'A');
});
test('Previous restarts after threshold, then moves to previous queue item',()=>{
 const f=fixture(); f.player.nextTrack(); f.render(); f.audio.currentTime=5;
 f.render().previousTrack(); assert.equal(f.audio.currentTime,0);
 f.render().previousTrack(); assert.equal(f.render().currentTrack.id,'A');
});

test('Shuffle reorders upcoming tracks without changing current item or losing entries',()=>{
 const f=fixture(); const before=f.player.queue.map(t=>t.id); f.player.toggleShuffle(); const p=f.render();
 assert.equal(p.currentTrack.id,'A'); assert.equal(p.queueIndex,0); assert.equal(p.isShuffle,true);
 assert.notDeepEqual(Array.from(p.queue,t=>t.id),Array.from(before));
 assert.deepEqual(Array.from(p.queue,t=>t.id).sort(),['A','B','C','D']);
});
test('Disabling shuffle restores relative order of the remaining tracks',()=>{
 const f=fixture(); f.player.toggleShuffle(); f.render().toggleShuffle(); const p=f.render();
 assert.equal(p.isShuffle,false); assert.deepEqual(Array.from(p.queue,t=>t.id),['A','B','C','D']);
});
test('Repeated explicit album shuffle avoids replaying the identical order',()=>{
 const f=fixture(); f.player.shuffleAndPlay(f.tracks); const first=f.render();
 const ids=Array.from(first.queue,t=>t.id); first.shuffleAndPlay(f.tracks); const second=f.render();
 assert.notDeepEqual(Array.from(second.queue,t=>t.id),ids);
 assert.deepEqual(Array.from(second.queue,t=>t.id).sort(),['A','B','C','D']); assert.equal(second.isShuffle,true);
});
test('Shuffle is a permutation under deterministic random edge cases and handles short queues',()=>{
 const f=fixture(); const original=Array.from(f.tracks,t=>t.id);
 for (const rng of [()=>0,()=>0.999999]) {
  const result=f.shuffleTracks(f.tracks,original,rng);
  assert.notDeepEqual(Array.from(result,t=>t.id),original);
  assert.deepEqual(Array.from(result,t=>t.id).sort(),original);
 }
 assert.equal(f.shuffleTracks([]).length,0); assert.equal(f.shuffleTracks([f.tracks[0]])[0].id,'A');
});
