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

function createTouchHarness({devicePixelRatio = 1, pointTarget = null} = {}) {
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
  harness.flushAnimationFrame();
  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [touch],
  }));

  assert.deepEqual(mouseEvents, [
    {
      type: 'mousemove',
      button: 0,
      buttons: 0,
      clientX: 120,
      clientY: 80,
    },
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
      buttons: 0,
      clientX: 120,
      clientY: 80,
    },
  ]);
  assert.equal(
    leakedTouches,
    0,
    'game touch events must not reach Cocos listeners',
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

  assert.deepEqual(
    draggedMoves,
    [],
    'drag moves should be coalesced until the next animation frame',
  );
  harness.flushAnimationFrame();
  assert.deepEqual(draggedMoves, [{
    clientX: 100,
    clientY: 80,
    target: harness.canvas,
  }]);
  assert.equal(
    leakedMoves,
    0,
    'game touch moves must not reach Cocos listeners',
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

  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [secondMove],
  }));
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
    {type: 'mousedown', clientX: 40, clientY: 40},
    {type: 'mouseup', clientX: 60, clientY: 60},
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
    leftButtonEvents.filter((event) => event.type === 'mousedown').length,
    1,
    'the remaining finger must not restart a left-button gesture',
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
  harness.flushAnimationFrame();
  assert.deepEqual(
    dragMoves,
    [],
    'moving a non-active touch must not move the captured left button',
  );

  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [active],
    changedTouches: [unrelated],
  }));
  assert.deepEqual(
    mouseUps,
    [],
    'ending a non-active touch must not release the captured left button',
  );

  harness.document.dispatchEvent(createTouchEvent('touchend', {
    touches: [],
    changedTouches: [active],
  }));
  assert.deepEqual(mouseUps, [{clientX: 70, clientY: 50}]);
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

  assert.deepEqual(
    mouseUps,
    [{button: 0, buttons: 0}],
    `${interruption.name} must release the pressed mouse exactly once`,
  );
  assert.equal(
    leakedCancellations,
    0,
    'touch cancellation must not reach Cocos listeners',
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
  assert.equal(mouseDowns, 1, 'reinstalling the patch must not duplicate input');
}

console.log('touch patch input contract passes');
