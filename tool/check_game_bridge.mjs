import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../assets/game_bridge/transport.js', import.meta.url), 'utf8');

function harness({available = true, failChunk = false, shortRead = false, autoRespond = true} = {}) {
  const requests = [];
  const timers = new Map();
  const handles = new Map();
  const files = new Map([['gp-next/packs/test.zip', Uint8Array.from({length: 190003}, (_, i) => i % 256)]]);
  let nextId = 0;
  let timerId = 0;
  const window = {
    __gardendlessHostConfig: {platform: 'android', hostAbi: 1, hasGpNext: true,
      gpNextCompatible: true, gpNextBaseDirectory: '/app/GardendlessLoader'},
    addEventListener() {}, dispatchEvent() {},
  };
  function respond(request, ok, value) {
    queueMicrotask(() => window.__gardendlessTransport.resolve({id: request.id, ok,
      ...(ok ? {value} : {error: {code: 'test_failure', message: value}})}));
  }
  if (available) window.gardendlessNative = {postMessage(raw) {
    const request = JSON.parse(raw);
    requests.push(request);
    if (!autoRespond) return;
    const a = request.args;
    try {
      let value = null;
      if (request.command === 'file:begin') {
        assert.equal(a.destination, 'gp-next');
        const bytes = a.mode === 'read' ? files.get(a.path) : new Uint8Array(a.totalBytes);
        if (!bytes) throw new Error('missing file');
        const handle = `handle-${++nextId}`;
        handles.set(handle, {mode: a.mode, bytes, path: a.path, offset: 0, index: 0});
        value = {handle, sizeBytes: bytes.length};
      } else if (request.command === 'file:chunk') {
        const h = handles.get(a.handle);
        assert(h, 'unknown handle');
        assert.equal(a.offset, h.offset);
        assert.equal(a.index, h.index++);
        if (h.mode === 'read') {
          assert(a.length <= 65536);
          const count = shortRead ? a.length - 1 : a.length;
          value = {data: Buffer.from(h.bytes.subarray(a.offset, a.offset + count)).toString('base64')};
          h.offset += count;
        } else {
          if (failChunk) throw new Error('write failed');
          const bytes = Buffer.from(a.data, 'base64');
          assert(bytes.length <= 65536);
          h.bytes.set(bytes, h.offset);
          h.offset += bytes.length;
        }
      } else if (request.command === 'file:finish') {
        const h = handles.get(a.handle);
        assert(h, 'unknown finish handle');
        if (a.action === 'commit') {
          assert.equal(h.offset, h.bytes.length);
          files.set(h.path, h.bytes);
        }
        handles.delete(a.handle);
      } else if (request.command === 'plugin:fs|exists') {
        value = files.has(a.path);
      } else if (request.command.startsWith('host:')) {
        value = a;
      } else {
        throw new Error(`unexpected command ${request.command}`);
      }
      respond(request, true, value);
    } catch (error) { respond(request, false, error.message); }
  }};
  const context = vm.createContext({window, Array, ArrayBuffer, Uint8Array, Blob,
    TextEncoder, TextDecoder, URL, Date, JSON, Math, Map, Set, Promise, Error,
    Event: class Event {}, CustomEvent: class CustomEvent {}, console,
    btoa: (v) => Buffer.from(v, 'binary').toString('base64'),
    atob: (v) => Buffer.from(v, 'base64').toString('binary'),
    clearTimeout(id) {timers.delete(id);},
    setTimeout(callback, delay) {const id = ++timerId; timers.set(id, {callback, delay}); return id;},
  });
  vm.runInContext(source, context);
  return {window, requests, timers, handles, files, transport: window.__gardendlessTransport};
}

{
  const h = harness();
  const result = await h.window.__TAURI_INTERNALS__.invoke('plugin:fs|read_file',
    {path: 'gp-next/packs/test.zip', options: {baseDir: 14}});
  assert(result instanceof ArrayBuffer, 'Tauri invoke must return ArrayBuffer, never a whole JSON number array');
  assert.deepEqual(new Uint8Array(result), h.files.get('gp-next/packs/test.zip'));
  assert.equal(h.requests[0].command, 'file:begin');
  assert.equal(h.requests.at(-1).args.action, 'close');
  assert.equal(h.handles.size, 0);
  assert(h.requests.every((r) => JSON.stringify(r).length < 100000));
}

{
  const h = harness();
  const backing = Uint8Array.from({length: 240017}, (_, i) => (i * 7) % 256);
  const input = backing.subarray(17, 230004);
  await h.window.__TAURI_INTERNALS__.invoke('plugin:fs|write_file', input,
    {headers: {path: encodeURIComponent('gp-next/installed/a b.bin'), options: JSON.stringify({baseDir: 14})}});
  assert.deepEqual(h.files.get('gp-next/installed/a b.bin'), input, 'subview must not include prefix/suffix bytes');
  assert.equal(h.requests[0].args.options.baseDir, 14);
  assert(h.requests.filter((r) => r.command === 'file:chunk').every((r) => Buffer.from(r.args.data, 'base64').length <= 65536));
  assert(h.requests.every((r) => !JSON.stringify(r).includes('__gardendlessBytes')));
  assert.equal(h.handles.size, 0);
}

{
  const h = harness();
  await h.window.__TAURI_INTERNALS__.invoke('plugin:fs|write_text_file', new Uint8Array(0),
    {headers: {path: 'gp-next/empty.txt', options: '{}'}});
  assert.equal(h.files.get('gp-next/empty.txt').length, 0);
  assert.deepEqual(h.requests.map((r) => r.command), ['file:begin', 'file:finish']);
}

{
  const h = harness();
  const text = 'a'.repeat(65535) + '中文🌻'.repeat(17000);
  const bytes = new TextEncoder().encode(text);
  const invoke = h.window.__TAURI_INTERNALS__.invoke;
  await invoke('plugin:fs|write_text_file', bytes,
    {headers: {path: encodeURIComponent('gp-next/文本.json'), options: '{}'}});
  const result = await invoke('plugin:fs|read_text_file', {path: 'gp-next/文本.json'});
  assert(result instanceof ArrayBuffer);
  assert.equal(new TextDecoder().decode(result), text, 'UTF-8 crossing chunk boundaries must be decoded once');
}

{
  const h = harness({failChunk: true});
  await assert.rejects(h.window.__TAURI_INTERNALS__.invoke('plugin:fs|write_file', new Uint8Array(80000),
    {headers: {path: 'gp-next/fail.bin', options: '{}'}}), /write failed/);
  assert.equal(h.requests.at(-1).args.action, 'cancel');
  assert.equal(h.handles.size, 0);
  assert(!h.files.has('gp-next/fail.bin'));
}

{
  const h = harness({shortRead: true});
  await assert.rejects(h.window.__TAURI_INTERNALS__.invoke('plugin:fs|read_file',
    {path: 'gp-next/packs/test.zip'}), /length|short/i);
  assert.equal(h.requests.at(-1).args.action, 'cancel');
  assert.equal(h.handles.size, 0);
}

{
  const h = harness();
  assert.equal(await h.window.__TAURI_INTERNALS__.invoke('plugin:drpc|is_running', {}), false);
  assert.equal(await h.window.__TAURI_INTERNALS__.invoke('plugin:window|set_size', {}), null);
  assert.equal(h.requests.length, 0);
  const pending = h.transport.invoke('host:wait');
  const id = h.requests.at(-1).id;
  assert.equal(await pending instanceof Object, true);
  assert.equal(h.transport.resolve({id, ok: true, value: 'duplicate'}), false);
  await assert.rejects(h.transport.invoke('host:oversized', {data: '界'.repeat(400000)}), /too large/);
}

{
  const h = harness({available: false});
  await assert.rejects(h.transport.invoke('host:no-native'), /unavailable/);
}

{
  const h = harness({autoRespond: false});
  const calls = Array.from({length: 64}, () => h.transport.invoke('host:wait'));
  const all = Promise.allSettled(calls);
  await assert.rejects(h.transport.invoke('host:full'), {code: 'resource_limit_exceeded'});
  const cancel = h.transport.invoke('file:finish', {args: {handle: 'live', action: 'cancel'}});
  const cancelled = assert.rejects(cancel, {code: 'host_destroyed'});
  assert.equal(h.requests.at(-1).args.action, 'cancel', 'cancellation must bypass ordinary admission limit');
  h.transport.rejectAll();
  assert.equal((await all).every((r) => r.status === 'rejected' && r.reason.code === 'host_destroyed'), true);
  await cancelled;
  assert.equal(h.timers.size, 0);
  await assert.rejects(h.transport.invoke('host:after-exit'), {code: 'host_destroyed'});
}

{
  const h = harness({autoRespond: false});
  const waiting = h.transport.invoke('host:wait');
  const deadline = assert.rejects(waiting, {code: 'deadline_exceeded'});
  const timer = [...h.timers.values()][0];
  assert.equal(timer.delay, 15000);
  timer.callback();
  await deadline;
  assert.equal(h.transport.resolve({id: h.requests[0].id, ok: true, value: 'late'}), false);
  const picker = h.transport.invoke('file:finish', {args: {handle: 'export', action: 'commit'}});
  const ended = assert.rejects(picker, {code: 'host_destroyed'});
  assert.equal([...h.timers.values()].at(-1).delay, 300000);
  h.transport.rejectAll();
  await ended;
}

{
  const h = harness({autoRespond: false});
  const writes = Array.from({length: 18}, (_, i) => h.transport.writeFile(new Uint8Array(1),
    {destination: 'gp-next', path: `queued-${i}`}));
  const settled = Promise.allSettled(writes);
  await Promise.resolve();
  assert.equal(h.requests.length, 1, 'file transfers must await backpressure');
  h.transport.rejectAll();
  const results = await settled;
  assert.equal(results.filter((r) => r.status === 'rejected' && r.reason.code === 'resource_limit_exceeded').length, 1);
  assert.equal(results.filter((r) => r.status === 'rejected' && r.reason.code === 'host_destroyed').length, 17);
}

console.log('unified file bridge: binary reads, bounded subview writes, empty files, failures, cancellation and RPC pass');
