import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(
  new URL('../assets/game_bridge/native_gestures.js', import.meta.url),
  'utf8',
);

// The model uses one coordinate space for the DOM and the game UI. Tiles are
// 100 x 100 units, the lawn starts at x = 100 and spans rows 0-4 and columns
// 0-8, and the seed bank sits above it at y < 0.
function rect(x, y, width, height) {
  return {x, y, width, height};
}

function createNode({area = null, active = true, components = new Map()} = {}) {
  const node = {
    isValid: true,
    activeInHierarchy: active,
    parent: null,
    children: [],
    emitted: [],
    getComponent(key) {
      if (key === 'cc.UITransform') return area ? {width: area.width, height: area.height, area} : null;
      return components.get(key) ?? null;
    },
    emit(type, event) {
      this.emitted.push([type, event.getButton()]);
    },
    getChildByName(name) {
      return this.children.find((child) => child.name === name) ?? null;
    },
    getComponentsInChildren(type) {
      const own = components.get(type);
      return (own ? [own] : []).concat(...this.children.map((child) => child.getComponentsInChildren(type)));
    },
    getComponentInChildren(type) {
      return this.getComponentsInChildren(type)[0] ?? null;
    },
    getSiblingIndex() {
      return this.parent ? this.parent.children.indexOf(this) : 0;
    },
  };
  return node;
}

function attach(parent, child, name) {
  child.parent = parent;
  child.name = name;
  parent.children.push(child);
  return child;
}

function createGame({occupied = []} = {}) {
  const tiles = new Map();
  let pointer = {x: 0, y: 0};
  const Mouse = {
    get position() {
      return {...pointer};
    },
    get positionOrg() {
      return {...pointer};
    },
    judgeInUITransform(transform) {
      const r = transform.area;
      return pointer.x >= r.x && pointer.x < r.x + r.width &&
        pointer.y >= r.y && pointer.y < r.y + r.height;
    },
  };
  const Square = {
    judgeLIndex: (y) => (y < 0 ? -1 : Math.min(5, Math.floor(y / 100))),
    judgeCIndex: (x) => (x < 100 ? -1 : Math.min(9, Math.floor((x - 100) / 100))),
    getLnC(l, c) {
      const key = `${l},${c}`;
      if (!tiles.has(key)) {
        tiles.set(key, {
          lIndex: l,
          cIndex: c,
          downs: [],
          reacts: [],
          plants: 0,
          isInLawn() {
            return l >= 0 && l <= 4 && c >= 0 && c <= 8;
          },
          getAllPlants() {
            return new Array(this.plants).fill('plant');
          },
          onMouseDown(event, fromUi) {
            this.downs.push({button: event.getButton(), fromUi});
            if (!occupied.includes(key)) ui.index = -1;
          },
          plantMouseReact(event) {
            this.reacts.push(event.getButton());
          },
        });
      }
      return tiles.get(key);
    },
  };
  const calls = [];
  function UIInGame() {}
  UIInGame.prototype.tryChangingIndex = function (index) {
    calls.push(['tryChangingIndex', index]);
    this.index = this.index === index ? -1 : index;
  };
  UIInGame.prototype.onMouseUp = function () {
    calls.push(['onMouseUp']);
  };
  const ui = new UIInGame();
  ui.index = -1;
  ui.paused = false;
  UIInGame.component = ui;
  const LevelPlay = {sandBoxModeOn: false, gameStarted: true, component: {}};
  const bankNode = createNode({area: rect(100, -100, 400, 100)});
  const Cards = {component: {uitransform: {}, node: bankNode}};
  const SandBoxZombieCards = {component: null};
  function CardDeck() {}
  function ArcadeDecodingPlants() {}

  // ScrollViewWithoutTouchevent overrides the four ScrollView touch
  // handlers with empty functions.
  const scrolled = [];
  function ScrollView() {}
  for (const name of ['_onTouchBegan', '_onTouchMoved', '_onTouchEnded', '_onTouchCancelled']) {
    ScrollView.prototype[name] = function () {
      scrolled.push(name);
    };
  }
  function ScrollViewWithoutTouchevent() {}
  ScrollViewWithoutTouchevent.prototype = Object.create(ScrollView.prototype);
  for (const name of ['_onTouchBegan', '_onTouchMoved', '_onTouchEnded', '_onTouchCancelled']) {
    ScrollViewWithoutTouchevent.prototype[name] = function () {};
  }

  const sceneComponents = new Map();
  class Button {}
  const cc = {
    Button,
    ScrollView,
    KeyCode: {TAB: 9, F5: 116, F7: 118},
    EventKeyboard: class {
      constructor(keyCode, type) {
        this.keyCode = keyCode;
        this.type = type;
      }
    },
    EventMouse: class {
      constructor(type) {
        this.type = type;
        this.button = 0;
      }

      setButton(button) {
        this.button = button;
      }

      getButton() {
        return this.button;
      }
    },
    Input: {EventType: {MOUSE_DOWN: 'mouse-down', KEY_DOWN: 'keydown', KEY_UP: 'keyup'}},
    Node: {EventType: {MOUSE_DOWN: 'mouse-down'}},
    director: {
      getScene: () => ({
        getComponentsInChildren: (type) => sceneComponents.get(type) ?? [],
      }),
    },
  };
  const zenGardenScene = {component: undefined};
  const KeyListener = {KeyBinds: {Sandbox_TimeFreeze: 'F5', Sandbox_SwitchMusic: 'F7',
    Sandbox_ChangeJam: 'TAB'}};
  const keys = [];
  UIInGame.prototype.onKeyDown = function (event) {
    keys.push(['down', event.keyCode, this.sandBoxSettingWindow ? 'open' : 'closed']);
  };
  UIInGame.prototype.onKeyUp = function (event) {
    keys.push(['up', event.keyCode]);
  };
  UIInGame.prototype.showSBSettings = function () {
    calls.push(['showSBSettings']);
    this.sandBoxSettingWindow = this.sandBoxSettingWindow ? null : this.sandboxMenu;
  };
  return {
    KeyListener,
    keys,
    Mouse,
    Square,
    UIInGame,
    LevelPlay,
    Cards,
    SandBoxZombieCards,
    CardDeck,
    ArcadeDecodingPlants,
    ScrollViewWithoutTouchevent,
    zenGardenScene,
    cc,
    sceneComponents,
    scrolled,
    bankNode,
    ui,
    calls,
    tile: (l, c) => Square.getLnC(l, c),
    get pointer() {
      return {...pointer};
    },
    pointAt(x, y) {
      pointer = {x, y};
    },
  };
}

function createGarden() {
  return {
    node: {isValid: true, activeInHierarchy: true},
    pressed: false,
    isShoveling: false,
    isGloving: false,
    isCarting: false,
    willMovePlantSlot: null,
  };
}

class TestMouseEvent extends Event {
  constructor(type, {button = 0, clientX = 0, clientY = 0} = {}) {
    super(type);
    Object.assign(this, {button, clientX, clientY, screenX: clientX, screenY: clientY});
  }
}

class TestWheelEvent extends Event {
  constructor(type, {deltaY = 0, deltaMode = 0, clientX = 0, clientY = 0, ...init} = {}) {
    super(type, init);
    Object.assign(this, {deltaY, deltaMode, clientX, clientY});
  }
}

function createHarness({
  mode = 'native',
  modulesRegistered = true,
  missing = [],
  occupied = [],
} = {}) {
  const game = createGame({occupied});
  const timers = [];
  const errors = [];
  let now = 0;
  let nextTimerId = 1;
  let registered = modulesRegistered;
  const exports = {
    ui: ['chunks:///_virtual/UI.ts', {UIInGame: game.UIInGame}],
    square: ['chunks:///_virtual/Square.ts', {Square: game.Square}],
    mouse: ['chunks:///_virtual/Mouse.ts', {Mouse: game.Mouse}],
    level: ['chunks:///_virtual/levelController.ts', {LevelPlay: game.LevelPlay}],
    cards: ['chunks:///_virtual/Cards.ts', {Cards: game.Cards}],
    zombieCards: ['chunks:///_virtual/SandBoxZombieCards.ts',
      {SandBoxZombieCards: game.SandBoxZombieCards}],
    cardDeck: ['chunks:///_virtual/CardDeck.ts', {CardDeck: game.CardDeck}],
    decoding: ['chunks:///_virtual/ArcadeDecodingPlants.ts',
      {ArcadeDecodingPlants: game.ArcadeDecodingPlants}],
    settingsList: ['chunks:///_virtual/ScrollViewWithoutTouchevent.ts',
      {ScrollViewWithoutTouchevent: game.ScrollViewWithoutTouchevent}],
    zenGarden: ['chunks:///_virtual/zenGardenScene.ts',
      {zenGardenScene: game.zenGardenScene}],
    keys: ['chunks:///_virtual/KeyListener.ts', {KeyListener: game.KeyListener}],
  };
  const modules = new Map(Object.entries(exports)
    .map(([key, [id, value]]) => [id, missing.includes(key) ? {} : value]));
  const canvas = new EventTarget();
  const wheel = [];
  canvas.addEventListener('wheel', (event) => wheel.push(event.deltaY));
  const window = new EventTarget();
  window.__gardendlessHostConfig = {platform: 'ios', touchGestureMode: mode};
  window.System = {
    get: (id) => {
      if (!registered) return null;
      if (id === 'cc') return missing.includes('cc') ? null : game.cc;
      return modules.get(id) ?? null;
    },
    resolve: (id) => id,
    import: () => {
      throw new Error('native_gestures.js must not import game modules');
    },
  };
  const document = new EventTarget();
  Object.assign(document, {
    readyState: 'complete',
    hidden: false,
    getElementById: (id) => (id === 'GameCanvas' ? canvas : null),
  });
  const context = vm.createContext({
    window,
    document,
    console: {error: (...args) => errors.push(args)},
    Event,
    WheelEvent: TestWheelEvent,
    Set,
    Map,
    WeakMap,
    Error,
    Math,
    Object,
    setTimeout(callback, delay = 0) {
      const id = nextTimerId++;
      timers.push({id, due: now + delay, callback});
      return id;
    },
    clearTimeout(id) {
      const index = timers.findIndex((timer) => timer.id === id);
      if (index >= 0) timers.splice(index, 1);
    },
  });
  vm.runInContext(source, context);

  function advance(milliseconds) {
    const until = now + milliseconds;
    for (;;) {
      timers.sort((a, b) => a.due - b.due || a.id - b.id);
      const timer = timers[0];
      if (!timer || timer.due > until) break;
      timers.shift();
      now = Math.max(now, timer.due);
      timer.callback();
    }
    now = until;
  }

  function fire(type, button = 0) {
    const {x, y} = game.pointer;
    window.dispatchEvent(new TestMouseEvent(type, {button, clientX: x, clientY: y}));
  }

  // Cocos dispatches canvas mouse events synchronously: the window capture
  // listener runs first, then the game's own handlers inside the same task.
  function press(handlers = () => {}, button = 0) {
    fire('mousedown', button);
    handlers();
    advance(0);
  }

  function move(x, y) {
    game.pointAt(x, y);
    fire('mousemove');
    advance(0);
  }

  function release(button = 0) {
    fire('mouseup', button);
    game.ui.onMouseUp({getButton: () => button});
    advance(0);
  }

  return {
    game,
    errors,
    timers,
    wheel,
    window,
    document,
    advance,
    press,
    move,
    release,
    register() {
      registered = true;
    },
    rerun() {
      vm.runInContext(source, context);
    },
  };
}

function pickUp(h, index) {
  h.press(() => h.game.ui.tryChangingIndex(index));
}

function cancels(h) {
  return h.game.calls.filter(
    ([name, index]) => name === 'tryChangingIndex' && index === -1,
  ).length;
}

// The simulated gesture mode leaves the game untouched.
{
  const h = createHarness({mode: 'simulated'});
  const garden = createGarden();
  h.game.zenGardenScene.component = garden;
  const originalUp = h.game.UIInGame.prototype.onMouseUp;
  const originalBegan = h.game.ScrollViewWithoutTouchevent.prototype._onTouchBegan;
  h.game.pointAt(450, -50);
  pickUp(h, 0);
  h.game.pointAt(450, 250);
  h.release();
  assert.equal(h.game.UIInGame.prototype.onMouseUp, originalUp);
  assert.equal(h.game.ScrollViewWithoutTouchevent.prototype._onTouchBegan, originalBegan);
  assert.equal(h.game.tile(2, 3).downs.length, 0);
  assert.equal(garden.pressed, false);
  assert.equal(h.timers.length, 0, 'simulated mode must not poll game modules');
}

// Drop: seed packet, shovel and plant food are applied to the release tile.
for (const index of [0, 8, -2, -3]) {
  const h = createHarness();
  h.game.pointAt(450, -50);
  pickUp(h, index);
  h.move(450, 250);
  h.release();
  assert.deepEqual(h.game.tile(2, 3).downs, [{button: 0, fromUi: true}],
    `a drag must apply tool ${index} to the release tile`);
  assert.equal(h.game.ui.index, -1);
  assert.equal(cancels(h), 0, 'a used drop must not also put the tool back');
  assert.equal(h.errors.length, 0);
}

// Drop: the release tile comes from Mouse.position at release time.
{
  const h = createHarness();
  h.game.pointAt(150, -50);
  pickUp(h, 1);
  h.game.pointAt(850, 450);
  h.release();
  assert.equal(h.game.tile(4, 7).downs.length, 1);
}

// Drop: a refused drop, or a drop off the lawn, puts the tool back.
{
  const refused = createHarness({occupied: ['2,3']});
  refused.game.pointAt(450, -50);
  pickUp(refused, 0);
  refused.game.pointAt(450, 250);
  refused.release();
  assert.equal(refused.game.tile(2, 3).downs.length, 1);
  assert.equal(refused.game.ui.index, -1, 'a refused drop must put the tool back');
  assert.equal(cancels(refused), 1);

  const offLawn = createHarness();
  offLawn.game.pointAt(450, -50);
  pickUp(offLawn, -2);
  offLawn.game.pointAt(50, 250);
  offLawn.release();
  assert.equal(offLawn.game.ui.index, -1, 'a drop off the lawn must put the tool back');
  assert.equal(cancels(offLawn), 1);
}

// Drop: taps keep the tool in hand.
{
  const card = createHarness();
  card.game.pointAt(450, -50);
  pickUp(card, 0);
  card.game.pointAt(460, -45);
  card.release();
  assert.equal(card.game.ui.index, 0, 'a tap on a seed packet keeps it in hand');
  assert.equal(cancels(card), 0);
  card.game.pointAt(450, 250);
  card.press(() => card.game.tile(2, 3).onMouseDown({getButton: () => 0}, true));
  card.release();
  assert.equal(card.game.tile(2, 3).downs.length, 1, 'tap planting must plant once');

  const lawn = createHarness();
  lawn.game.pointAt(450, 250);
  pickUp(lawn, 2);
  lawn.release();
  assert.equal(lawn.game.tile(2, 3).downs.length, 0);
  assert.equal(lawn.game.ui.index, 2);
}

// Drop: keyboard selection, other hand modes, pause, right button and a hand
// changed during the drag keep the game's own behavior.
{
  const keyboard = createHarness();
  keyboard.game.pointAt(450, -50);
  keyboard.game.ui.tryChangingIndex(3);
  keyboard.game.pointAt(450, 250);
  keyboard.release();
  assert.equal(keyboard.game.ui.index, 3);

  for (const index of [-5]) {
    const h = createHarness();
    h.game.pointAt(450, -50);
    pickUp(h, index);
    h.game.pointAt(450, 250);
    h.release();
    assert.equal(h.game.tile(2, 3).downs.length, 0, `tool ${index} must not drop`);
    assert.equal(h.game.ui.index, index);
  }

  const paused = createHarness();
  paused.game.pointAt(450, -50);
  pickUp(paused, 0);
  paused.game.ui.paused = true;
  paused.game.pointAt(50, 250);
  paused.release();
  assert.equal(paused.game.ui.index, 0);

  const rightButton = createHarness();
  rightButton.game.pointAt(450, -50);
  pickUp(rightButton, 0);
  rightButton.game.pointAt(450, 250);
  rightButton.release(2);
  assert.equal(rightButton.game.tile(2, 3).downs.length, 0);
  assert.equal(cancels(rightButton), 0);

  const changed = createHarness();
  changed.game.pointAt(450, -50);
  pickUp(changed, 0);
  changed.game.ui.tryChangingIndex(1);
  changed.game.pointAt(450, 250);
  changed.release();
  assert.equal(changed.game.tile(2, 3).downs.length, 0);
  assert.equal(changed.game.ui.index, 1);

  const lost = createHarness();
  lost.game.pointAt(450, -50);
  pickUp(lost, 0);
  lost.press();
  lost.game.pointAt(450, 250);
  lost.release();
  assert.equal(lost.game.tile(2, 3).downs.length, 0,
    'a pickup whose release never arrived is dropped by the next press');
}

// Drop: sniper aiming and sandbox zombie cards drop on another tile; a
// release where the sniper was pressed keeps aiming.
{
  const sniper = createHarness();
  sniper.game.pointAt(450, 250);
  pickUp(sniper, -4);
  sniper.move(650, 250);
  sniper.release();
  assert.deepEqual(sniper.game.tile(2, 5).downs, [{button: 0, fromUi: true}],
    'dragging from the sniper must fire at the release tile');

  const aiming = createHarness();
  aiming.game.pointAt(450, 250);
  pickUp(aiming, -4);
  aiming.release();
  assert.equal(aiming.game.ui.index, -4, 'a tap on the sniper keeps aiming');

  const zombie = createHarness();
  zombie.game.pointAt(450, -50);
  pickUp(zombie, 9);
  zombie.move(450, 250);
  zombie.release();
  assert.equal(zombie.game.tile(2, 3).downs.length, 1, 'a zombie card drops on the lawn');
}

// Decoding minigame: a picked card drops on another slot through the slot's
// own left-press handler; an unused drag releases it; a tap keeps it.
{
  function decodingHarness() {
    const h = createHarness();
    const source = {node: createNode({area: rect(100, 400, 80, 80)})};
    const slotA = {node: createNode({area: rect(300, 100, 80, 80)})};
    const slotB = {node: createNode({area: rect(400, 100, 80, 80)})};
    const decoding = {
      node: {activeInHierarchy: true},
      confirming: false,
      PickedCard: null,
      MergedCards: [slotA, slotB],
      released: 0,
      ReleaseCard() {
        this.released += 1;
        this.PickedCard = null;
      },
    };
    h.game.sceneComponents.set(h.game.ArcadeDecodingPlants, [decoding]);
    return {h, source, slotA, slotB, decoding};
  }

  const drop = decodingHarness();
  drop.h.game.pointAt(140, 440);
  drop.h.press(() => {
    drop.decoding.PickedCard = drop.source;
  });
  drop.h.move(420, 120);
  drop.h.release();
  assert.deepEqual(drop.slotB.node.emitted, [['mouse-down', 0]],
    'a drop on a slot must press that slot');
  assert.equal(drop.decoding.released, 0);

  const away = decodingHarness();
  away.h.game.pointAt(140, 440);
  away.h.press(() => {
    away.decoding.PickedCard = away.source;
  });
  away.h.move(700, 700);
  away.h.release();
  assert.equal(away.decoding.released, 1, 'an unused drag releases the card');

  const tap = decodingHarness();
  tap.h.game.pointAt(140, 440);
  tap.h.press(() => {
    tap.decoding.PickedCard = tap.source;
  });
  tap.h.release();
  assert.equal(tap.decoding.released, 0, 'a tap keeps the card picked');
  assert.deepEqual(tap.slotA.node.emitted, []);

  const swap = decodingHarness();
  swap.decoding.PickedCard = null;
  swap.h.game.pointAt(320, 120);
  swap.h.press(() => {
    swap.decoding.PickedCard = swap.slotA;
  });
  swap.h.move(330, 125);
  swap.h.release();
  assert.deepEqual(swap.slotA.node.emitted, [], 'a slot never drops on itself');
  swap.h.press();
  swap.h.release();
  assert.equal(swap.decoding.released, 0, 'a press that picks nothing drops nothing');
}

// Zen Garden: a plant picked with the glove moves to the release slot, and a
// tool taken from its button applies to the release slot; unused drags put
// the plant or the tool back.
{
  function zenHarness() {
    const h = createHarness();
    const garden = createGarden();
    const slots = [rect(100, 100, 100, 100), rect(300, 100, 100, 100)].map((area) => ({
      area,
      judgeMouse() {
        const {x, y} = h.game.pointer;
        return x >= area.x && x < area.x + area.width && y >= area.y && y < area.y + area.height;
      },
    }));
    const pressed = [];
    garden.currentZen = {slots, MouseDown: (slot) => pressed.push(slots.indexOf(slot))};
    garden.cancelled = 0;
    garden.indexTo_1 = function () {
      this.cancelled += 1;
      this.isShoveling = this.isGloving = this.isCarting = false;
    };
    garden.setWillMovePlantSlot = function (slot) {
      this.willMovePlantSlot = slot;
    };
    h.game.zenGardenScene.component = garden;
    return {h, garden, slots, pressed};
  }

  const glove = zenHarness();
  glove.garden.isGloving = true;
  glove.h.game.pointAt(150, 150);
  glove.h.press(() => {
    glove.garden.willMovePlantSlot = glove.slots[0];
  });
  glove.h.move(350, 150);
  glove.h.release();
  assert.deepEqual(glove.pressed, [1], 'a gloved plant moves to the release slot');

  const gloveTap = zenHarness();
  gloveTap.garden.isGloving = true;
  gloveTap.h.game.pointAt(150, 150);
  gloveTap.h.press(() => {
    gloveTap.garden.willMovePlantSlot = gloveTap.slots[0];
  });
  gloveTap.h.release();
  assert.deepEqual(gloveTap.pressed, [], 'a gloved tap only picks the plant');
  assert.equal(gloveTap.garden.willMovePlantSlot, gloveTap.slots[0]);

  const gloveAway = zenHarness();
  gloveAway.garden.isGloving = true;
  gloveAway.h.game.pointAt(150, 150);
  gloveAway.h.press(() => {
    gloveAway.garden.willMovePlantSlot = gloveAway.slots[0];
  });
  gloveAway.h.move(700, 700);
  gloveAway.h.release();
  assert.equal(gloveAway.garden.willMovePlantSlot, null, 'an unused glove drag drops the plant');
  assert.equal(gloveAway.garden.isGloving, true, 'the glove stays in hand');

  const shovel = zenHarness();
  shovel.h.game.pointAt(700, 50);
  shovel.h.press(() => {
    shovel.garden.isShoveling = true;
  });
  shovel.h.move(350, 150);
  shovel.h.release();
  assert.deepEqual(shovel.pressed, [1], 'a tool dragged from its button applies to the slot');

  const shovelAway = zenHarness();
  shovelAway.h.game.pointAt(700, 50);
  shovelAway.h.press(() => {
    shovelAway.garden.isShoveling = true;
  });
  shovelAway.h.move(700, 600);
  shovelAway.h.release();
  assert.equal(shovelAway.garden.cancelled, 1, 'an unused tool drag puts the tool back');

  const toolTap = zenHarness();
  toolTap.h.game.pointAt(700, 50);
  toolTap.h.press(() => {
    toolTap.garden.isShoveling = true;
  });
  toolTap.h.release();
  assert.equal(toolTap.garden.cancelled, 0, 'a tap on a tool button keeps the tool');
  assert.deepEqual(toolTap.pressed, []);
}

// Zen Garden: an empty-handed left press pans until its release.
{
  const h = createHarness();
  const garden = createGarden();
  h.game.zenGardenScene.component = garden;
  h.press();
  assert.equal(garden.pressed, true, 'an empty-handed press must pan');
  h.release();
  assert.equal(garden.pressed, false, 'the release must stop panning');

  for (const tool of ['isShoveling', 'isGloving', 'isCarting']) {
    const toolGarden = createGarden();
    toolGarden[tool] = true;
    h.game.zenGardenScene.component = toolGarden;
    h.press();
    assert.equal(toolGarden.pressed, false, `${tool} must not pan`);
    h.release();
  }

  const buttonGarden = createGarden();
  h.game.zenGardenScene.component = buttonGarden;
  h.press(() => {
    buttonGarden.isShoveling = true;
  });
  assert.equal(buttonGarden.pressed, false, 'a tool button press must not pan');
  h.release();

  const rightGarden = createGarden();
  rightGarden.pressed = true;
  h.game.zenGardenScene.component = rightGarden;
  h.press();
  h.release();
  assert.equal(rightGarden.pressed, true, 'a right-button pan stays the game\'s own');

  for (const interrupt of [
    () => h.window.dispatchEvent(new Event('blur')),
    () => {
      h.document.hidden = true;
      h.document.dispatchEvent(new Event('visibilitychange'));
      h.document.hidden = false;
    },
  ]) {
    const interrupted = createGarden();
    h.game.zenGardenScene.component = interrupted;
    h.press();
    interrupt();
    assert.equal(interrupted.pressed, false, 'interruptions must stop panning');
  }
}

// Settings list: one finger scrolls it unless the touch starts on a slider.
{
  const h = createHarness();
  const list = new h.game.ScrollViewWithoutTouchevent();
  list.node = createNode();
  const button = createNode();
  button.parent = list.node;
  const slider = createNode({components: new Map([['cc.Slider', {}]])});
  slider.parent = list.node;
  const handle = createNode();
  handle.parent = slider;

  list._onTouchBegan({target: button}, []);
  list._onTouchMoved({target: button}, []);
  list._onTouchEnded({target: button}, []);
  assert.deepEqual(h.game.scrolled, ['_onTouchBegan', '_onTouchMoved', '_onTouchEnded'],
    'a touch on the list must scroll it');

  h.game.scrolled.length = 0;
  list._onTouchBegan({target: handle}, []);
  list._onTouchMoved({target: handle}, []);
  list._onTouchCancelled({target: handle}, []);
  assert.deepEqual(h.game.scrolled, [], 'a touch that starts on a slider must not scroll');

  const fresh = new h.game.ScrollViewWithoutTouchevent();
  fresh.node = createNode();
  fresh._onTouchMoved({target: button}, []);
  assert.deepEqual(h.game.scrolled, [], 'a move without a seen start must not scroll');
}

// Sandbox swipe: swiping along the seed bank cycles it like the wheel and
// cancels the card the press picked; a drag toward the lawn still plants.
{
  const h = createHarness();
  h.game.LevelPlay.sandBoxModeOn = true;
  h.game.pointAt(300, -50);
  pickUp(h, 0);
  h.move(290, -50);
  assert.deepEqual(h.wheel, [], 'movement within the slop must not cycle');
  h.move(255, -50);
  assert.deepEqual(h.wheel, [], 'the first step needs a full step past the slop');
  assert.equal(h.game.ui.index, -1, 'cycling must put the picked card back');
  h.move(240, -48);
  assert.deepEqual(h.wheel, [100], 'swiping toward the start shows the next cards');
  h.move(300, -50);
  h.move(340, -50);
  assert.deepEqual(h.wheel, [100, -100, -100],
    'swiping back shows the previous cards, one step per 40 pixels');
  h.move(450, 250);
  h.release();
  assert.equal(h.game.tile(2, 3).downs.length, 0, 'a cycling swipe must not plant');

  const plant = createHarness();
  plant.game.LevelPlay.sandBoxModeOn = true;
  plant.game.pointAt(300, -50);
  pickUp(plant, 0);
  plant.move(305, 20);
  plant.move(450, 250);
  plant.release();
  assert.deepEqual(plant.wheel, []);
  assert.equal(plant.game.tile(2, 3).downs.length, 1, 'a drag toward the lawn still plants');

  const level = createHarness();
  level.game.pointAt(300, -50);
  pickUp(level, 0);
  level.move(200, -50);
  assert.deepEqual(level.wheel, [], 'outside sandbox the bank does not cycle');
  assert.equal(level.game.ui.index, 0);

  const armor = createHarness();
  armor.game.LevelPlay.sandBoxModeOn = true;
  const armorParent = createNode({area: rect(600, 300, 60, 160)});
  armor.game.ui.SBZombieArmorIconSlot = {isValid: true, activeInHierarchy: true, parent: armorParent};
  armor.game.pointAt(630, 400);
  armor.press();
  armor.move(630, 340);
  assert.deepEqual(armor.wheel, [100], 'a vertical strip cycles with vertical swipes');
}

// Long press: custom decks, decoding slots and sandbox plants get the game's
// right-button action; anything else, or a moving finger, gets nothing.
{
  function deckHarness(flags = {}) {
    const h = createHarness();
    const deckNode = createNode({
      area: rect(100, 100, 200, 60),
      components: new Map([[h.game.CardDeck, {
        AddMode: false, ChallengingMode: false, RecommendedMode: false, ...flags,
      }]]),
    });
    h.game.LevelPlay.component.carddeck_displayer = {
      node: {activeInHierarchy: true},
      CardDeckParent: {children: [deckNode]},
    };
    return {h, deckNode};
  }

  const {h: deckH, deckNode} = deckHarness();
  deckH.game.pointAt(150, 120);
  deckH.press();
  deckH.advance(499);
  assert.deepEqual(deckNode.emitted, []);
  deckH.advance(1);
  assert.deepEqual(deckNode.emitted, [['mouse-down', 2]],
    'a long press on a custom deck must right-click it');
  deckH.release();

  const {h: shortH, deckNode: shortDeck} = deckHarness();
  shortH.game.pointAt(150, 120);
  shortH.press();
  shortH.advance(300);
  shortH.release();
  shortH.advance(500);
  assert.deepEqual(shortDeck.emitted, [], 'a tap must not become a long press');

  const {h: movedH, deckNode: movedDeck} = deckHarness();
  movedH.game.pointAt(150, 120);
  movedH.press();
  movedH.move(170, 120);
  movedH.advance(600);
  assert.deepEqual(movedDeck.emitted, [], 'a moving finger must not long press');

  const {h: challengeH, deckNode: challengeDeck} = deckHarness({ChallengingMode: true});
  challengeH.game.pointAt(150, 120);
  challengeH.press();
  challengeH.advance(500);
  assert.deepEqual(challengeDeck.emitted, [], 'built-in decks are not editable');

  const decodeH = createHarness();
  const slotNode = createNode({area: rect(400, 100, 80, 80)});
  const emptyNode = createNode({area: rect(500, 100, 80, 80)});
  decodeH.game.sceneComponents.set(decodeH.game.ArcadeDecodingPlants, [{
    node: {activeInHierarchy: true},
    confirming: false,
    MergedCards: [
      {node: emptyNode, currentPlant: '', isCorrect: () => false},
      {node: slotNode, currentPlant: 'peashooter', isCorrect: () => false},
    ],
  }]);
  decodeH.game.pointAt(520, 120);
  decodeH.press();
  decodeH.advance(500);
  assert.deepEqual(emptyNode.emitted, [], 'an empty slot has nothing to clear');
  decodeH.release();
  decodeH.game.pointAt(420, 120);
  decodeH.press();
  decodeH.advance(500);
  assert.deepEqual(slotNode.emitted, [['mouse-down', 2]],
    'a long press on a filled decoding slot must right-click it');

  const sandboxH = createHarness();
  sandboxH.game.LevelPlay.sandBoxModeOn = true;
  sandboxH.game.tile(2, 3).plants = 1;
  sandboxH.game.pointAt(450, 250);
  sandboxH.press();
  sandboxH.advance(500);
  assert.deepEqual(sandboxH.game.tile(2, 3).reacts, [2],
    'a long press on a sandbox plant must right-click it');
  sandboxH.release();

  const holdingH = createHarness();
  holdingH.game.LevelPlay.sandBoxModeOn = true;
  holdingH.game.tile(2, 3).plants = 1;
  holdingH.game.ui.index = 0;
  holdingH.game.pointAt(450, 250);
  holdingH.press();
  holdingH.advance(500);
  assert.deepEqual(holdingH.game.tile(2, 3).reacts, [], 'holding a tool is not a long press');

  const levelH = createHarness();
  levelH.game.tile(2, 3).plants = 1;
  levelH.game.pointAt(450, 250);
  levelH.press();
  levelH.advance(500);
  assert.deepEqual(levelH.game.tile(2, 3).reacts, [], 'outside sandbox plants have no right action');
}

// Sandbox menu: a tap on a shortcut row closes the window, then sends the
// row's key; a tap outside the window closes it; a tap on a button drawn above
// the window, or on a toggle row, is left to the game.
{
  function menuHarness() {
    const h = createHarness();
    const {cc, ui} = h.game;
    const upper = createNode();
    const menu = attach(upper, createNode({area: rect(0, 0, 1000, 700)}), 'SandboxLevelSettingWindow');
    const frame = attach(menu, createNode({area: rect(200, 100, 500, 450)}), 'windowCommon');
    const view = attach(frame, createNode({area: rect(220, 160, 460, 360)}), 'view');
    const content = attach(view, createNode({area: rect(220, 160, 460, 900)}), 'content');
    const rows = {};
    for (const [index, name] of ['StageEffect', 'SuperSlow', 'SwitchMusic', 'FreePlant'].entries()) {
      rows[name] = attach(content, createNode({area: rect(220, 160 + index * 60, 460, 50)}), name);
    }
    frame.getComponentInChildren = (type) => (type === cc.ScrollView
      ? {view: {node: view}, content}
      : null);
    menu.getComponentInChildren = frame.getComponentInChildren;
    const button = {enabledInHierarchy: true, interactable: true, node: null};
    const toolbar = attach(upper, createNode({
      area: rect(20, 120, 60, 60),
      components: new Map([[cc.Button, button]]),
    }), 'sandBoxSettingButton');
    button.node = toolbar;
    attach(upper, createNode({area: rect(0, 0, 1000, 700)}), 'ScreenFlash');
    ui.sandboxMenu = menu;
    ui.sandBoxSettingWindow = menu;
    return {h, rows};
  }

  const shortcut = menuHarness();
  shortcut.h.game.pointAt(400, 245);
  shortcut.h.press();
  shortcut.h.release();
  assert.equal(shortcut.h.game.ui.sandBoxSettingWindow, null, 'a shortcut row closes the window');
  assert.deepEqual(shortcut.h.game.keys, [['down', 116, 'closed']],
    'the row\'s key reaches the game after the window closed');
  shortcut.h.advance(50);
  assert.deepEqual(shortcut.h.game.keys.at(-1), ['up', 116]);

  const toggle = menuHarness();
  toggle.h.game.pointAt(400, 365);
  toggle.h.press();
  toggle.h.release();
  assert.notEqual(toggle.h.game.ui.sandBoxSettingWindow, null, 'toggle rows are the game\'s own buttons');
  assert.deepEqual(toggle.h.game.keys, []);

  const outside = menuHarness();
  outside.h.game.pointAt(900, 650);
  outside.h.press();
  outside.h.release();
  assert.equal(outside.h.game.ui.sandBoxSettingWindow, null,
    'a tap outside closes the window even under full-screen effect layers');

  const toolbar = menuHarness();
  toolbar.h.game.pointAt(40, 140);
  toolbar.h.press();
  toolbar.h.release();
  assert.notEqual(toolbar.h.game.ui.sandBoxSettingWindow, null,
    'the toolbar button above the window keeps its own toggle');
  assert.equal(toolbar.h.game.calls.filter(([name]) => name === 'showSBSettings').length, 0);

  const scrolled = menuHarness();
  scrolled.h.game.pointAt(400, 245);
  scrolled.h.press();
  scrolled.h.move(400, 300);
  scrolled.h.release();
  assert.notEqual(scrolled.h.game.ui.sandBoxSettingWindow, null, 'a scroll is not a tap');
  assert.deepEqual(scrolled.h.game.keys, []);
}

// Installation: modules registered after load install every rule once.
{
  const h = createHarness({modulesRegistered: false});
  const originalUp = h.game.UIInGame.prototype.onMouseUp;
  assert.equal(h.timers.length, 1, 'missing modules must be polled');
  h.register();
  h.advance(250);
  assert.notEqual(h.game.UIInGame.prototype.onMouseUp, originalUp);
  const installedUp = h.game.UIInGame.prototype.onMouseUp;
  h.rerun();
  h.advance(250);
  assert.equal(h.game.UIInGame.prototype.onMouseUp, installedUp, 'install once');
}

// Installation: a changed game interface disables only the rule that uses it.
{
  const noSquare = createHarness({missing: ['square']});
  assert.equal(noSquare.timers.length, 0, 'a mismatched interface must not be polled');
  assert.deepEqual(
    noSquare.errors.map((args) => String(args[0]).match(/（(\w+)）/)[1]),
    ['drop', 'swipe', 'longPress', 'decoding', 'sandboxMenu'],
    'every rule that needs Square is reported once',
  );
  const squareGarden = createGarden();
  noSquare.game.zenGardenScene.component = squareGarden;
  noSquare.press();
  assert.equal(squareGarden.pressed, true, 'panning must not depend on Square');
  noSquare.release();

  const noZen = createHarness({missing: ['zenGarden']});
  assert.equal(noZen.errors.length, 1, 'each failed rule is reported once');
  noZen.game.pointAt(450, -50);
  pickUp(noZen, 0);
  noZen.game.pointAt(450, 250);
  noZen.release();
  assert.equal(noZen.game.tile(2, 3).downs.length, 1, 'planting must not depend on Zen Garden');

  const noList = createHarness({missing: ['settingsList']});
  assert.equal(noList.errors.length, 1);
  const garden = createGarden();
  noList.game.zenGardenScene.component = garden;
  noList.press();
  assert.equal(garden.pressed, true, 'panning must not depend on the settings list');
  noList.release();

  const noCc = createHarness({missing: ['cc']});
  assert.deepEqual(
    noCc.errors.map((args) => String(args[0]).match(/（(\w+)）/)[1]),
    ['longPress', 'decoding', 'sandboxMenu'],
    'rules that need the engine are reported once each',
  );
  noCc.game.LevelPlay.sandBoxModeOn = true;
  noCc.game.pointAt(300, -50);
  noCc.press();
  noCc.move(240, -50);
  assert.deepEqual(noCc.wheel, [100], 'swipes must not depend on long press');
}

console.log('native gestures contract passes');
