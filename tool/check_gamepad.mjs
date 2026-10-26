import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(
  new URL('../assets/game_bridge/gamepad.js', import.meta.url),
  'utf8',
);

// Standard mapping indexes.
const A = 0;
const B = 1;
const X = 2;
const Y = 3;
const LB = 4;
const RB = 5;
const LT = 6;
const RT = 7;
const START = 9;
const UP = 12;
const DOWN = 13;
const LEFT = 14;
const RIGHT = 15;

class TestMouseEvent extends Event {
  constructor(type, init = {}) {
    super(type, init);
    Object.assign(this, {
      clientX: init.clientX,
      clientY: init.clientY,
      button: init.button,
      buttons: init.buttons,
    });
  }
}

class TestWheelEvent extends Event {
  constructor(type, init = {}) {
    super(type, init);
    Object.assign(this, {deltaY: init.deltaY, clientX: init.clientX, clientY: init.clientY});
  }
}

function createPad() {
  return {
    connected: true,
    mapping: 'standard',
    axes: [0, 0, 0, 0],
    buttons: Array.from({length: 17}, () => ({pressed: false})),
  };
}

// A level with three seed packets. The engine hands every key event to the
// level's listeners; the card keys select a packet the way UIInGame.onKeyDown
// does.
function createLevel({selectable = [true, true, true]} = {}) {
  const KeyCode = {KEY_A: 65, KEY_D: 68, KEY_F: 70, KEY_Q: 81, KEY_S: 83, KEY_W: 87,
    KEY_X: 88, SPACE: 32, ALT_LEFT: 18};
  const KeyBinds = {Game_Shovel: 'KEY_D', Game_Plantfood: 'KEY_F', Game_Pause: 'SPACE',
    Rhythm_PhatBeet1: 'DIGIT_2', Rhythm_PhatBeet2: 'KEY_W', Rhythm_PhatBeet3: 'KEY_S',
    Rhythm_PhatBeet4: 'KEY_X', Rhythm_PhatBeet5: 'ALT_LEFT', AirRaid_W: 'KEY_W',
    AirRaid_S: 'KEY_S', AirRaid_A: 'KEY_A', AirRaid_D: 'KEY_D'};
  for (let card = 1; card <= 8; card++) {
    KeyCode[`DIGIT_${card}`] = 48 + card;
    KeyBinds[`Game_Card${card}`] = `DIGIT_${card}`;
  }
  const keys = [];
  const ui = {
    isValid: true,
    node: {activeInHierarchy: true},
    index: -1,
    cards: {CFs: selectable.map((value) => ({ca: {getSelectable: () => value}}))},
    onKeyDown(event) {
      keys.push(['down', event.keyCode, event.type]);
      const card = event.keyCode - 49;
      if (card >= 0 && card < this.cards.CFs.length) this.index = card;
    },
    onKeyUp(event) {
      keys.push(['up', event.keyCode, event.type]);
    },
  };
  const cc = {
    KeyCode,
    Input: {EventType: {KEY_DOWN: 'keydown', KEY_UP: 'keyup'}},
    EventKeyboard: class {
      constructor(keyCode, type) {
        this.keyCode = keyCode;
        this.type = type;
      }
    },
    input: {
      _eventKeyboardList: [],
      _dispatchOrPushEvent(event, list) {
        assert.equal(list, this._eventKeyboardList);
        if (event.type === 'keydown') ui.onKeyDown(event);
        else ui.onKeyUp(event);
      },
    },
  };
  const LevelPlay = {gaming: true, AirRaidProps: null, component: {rhythmGameProps: null}};
  return {ui, cc, KeyBinds, LevelPlay, keys};
}

function createHarness({pads = [createPad()], getGamepads = true, level = createLevel(),
  missing = []} = {}) {
  const errors = [];
  const events = [];
  const frames = new Map();
  let nextFrame = 1;
  let time = 0;
  let overlayOpen = false;
  const canvas = new EventTarget();
  Object.assign(canvas, {
    id: 'GameCanvas',
    isConnected: true,
    getBoundingClientRect: () => ({left: 0, top: 0, right: 1000, bottom: 600, width: 1000, height: 600}),
  });
  for (const type of ['mousemove', 'mousedown', 'mouseup']) {
    canvas.addEventListener(type, (event) => events.push(
      [type, Math.round(event.clientX), Math.round(event.clientY), event.button, event.buttons]));
  }
  canvas.addEventListener('wheel', (event) => events.push(['wheel', event.deltaY]));
  const overlay = {classList: {contains: (name) => name === 'gp-open' && overlayOpen}};
  const cursorNodes = [];
  const window = new EventTarget();
  const tips = [];
  let tipBarReady = true;
  window.__gardendlessGameTip = {
    show(text, seconds) {
      tips.push([text.zh, seconds, tipBarReady]);
      return tipBarReady;
    },
  };
  const document = new EventTarget();
  Object.assign(document, {
    hidden: false,
    body: {appendChild: (node) => cursorNodes.push(node)},
    getElementById: (id) => ({GameCanvas: canvas, 'gp-overlay': overlay})[id] ?? null,
    createElement: () => ({style: {}, innerHTML: ''}),
  });
  const modules = new Map([
    ['chunks:///_virtual/UI.ts', {UIInGame: {component: level.ui}}],
    ['chunks:///_virtual/KeyListener.ts', {KeyListener: {KeyBinds: level.KeyBinds}}],
    ['chunks:///_virtual/levelController.ts', {LevelPlay: level.LevelPlay}],
    ['cc', level.cc],
  ]);
  for (const id of missing) modules.delete(id);
  window.System = {get: (id) => modules.get(id) ?? null, resolve: (id) => id};
  const context = vm.createContext({
    window,
    document,
    navigator: getGamepads ? {getGamepads: () => pads} : {},
    console: {error: (...args) => errors.push(args)},
    MouseEvent: TestMouseEvent,
    WheelEvent: TestWheelEvent,
    requestAnimationFrame(callback) {
      frames.set(nextFrame, callback);
      return nextFrame++;
    },
    cancelAnimationFrame(id) {
      frames.delete(id);
    },
  });
  vm.runInContext(source, context);

  function frame(milliseconds = 100) {
    time += milliseconds;
    const pending = [...frames.values()];
    frames.clear();
    for (const callback of pending) callback(time);
  }

  function button(index, pressed) {
    for (const pad of pads) pad.buttons[index] = {pressed};
  }

  // A press seen on one frame and a release on the next.
  function tap(index) {
    button(index, true);
    frame();
    button(index, false);
    frame();
  }

  function cursor() {
    const node = cursorNodes[0];
    if (!node || node.style.display !== 'block') return null;
    const [, x, y] = /translate\(([-\d.]+)px,([-\d.]+)px\)/.exec(node.style.transform);
    return {x: Number(x) + 10, y: Number(y) + 10};
  }

  function dispatch(type, trusted) {
    const event = new Event(type);
    Object.defineProperty(event, 'isTrusted', {value: trusted});
    window.dispatchEvent(event);
  }

  return {
    pads,
    level,
    errors,
    events,
    frames,
    window,
    document,
    frame,
    button,
    tap,
    cursor,
    cursorScale: () => cursorNodes[0].style.scale,
    dispatch,
    tips,
    openGpNext() {
      overlayOpen = true;
    },
    setTipBarReady(ready) {
      tipBarReady = ready;
    },
    take() {
      return events.splice(0);
    },
  };
}

// Without the Gamepad API the script does nothing.
{
  const h = createHarness({getGamepads: false});
  assert.equal(h.frames.size, 0);
  h.window.dispatchEvent(new Event('gamepadconnected'));
  assert.equal(h.frames.size, 0, 'no polling without the Gamepad API');
}

// A connected controller is polled, but the cursor waits for its input.
{
  const h = createHarness();
  assert.equal(h.frames.size, 1, 'a controller connected at load is polled');
  h.frame();
  h.frame();
  assert.equal(h.cursor(), null);
  assert.deepEqual(h.take(), [], 'an idle controller sends nothing');
}

// The first controller input lists the buttons in the game's tip bar once,
// trying again on later frames until the game has loaded the bar.
{
  const h = createHarness();
  h.setTipBarReady(false);
  h.pads[0].axes[0] = 1;
  h.frame();
  h.frame();
  assert.equal(h.tips.length, 2, 'every frame tries while the bar is missing');
  h.setTipBarReady(true);
  h.frame();
  h.frame();
  h.pads[0].axes[0] = 0;
  h.dispatch('touchstart', true);
  h.tap(A);
  assert.equal(h.tips.length, 3, 'the buttons are listed once a session');
  assert.match(h.tips[2][0], /^手柄：A 点击/);
  assert.equal(h.tips[2][1], 6);
}

// The left stick shows the cursor at the centre of the canvas and moves it,
// a canvas width per second at full tilt, within the canvas.
{
  const h = createHarness();
  h.frame();
  h.pads[0].axes[0] = 1;
  h.frame();
  assert.deepEqual(h.cursor(), {x: 600, y: 300});
  assert.deepEqual(h.take(), [['mousemove', 500, 300, 0, 0], ['mousemove', 600, 300, 0, 0]],
    'showing moves the game pointer to the cursor first');
  h.pads[0].axes[0] = 0.6;
  h.frame();
  assert.deepEqual(h.cursor(), {x: 625, y: 300}, 'a partial tilt moves quadratically slower');
  h.pads[0].axes[0] = 0.15;
  h.take();
  h.frame();
  assert.deepEqual(h.take(), [], 'tilt inside the dead zone does not move');
  h.pads[0].axes = [1, 1, 0, 0];
  for (let i = 0; i < 20; i++) h.frame();
  assert.deepEqual(h.cursor(), {x: 999, y: 599}, 'the cursor stays on the canvas');
  h.pads[0].axes = [-1, 0, 0, 0];
  h.frame();
  assert.deepEqual(h.cursor(), {x: 899, y: 599});
  h.pads[0].axes = [0, 0, 0, 0];
  h.button(RIGHT, true);
  h.frame();
  assert.deepEqual(h.cursor(), {x: 919, y: 599}, 'the D-pad nudges at a fifth of full tilt');
}

// A and B hold the left and right buttons; holding A drags. The dot shrinks
// while a button is held.
{
  const h = createHarness();
  h.button(A, true);
  h.frame();
  assert.deepEqual(h.take(), [['mousemove', 500, 300, 0, 0], ['mousedown', 500, 300, 0, 1]]);
  assert.equal(h.cursorScale(), '0.8');
  h.pads[0].axes[0] = 1;
  h.frame();
  h.pads[0].axes[0] = 0;
  h.button(A, false);
  h.frame();
  assert.deepEqual(h.take(), [['mousemove', 600, 300, 0, 1], ['mouseup', 600, 300, 0, 0]]);
  assert.equal(h.cursorScale(), '1');
  h.tap(B);
  assert.deepEqual(h.take(), [['mousedown', 600, 300, 2, 2], ['mouseup', 600, 300, 2, 0]]);
}

// The right stick turns the wheel: a notch as it tips, then ten a second at
// full tilt, starting over each time it returns to centre.
{
  const h = createHarness();
  h.frame();
  h.pads[0].axes[3] = 1;
  h.frame();
  h.frame();
  h.frame();
  h.pads[0].axes[3] = 0;
  h.frame();
  h.pads[0].axes[3] = -1;
  h.frame();
  h.pads[0].axes[3] = 0;
  h.frame();
  assert.deepEqual(h.take().filter(([type]) => type === 'wheel'),
    [['wheel', 100], ['wheel', 100], ['wheel', 100], ['wheel', -100]]);
}

// Touch and real mouse input hide the cursor; the controller brings it back
// and moves the game pointer back to it. Synthetic events keep it.
{
  const h = createHarness();
  h.pads[0].axes[0] = 1;
  h.frame();
  h.frame();
  h.pads[0].axes[0] = 0;
  h.dispatch('mousemove', false);
  assert.deepEqual(h.cursor(), {x: 600, y: 300}, 'synthetic mouse events keep the cursor');
  for (const type of ['touchstart', 'mousedown', 'mousemove']) {
    h.dispatch(type, true);
    assert.equal(h.cursor(), null, `a real ${type} hides the cursor`);
    h.take();
    h.tap(A);
    assert.deepEqual(h.cursor(), {x: 600, y: 300});
    assert.deepEqual(h.take().slice(0, 2), [['mousemove', 600, 300, 0, 0], ['mousedown', 600, 300, 0, 1]]);
  }
}

// An open GP-Next panel releases the buttons, hides the cursor and ignores
// the controller.
{
  const h = createHarness();
  h.button(A, true);
  h.frame();
  h.take();
  h.openGpNext();
  h.frame();
  assert.deepEqual(h.take(), [['mouseup', 500, 300, 0, 0]]);
  assert.equal(h.cursor(), null);
  h.pads[0].axes[0] = 1;
  h.tap(B);
  assert.deepEqual(h.take(), []);
}

// Leaving the window releases a held button.
{
  const h = createHarness();
  h.button(A, true);
  h.frame();
  h.take();
  h.window.dispatchEvent(new Event('blur'));
  assert.deepEqual(h.take(), [['mouseup', 500, 300, 0, 0]]);
}

// A disconnected controller releases its buttons and stops the polling; the
// next connection starts it again.
{
  const h = createHarness();
  h.button(A, true);
  h.frame();
  h.take();
  h.pads.length = 0;
  h.frame();
  assert.deepEqual(h.take(), [['mouseup', 500, 300, 0, 0]]);
  assert.equal(h.cursor(), null);
  assert.equal(h.frames.size, 0, 'polling stops without a controller');
  h.window.dispatchEvent(new Event('gamepadconnected'));
  assert.equal(h.frames.size, 1);
}

// In a level, X, Y and Start send the player's shovel, plant food and pause
// keys to the level's key handler.
{
  const level = createLevel();
  level.KeyBinds.Game_Shovel = 'KEY_Q';
  const h = createHarness({level});
  h.tap(X);
  h.tap(Y);
  h.tap(START);
  assert.deepEqual(level.keys, [
    ['down', 81, 'keydown'], ['up', 81, 'keyup'],
    ['down', 70, 'keydown'], ['up', 70, 'keyup'],
    ['down', 32, 'keydown'], ['up', 32, 'keyup'],
  ]);
  assert.equal(h.errors.length, 0);
}

// LB and RB step through the packets the level would hand out now, never to
// the packet already in hand.
{
  const level = createLevel({selectable: [true, false, true]});
  const h = createHarness({level});
  const steps = [];
  for (const index of [RB, RB, RB, LB, LB]) {
    h.tap(index);
    steps.push(level.ui.index);
  }
  assert.deepEqual(steps, [0, 2, 0, 2, 0], 'unselectable packets are skipped');
  level.ui.index = -2;
  h.tap(LB);
  assert.equal(level.ui.index, 2, 'from a tool, LB starts at the last packet');

  const lone = createLevel({selectable: [true, false]});
  const loneH = createHarness({level: lone});
  loneH.tap(RB);
  loneH.tap(RB);
  assert.equal(lone.ui.index, 0);
  assert.deepEqual(lone.keys.filter(([kind]) => kind === 'down'), [['down', 49, 'keydown']],
    'the packet in hand is not sent again');

  const broke = createLevel({selectable: [false, false]});
  const brokeH = createHarness({level: broke});
  brokeH.tap(RB);
  assert.deepEqual(broke.keys, [], 'nothing is sent when no packet can be taken');
}

// Rhythm: while a rhythm level plays, each row of buttons holds its lane's
// key through the engine, top to bottom, for as long as any button of the
// row is down. The cursor hides, A and B no longer click, X and Y take no
// tools, and Start still pauses.
{
  const level = createLevel();
  level.LevelPlay.component.rhythmGameProps = {};
  const h = createHarness({level});
  const lanes = () => level.keys.splice(0).map(([kind, code]) => `${kind} ${code}`);
  h.button(LB, true);
  h.frame();
  h.frame();
  assert.deepEqual(lanes(), ['down 50'], 'LB holds lane 1 once');
  assert.equal(h.cursor(), null, 'a rhythm level shows no cursor');
  h.button(LB, false);
  h.frame();
  assert.deepEqual(lanes(), ['up 50']);

  h.button(LEFT, true);
  h.frame();
  h.button(B, true);
  h.frame();
  h.button(LEFT, false);
  h.frame();
  assert.deepEqual(lanes(), ['down 83'], 'lane 3 stays held while B is down');
  h.button(B, false);
  h.frame();
  assert.deepEqual(lanes(), ['up 83']);

  for (const [index, code] of [[RB, 50], [Y, 87], [UP, 87], [X, 83], [RIGHT, 83],
    [A, 88], [DOWN, 88], [LT, 18], [RT, 18]]) {
    h.tap(index);
    assert.deepEqual(lanes(), [`down ${code}`, `up ${code}`], `button ${index}`);
  }
  assert.deepEqual(h.take().filter(([type]) => type !== 'mousemove'), [],
    'no button clicks in a rhythm level');

  h.tap(START);
  assert.deepEqual(lanes(), ['down 32', 'up 32'], 'Start pauses');
  assert.deepEqual(h.tips.map(([text]) => text.split('：')[0]), ['手柄', '节奏关从上到下五路'],
    'the first rhythm level lists the lanes');

  // Pausing hands the controller back to the cursor and lets go of lanes.
  h.button(DOWN, true);
  h.frame();
  level.ui.paused = true;
  h.frame();
  assert.deepEqual(lanes(), ['down 88', 'up 88']);
  assert.notEqual(h.cursor(), null);
  h.button(DOWN, false);
  h.tap(A);
  assert.deepEqual(h.take().filter(([type]) => type !== 'mousemove').map(([type]) => type),
    ['mousedown', 'mouseup'], 'the pause menu takes clicks');
  assert.equal(h.errors.length, 0);
}

// Air Raid: while the plane follows the mouse, the stick flies it through a
// hidden cursor and the D-pad moves at full speed. Once the plane takes
// keys, the stick and D-pad hold W/A/S/D and the cursor stays put.
{
  const level = createLevel();
  level.LevelPlay.AirRaidProps = {mouse_binded: true};
  const h = createHarness({level});
  h.pads[0].axes[0] = 1;
  h.frame();
  h.frame();
  assert.equal(h.cursor(), null, 'the plane is the pointer');
  assert.deepEqual(h.take().at(-1), ['mousemove', 600, 300, 0, 0]);
  h.pads[0].axes[0] = 0;
  h.button(RIGHT, true);
  h.frame();
  h.button(RIGHT, false);
  assert.deepEqual(h.take().at(-1), ['mousemove', 700, 300, 0, 0], 'the D-pad flies at full speed');

  level.LevelPlay.AirRaidProps.mouse_binded = false;
  const steer = () => level.keys.splice(0).map(([kind, code]) => `${kind} ${code}`);
  h.pads[0].axes = [-1, 0, 0, 0];
  h.frame();
  h.frame();
  assert.deepEqual(steer(), ['down 65'], 'the stick holds A');
  h.pads[0].axes = [0.8, -0.8, 0, 0];
  h.frame();
  assert.deepEqual(steer(), ['down 87', 'up 65', 'down 68'], 'a diagonal holds two keys');
  h.pads[0].axes = [0.3, 0, 0, 0];
  h.frame();
  assert.deepEqual(steer(), ['up 87', 'up 68'], 'a small tilt holds nothing');
  h.button(DOWN, true);
  h.frame();
  assert.deepEqual(steer(), ['down 83'], 'the D-pad holds keys too');
  assert.deepEqual(h.take().filter(([type]) => type === 'mousemove'), [],
    'the cursor stays put while the plane takes keys');
  assert.notEqual(h.cursor(), null);

  level.LevelPlay.AirRaidProps.mouse_binded = true;
  h.frame();
  assert.deepEqual(steer(), ['up 83'], 'switching back lets go of the keys');
  assert.equal(h.errors.length, 0);
}

// Outside a level the shortcut buttons do nothing.
{
  const level = createLevel();
  level.ui.node.activeInHierarchy = false;
  const h = createHarness({level});
  h.tap(X);
  h.tap(RB);
  assert.deepEqual(level.keys, []);
  assert.equal(h.errors.length, 0);
}

// Missing level interfaces turn the shortcuts off once; the cursor and the
// mouse buttons keep working.
{
  const h = createHarness({missing: ['chunks:///_virtual/KeyListener.ts']});
  h.tap(X);
  h.tap(Y);
  assert.equal(h.errors.length, 1);
  assert.match(String(h.errors[0][0]), /手柄快捷键已停用/);
  h.take();
  h.tap(A);
  assert.deepEqual(h.take(), [['mousedown', 500, 300, 0, 1], ['mouseup', 500, 300, 0, 0]]);
}

console.log('gamepad contract passes');
