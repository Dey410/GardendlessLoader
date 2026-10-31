import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const touchAdapterSource = fs.readFileSync(
  new URL('../assets/game_bridge/touch_input_adapter.js', import.meta.url),
  'utf8',
);
const touchStateMachineSource = fs.readFileSync(
  new URL('../assets/game_bridge/touch_state_machine.js', import.meta.url),
  'utf8',
);
const renderScaleSource = fs.readFileSync(
  new URL('../assets/game_bridge/render_scale.js', import.meta.url),
  'utf8',
);
assert.doesNotMatch(
  touchAdapterSource,
  /android-reference/,
  'the shared adapter must not retain an Android-only execution branch',
);
assert.match(
  touchAdapterSource,
  /dragCommitMinimumDelayMilliseconds = 50;/,
  'drag placement must use the accepted 50 ms minimum release delay',
);

class TestMouseEvent extends Event {
  constructor(type, options = {}) {
    super(type, options);
    Object.assign(this, {
      altKey: options.altKey ?? false,
      button: options.button ?? 0,
      buttons: options.buttons ?? 0,
      clientX: options.clientX ?? 0,
      clientY: options.clientY ?? 0,
      ctrlKey: options.ctrlKey ?? false,
      detail: options.detail ?? 0,
      metaKey: options.metaKey ?? false,
      relatedTarget: options.relatedTarget ?? null,
      screenX: options.screenX ?? 0,
      screenY: options.screenY ?? 0,
      shiftKey: options.shiftKey ?? false,
      view: options.view ?? null,
    });
  }
}

class TestWheelEvent extends TestMouseEvent {
  constructor(type, options = {}) {
    super(type, options);
    Object.assign(this, {
      deltaMode: options.deltaMode ?? 0,
      deltaY: options.deltaY ?? 0,
    });
  }
}

function createTouch(identifier, target, x, y) {
  return {
    identifier,
    target,
    screenX: x,
    screenY: y,
    clientX: x,
    clientY: y,
  };
}

function createElement(properties = {}) {
  const element = new EventTarget();
  Object.assign(element, {
    className: '',
    isConnected: true,
    isContentEditable: false,
    parentElement: null,
    tagName: 'DIV',
    getAttribute: () => null,
    ...properties,
  });
  return element;
}

function createTouchEvent(type, {touches, changedTouches}) {
  const event = new Event(type, {cancelable: true});
  Object.defineProperties(event, {
    touches: {value: touches},
    changedTouches: {value: changedTouches},
  });
  return event;
}

function createTouchHarness({
  animationFrameMilliseconds = 16,
  canvasAvailable = true,
  devicePixelRatio: initialDevicePixelRatio = 1,
  hostConfig = {},
  pointTarget = null,
  stateMachineAvailable = true,
  stateMachineCreateThrows = false,
  stateMachineHandleThrows = false,
} = {}) {
  const appendedElements = [];
  const frames = new Map();
  const intervals = [];
  const mutationObservers = [];
  let nextFrame = 1;
  let now = 0;
  let devicePixelRatio = initialDevicePixelRatio;
  const canvas = new EventTarget();
  Object.assign(canvas, {
    id: 'GameCanvas',
    isConnected: true,
    parentElement: null,
  });
  const documentRoot = createElement({
    tagName: 'HTML',
    appendChild(element) {
      element.parentElement = documentRoot;
      appendedElements.push(element);
      return element;
    },
  });
  const document = new EventTarget();
  Object.assign(document, {
    body: canvasAvailable ? canvas : documentRoot,
    createElement: (tagName) => createElement({
      tagName: tagName.toUpperCase(),
      textContent: '',
    }),
    documentElement: documentRoot,
    elementFromPoint: () => pointTarget ?? canvas,
    getElementById: (id) => {
      if (id === 'GameCanvas') {
        return canvasAvailable && canvas.isConnected ? canvas : null;
      }
      return appendedElements.find((element) => element.id === id) ?? null;
    },
    head: documentRoot,
    hidden: false,
  });
  const window = new EventTarget();
  // Browsers expose the ratio as an accessor on window.
  Object.defineProperty(window, 'devicePixelRatio', {
    configurable: true,
    enumerable: true,
    get: () => devicePixelRatio,
  });
  window.__gardendlessHostConfig = hostConfig;
  const context = {
    Event,
    Math,
    MouseEvent: TestMouseEvent,
    MutationObserver: class {
      constructor(callback) {
        mutationObservers.push(callback);
      }

      observe() {}
    },
    WheelEvent: TestWheelEvent,
    cancelAnimationFrame(id) {
      frames.delete(id);
    },
    document,
    performance: {
      now: () => now,
    },
    requestAnimationFrame(callback) {
      const id = nextFrame++;
      frames.set(id, callback);
      return id;
    },
    setInterval(callback) {
      intervals.push(callback);
      return intervals.length;
    },
    window,
  };
  context.globalThis = context;
  vm.createContext(context);
  let stateMachineCreations = 0;
  if (stateMachineAvailable) {
    vm.runInContext(touchStateMachineSource, context);
    const originalCreate = window.__gardendlessTouchStateMachine.create;
    window.__gardendlessTouchStateMachine.create = (options) => {
      stateMachineCreations += 1;
      if (stateMachineCreateThrows) {
        throw new Error('state machine create failed');
      }
      const machine = originalCreate(options);
      return stateMachineHandleThrows
        ? {handle: () => { throw new Error('state machine handle failed'); }}
        : machine;
    };
  }
  vm.runInContext(touchAdapterSource, context);

  return {
    appendedElements,
    canvas,
    document,
    advanceTime(milliseconds) {
      now += milliseconds;
    },
    runIntervals() {
      for (const callback of intervals) {
        callback();
      }
    },
    flushAnimationFrame() {
      const pending = Array.from(frames.values());
      frames.clear();
      now += animationFrameMilliseconds;
      for (const callback of pending) {
        callback(now);
      }
    },
    scheduleAnimationFrame(callback) {
      const id = nextFrame++;
      frames.set(id, callback);
      return id;
    },
    removeCanvas() {
      canvas.isConnected = false;
      for (const callback of mutationObservers) {
        callback();
      }
    },
    setHidden(hidden) {
      document.hidden = hidden;
      document.dispatchEvent(new Event('visibilitychange'));
    },
    rerunTouchAdapter() {
      vm.runInContext(touchAdapterSource, context);
    },
    injectScript(scriptSource) {
      vm.runInContext(scriptSource, context);
    },
    setDevicePixelRatio(value) {
      devicePixelRatio = value;
    },
    get stateMachineCreations() {
      return stateMachineCreations;
    },
    window,
  };
}

function attachPvzGePlacementModel(harness, {seedCard, lawnTiles}) {
  let pointer = {clientX: 0, clientY: 0};
  let mouseInLnC = null;
  let selected = false;
  let mouseClickCoolingDown = 0;
  const planted = [];

  harness.canvas.addEventListener('mousemove', (event) => {
    // Mouse.ts updates Mouse.position synchronously from Cocos MOUSE_MOVE.
    pointer = {clientX: event.clientX, clientY: event.clientY};
  });
  harness.canvas.addEventListener('mousedown', (event) => {
    // UI.ts consumes MOUSE_DOWN against Square.mouseInLnC. Lawn placement is
    // not committed by MOUSE_UP in pvzge-lite 0.13.0.
    if (event.button !== 0 || mouseClickCoolingDown > 0) {
      return;
    }
    mouseClickCoolingDown = 2;
    if (event.clientX === seedCard.clientX &&
        event.clientY === seedCard.clientY) {
      selected = true;
      return;
    }
    if (selected && mouseInLnC &&
        mouseInLnC.clientX === event.clientX &&
        mouseInLnC.clientY === event.clientY) {
      planted.push(mouseInLnC);
      selected = false;
    }
  });
  harness.canvas.addEventListener('mouseup', (event) => {
    // UI.ts applies the same two-tick guard to an accepted MOUSE_UP. This is
    // the release-side cooldown that can outlive several high-refresh browser
    // frames when Cocos updates more slowly.
    if (event.button === 0 && mouseClickCoolingDown === 0) {
      mouseClickCoolingDown = 2;
    }
  });

  function scheduleGameFrame() {
    harness.scheduleAnimationFrame(() => {
      // Square.ts derives mouseInLnC during Component.update, after Mouse.ts
      // has accepted the DOM/Cocos move. UI.ts decrements its click guard in
      // lateUpdate.
      mouseInLnC = lawnTiles.find((tile) =>
        tile.clientX === pointer.clientX && tile.clientY === pointer.clientY,
      ) ?? null;
      if (mouseClickCoolingDown > 0) {
        mouseClickCoolingDown -= 1;
      }
    });
  }

  return {
    get planted() {
      return planted;
    },
    get selected() {
      return selected;
    },
    scheduleGameFrame,
  };
}

function dispatchTouchStart(harness, identifier, point) {
  const touch = createTouch(
    identifier,
    harness.canvas,
    point.clientX,
    point.clientY,
  );
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  }));
  return touch;
}

function dispatchTouchEnd(harness, touch) {
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [touch],
  }));
}

function flushPvzGeFrame(harness, game) {
  game.scheduleGameFrame();
  harness.flushAnimationFrame();
}

for (const platform of ['android', 'ios', 'ohos']) {
  const seedCard = {clientX: 60, clientY: 50};
  const firstLawnTile = {clientX: 180, clientY: 90};
  const dragLawnTile = {clientX: 240, clientY: 130};
  const tapHarness = createTouchHarness({
    hostConfig: {platform},
  });
  const tapGame = attachPvzGePlacementModel(tapHarness, {
    seedCard,
    lawnTiles: [firstLawnTile, dragLawnTile],
  });

  const cardTap = dispatchTouchStart(tapHarness, 92, seedCard);
  dispatchTouchEnd(tapHarness, cardTap);
  flushPvzGeFrame(tapHarness, tapGame);
  flushPvzGeFrame(tapHarness, tapGame);
  assert.equal(
    tapGame.selected,
    true,
    `the first ${platform} tap must select the plant card`,
  );

  const lawnTap = dispatchTouchStart(tapHarness, 93, firstLawnTile);
  dispatchTouchEnd(tapHarness, lawnTap);
  // Register the game loop after the adapter's first RAF callback. A correct
  // adapter must still allow one complete Square.update before MOUSE_DOWN.
  flushPvzGeFrame(tapHarness, tapGame);
  flushPvzGeFrame(tapHarness, tapGame);
  assert.deepEqual(
    tapGame.planted,
    [firstLawnTile],
    `the second ${platform} tap must plant on its lawn tile immediately`,
  );

  const dragHarness = createTouchHarness({
    hostConfig: {platform},
  });
  const dragGame = attachPvzGePlacementModel(dragHarness, {
    seedCard,
    lawnTiles: [firstLawnTile, dragLawnTile],
  });
  const dragStart = dispatchTouchStart(dragHarness, 94, seedCard);
  flushPvzGeFrame(dragHarness, dragGame);
  flushPvzGeFrame(dragHarness, dragGame);
  const dragEnd = createTouch(
    94,
    dragHarness.canvas,
    dragLawnTile.clientX,
    dragLawnTile.clientY,
  );
  dragHarness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [dragEnd],
    changedTouches: [dragEnd],
  }));
  flushPvzGeFrame(dragHarness, dragGame);
  dispatchTouchEnd(dragHarness, dragEnd);
  for (let frame = 0; frame < 8; frame += 1) {
    flushPvzGeFrame(dragHarness, dragGame);
  }
  assert.deepEqual(
    dragGame.planted,
    [dragLawnTile],
    `${platform} drag planting must commit at release without a second tap`,
  );

  const sparseDragHarness = createTouchHarness({
    hostConfig: {platform},
  });
  const sparseDragGame = attachPvzGePlacementModel(sparseDragHarness, {
    seedCard,
    lawnTiles: [firstLawnTile, dragLawnTile],
  });
  dispatchTouchStart(sparseDragHarness, 99, seedCard);
  flushPvzGeFrame(sparseDragHarness, sparseDragGame);
  flushPvzGeFrame(sparseDragHarness, sparseDragGame);
  const sparseDragEnd = createTouch(
    99,
    sparseDragHarness.canvas,
    dragLawnTile.clientX,
    dragLawnTile.clientY,
  );
  // Some WebViews coalesce a fast drag so the distant release point arrives
  // without an intermediate touchmove. The release coordinate must still
  // classify and commit the gesture as a drag.
  dispatchTouchEnd(sparseDragHarness, sparseDragEnd);
  for (let frame = 0; frame < 8; frame += 1) {
    flushPvzGeFrame(sparseDragHarness, sparseDragGame);
  }
  assert.deepEqual(
    sparseDragGame.planted,
    [dragLawnTile],
    `${platform} coalesced drag must commit from its distant release point`,
  );

  const mixedRateHarness = createTouchHarness({
    animationFrameMilliseconds: 16,
    hostConfig: {platform},
  });
  const mixedRateGame = attachPvzGePlacementModel(mixedRateHarness, {
    seedCard,
    lawnTiles: [firstLawnTile, dragLawnTile],
  });
  dispatchTouchStart(mixedRateHarness, 100, seedCard);
  flushPvzGeFrame(mixedRateHarness, mixedRateGame);
  flushPvzGeFrame(mixedRateHarness, mixedRateGame);
  flushPvzGeFrame(mixedRateHarness, mixedRateGame);
  const mixedRateEnd = createTouch(
    100,
    mixedRateHarness.canvas,
    dragLawnTile.clientX,
    dragLawnTile.clientY,
  );
  mixedRateHarness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [mixedRateEnd],
    changedTouches: [mixedRateEnd],
  }));
  flushPvzGeFrame(mixedRateHarness, mixedRateGame);
  dispatchTouchEnd(mixedRateHarness, mixedRateEnd);
  for (let browserFrame = 1; browserFrame <= 20; browserFrame += 1) {
    // Model a 60 Hz WebView whose Cocos game loop updates at 30 Hz.
    if (browserFrame % 2 === 0) {
      mixedRateGame.scheduleGameFrame();
    }
    mixedRateHarness.flushAnimationFrame();
  }
  assert.deepEqual(
    mixedRateGame.planted,
    [dragLawnTile],
    `${platform} drag commit must wait for a slower Cocos game loop`,
  );
}

for (const platform of ['android', 'ios', 'ohos']) {
  const harness = createTouchHarness({
    devicePixelRatio: 2,
    hostConfig: {platform},
  });
  const primaryEvents = [];
  for (const type of ['mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, () => primaryEvents.push(type));
  }
  const start = dispatchTouchStart(
    harness,
    98,
    {clientX: 100, clientY: 100},
  );
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();
  const jitter = createTouch(98, harness.canvas, 106, 104);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [jitter],
    changedTouches: [jitter],
  }));
  dispatchTouchEnd(harness, jitter);
  for (let frame = 0; frame < 4; frame += 1) {
    harness.flushAnimationFrame();
  }
  assert.deepEqual(
    primaryEvents,
    ['mousedown', 'mouseup'],
    `${platform} sub-threshold finger jitter must remain one click`,
  );
  assert.equal(start.identifier, jitter.identifier);
}

for (const platform of ['android', 'ios', 'ohos']) {
  const harness = createTouchHarness({
    hostConfig: {platform},
  });
  const primaryEvents = [];
  for (const type of ['mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      if (event.button === 0) {
        primaryEvents.push(type);
      }
    });
  }

  const first = createTouch(95, harness.canvas, 60, 50);
  const second = createTouch(96, harness.canvas, 100, 50);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [first],
    changedTouches: [first],
  }));
  harness.flushAnimationFrame();
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [first, second],
    changedTouches: [second],
  }));
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();

  assert.deepEqual(
    primaryEvents,
    [],
    `${platform} second-finger transition must cancel a pending primary down`,
  );
}

for (const platform of ['android', 'ios', 'ohos']) {
  const harness = createTouchHarness({
    hostConfig: {platform},
  });
  const primaryEvents = [];
  for (const type of ['mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      if (event.button === 0) {
        primaryEvents.push(type);
      }
    });
  }

  const touch = createTouch(97, harness.canvas, 60, 50);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  }));
  harness.flushAnimationFrame();
  harness.document.dispatchEvent(createTouchEvent('touchcancel', {
    touches: [],
    changedTouches: [touch],
  }));
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();

  assert.deepEqual(
    primaryEvents,
    [],
    `${platform} cancellation must not leak a delayed primary event`,
  );
}

{
  const harness = createTouchHarness({stateMachineHandleThrows: true});
  let leakedTouches = 0;
  harness.document.addEventListener('touchstart', () => {
    leakedTouches += 1;
  });
  const touch = createTouch(87, harness.canvas, 50, 50);
  const start = createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  });

  harness.document.dispatchEvent(start);

  assert.equal(start.defaultPrevented, true);
  assert.equal(leakedTouches, 0, 'state machine execution failure must fail closed');
}

{
  const harness = createTouchHarness({stateMachineCreateThrows: true});
  let leakedTouches = 0;
  harness.document.addEventListener('touchstart', () => {
    leakedTouches += 1;
  });
  const touch = createTouch(88, harness.canvas, 50, 50);
  const start = createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  });

  harness.document.dispatchEvent(start);

  assert.equal(start.defaultPrevented, true);
  assert.equal(leakedTouches, 0, 'state machine creation failure must fail closed');
}

{
  const harness = createTouchHarness({stateMachineAvailable: false});
  let leakedTouches = 0;
  harness.document.addEventListener('touchstart', () => {
    leakedTouches += 1;
  });
  const touch = createTouch(89, harness.canvas, 50, 50);
  const start = createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  });

  harness.document.dispatchEvent(start);

  assert.equal(start.defaultPrevented, true);
  assert.equal(leakedTouches, 0, 'missing state machine must fail closed');
}

{
  const target = createElement({id: 'missing-canvas-target'});
  const harness = createTouchHarness({canvasAvailable: false});
  let leakedTouches = 0;
  harness.document.addEventListener('touchstart', () => {
    leakedTouches += 1;
  });
  const touch = createTouch(90, target, 50, 50);
  const start = createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  });

  harness.document.dispatchEvent(start);

  assert.equal(start.defaultPrevented, true);
  assert.equal(leakedTouches, 0, 'missing GameCanvas must fail closed');
}

{
  const harness = createTouchHarness({
    hostConfig: {
      platform: 'ios',
      touchDiagnosticsEnabled: true,
    },
  });
  const touch = createTouch(91, harness.canvas, 70, 60);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [touch],
  }));

  const trace = harness.window.__gardendlessTouchDiagnostics.snapshot();
  assert.ok(trace.some((entry) => entry.event === 'touch_owner'));
  assert.ok(trace.some((entry) => entry.event === 'touch_transition'));
  assert.ok(trace.some((entry) => entry.event === 'touch_output'));
  assert.equal(
    trace.some((entry) => 'text' in entry || 'value' in entry),
    false,
    'touch diagnostics must not capture page or form content',
  );

  const logs = [];
  harness.window.__gardendlessHost = {
    invoke(command, payload) {
      logs.push({command, args: payload.args});
      return Promise.resolve(null);
    },
  };
  harness.runIntervals();
  assert.ok(logs.length > 0, 'the trace must reach the host logs');
  const sent = [];
  for (const {command, args} of logs) {
    assert.equal(command, 'host:log');
    assert.equal(args.event, 'touch_trace');
    assert.equal(args.outcome, 'observed');
    assert.ok(args.message.length <= 1900, 'each batch fits a log message');
    const batch = JSON.parse(args.message);
    assert.equal(args.context.count, batch.length);
    sent.push(...batch);
  }
  assert.deepEqual(
    sent.map((entry) => entry.sequence),
    [...trace].map((entry) => entry.sequence),
    'every recorded entry is sent once, in order',
  );
  logs.length = 0;
  harness.runIntervals();
  assert.equal(logs.length, 0, 'sent entries are not sent again');
}

{
  const harness = createTouchHarness();
  assert.equal(
    harness.stateMachineCreations,
    1,
    'the DOM adapter must delegate game gestures to the shared state machine',
  );
}

{
  const coveringElement = createElement({id: 'transparent-cover'});
  const harness = createTouchHarness({pointTarget: coveringElement});
  const canvasEvents = [];
  const coveringEvents = [];
  for (const type of ['mousemove', 'mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      canvasEvents.push({
        type: event.type,
        clientX: event.clientX,
        clientY: event.clientY,
      });
    });
    coveringElement.addEventListener(type, (event) => {
      coveringEvents.push(event.type);
    });
  }

  const start = createTouch(11, harness.canvas, 60, 50);
  const end = createTouch(11, harness.canvas, 240, 130);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [start],
    changedTouches: [start],
  }));
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [end],
    changedTouches: [end],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [end],
  }));

  harness.flushAnimationFrame();
  assert.deepEqual(canvasEvents, [
    {type: 'mousemove', clientX: 60, clientY: 50},
    {type: 'mousedown', clientX: 60, clientY: 50},
    {type: 'mousemove', clientX: 240, clientY: 130},
    {type: 'mouseup', clientX: 240, clientY: 130},
  ], 'the frame-synchronized drag must stay on GameCanvas');
  harness.flushAnimationFrame();
  assert.deepEqual(
    coveringEvents,
    [],
    'an element covering the release point must not steal the Cocos mouse-up',
  );
}

{
  const initialOverlay = createElement({id: 'seed-card-overlay'});
  const harness = createTouchHarness();
  const canvasEvents = [];
  const overlayEvents = [];
  for (const type of ['mousemove', 'mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      canvasEvents.push(event.type);
    });
    initialOverlay.addEventListener(type, (event) => {
      overlayEvents.push(event.type);
    });
  }

  const start = createTouch(111, initialOverlay, 50, 40);
  const end = createTouch(111, initialOverlay, 220, 130);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [start],
    changedTouches: [start],
  }));
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [end],
    changedTouches: [end],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [end],
  }));
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();

  assert.deepEqual(canvasEvents, [
    'mousemove',
    'mousedown',
    'mousemove',
    'mouseup',
  ], 'game gestures must always reach the APK GameCanvas target');
  assert.deepEqual(
    overlayEvents,
    [],
    'the touch-down DOM target must not retain the game mouse sequence',
  );
}

{
  const harness = createTouchHarness({
    hostConfig: {platform: 'ios'},
  });
  const draggedMoves = [];
  harness.canvas.addEventListener('mousemove', (event) => {
    if (event.buttons === 1) {
      draggedMoves.push({clientX: event.clientX, clientY: event.clientY});
    }
  });

  const start = createTouch(21, harness.canvas, 40, 30);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [start],
    changedTouches: [start],
  }));
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();

  for (const [clientX, clientY] of [[70, 50], [85, 65], [100, 80]]) {
    const move = createTouch(21, harness.canvas, clientX, clientY);
    harness.document.dispatchEvent(createTouchEvent('touchmove', {
      touches: [move],
      changedTouches: [move],
    }));
  }

  assert.deepEqual(
    draggedMoves,
    [],
    'JavaScript touch moves must wait for the next browser frame',
  );
  harness.flushAnimationFrame();
  assert.deepEqual(
    draggedMoves,
    [{clientX: 100, clientY: 80}],
    'a touch-move burst must dispatch only its latest point',
  );

  const pendingMove = createTouch(21, harness.canvas, 130, 95);
  const release = createTouch(21, harness.canvas, 140, 105);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [pendingMove],
    changedTouches: [pendingMove],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [release],
  }));
  assert.deepEqual(
    draggedMoves,
    [
      {clientX: 100, clientY: 80},
      {clientX: 140, clientY: 105},
    ],
    'touch release must synchronously commit the final pointer position',
  );
  harness.flushAnimationFrame();
  assert.equal(
    draggedMoves.length,
    2,
    'touch release must cancel the pending move frame',
  );
}

{
  const pointTarget = createElement({id: 'point-target'});
  const harness = createTouchHarness({pointTarget});
  const rightClicks = [];
  let pointTargetRightClicks = 0;
  for (const type of ['mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      if (event.button === 2) {
        rightClicks.push({
          type: event.type,
          button: event.button,
          buttons: event.buttons,
          clientX: event.clientX,
          clientY: event.clientY,
        });
      }
    });
  }
  pointTarget.addEventListener('mousedown', (event) => {
    if (event.button === 2) {
      pointTargetRightClicks += 1;
    }
  });

  const firstStart = createTouch(31, harness.canvas, 80, 100);
  const secondStart = createTouch(32, harness.canvas, 120, 100);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [firstStart],
    changedTouches: [firstStart],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [firstStart, secondStart],
    changedTouches: [secondStart],
  }));

  const firstMove = createTouch(31, harness.canvas, 180, 100);
  const secondMove = createTouch(32, harness.canvas, 220, 100);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [firstMove, secondMove],
    changedTouches: [firstMove, secondMove],
  }));
  harness.advanceTime(1000);
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [secondMove],
    changedTouches: [firstMove],
  }));

  assert.deepEqual(
    rightClicks,
    [],
    'the APK waits until both fingers are lifted before right-clicking',
  );

  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [secondMove],
  }));
  assert.deepEqual(rightClicks, [
    {
      type: 'mousedown',
      button: 2,
      buttons: 2,
      clientX: 100,
      clientY: 100,
    },
    {
      type: 'mouseup',
      button: 2,
      buttons: 0,
      clientX: 100,
      clientY: 100,
    },
  ]);
  assert.equal(
    pointTargetRightClicks,
    0,
    'right clicks must target GameCanvas instead of the hit-tested element',
  );

  assert.equal(
    rightClicks.length,
    2,
    'lifting the remaining finger must not emit another right click',
  );
}

{
  const harness = createTouchHarness({devicePixelRatio: 2});
  const wheelEvents = [];
  let rightClicks = 0;
  harness.canvas.addEventListener('wheel', (event) => {
    wheelEvents.push({
      deltaY: event.deltaY,
      clientX: event.clientX,
      clientY: event.clientY,
      target: event.target,
    });
  });
  harness.canvas.addEventListener('mousedown', (event) => {
    if (event.button === 2) {
      rightClicks += 1;
    }
  });

  const firstStart = createTouch(41, harness.canvas, 80, 100);
  const secondStart = createTouch(42, harness.canvas, 120, 100);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [firstStart],
    changedTouches: [firstStart],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [firstStart, secondStart],
    changedTouches: [secondStart],
  }));

  const firstWithinSlop = createTouch(41, harness.canvas, 80, 110);
  const secondWithinSlop = createTouch(42, harness.canvas, 120, 110);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [firstWithinSlop, secondWithinSlop],
    changedTouches: [firstWithinSlop, secondWithinSlop],
  }));
  assert.deepEqual(
    wheelEvents,
    [],
    'movement at the 20 physical pixel slop must remain a right-click candidate',
  );

  const firstScroll = createTouch(41, harness.canvas, 80, 111);
  const secondScroll = createTouch(42, harness.canvas, 120, 111);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [firstScroll, secondScroll],
    changedTouches: [firstScroll, secondScroll],
  }));
  assert.deepEqual(wheelEvents, [{
    deltaY: -4.5,
    clientX: 100,
    clientY: 111,
    target: harness.canvas,
  }]);

  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [secondScroll],
    changedTouches: [firstScroll],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [secondScroll],
  }));
  assert.equal(rightClicks, 0, 'a scrolling gesture must not become a right click');
}

{
  const harness = createTouchHarness();
  const leftButtonEvents = [];
  for (const type of ['mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      if (event.button === 0) {
        leftButtonEvents.push({
          type: event.type,
          buttons: event.buttons,
          clientX: event.clientX,
          clientY: event.clientY,
        });
      }
    });
  }

  const firstStart = createTouch(51, harness.canvas, 40, 40);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [firstStart],
    changedTouches: [firstStart],
  }));
  harness.flushAnimationFrame();

  const firstMove = createTouch(51, harness.canvas, 60, 60);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [firstMove],
    changedTouches: [firstMove],
  }));
  harness.flushAnimationFrame();

  const secondStart = createTouch(52, harness.canvas, 140, 60);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [firstMove, secondStart],
    changedTouches: [secondStart],
  }));
  assert.deepEqual(leftButtonEvents, [
    {type: 'mousedown', buttons: 1, clientX: 40, clientY: 40},
  ]);

  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [firstMove],
    changedTouches: [secondStart],
  }));
  const remainingMove = createTouch(51, harness.canvas, 80, 80);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [remainingMove],
    changedTouches: [remainingMove],
  }));
  harness.flushAnimationFrame();
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [remainingMove],
  }));

  assert.equal(
    leftButtonEvents.length,
    1,
    'adding a second finger must not release or restart the left button',
  );
}

{
  const harness = createTouchHarness();
  const dragMoves = [];
  const mouseUps = [];
  harness.canvas.addEventListener('mousemove', (event) => {
    if (event.buttons === 1) {
      dragMoves.push({
        clientX: event.clientX,
        clientY: event.clientY,
      });
    }
  });
  harness.canvas.addEventListener('mouseup', (event) => {
    mouseUps.push({
      clientX: event.clientX,
      clientY: event.clientY,
    });
  });

  const active = createTouch(53, harness.canvas, 70, 50);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [active],
    changedTouches: [active],
  }));
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();

  const unrelated = createTouch(54, harness.canvas, 150, 90);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [unrelated],
    changedTouches: [unrelated],
  }));
  harness.flushAnimationFrame();
  assert.deepEqual(
    dragMoves,
    [{clientX: 150, clientY: 90}],
    'the APK follows the sole current pointer without identifier capture',
  );

  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [unrelated],
  }));
  harness.flushAnimationFrame();
  assert.deepEqual(
    mouseUps,
    [{clientX: 150, clientY: 90}],
    'the APK releases at the sole current pointer position',
  );
}

for (const interruption of [
  {
    name: 'touch cancellation',
    trigger(harness, touch) {
      harness.document.dispatchEvent(createTouchEvent('touchcancel', {
        touches: [],
        changedTouches: [touch],
      }));
    },
  },
  {
    name: 'window blur',
    trigger(harness) {
      harness.window.dispatchEvent(new Event('blur'));
    },
  },
  {
    name: 'page hiding',
    trigger(harness) {
      harness.setHidden(true);
    },
  },
  {
    name: 'target removal',
    trigger(harness) {
      harness.removeCanvas();
    },
  },
]) {
  const harness = createTouchHarness();
  const mouseUps = [];
  let leakedCancellations = 0;
  harness.canvas.addEventListener('mouseup', (event) => {
    mouseUps.push({
      button: event.button,
      buttons: event.buttons,
    });
  });
  harness.document.addEventListener('touchcancel', () => {
    leakedCancellations += 1;
  });

  const touch = createTouch(21, harness.canvas, 200, 120);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  }));
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();
  interruption.trigger(harness, touch);
  interruption.trigger(harness, touch);

  assert.deepEqual(mouseUps, [], `${interruption.name} must not release the mouse`);
  assert.equal(leakedCancellations, 0, 'game cancellations must fail closed');

  const freshTouch = createTouch(22, harness.canvas, 210, 125);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [freshTouch],
    changedTouches: [freshTouch],
  }));
  assert.equal(
    mouseUps.length,
    0,
    `${interruption.name} must clear internal state without a compensating up`,
  );
}

{
  const harness = createTouchHarness();
  const input = createElement({tagName: 'INPUT'});
  let nativeTouches = 0;
  harness.document.addEventListener('touchstart', () => {
    nativeTouches += 1;
  });
  harness.document.addEventListener('touchend', () => {
    nativeTouches += 1;
  });
  const touch = createTouch(61, input, 30, 20);
  const start = createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  });
  const end = createTouchEvent('touchend', {
    touches: [],
    changedTouches: [touch],
  });

  harness.document.dispatchEvent(start);
  harness.document.dispatchEvent(end);

  assert.equal(nativeTouches, 2, 'native form controls must retain touch input');
  assert.equal(start.defaultPrevented, false);
  assert.equal(end.defaultPrevented, false);
}

{
  const harness = createTouchHarness();
  const recoveryScreen = createElement({className: 'gp-recovery-screen'});
  const recoveryButton = createElement({
    parentElement: recoveryScreen,
    tagName: 'BUTTON',
  });
  let nativeTouches = 0;
  let canvasMouseDowns = 0;
  harness.document.addEventListener('touchstart', () => {
    nativeTouches += 1;
  });
  harness.document.addEventListener('touchend', () => {
    nativeTouches += 1;
  });
  harness.canvas.addEventListener('mousedown', () => {
    canvasMouseDowns += 1;
  });
  const touch = createTouch(62, recoveryButton, 90, 70);
  const start = createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  });
  const end = createTouchEvent('touchend', {
    touches: [],
    changedTouches: [touch],
  });

  harness.document.dispatchEvent(start);
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();
  harness.document.dispatchEvent(end);

  assert.equal(
    nativeTouches,
    2,
    'GP-Next startup recovery controls must retain native touch input',
  );
  assert.equal(start.defaultPrevented, false);
  assert.equal(end.defaultPrevented, false);
  assert.equal(
    canvasMouseDowns,
    0,
    'recovery controls must not redirect touches to GameCanvas',
  );
}

for (const gameGesture of [
  {
    name: 'two-finger gesture',
    dispatch(harness) {
      const first = createTouch(71, harness.canvas, 80, 80);
      const second = createTouch(72, harness.canvas, 120, 80);
      harness.document.dispatchEvent(createTouchEvent('touchstart', {
        touches: [first],
        changedTouches: [first],
      }));
      harness.document.dispatchEvent(createTouchEvent('touchstart', {
        touches: [first, second],
        changedTouches: [second],
      }));
      harness.document.dispatchEvent(createTouchEvent('touchmove', {
        touches: [first, second],
        changedTouches: [first, second],
      }));
    },
  },
  {
    name: 'three-finger gesture',
    dispatch(harness) {
      const touches = [
        createTouch(73, harness.canvas, 60, 80),
        createTouch(74, harness.canvas, 100, 80),
        createTouch(75, harness.canvas, 140, 80),
      ];
      harness.document.dispatchEvent(createTouchEvent('touchstart', {
        touches,
        changedTouches: touches,
      }));
    },
  },
  {
    name: 'GP-Next backdrop gesture',
    dispatch(harness) {
      const overlay = createElement({
        id: 'gp-overlay',
        classList: {
          contains: (name) => name === 'gp-open',
        },
      });
      const originalGetElementById = harness.document.getElementById;
      harness.document.getElementById = (id) =>
        id === 'gp-overlay' ? overlay : originalGetElementById(id);
      const touch = createTouch(76, harness.canvas, 100, 80);
      harness.document.dispatchEvent(createTouchEvent('touchstart', {
        touches: [touch],
        changedTouches: [touch],
      }));
      harness.document.dispatchEvent(createTouchEvent('touchend', {
        touches: [],
        changedTouches: [touch],
      }));
    },
  },
]) {
  const harness = createTouchHarness();
  let leakedTouches = 0;
  for (const type of ['touchstart', 'touchmove', 'touchend', 'touchcancel']) {
    harness.document.addEventListener(type, () => {
      leakedTouches += 1;
    });
  }

  gameGesture.dispatch(harness);

  assert.equal(
    leakedTouches,
    0,
    `${gameGesture.name} must not reach Cocos touch listeners`,
  );
}

{
  const harness = createTouchHarness();
  const overlay = createElement({
    id: 'gp-overlay',
    classList: {
      contains: (name) => name === 'gp-open',
    },
  });
  const originalGetElementById = harness.document.getElementById;
  harness.document.getElementById = (id) =>
    id === 'gp-overlay' ? overlay : originalGetElementById(id);
  let hides = 0;
  harness.window.gpNext = {
    hide() {
      hides += 1;
    },
  };

  const first = createTouch(77, harness.canvas, 100, 80);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [first],
    changedTouches: [first],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [first],
  }));
  harness.advanceTime(100);
  const second = createTouch(78, harness.canvas, 104, 82);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [second],
    changedTouches: [second],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [second],
  }));

  assert.equal(hides, 1, 'GP-Next backdrop double-tap must keep closing the overlay');
}

{
  const harness = createTouchHarness();
  const styles = harness.appendedElements.filter(
    (element) => element.tagName === 'STYLE',
  );
  assert.equal(styles.length, 1, 'touch-action style must be installed once');
  assert.match(styles[0].textContent, /#GameCanvas/);
  assert.match(styles[0].textContent, /touch-action:\s*none/);

  harness.rerunTouchAdapter();
  assert.equal(
    harness.appendedElements.filter(
      (element) => element.tagName === 'STYLE',
    ).length,
    1,
    'reinstalling the patch must not duplicate styles',
  );

  let mouseDowns = 0;
  harness.canvas.addEventListener('mousedown', () => {
    mouseDowns += 1;
  });
  const touch = createTouch(81, harness.canvas, 90, 70);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  }));
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [touch],
  }));
  assert.equal(
    mouseDowns,
    1,
    'reinstalling the patch must not duplicate exact APK single-touch input',
  );
}

{
  // A resize during a drag must drop the gesture instead of releasing or
  // placing at a point measured before the geometry changed. Every platform
  // shares this adapter path, so one iOS harness covers it.
  const seedCard = {clientX: 60, clientY: 50};
  const firstLawnTile = {clientX: 180, clientY: 90};
  const dragLawnTile = {clientX: 240, clientY: 130};
  const harness = createTouchHarness({hostConfig: {platform: 'ios'}});
  const game = attachPvzGePlacementModel(harness, {
    seedCard,
    lawnTiles: [firstLawnTile, dragLawnTile],
  });
  const mouseUps = [];
  harness.canvas.addEventListener('mouseup', (event) => {
    mouseUps.push({clientX: event.clientX, clientY: event.clientY});
  });

  dispatchTouchStart(harness, 120, seedCard);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  assert.equal(game.selected, true, 'the drag must select the plant card');
  const drag = createTouch(
    120,
    harness.canvas,
    dragLawnTile.clientX,
    dragLawnTile.clientY,
  );
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [drag],
    changedTouches: [drag],
  }));
  flushPvzGeFrame(harness, game);

  harness.window.dispatchEvent(new Event('resize'));
  for (let frame = 0; frame < 8; frame += 1) {
    flushPvzGeFrame(harness, game);
  }
  assert.deepEqual(
    game.planted,
    [],
    'resize must cancel the in-flight drag without placing',
  );
  assert.deepEqual(
    mouseUps,
    [],
    'resize must not synthesize a mouse release',
  );

  dispatchTouchEnd(harness, drag);
  const freshTap = dispatchTouchStart(harness, 121, firstLawnTile);
  dispatchTouchEnd(harness, freshTap);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  assert.deepEqual(
    game.planted,
    [firstLawnTile],
    'the first tap after a resize must plant normally',
  );
}

{
  // A resize between the finger lifting and the deferred drag commit must
  // cancel that commit instead of planting at the pre-resize release point.
  const seedCard = {clientX: 60, clientY: 50};
  const firstLawnTile = {clientX: 180, clientY: 90};
  const dragLawnTile = {clientX: 240, clientY: 130};
  const harness = createTouchHarness({hostConfig: {platform: 'ios'}});
  const game = attachPvzGePlacementModel(harness, {
    seedCard,
    lawnTiles: [firstLawnTile, dragLawnTile],
  });
  const commits = [];
  for (const type of ['mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      commits.push({
        type: event.type,
        clientX: event.clientX,
        clientY: event.clientY,
      });
    });
  }

  dispatchTouchStart(harness, 130, seedCard);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  const drag = createTouch(
    130,
    harness.canvas,
    dragLawnTile.clientX,
    dragLawnTile.clientY,
  );
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [drag],
    changedTouches: [drag],
  }));
  flushPvzGeFrame(harness, game);
  dispatchTouchEnd(harness, drag);
  commits.length = 0;

  harness.window.dispatchEvent(new Event('resize'));
  for (let frame = 0; frame < 12; frame += 1) {
    flushPvzGeFrame(harness, game);
  }
  assert.deepEqual(
    commits,
    [],
    'resize must cancel an undelivered drag placement',
  );
  assert.deepEqual(game.planted, [], 'a cancelled placement must not plant');

  harness.window.dispatchEvent(new Event('resize'));
  const freshTap = dispatchTouchStart(harness, 131, firstLawnTile);
  dispatchTouchEnd(harness, freshTap);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  assert.deepEqual(
    game.planted,
    [firstLawnTile],
    'a tap after repeated resize must plant exactly once',
  );
}

{
  // The delayed placement of a finished drag is still pending when a form
  // field takes the touch; a resize that arrives during that native gesture
  // must cancel it. Its release point belongs to the old geometry, and the
  // form gesture itself must keep working.
  const seedCard = {clientX: 60, clientY: 50};
  const firstLawnTile = {clientX: 180, clientY: 90};
  const dragLawnTile = {clientX: 240, clientY: 130};
  const harness = createTouchHarness({hostConfig: {platform: 'ios'}});
  const game = attachPvzGePlacementModel(harness, {
    seedCard,
    lawnTiles: [firstLawnTile, dragLawnTile],
  });
  const releases = [];
  for (const type of ['mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      releases.push({
        type: event.type,
        clientX: event.clientX,
        clientY: event.clientY,
      });
    });
  }
  let nativeTouches = 0;
  for (const type of ['touchstart', 'touchend']) {
    harness.document.addEventListener(type, () => {
      nativeTouches += 1;
    });
  }

  dispatchTouchStart(harness, 132, seedCard);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  const drag = createTouch(
    132,
    harness.canvas,
    dragLawnTile.clientX,
    dragLawnTile.clientY,
  );
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [drag],
    changedTouches: [drag],
  }));
  flushPvzGeFrame(harness, game);
  dispatchTouchEnd(harness, drag);
  releases.length = 0;

  // No frame runs between the release and the field touch, so the deferred
  // placement is still scheduled when the resize arrives.
  const field = createElement({tagName: 'INPUT'});
  const fieldTouch = createTouch(133, field, 40, 30);
  const fieldStart = createTouchEvent('touchstart', {
    touches: [fieldTouch],
    changedTouches: [fieldTouch],
  });
  harness.document.dispatchEvent(fieldStart);
  harness.window.dispatchEvent(new Event('resize'));
  const fieldEnd = createTouchEvent('touchend', {
    touches: [],
    changedTouches: [fieldTouch],
  });
  harness.document.dispatchEvent(fieldEnd);

  for (let frame = 0; frame < 12; frame += 1) {
    flushPvzGeFrame(harness, game);
  }
  assert.deepEqual(
    releases,
    [],
    'the resize must cancel the delayed placement held by the form touch',
  );
  assert.deepEqual(
    game.planted,
    [],
    'the cancelled placement must not plant at the old geometry',
  );
  assert.equal(
    fieldStart.defaultPrevented,
    false,
    'the form touch must stay native',
  );
  assert.equal(
    fieldEnd.defaultPrevented,
    false,
    'the form release must stay native',
  );
  assert.equal(
    nativeTouches,
    2,
    'the form field must still receive its own touch events',
  );

  const freshTap = dispatchTouchStart(harness, 134, firstLawnTile);
  dispatchTouchEnd(harness, freshTap);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  assert.deepEqual(
    game.planted,
    [firstLawnTile],
    'a game gesture must work again after the form touch and resize',
  );
}

{
  // Touches pressed before the resize are still on the glass. Neither they nor
  // a finger added to them may start input until every old finger has lifted.
  const seedCard = {clientX: 60, clientY: 50};
  const firstLawnTile = {clientX: 180, clientY: 90};
  const dragLawnTile = {clientX: 240, clientY: 130};
  const harness = createTouchHarness({hostConfig: {platform: 'ios'}});
  const game = attachPvzGePlacementModel(harness, {
    seedCard,
    lawnTiles: [firstLawnTile, dragLawnTile],
  });
  const canvasInput = [];
  for (const type of ['mousemove', 'mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      canvasInput.push({
        type: event.type,
        clientX: event.clientX,
        clientY: event.clientY,
      });
    });
  }

  dispatchTouchStart(harness, 140, seedCard);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  harness.window.dispatchEvent(new Event('resize'));
  canvasInput.length = 0;

  const staleMove = createTouch(
    140,
    harness.canvas,
    dragLawnTile.clientX,
    dragLawnTile.clientY,
  );
  const staleMoveEvent = createTouchEvent('touchmove', {
    touches: [staleMove],
    changedTouches: [staleMove],
  });
  harness.document.dispatchEvent(staleMoveEvent);
  assert.equal(
    staleMoveEvent.defaultPrevented,
    true,
    'stale touches must stay away from Cocos listeners',
  );

  const addedFinger = createTouch(
    141,
    harness.canvas,
    firstLawnTile.clientX,
    firstLawnTile.clientY,
  );
  const addedStart = createTouchEvent('touchstart', {
    touches: [staleMove, addedFinger],
    changedTouches: [addedFinger],
  });
  harness.document.dispatchEvent(addedStart);
  assert.equal(addedStart.defaultPrevented, true);
  assert.deepEqual(
    canvasInput,
    [],
    'fingers left over from the old geometry must not produce input',
  );

  const addedEnd = createTouchEvent('touchend', {
    touches: [staleMove],
    changedTouches: [addedFinger],
  });
  harness.document.dispatchEvent(addedEnd);
  assert.equal(addedEnd.defaultPrevented, true, 'stale touchend must not reach the game');
  const anotherFinger = createTouch(
    142,
    harness.canvas,
    dragLawnTile.clientX,
    dragLawnTile.clientY,
  );
  const anotherStart = createTouchEvent('touchstart', {
    touches: [staleMove, anotherFinger],
    changedTouches: [anotherFinger],
  });
  harness.document.dispatchEvent(anotherStart);
  assert.equal(anotherStart.defaultPrevented, true);
  assert.deepEqual(
    canvasInput,
    [],
    'a new finger must wait until the touches from before the resize lift',
  );

  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [staleMove],
    changedTouches: [anotherFinger],
  }));
  const staleEnd = createTouchEvent('touchend', {
    touches: [],
    changedTouches: [staleMove],
  });
  harness.document.dispatchEvent(staleEnd);
  assert.equal(staleEnd.defaultPrevented, true, 'the last stale touchend must not reach the game');
  flushPvzGeFrame(harness, game);
  assert.deepEqual(
    canvasInput,
    [],
    'draining stale touches must not replay the interrupted gesture',
  );

  const freshTap = dispatchTouchStart(harness, 143, firstLawnTile);
  dispatchTouchEnd(harness, freshTap);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  assert.deepEqual(
    game.planted,
    [firstLawnTile],
    'a normal new gesture must work again once every old finger lifted',
  );
}

{
  // WebKit can stop reporting the old touch after the resize without an end
  // event. A new touch that the browser reports as the only active one is
  // therefore still a fresh gesture.
  const seedCard = {clientX: 60, clientY: 50};
  const firstLawnTile = {clientX: 180, clientY: 90};
  const dragLawnTile = {clientX: 240, clientY: 130};
  const harness = createTouchHarness({hostConfig: {platform: 'ios'}});
  const game = attachPvzGePlacementModel(harness, {
    seedCard,
    lawnTiles: [firstLawnTile, dragLawnTile],
  });

  dispatchTouchStart(harness, 144, seedCard);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  harness.window.dispatchEvent(new Event('resize'));
  flushPvzGeFrame(harness, game);

  const freshTap = dispatchTouchStart(harness, 145, firstLawnTile);
  dispatchTouchEnd(harness, freshTap);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  assert.deepEqual(
    game.planted,
    [firstLawnTile],
    'a lone new touch after a resize must start a new gesture',
  );
}

{
  // Repeated resize events, and re-running the injected adapter, must not
  // inject extra input or corrupt the state used by the next gesture.
  const seedCard = {clientX: 60, clientY: 50};
  const firstLawnTile = {clientX: 180, clientY: 90};
  const harness = createTouchHarness({hostConfig: {platform: 'ios'}});
  const game = attachPvzGePlacementModel(harness, {
    seedCard,
    lawnTiles: [firstLawnTile],
  });
  const input = [];
  for (const type of ['mousemove', 'mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      input.push({type: event.type, clientX: event.clientX, clientY: event.clientY});
    });
  }

  dispatchTouchStart(harness, 150, seedCard);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  harness.window.dispatchEvent(new Event('resize'));
  const afterResize = input.length;
  harness.window.dispatchEvent(new Event('resize'));
  harness.window.dispatchEvent(new Event('resize'));
  for (let frame = 0; frame < 4; frame += 1) {
    flushPvzGeFrame(harness, game);
  }
  assert.equal(
    input.length,
    afterResize,
    'repeated resize must not inject game input',
  );
  assert.deepEqual(game.planted, [], 'repeated resize must not place');

  dispatchTouchEnd(harness, createTouch(
    150,
    harness.canvas,
    seedCard.clientX,
    seedCard.clientY,
  ));
  harness.rerunTouchAdapter();
  harness.window.dispatchEvent(new Event('resize'));
  assert.equal(
    input.length,
    afterResize,
    'reinstalling the adapter and resizing again must still not inject input',
  );

  const freshTap = dispatchTouchStart(harness, 151, firstLawnTile);
  dispatchTouchEnd(harness, freshTap);
  flushPvzGeFrame(harness, game);
  flushPvzGeFrame(harness, game);
  const mouseDowns = input.filter((entry) => entry.type === 'mousedown');
  assert.equal(
    mouseDowns.length,
    2,
    'selecting the card and planting must stay one click each',
  );
  assert.deepEqual(game.planted, [firstLawnTile]);
}

{
  // A form field keeps ownership across the keyboard-driven resize that it
  // causes, and its touches never become game input.
  const harness = createTouchHarness({hostConfig: {platform: 'ios'}});
  const canvasInput = [];
  for (const type of ['mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, () => canvasInput.push(type));
  }
  let nativeTouches = 0;
  for (const type of ['touchstart', 'touchend']) {
    harness.document.addEventListener(type, () => {
      nativeTouches += 1;
    });
  }

  const field = createElement({tagName: 'INPUT'});
  const fieldTouch = createTouch(160, field, 30, 20);
  const fieldStart = createTouchEvent('touchstart', {
    touches: [fieldTouch],
    changedTouches: [fieldTouch],
  });
  harness.document.dispatchEvent(fieldStart);
  harness.window.dispatchEvent(new Event('resize'));
  const fieldMove = createTouchEvent('touchmove', {
    touches: [fieldTouch],
    changedTouches: [fieldTouch],
  });
  harness.document.dispatchEvent(fieldMove);
  const fieldEnd = createTouchEvent('touchend', {
    touches: [],
    changedTouches: [fieldTouch],
  });
  harness.document.dispatchEvent(fieldEnd);

  assert.equal(
    fieldStart.defaultPrevented,
    false,
    'a form focus must survive a resize',
  );
  assert.equal(fieldMove.defaultPrevented, false);
  assert.equal(fieldEnd.defaultPrevented, false);
  assert.equal(
    nativeTouches,
    2,
    'the form field must still receive its own touch events',
  );
  assert.deepEqual(
    canvasInput,
    [],
    'a resized form gesture must not reach GameCanvas',
  );

  // While the touches from before a resize drain, native and GP-Next surfaces
  // stay usable and still produce no game input.
  const overlay = createElement({id: 'gp-overlay'});
  const held = createTouch(161, harness.canvas, 70, 60);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [held],
    changedTouches: [held],
  }));
  harness.window.dispatchEvent(new Event('resize'));
  for (const target of [createElement({tagName: 'INPUT'}), overlay]) {
    const touch = createTouch(162, target, 40, 30);
    const start = createTouchEvent('touchstart', {
      touches: [held, touch],
      changedTouches: [touch],
    });
    harness.document.dispatchEvent(start);
    const end = createTouchEvent('touchend', {
      touches: [held],
      changedTouches: [touch],
    });
    harness.document.dispatchEvent(end);
    assert.equal(
      start.defaultPrevented,
      false,
      'native controls must stay usable while stale touches drain',
    );
    assert.equal(end.defaultPrevented, false);
  }
  assert.equal(
    nativeTouches,
    6,
    'native and GP-Next touches must reach the page untouched',
  );
  assert.deepEqual(
    canvasInput,
    [],
    'native taps during a resize drain must not become game input',
  );
}

{
  // A GP-Next backdrop double tap that straddles a resize used stale points.
  const harness = createTouchHarness({hostConfig: {platform: 'ios'}});
  const overlay = createElement({
    id: 'gp-overlay',
    classList: {contains: (name) => name === 'gp-open'},
  });
  const originalGetElementById = harness.document.getElementById;
  harness.document.getElementById = (id) =>
    id === 'gp-overlay' ? overlay : originalGetElementById(id);
  let hides = 0;
  harness.window.gpNext = {
    hide() {
      hides += 1;
    },
  };

  const first = createTouch(163, harness.canvas, 100, 80);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [first],
    changedTouches: [first],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [first],
  }));
  harness.advanceTime(100);
  harness.window.dispatchEvent(new Event('resize'));
  const second = createTouch(164, harness.canvas, 102, 82);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [second],
    changedTouches: [second],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [second],
  }));

  assert.equal(
    hides,
    0,
    'a backdrop double tap that straddles a resize must not close the overlay',
  );
}

{
  // Touch thresholds are physical pixels, so they must keep reading the real
  // device ratio even when render_scale.js makes Cocos see the scaled one.
  const harness = createTouchHarness({
    devicePixelRatio: 2,
    hostConfig: {platform: 'ios'},
  });
  let releasing = false;
  let releaseMoves = 0;
  let releaseUps = 0;
  harness.canvas.addEventListener('mousemove', () => {
    if (releasing) {
      releaseMoves += 1;
    }
  });
  harness.canvas.addEventListener('mouseup', () => {
    if (releasing) {
      releaseUps += 1;
    }
  });
  harness.window.__gardendlessHost = {config: {renderScale: 0.5}};
  harness.injectScript(renderScaleSource);
  assert.equal(
    harness.window.devicePixelRatio,
    1,
    'Cocos must see the user scale applied to the real ratio',
  );

  function runShortGesture(identifier, startX, startY, endX, endY) {
    releasing = false;
    releaseMoves = 0;
    releaseUps = 0;
    dispatchTouchStart(harness, identifier, {clientX: startX, clientY: startY});
    harness.flushAnimationFrame();
    harness.flushAnimationFrame();
    const move = createTouch(identifier, harness.canvas, endX, endY);
    harness.document.dispatchEvent(createTouchEvent('touchmove', {
      touches: [move],
      changedTouches: [move],
    }));
    harness.flushAnimationFrame();
    releasing = true;
    dispatchTouchEnd(harness, move);
    releasing = false;
    const measured = {releaseMoves, releaseUps};
    for (let frame = 0; frame < 8; frame += 1) {
      harness.flushAnimationFrame();
    }
    return measured;
  }

  assert.deepEqual(
    runShortGesture(170, 100, 100, 115, 100),
    {releaseMoves: 1, releaseUps: 0},
    '15 px at a real 2x ratio is a drag, so the scaled 1x ratio is not used',
  );

  harness.setDevicePixelRatio(1);
  assert.equal(
    harness.window.devicePixelRatio,
    0.5,
    'the wrapper follows the live ratio',
  );
  assert.deepEqual(
    runShortGesture(171, 100, 100, 112, 100),
    {releaseMoves: 0, releaseUps: 1},
    '12 px at the new 1x ratio is a tap, so the ratio is re-read on every gesture',
  );

  harness.injectScript(renderScaleSource);
  assert.equal(
    harness.window.devicePixelRatio,
    0.5,
    're-injecting render scale must not multiply the ratio',
  );
  assert.deepEqual(
    runShortGesture(172, 100, 100, 112, 100),
    {releaseMoves: 0, releaseUps: 1},
    'the duplicate injection must not change the gesture thresholds',
  );
}

console.log('touch input adapter contract passes');
