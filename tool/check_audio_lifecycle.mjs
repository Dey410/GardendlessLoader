import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(
  new URL('../assets/game_bridge/audio_lifecycle.js', import.meta.url),
  'utf8',
);

function run() {
  const calls = [];
  class AudioContext {
    constructor(options) {
      this.options = options;
      this.state = 'running';
      this.listeners = [];
    }
    addEventListener(type, listener) { this.listeners.push(listener); }
    resume() { calls.push('resume'); this.state = 'running'; return Promise.resolve(); }
    suspend() { calls.push('suspend'); this.state = 'suspended'; return Promise.resolve(); }
  }
  class HTMLMediaElement {
    constructor() { this.paused = true; }
    addEventListener() {}
    play() { calls.push('play'); this.paused = false; return Promise.resolve(); }
    pause() { calls.push('pause'); this.paused = true; }
  }
  const window = {AudioContext, webkitAudioContext: AudioContext, HTMLMediaElement};
  vm.runInNewContext(source, {window, Promise});
  return {window, calls, Base: AudioContext, Media: HTMLMediaElement};
}

const tick = () => new Promise(resolve => setImmediate(resolve));

{
  const {window, calls, Base, Media} = run();
  const context = new window.AudioContext({sampleRate: 32000});
  assert.ok(context instanceof Base, 'tracked contexts stay AudioContexts');
  assert.deepEqual(context.options, {sampleRate: 32000});
  assert.equal(window.webkitAudioContext, window.AudioContext);
  const element = new Media();
  await element.play();
  calls.length = 0;

  window.__gardendlessSetSceneActive(false);
  assert.deepEqual(calls, ['suspend', 'pause'], 'inactive suspends running audio');

  let resumed = false;
  context.resume().then(() => { resumed = true; });
  let played = false;
  element.play().then(() => { played = true; });
  await tick();
  assert.equal(resumed, false, 'resume waits while the scene is inactive');
  assert.equal(played, false, 'play waits while the scene is inactive');
  assert.deepEqual(calls, ['suspend', 'pause']);

  window.__gardendlessSetSceneActive(true);
  await tick();
  assert.equal(resumed, true);
  assert.equal(played, true);
  assert.equal(context.state, 'running');
  assert.equal(element.paused, false);
}

{
  const {window, calls} = run();
  const context = new window.AudioContext();
  context.state = 'suspended';
  window.__gardendlessSetSceneActive(false);
  window.__gardendlessSetSceneActive(true);
  await tick();
  assert.deepEqual(calls, [], 'audio the page left suspended stays suspended');
  await context.resume();
  assert.deepEqual(calls, ['resume'], 'resume runs at once while active');
}

console.log('audio_lifecycle.js checks passed');
