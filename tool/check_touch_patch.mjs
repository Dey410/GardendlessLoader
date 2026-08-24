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
const androidGameActivitySource = fs.readFileSync(
  new URL(
    '../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameActivity.kt',
    import.meta.url,
  ),
  'utf8',
);

assert.match(
  androidGameActivitySource,
  /webView = WebView\(this\)\.apply/,
  'Android must use a plain WebView without native touch-to-mouse injection',
);
assert.match(
  androidGameActivitySource,
  /\.put\("touchAdapter", "javascript"\)/,
  'Android must select the shared JavaScript touch adapter',
);
assert.doesNotMatch(
  touchAdapterSource,
  /android-reference/,
  'the shared adapter must not retain an Android-only execution branch',
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
  devicePixelRatio = 1,
  hostConfig = {},
  pointTarget = null,
  stateMachineAvailable = true,
  stateMachineCreateThrows = false,
  stateMachineHandleThrows = false,
} = {}) {
  const appendedElements = [];
  const frames = new Map();
  const mutationObservers = [];
  let nextFrame = 1;
  let now = 0;
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
  window.devicePixelRatio = devicePixelRatio;
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
    hostConfig: {platform, touchAdapter: 'javascript'},
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
    hostConfig: {platform, touchAdapter: 'javascript'},
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
    hostConfig: {platform, touchAdapter: 'javascript'},
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
    animationFrameMilliseconds: 8,
    hostConfig: {platform, touchAdapter: 'javascript'},
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
    // Model a 120 Hz WebView whose Cocos game loop updates at 30 Hz.
    if (browserFrame % 4 === 0) {
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
    hostConfig: {platform, touchAdapter: 'javascript'},
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
    hostConfig: {platform, touchAdapter: 'javascript'},
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
    hostConfig: {platform, touchAdapter: 'javascript'},
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
      touchAdapter: 'javascript',
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
  const harness = createTouchHarness();
  const gameTimeline = [];
  for (const type of ['mousemove', 'mousedown', 'mouseup', 'click']) {
    harness.canvas.addEventListener(type, (event) => {
      gameTimeline.push(`mouse:${type}:${event.buttons}`);
    });
  }
  for (const type of ['touchstart', 'touchmove', 'touchend']) {
    harness.document.addEventListener(type, () => {
      gameTimeline.push(`touch:${type}`);
    });
  }

  const start = createTouch(6, harness.canvas, 60, 50);
  const end = createTouch(6, harness.canvas, 240, 130);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [start],
    changedTouches: [start],
  }));
  harness.advanceTime(3000);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [end],
    changedTouches: [end],
  }));
  harness.advanceTime(3000);
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [end],
  }));
  harness.flushAnimationFrame();
  harness.flushAnimationFrame();

  assert.deepEqual(gameTimeline, [
    'mouse:mousedown:1',
    'mouse:mousemove:1',
    'mouse:mouseup:1',
  ], 'non-Android hosts retain the immediate mouse gesture fallback');
}

{
  const harness = createTouchHarness();
  const mouseEvents = [];
  let leakedTouches = 0;
  for (const type of ['mousemove', 'mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      mouseEvents.push({
        type: event.type,
        button: event.button,
        buttons: event.buttons,
        clientX: event.clientX,
        clientY: event.clientY,
      });
    });
  }
  harness.document.addEventListener('touchstart', () => {
    leakedTouches += 1;
  });
  harness.document.addEventListener('touchend', () => {
    leakedTouches += 1;
  });

  const touch = createTouch(7, harness.canvas, 120, 80);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  }));
  assert.deepEqual(mouseEvents, [
    {
      type: 'mousedown',
      button: 0,
      buttons: 1,
      clientX: 120,
      clientY: 80,
    },
  ], 'single touch must immediately expose the APK mouse-down');
  harness.flushAnimationFrame();
  assert.deepEqual(mouseEvents, [
    {
      type: 'mousedown',
      button: 0,
      buttons: 1,
      clientX: 120,
      clientY: 80,
    },
  ], 'single-touch mapping must not defer the APK mouse-down');
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [touch],
  }));

  assert.deepEqual(mouseEvents, [
    {
      type: 'mousedown',
      button: 0,
      buttons: 1,
      clientX: 120,
      clientY: 80,
    },
    {
      type: 'mouseup',
      button: 0,
      buttons: 1,
      clientX: 120,
      clientY: 80,
    },
  ]);
  assert.equal(
    leakedTouches,
    0,
    'original game touches must be hidden from Cocos like the APK extension',
  );
}

{
  const plantedTiles = [];
  let cocosPointer = {clientX: 0, clientY: 0};
  let leftPressed = false;
  const harness = createTouchHarness();
  harness.canvas.addEventListener('mousemove', (event) => {
    cocosPointer = {clientX: event.clientX, clientY: event.clientY};
  });
  harness.canvas.addEventListener('mousedown', (event) => {
    if (event.button === 0 && event.buttons === 1) {
      leftPressed = true;
      cocosPointer = {clientX: event.clientX, clientY: event.clientY};
    }
  });
  harness.canvas.addEventListener('mouseup', (event) => {
    if (event.button === 0 && leftPressed) {
      plantedTiles.push(cocosPointer);
    }
    leftPressed = false;
  });

  const tap = createTouch(9, harness.canvas, 180, 90);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [tap],
    changedTouches: [tap],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [tap],
  }));
  assert.deepEqual(
    plantedTiles,
    [{clientX: 180, clientY: 90}],
    'tap planting requires the APK mouse-down and mouse-up sequence',
  );

  const dragStart = createTouch(10, harness.canvas, 60, 50);
  const dragEnd = createTouch(10, harness.canvas, 240, 130);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [dragStart],
    changedTouches: [dragStart],
  }));
  harness.advanceTime(6000);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [dragEnd],
    changedTouches: [dragEnd],
  }));
  harness.advanceTime(6000);
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [dragEnd],
  }));
  assert.deepEqual(
    plantedTiles,
    [
      {clientX: 180, clientY: 90},
      {clientX: 240, clientY: 130},
    ],
    'the fallback mouse stream releases at the final pointer position',
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
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [end],
    changedTouches: [end],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [end],
  }));

  assert.deepEqual(canvasEvents, [
    {type: 'mousedown', clientX: 60, clientY: 50},
    {type: 'mousemove', clientX: 240, clientY: 130},
    {type: 'mouseup', clientX: 240, clientY: 130},
  ], 'the fallback drag must stay on GameCanvas');
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
  const harness = createTouchHarness();
  const leftEvents = [];
  let syntheticClicks = 0;
  for (const type of ['mousemove', 'mousedown', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      leftEvents.push({
        type: event.type,
        buttons: event.buttons,
        clientX: event.clientX,
        clientY: event.clientY,
      });
    });
  }
  harness.canvas.addEventListener('click', () => {
    syntheticClicks += 1;
  });

  const start = createTouch(12, harness.canvas, 70, 60);
  const end = createTouch(12, harness.canvas, 230, 140);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [start],
    changedTouches: [start],
  }));
  harness.flushAnimationFrame();
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [end],
    changedTouches: [end],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [end],
  }));

  assert.deepEqual(leftEvents, [
    {type: 'mousedown', buttons: 1, clientX: 70, clientY: 60},
    {type: 'mousemove', buttons: 1, clientX: 230, clientY: 140},
    {type: 'mouseup', buttons: 1, clientX: 230, clientY: 140},
  ], 'the fallback drag release must remain immediate');

  harness.flushAnimationFrame();
  harness.flushAnimationFrame();
  assert.deepEqual(leftEvents, [
    {type: 'mousedown', buttons: 1, clientX: 70, clientY: 60},
    {type: 'mousemove', buttons: 1, clientX: 230, clientY: 140},
    {type: 'mouseup', buttons: 1, clientX: 230, clientY: 140},
  ], 'the fallback must not schedule a replay');
  assert.equal(
    syntheticClicks,
    0,
    'the browser-owned touch path must not receive a synthetic click replay',
  );
}

{
  const harness = createTouchHarness();
  const draggedMoves = [];
  let leakedMoves = 0;
  harness.canvas.addEventListener('mousemove', (event) => {
    if (event.buttons === 1) {
      draggedMoves.push({
        clientX: event.clientX,
        clientY: event.clientY,
        target: event.target,
      });
    }
  });
  harness.document.addEventListener('touchmove', () => {
    leakedMoves += 1;
  });

  const start = createTouch(11, harness.canvas, 40, 30);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [start],
    changedTouches: [start],
  }));
  harness.flushAnimationFrame();

  const firstMove = createTouch(11, harness.canvas, 70, 50);
  const lastMove = createTouch(11, harness.canvas, 100, 80);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [firstMove],
    changedTouches: [firstMove],
  }));
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [lastMove],
    changedTouches: [lastMove],
  }));

  assert.deepEqual(draggedMoves, [
    {
      clientX: 70,
      clientY: 50,
      target: harness.canvas,
    },
    {
      clientX: 100,
      clientY: 80,
      target: harness.canvas,
    },
  ], 'every single-touch move must dispatch immediately');
  assert.equal(
    leakedMoves,
    0,
    'original game touch moves must be hidden like the APK extension',
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

  const unrelated = createTouch(54, harness.canvas, 150, 90);
  harness.document.dispatchEvent(createTouchEvent('touchmove', {
    touches: [unrelated],
    changedTouches: [unrelated],
  }));
  assert.deepEqual(
    dragMoves,
    [{clientX: 150, clientY: 90}],
    'the APK follows the sole current pointer without identifier capture',
  );

  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [unrelated],
  }));
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

console.log('touch input adapter contract passes');
