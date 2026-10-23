import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

// game_tip.js, pause_on_return.js and haptic_effects.js: what the loader
// says and does back to the player inside the game.
function read(name) {
  return fs.readFileSync(new URL(`../assets/game_bridge/${name}`, import.meta.url), 'utf8');
}

const sources = {
  tip: read('game_tip.js'),
  pause: read('pause_on_return.js'),
  haptics: read('haptic_effects.js'),
};

function createHarness({modules = new Map(), config = {}, pads = null} = {}) {
  const errors = [];
  const invoked = [];
  const timers = [];
  let now = 0;
  let nextTimerId = 1;
  const window = new EventTarget();
  window.System = {get: (id) => modules.get(id) ?? null, resolve: (id) => id};
  window.__gardendlessHost = {
    config,
    invoke(command, payload) {
      invoked.push([command, payload.kind, now]);
      return Promise.resolve(null);
    },
  };
  const document = new EventTarget();
  Object.assign(document, {hidden: false, readyState: 'complete'});
  const context = vm.createContext({
    window,
    document,
    navigator: pads ? {getGamepads: () => pads} : {},
    performance: {now: () => now},
    console: {error: (...args) => errors.push(args)},
    setTimeout(callback, delay = 0, ...args) {
      const id = nextTimerId++;
      timers.push({id, due: now + delay, callback, args});
      return id;
    },
    clearTimeout(id) {
      const index = timers.findIndex((timer) => timer.id === id);
      if (index >= 0) timers.splice(index, 1);
    },
  });
  return {
    window,
    document,
    errors,
    invoked,
    run(name) {
      vm.runInContext(sources[name], context);
    },
    advance(milliseconds) {
      const until = now + milliseconds;
      for (;;) {
        timers.sort((a, b) => a.due - b.due || a.id - b.id);
        const timer = timers[0];
        if (!timer || timer.due > until) break;
        timers.shift();
        now = timer.due;
        timer.callback(...timer.args);
      }
      now = until;
    },
    hide(hidden = true) {
      document.hidden = hidden;
      document.dispatchEvent(new Event('visibilitychange'));
    },
  };
}

// Tip bar ---------------------------------------------------------------

function tipModules({language = 'zh', bar = 'ready'} = {}) {
  const lines = [];
  const cp = bar === 'mismatch' ? {} : {
    gameTipString(text, seconds) {
      lines.push([text, seconds]);
    },
  };
  const KeyListener = {cp: bar === 'loading' ? undefined : cp};
  const MultiLanguage = {getString: (text) => text[language]};
  return {
    lines,
    modules: new Map([
      ['chunks:///_virtual/KeyListener.ts', {KeyListener}],
      ['chunks:///_virtual/MultiLanguage.ts', {MultiLanguage}],
    ]),
  };
}

// The line goes to the game's tip bar in the game's language.
for (const language of ['zh', 'en']) {
  const {lines, modules} = tipModules({language});
  const h = createHarness({modules});
  h.run('tip');
  assert.equal(h.window.__gardendlessGameTip.show({zh: '你好', en: 'Hello'}, 4), true);
  assert.deepEqual(lines, [[language === 'zh' ? '你好' : 'Hello', 4]]);
  assert.equal(h.errors.length, 0);
}

// Before the game has loaded its tip bar nothing is shown and nothing is
// wrong; a changed interface turns the helper off once.
{
  const loading = createHarness({modules: tipModules({bar: 'loading'}).modules});
  loading.run('tip');
  assert.equal(loading.window.__gardendlessGameTip.show({zh: '你好', en: 'Hello'}, 4), false);
  const empty = createHarness();
  empty.run('tip');
  assert.equal(empty.window.__gardendlessGameTip.show({zh: '你好', en: 'Hello'}, 4), false);
  assert.equal(loading.errors.length + empty.errors.length, 0);

  const mismatch = createHarness({modules: tipModules({bar: 'mismatch'}).modules});
  mismatch.run('tip');
  const tips = mismatch.window.__gardendlessGameTip;
  assert.equal(tips.show({zh: '你好', en: 'Hello'}, 4), false);
  assert.equal(tips.show({zh: '你好', en: 'Hello'}, 4), false);
  assert.equal(mismatch.errors.length, 1);
  assert.match(String(mismatch.errors[0][0]), /游戏提示条已停用/);
}

// Pause on return ---------------------------------------------------------

function pauseModules({paused = false, started = true, won = false, lost = false,
  active = true, pauseMenu = true} = {}) {
  const calls = [];
  const ui = {
    isValid: true,
    node: {activeInHierarchy: active},
    paused,
  };
  if (pauseMenu) {
    ui.pauseMenu = function () {
      calls.push('pauseMenu');
      this.paused = !this.paused;
    };
  }
  const LevelPlay = {gameStarted: started, component: {gameWon: won, gameLost: lost}};
  return {
    ui,
    calls,
    modules: new Map([
      ['chunks:///_virtual/UI.ts', {UIInGame: {component: ui}}],
      ['chunks:///_virtual/levelController.ts', {LevelPlay}],
    ]),
  };
}

// Hiding the page during play opens the level's pause menu once; coming back
// leaves it open.
{
  const {ui, calls, modules} = pauseModules();
  const h = createHarness({modules});
  h.run('pause');
  h.hide();
  assert.deepEqual(calls, ['pauseMenu']);
  assert.equal(ui.paused, true);
  h.hide(false);
  h.hide();
  assert.deepEqual(calls, ['pauseMenu'], 'an open pause menu is not toggled shut');
  assert.equal(h.errors.length, 0);
}

// No pause outside play: already paused, before the level starts, after it
// is won or lost, or outside a level.
for (const [state, why] of [
  [{paused: true}, 'already paused'],
  [{started: false}, 'before the level starts'],
  [{won: true}, 'after a win'],
  [{lost: true}, 'after a loss'],
  [{active: false}, 'outside a level'],
]) {
  const {calls, modules} = pauseModules(state);
  const h = createHarness({modules});
  h.run('pause');
  h.hide();
  assert.deepEqual(calls, [], why);
  assert.equal(h.errors.length, 0, why);
}

// A changed level interface is reported once.
{
  const {modules} = pauseModules({pauseMenu: false});
  const h = createHarness({modules});
  h.run('pause');
  h.hide();
  h.hide(false);
  h.hide();
  assert.equal(h.errors.length, 1);
  assert.match(String(h.errors[0][0]), /回来先暂停已停用/);
}

// Haptic effects ----------------------------------------------------------

const soundModuleId = 'chunks:///_virtual/SoundRescourses.ts';

function createSounds(names) {
  const played = [];
  const sounds = {};
  for (const name of names) {
    sounds[name] = function (...args) {
      played.push([name, this === sounds, args]);
      return `${name} played`;
    };
  }
  return {sounds, played};
}

const mapped = ['playRhythmHit', 'playReadyOrSet', 'playPlantFoodStart', 'playLetsRock',
  'playExplosion', 'playSpudow', 'playGargantuarAsh', 'playShipDestroySound', 'playAwooga',
  'playHugeWave', 'playFinalWave', 'playSandStormWarn', 'playZombossHPFillStart',
  'playLevelTaskComplete', 'playLevelTaskFail'];

function hapticHarness({enabled = true, names = mapped.concat(['playCardChosen']), pads = null,
  registered = true} = {}) {
  const {sounds, played} = createSounds(names);
  const modules = new Map(registered ? [[soundModuleId, {sounds}]] : []);
  const h = createHarness({modules, config: {hapticEffectsEnabled: enabled}, pads});
  h.run('haptics');
  return {h, sounds, played, modules};
}

// Turned off, the sound effects stay untouched.
{
  const {h, sounds} = hapticHarness({enabled: false});
  const original = sounds.playExplosion;
  h.advance(1000);
  assert.equal(sounds.playExplosion, original);
}

// Each mapped sound still plays as before and adds its haptic pattern;
// other sounds stay untouched.
{
  const {h, sounds, played} = hapticHarness();
  const untouched = sounds.playCardChosen;
  assert.equal(sounds.playExplosion('x'), 'playExplosion played');
  assert.deepEqual(played, [['playExplosion', true, ['x']]]);
  assert.deepEqual(h.invoked, [['host:haptic', 'heavy', 0]]);
  assert.equal(sounds.playCardChosen, untouched);

  const patterns = {};
  for (const name of mapped) {
    h.invoked.length = 0;
    h.advance(1000);
    sounds[name]();
    h.advance(1000);
    patterns[name] = h.invoked.map(([, kind, at]) => `${kind}@${at % 1000}`).join(' ');
  }
  assert.deepEqual(patterns, {
    playRhythmHit: 'selection@0',
    playReadyOrSet: 'selection@0',
    playPlantFoodStart: 'impact@0',
    playLetsRock: 'impact@0',
    playExplosion: 'heavy@0',
    playSpudow: 'heavy@0',
    playGargantuarAsh: 'heavy@0',
    playShipDestroySound: 'heavy@0',
    playAwooga: 'heavy@0 heavy@180',
    playHugeWave: 'heavy@0 heavy@180',
    playFinalWave: 'heavy@0 heavy@180',
    playSandStormWarn: 'heavy@0',
    playZombossHPFillStart: 'heavy@0 heavy@180',
    playLevelTaskComplete: 'impact@0 heavy@120',
    playLevelTaskFail: 'heavy@0 heavy@120 heavy@240',
  });
  assert.equal(h.errors.length, 0);
}

// A burst of explosions is felt once.
{
  const {h, sounds, played} = hapticHarness();
  sounds.playExplosion();
  h.advance(50);
  sounds.playGargantuarAsh();
  h.advance(60);
  sounds.playExplosion();
  assert.equal(played.length, 3, 'every sound still plays');
  assert.deepEqual(h.invoked.map(([, , at]) => at), [0, 110]);
}

// A controller that has given input rumbles instead of the device.
{
  const effects = [];
  const pad = {
    connected: true,
    vibrationActuator: {
      playEffect(type, params) {
        effects.push([type, params.duration, params.strongMagnitude, params.weakMagnitude]);
        return Promise.resolve('complete');
      },
    },
  };
  const {h, sounds} = hapticHarness({pads: [null, pad]});
  sounds.playExplosion();
  h.advance(1000);
  sounds.playRhythmHit();
  assert.deepEqual(effects, [['dual-rumble', 140, 1, 0.6], ['dual-rumble', 20, 0, 0.4]]);
  assert.deepEqual(h.invoked, []);

  const silent = hapticHarness({pads: [{connected: true}]});
  silent.sounds.playExplosion();
  assert.deepEqual(silent.h.invoked.map(([, kind]) => kind), ['heavy'],
    'a controller without a rumble motor leaves it to the device');
}

// The facade is read once the game has registered it; a missing facade or
// sound is reported once, and the sounds that exist still work.
{
  const late = hapticHarness({registered: false});
  const {sounds} = createSounds(mapped);
  const original = sounds.playExplosion;
  late.modules.set(soundModuleId, {sounds});
  late.h.advance(250);
  assert.notEqual(sounds.playExplosion, original, 'a late module is installed');

  const noFacade = createHarness({modules: new Map([[soundModuleId, {}]]),
    config: {hapticEffectsEnabled: true}});
  noFacade.run('haptics');
  assert.equal(noFacade.errors.length, 1);
  assert.match(String(noFacade.errors[0][0]), /触感音效已停用/);

  const partial = hapticHarness({names: mapped.filter((name) => name !== 'playSpudow')});
  assert.equal(partial.h.errors.length, 1);
  assert.match(String(partial.h.errors[0][0]), /playSpudow/);
  partial.sounds.playExplosion();
  assert.deepEqual(partial.h.invoked.map(([, kind]) => kind), ['heavy']);
}

// A failing haptic never breaks the sound: it plays, and haptics turn off.
{
  const {h, sounds, played} = hapticHarness();
  h.window.__gardendlessHost.invoke = () => {
    throw new Error('bridge gone');
  };
  assert.equal(sounds.playExplosion(), 'playExplosion played');
  h.advance(1000);
  assert.equal(sounds.playHugeWave(), 'playHugeWave played');
  assert.equal(played.length, 2);
  assert.equal(h.errors.length, 1);
}

console.log('game feedback contract passes');
