import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(
  new URL('../assets/game_bridge/auto_sun.js', import.meta.url),
  'utf8',
);

class TestKeyboardEvent extends Event {
  constructor(type, options = {}) {
    super(type, options);
    Object.assign(this, {
      key: options.key ?? '',
      code: options.code ?? '',
      keyCode: options.keyCode ?? 0,
      which: options.which ?? 0,
      repeat: options.repeat ?? false,
    });
  }
}

function createElement(tagName = 'DIV') {
  const element = new EventTarget();
  Object.assign(element, {
    tagName,
    isContentEditable: false,
    getAttribute: () => null,
  });
  return element;
}

function createHarness({
  enabled = true,
  hasGpNext = false,
  gaming = true,
  modulesAvailable = true,
  modulesRegistered = true,
  unexpectedExports = false,
  realV010Exports = false,
} = {}) {
  let now = 0;
  let nextTimerId = 1;
  let modulesReady = modulesAvailable;
  let getCount = 0;
  let importCount = 0;
  const timers = new Map();
  const errors = [];
  const keyboardEvents = [];
  const levelController = {gaming, AirRaidProps: null};
  const UI = {component: {paused: false}};
  const levelModuleExports = realV010Exports
    ? {
        LevelPlay: levelController,
        levelController: function LevelController() {},
      }
    : {levelController};
  let uiModuleExports;
  if (realV010Exports) {
    function UIInGame() {}
    UIInGame.component = UI.component;
    uiModuleExports = {UIInGame};
  } else {
    uiModuleExports = {UI};
  }
  const body = createElement('BODY');
  const canvas = createElement('CANVAS');
  canvas.id = 'GameCanvas';
  for (const type of ['keydown', 'keyup']) {
    canvas.addEventListener(type, (event) => {
      keyboardEvents.push({
        type: event.type,
        key: event.key,
        code: event.code,
        keyCode: event.keyCode,
        which: event.which,
        repeat: event.repeat,
        at: now,
      });
    });
  }

  const document = new EventTarget();
  Object.assign(document, {
    activeElement: body,
    body,
    hidden: false,
    readyState: 'complete',
    getElementById: (id) => id === 'GameCanvas' ? canvas : null,
  });
  const window = new EventTarget();
  window.__gardendlessHost = {
    config: {autoCollectSunEnabled: enabled, hasGpNext},
  };
  const levelId = 'chunks:///_virtual/levelController.ts';
  const uiId = 'chunks:///_virtual/UI.ts';
  window.System = {
    get(path) {
      getCount += 1;
      if (!modulesReady) return undefined;
      if (unexpectedExports) return {};
      if (path.endsWith('levelController.ts')) return levelModuleExports;
      if (path.endsWith('UI.ts')) return uiModuleExports;
      throw new Error(`Unexpected module: ${path}`);
    },
    async import(path) {
      importCount += 1;
      if (!modulesRegistered) {
        throw new Error('early System.import poisons cold game startup');
      }
      modulesReady = true;
      if (path === levelId) return levelModuleExports;
      if (path === uiId) return uiModuleExports;
      throw new Error(`Unexpected module: ${path}`);
    },
    registerRegistry: modulesRegistered ? {
      [levelId]: [{}, () => {}],
      [uiId]: [{}, () => {}],
    } : {},
  };

  const context = {
    Event,
    KeyboardEvent: TestKeyboardEvent,
    Map,
    Object,
    Promise,
    Set,
    String,
    clearTimeout(id) {
      timers.delete(id);
    },
    console: {
      error(...values) {
        errors.push(values);
      },
    },
    document,
    performance: {now: () => now},
    setTimeout(callback, delay = 0) {
      const id = nextTimerId++;
      timers.set(id, {at: now + delay, callback});
      return id;
    },
    window,
  };
  context.globalThis = context;
  vm.createContext(context);

  async function flushMicrotasks() {
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
  }

  async function advance(milliseconds) {
    const target = now + milliseconds;
    while (true) {
      let selectedId = null;
      let selected = null;
      for (const [id, timer] of timers) {
        if (timer.at > target) continue;
        if (selected === null || timer.at < selected.at ||
            (timer.at === selected.at && id < selectedId)) {
          selectedId = id;
          selected = timer;
        }
      }
      if (selected === null) break;
      now = selected.at;
      timers.delete(selectedId);
      selected.callback();
      await flushMicrotasks();
    }
    now = target;
    await flushMicrotasks();
  }

  function run() {
    vm.runInContext(source, context);
  }

  run();

  return {
    UI,
    advance,
    body,
    document,
    errors,
    flushMicrotasks,
    get getCount() {
      return getCount;
    },
    get importCount() {
      return importCount;
    },
    keyboardEvents,
    levelController,
    rerun: run,
    setActiveElement(element) {
      document.activeElement = element;
      document.dispatchEvent(new Event('focusin'));
    },
    setHidden(hidden) {
      document.hidden = hidden;
      document.dispatchEvent(new Event('visibilitychange'));
    },
    setModulesAvailable(available) {
      modulesReady = available;
    },
    window,
  };
}

for (const options of [
  {enabled: false, hasGpNext: false},
  {enabled: false, hasGpNext: true},
]) {
  const harness = createHarness(options);
  await harness.flushMicrotasks();
  await harness.advance(10000);
  assert.equal(harness.getCount, 0);
  assert.equal(harness.importCount, 0);
  assert.deepEqual(harness.keyboardEvents, []);
}

{
  const harness = createHarness({enabled: true, hasGpNext: true});
  await harness.flushMicrotasks();
  assert.equal(harness.getCount, 2);
  assert.equal(harness.importCount, 0);

  await harness.advance(2999);
  assert.deepEqual(harness.keyboardEvents, []);
  await harness.advance(1);
  assert.deepEqual(harness.keyboardEvents, [{
    type: 'keydown',
    key: 'a',
    code: 'KeyA',
    keyCode: 65,
    which: 65,
    repeat: false,
    at: 3000,
  }]);
  await harness.advance(49);
  assert.equal(harness.keyboardEvents.length, 1);
  await harness.advance(1);
  assert.deepEqual(harness.keyboardEvents[1], {
    type: 'keyup',
    key: 'a',
    code: 'KeyA',
    keyCode: 65,
    which: 65,
    repeat: false,
    at: 3050,
  });

  await harness.advance(2950);
  assert.equal(harness.keyboardEvents[2].type, 'keydown');
  assert.equal(harness.keyboardEvents[2].at, 6000);
}

{
  const harness = createHarness();
  await harness.flushMicrotasks();
  assert.equal(harness.getCount, 2);
  assert.equal(harness.importCount, 0);

  await harness.advance(2999);
  assert.deepEqual(harness.keyboardEvents, []);
  await harness.advance(1);
  assert.deepEqual(harness.keyboardEvents, [{
    type: 'keydown',
    key: 'a',
    code: 'KeyA',
    keyCode: 65,
    which: 65,
    repeat: false,
    at: 3000,
  }]);
  await harness.advance(49);
  assert.equal(harness.keyboardEvents.length, 1);
  await harness.advance(1);
  assert.deepEqual(harness.keyboardEvents[1], {
    type: 'keyup',
    key: 'a',
    code: 'KeyA',
    keyCode: 65,
    which: 65,
    repeat: false,
    at: 3050,
  });

  await harness.advance(2950);
  assert.equal(harness.keyboardEvents[2].type, 'keydown');
  assert.equal(harness.keyboardEvents[2].at, 6000);
}

{
  const harness = createHarness({realV010Exports: true});
  await harness.flushMicrotasks();
  assert.equal(harness.getCount, 2);
  assert.equal(harness.importCount, 0);

  await harness.advance(2999);
  assert.deepEqual(harness.keyboardEvents, []);
  await harness.advance(1);
  assert.equal(harness.keyboardEvents[0].type, 'keydown');
  assert.equal(harness.keyboardEvents[0].keyCode, 65);
}

{
  const harness = createHarness({
    modulesAvailable: false,
    modulesRegistered: false,
  });
  await harness.flushMicrotasks();
  await harness.advance(1000);
  assert.equal(harness.importCount, 0);
  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.keyboardEvents, []);

  harness.setModulesAvailable(true);
  await harness.advance(249);
  assert.deepEqual(harness.keyboardEvents, []);
  await harness.advance(1);
  assert.equal(harness.importCount, 0);
  await harness.advance(2999);
  assert.deepEqual(harness.keyboardEvents, []);
  await harness.advance(1);
  assert.equal(harness.keyboardEvents[0].type, 'keydown');
}

{
  const harness = createHarness({
    modulesAvailable: false,
    modulesRegistered: true,
  });
  await harness.flushMicrotasks();
  assert.equal(harness.importCount, 2);
  await harness.advance(2999);
  assert.deepEqual(harness.keyboardEvents, []);
  await harness.advance(1);
  assert.equal(harness.keyboardEvents[0].type, 'keydown');
}

{
  const harness = createHarness({gaming: false});
  await harness.flushMicrotasks();
  await harness.advance(5000);
  assert.deepEqual(harness.keyboardEvents, []);
  harness.levelController.gaming = true;
  await harness.advance(3249);
  assert.deepEqual(harness.keyboardEvents, []);
  await harness.advance(1);
  assert.equal(harness.keyboardEvents[0].type, 'keydown');
}

{
  const harness = createHarness();
  await harness.flushMicrotasks();
  await harness.advance(2000);
  harness.UI.component.paused = true;
  await harness.advance(250);
  harness.UI.component.paused = false;
  await harness.advance(3249);
  assert.deepEqual(harness.keyboardEvents, []);
  await harness.advance(1);
  assert.equal(harness.keyboardEvents[0].type, 'keydown');
}

for (const invalidate of [
  (harness) => {
    harness.setHidden(true);
    harness.setHidden(false);
  },
  (harness) => {
    harness.setActiveElement(createElement('INPUT'));
    harness.setActiveElement(harness.body);
  },
  (harness) => {
    harness.setActiveElement(createElement('SELECT'));
    harness.setActiveElement(harness.body);
  },
  (harness) => {
    const editable = createElement();
    editable.isContentEditable = true;
    harness.setActiveElement(editable);
    harness.setActiveElement(harness.body);
  },
  (harness) => {
    harness.window.dispatchEvent(new Event('blur'));
    harness.window.dispatchEvent(new Event('focus'));
  },
  (harness) => {
    harness.levelController.AirRaidProps = {};
  },
  (harness) => {
    harness.levelController.gaming = false;
  },
]) {
  const harness = createHarness();
  await harness.flushMicrotasks();
  await harness.advance(2000);
  invalidate(harness);
  await harness.advance(1000);
  assert.deepEqual(
    harness.keyboardEvents,
    [],
    'an invalid state must cancel the pending collection cycle',
  );
}

{
  const harness = createHarness({unexpectedExports: true});
  await harness.flushMicrotasks();
  await harness.advance(10000);
  harness.rerun();
  await harness.flushMicrotasks();
  assert.deepEqual(harness.keyboardEvents, []);
  assert.equal(harness.errors.length, 1);
}

{
  const harness = createHarness();
  harness.rerun();
  await harness.flushMicrotasks();
  await harness.advance(3000);
  assert.equal(
    harness.keyboardEvents.filter((event) => event.type === 'keydown').length,
    1,
  );
}

console.log('automatic sun collection contract passes');
