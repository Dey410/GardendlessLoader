import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const transportSource = fs.readFileSync(
  new URL('../assets/game_bridge/transport.js', import.meta.url),
  'utf8',
);
const gpNextCoreSource = fs.readFileSync(
  new URL('../assets/game_bridge/gp_next_core.js', import.meta.url),
  'utf8',
);
const gpNextCompatSource = fs.readFileSync(
  new URL('../assets/game_bridge/gp_next_compat_bridge.js', import.meta.url),
  'utf8',
);

function createTransportHarness({nativeAvailable = true} = {}) {
  const posted = [];
  const timers = new Map();
  let nextTimer = 1;
  const window = {
    addEventListener() {},
    dispatchEvent() {},
  };
  if (nativeAvailable) {
    window.gardendlessNative = {
      postMessage(raw) {
        posted.push(JSON.parse(raw));
      },
    };
  }
  const context = {
    Date,
    Error,
    Event: class Event {
      constructor(type) { this.type = type; }
    },
    JSON,
    Map,
    Promise,
    Set,
    String,
    clearTimeout(id) { timers.delete(id); },
    setTimeout(callback, delay) {
      const id = nextTimer++;
      timers.set(id, {callback, delay});
      return id;
    },
    window,
  };
  context.globalThis = context;
  vm.createContext(context);
  vm.runInContext(transportSource, context);
  return {transport: window.__gardendlessTransport, posted, timers};
}

{
  const harness = createTransportHarness();
  const first = harness.transport.invoke('host:first', {value: 1});
  const second = harness.transport.invoke('host:second', {value: 2});

  assert.equal(harness.posted.length, 2);
  assert.notEqual(harness.posted[0].id, harness.posted[1].id);
  assert.equal(harness.posted[0].namespace, 'host');
  assert.deepEqual(harness.posted[0].args, {value: 1});

  assert.equal(harness.transport.resolve({
    id: harness.posted[1].id,
    ok: true,
    value: 'second-result',
  }), true);
  assert.equal(harness.transport.resolve({
    id: harness.posted[0].id,
    ok: true,
    value: 'first-result',
  }), true);
  assert.equal(await first, 'first-result');
  assert.equal(await second, 'second-result');
  assert.equal(harness.transport.resolve({
    id: harness.posted[0].id,
    ok: true,
    value: 'duplicate',
  }), false);
  assert.equal(harness.transport.resolve('{invalid-json'), false);
}

{
  const harness = createTransportHarness();
  await assert.rejects(
    harness.transport.invoke('host:oversized', {
      data: 'x'.repeat(1024 * 1024),
    }),
    /too large/,
  );
  assert.equal(harness.posted.length, 0);
}

{
  const harness = createTransportHarness();
  const pending = harness.transport.invoke('host:wait', {});
  const timer = Array.from(harness.timers.values()).find(
    (entry) => entry.delay === 15000,
  );
  assert(timer, 'normal bridge timeout was not registered');
  timer.callback();
  await assert.rejects(pending, /timed out/);
}

{
  const harness = createTransportHarness();
  const pending = harness.transport.invoke('host:exportCommit', {});
  assert(Array.from(harness.timers.values()).some(
    (entry) => entry.delay === 5 * 60 * 1000,
  ));
  harness.transport.rejectAll('host_destroyed', 'destroyed');
  await assert.rejects(pending, (error) => {
    assert.equal(error.code, 'host_destroyed');
    return true;
  });
}

{
  const harness = createTransportHarness({nativeAvailable: false});
  await assert.rejects(
    harness.transport.invoke('host:unavailable', {}),
    /unavailable/,
  );
}

{
  const nativeCalls = [];
  const window = {
    __gardendlessHostConfig: {gpNextBaseDirectory: '/data/GardendlessLoader'},
    __gardendlessTransport: {
      async invoke(command, payload) {
        nativeCalls.push({command, payload});
        return command === 'plugin:fs|exists';
      },
    },
  };
  const context = {
    Array,
    ArrayBuffer,
    Error,
    JSON,
    Object,
    Promise,
    Set,
    String,
    Uint8Array,
    window,
  };
  context.globalThis = context;
  vm.createContext(context);
  vm.runInContext(gpNextCoreSource, context);
  vm.runInContext(gpNextCompatSource, context);

  assert.equal(
    await window.__TAURI_INTERNALS__.invoke('plugin:drpc|is_running', {}, {}),
    false,
  );
  assert.equal(
    await window.__TAURI_INTERNALS__.invoke(
      'plugin:window|is_maximized',
      {label: 'main'},
      {},
    ),
    false,
  );
  for (const command of [
    'plugin:window|set_size',
    'plugin:window|set_fullscreen',
    'plugin:window|center',
    'plugin:window|close',
    'open_devtools',
  ]) {
    assert.equal(
      await window.__TAURI_INTERNALS__.invoke(command, {label: 'main'}, {}),
      null,
      command,
    );
  }
  assert.equal(nativeCalls.length, 0, 'optional GP-Next commands stay in the shared core');

  const exists = await window.__TAURI_INTERNALS__.invoke(
    'plugin:fs|exists',
    {path: 'gp-next/packs/a.zip'},
    {baseDir: 14},
  );
  assert.equal(exists, true);
  assert.equal(nativeCalls[0].command, 'plugin:fs|exists');
  assert.equal(nativeCalls[0].payload.namespace, 'gp-next');
  assert.equal(
    JSON.stringify(nativeCalls[0].payload.args),
    JSON.stringify({path: 'gp-next/packs/a.zip'}),
  );
  assert.equal(
    JSON.stringify(nativeCalls[0].payload.options),
    JSON.stringify({baseDir: 14}),
  );

  await window.__TAURI_INTERNALS__.invoke(
    'plugin:fs|write_text_file',
    new Uint8Array([1, 2, 255]),
    {},
  );
  assert.equal(
    JSON.stringify(nativeCalls[1].payload.args.__gardendlessBytes),
    JSON.stringify([1, 2, 255]),
  );
}

console.log('game bridge concurrency, timeout, validation, teardown, and GP-Next forwarding pass');
