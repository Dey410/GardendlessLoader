import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const touchPatchSource = fs.readFileSync(
  new URL('../assets/game_bridge/touch_patch.js', import.meta.url),
  'utf8',
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
  devicePixelRatio = 1,
  hostConfig = {},
  pointTarget = null,
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
    body: canvas,
    createElement: (tagName) => createElement({
      tagName: tagName.toUpperCase(),
      textContent: '',
    }),
    documentElement: documentRoot,
    elementFromPoint: () => pointTarget ?? canvas,
    getElementById: (id) => {
      if (id === 'GameCanvas') {
        return canvas;
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
  vm.runInContext(touchPatchSource, context);

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
      now += 16;
      for (const callback of pending) {
        callback(now);
      }
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
    rerunTouchPatch() {
      vm.runInContext(touchPatchSource, context);
    },
    window,
  };
}

{
  const harness = createTouchHarness({
    hostConfig: {nativeSingleTouchMouse: true},
  });
  const mouseEvents = [];
  let leakedTouches = 0;
  for (const type of ['mousedown', 'mousemove', 'mouseup']) {
    harness.canvas.addEventListener(type, (event) => {
      mouseEvents.push(event.type);
    });
  }
  for (const type of ['touchstart', 'touchmove', 'touchend']) {
    harness.document.addEventListener(type, () => {
      leakedTouches += 1;
    });
  }

  const start = createTouch(1, harness.canvas, 40, 40);
  const move = createTouch(1, harness.canvas, 160, 100);
  const startEvent = createTouchEvent('touchstart', {
    touches: [start],
    changedTouches: [start],
  });
  const moveEvent = createTouchEvent('touchmove', {
    touches: [move],
    changedTouches: [move],
  });
  const endEvent = createTouchEvent('touchend', {
    touches: [],
    changedTouches: [move],
  });

  harness.document.dispatchEvent(startEvent);
  harness.document.dispatchEvent(moveEvent);
  harness.document.dispatchEvent(endEvent);
  harness.flushAnimationFrame();

  assert.deepEqual(
    mouseEvents,
    [],
    'the Android native mouse path must not be duplicated by JavaScript',
  );
  assert.equal(
    leakedTouches,
    0,
    'native-mapped game touches must still be hidden from Cocos touch input',
  );
  assert.equal(startEvent.defaultPrevented, true);
  assert.equal(moveEvent.defaultPrevented, true);
  assert.equal(endEvent.defaultPrevented, true);
}

{
  const input = createElement({tagName: 'INPUT'});
  const harness = createTouchHarness({
    hostConfig: {nativeSingleTouchMouse: true},
  });
  let leakedNativeMouseEvents = 0;
  for (const type of ['mousemove', 'mousedown', 'mouseup']) {
    harness.document.addEventListener(type, () => {
      leakedNativeMouseEvents += 1;
    });
  }

  const touch = createTouch(2, input, 30, 20);
  harness.document.dispatchEvent(createTouchEvent('touchstart', {
    touches: [touch],
    changedTouches: [touch],
  }));
  harness.document.dispatchEvent(new TestMouseEvent('mousemove', {
    cancelable: true,
  }));
  harness.document.dispatchEvent(new TestMouseEvent('mousedown', {
    cancelable: true,
  }));
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [touch],
  }));
  harness.document.dispatchEvent(new TestMouseEvent('mouseup', {
    cancelable: true,
  }));

  assert.equal(
    leakedNativeMouseEvents,
    0,
    'host-injected mouse events must not duplicate browser-owned native controls',
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
  assert.equal(
    leakedCancellations,
    interruption.name === 'touch cancellation' ? 2 : 0,
    'APK-style touch cancellation is not intercepted for game input',
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
  const styles = harness.appendedElements.filter(
    (element) => element.tagName === 'STYLE',
  );
  assert.equal(styles.length, 1, 'touch-action style must be installed once');
  assert.match(styles[0].textContent, /#GameCanvas/);
  assert.match(styles[0].textContent, /touch-action:\s*none/);

  harness.rerunTouchPatch();
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

console.log('touch patch input contract passes');
