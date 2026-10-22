'use strict';

// Exercises transpiled production .ets code. All filesystem APIs below are
// in-memory platform doubles; this suite never creates or removes disk fixtures.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');
const ts = require(process.env.OHOS_TYPESCRIPT_PATH || 'typescript');
const sourceRoot = path.resolve(__dirname, '../entry/src/main/ets');

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function harness(hasGpNext = true) {
  const nodes = new Map();
  const descriptors = new Map();
  const replies = [];
  const events = [];
  let nextFd = 10;
  let readGate = null;
  let renameGate = null;
  let shortRead = false;
  const pickerResult = deferred();
  const stat = (node) => ({
    size: node.bytes?.length || 0,
    isFile: () => node.kind === 'file',
    isDirectory: () => node.kind === 'directory',
    isSymbolicLink: () => node.kind === 'link',
  });
  const missing = () => Object.assign(new Error('missing'), { code: 13900002 });
  const fileNode = (target) => {
    const node = typeof target === 'number' ? descriptors.get(target)?.node : nodes.get(target);
    if (!node) throw missing();
    return node;
  };
  const memoryFs = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 2, CREATE: 64, TRUNC: 512, NOFOLLOW: 262144 },
    access: async (target) => nodes.has(target),
    statSync: (target) => stat(fileNode(target)),
    lstatSync: (target) => stat(fileNode(target)),
    lstat: async (target) => stat(fileNode(target)),
    stat: async (target) => stat(fileNode(target)),
    mkdir: async (target) => { nodes.set(target, { kind: 'directory' }); },
    listFile: async (target) => [...nodes.keys()].filter((name) => name.startsWith(target + '/') && !name.slice(target.length + 1).includes('/')).map((name) => name.slice(target.length + 1)),
    open: async (target, mode = 0) => {
      let node = nodes.get(target);
      if (!node && (mode & 64)) { node = { kind: 'file', bytes: Buffer.alloc(0) }; nodes.set(target, node); }
      if (!node) throw missing();
      if (node.kind === 'link' && (mode & 262144)) throw new Error('link rejected');
      if (mode & 512) node.bytes = Buffer.alloc(0);
      const fd = nextFd++;
      descriptors.set(fd, { node, target });
      return { fd };
    },
    close: async (fd) => { descriptors.delete(fd); },
    read: async (fd, array, options) => {
      if (readGate) await readGate.promise;
      const node = fileNode(fd);
      const count = Math.max(0, Math.min(options.length, node.bytes.length - options.offset) - (shortRead ? 1 : 0));
      new Uint8Array(array).set(node.bytes.subarray(options.offset, options.offset + count));
      return count;
    },
    write: async (fd, array, options) => {
      const node = fileNode(fd);
      const bytes = Buffer.from(array);
      const output = Buffer.alloc(Math.max(node.bytes.length, options.offset + options.length));
      node.bytes.copy(output);
      bytes.copy(output, options.offset, 0, options.length);
      node.bytes = output;
      return options.length;
    },
    fsync: async (fd) => { fileNode(fd); },
    rename: async (source, destination) => {
      if (renameGate) await renameGate.promise;
      const node = fileNode(source);
      nodes.set(destination, node);
      nodes.delete(source);
    },
    unlink: async (target) => { nodes.delete(target); },
    rmdir: async (target) => { nodes.delete(target); },
  };
  for (const folder of ['/sandbox', '/sandbox/docs', '/sandbox/gp-next', '/sandbox/gp-next/.exports']) nodes.set(folder, { kind: 'directory' });
  const util = {
    Type: { BASIC: 0 },
    generateRandomUUID: () => crypto.randomUUID(),
    TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
    TextDecoder: { create: () => ({ decodeToString: (bytes) => new TextDecoder().decode(bytes) }) },
    Base64Helper: class {
      async encodeToString(bytes) { return Buffer.from(bytes).toString('base64'); }
      async decode(data) { return new Uint8Array(Buffer.from(data, 'base64')); }
    },
  };
  const picker = {
    DocumentSaveOptions: class {}, DocumentSelectOptions: class {},
    DocumentViewPicker: class { save() { return pickerResult.promise; } async select() { return []; } },
    DocumentSelectMode: { FOLDER: 1, FILE: 0 },
  };
  const modules = new Map();
  function load(relative) {
    const filename = path.resolve(sourceRoot, relative + '.ets');
    if (modules.has(filename)) return modules.get(filename).exports;
    const module = { exports: {} };
    modules.set(filename, module);
    const javascript = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS },
      fileName: filename,
    }).outputText;
    const localRequire = (name) => {
      if (name === '@ohos.file.fs') return { default: memoryFs };
      if (name === '@kit.ArkTS') return { util, url: { URL: { parseURL: (value) => new URL(value) } } };
      if (name === '@kit.ArkWeb') return { WebNetErrorList: { NET_OK: 0, ERR_FAILED: -1 }, webview: {
        WebSchemeHandler: class { onRequestStart(callback) { this.start = callback; } onRequestStop(callback) { this.stop = callback; } },
        WebSchemeHandlerResponse: class {
          setNetErrorCode(value) { this.errorCode = value; } setStatus(value) { this.status = value; }
          setStatusText() {} setMimeType() {} setEncoding() {} setHeaderByName() {}
        },
      } };
      if (name === '@ohos.file.picker') return { default: picker };
      if (name === '@ohos/flutter_ohos') return { MethodChannel: class {} };
      if (name === '@kit.ArkUI') return { promptAction: { showDialog: async () => ({ index: 1 }) } };
      if (name.endsWith('/logging/AppLogStore')) return { appLogStore: { emit: (event) => events.push(event) } };
      if (name.endsWith('/picker/DocumentPickerOrientation')) return { withDocumentPickerOrientation: (_context, operation) => operation() };
      if (name.startsWith('.')) return load(path.relative(sourceRoot, path.resolve(path.dirname(filename), name)));
      throw new Error('Unexpected runtime import: ' + name);
    };
    vm.runInThisContext('(function(require,module,exports){' + javascript + '\n})', { filename })(localRequire, module, module.exports);
    return module.exports;
  }
  const { GameSession } = load('game/GameSession');
  const { GpNextNativeCore } = load('game/GpNextNativeCore');
  const session = new GameSession(JSON.stringify({ schemaVersion: 1, sessionId: 'session-one', platform: 'ohos', origin: GameSession.ORIGIN,
    resourceRoot: '/sandbox/docs', entryUrl: GameSession.ORIGIN + '/index.html', activationGeneration: 1,
    hasGpNext, gpNextCompatible: hasGpNext, watermarkEnabled: true, autoCollectSunEnabled: false,
    allowedRemoteHosts: [], gpNextRoot: '/sandbox/gp-next', exportTemporaryRoot: '/sandbox/gp-next/.exports' }));
  const core = new GpNextNativeCore(session);
  const invoke = (command, args) => core.invoke({ command, args });
  return { core, invoke, nodes, descriptors, replies, events, pickerResult, load, session,
    file: (name, bytes) => nodes.set('/sandbox/gp-next/' + name, { kind: 'file', bytes: Buffer.from(bytes) }),
    setReadGate: (value) => { readGate = value; }, setRenameGate: (value) => { renameGate = value; }, setShortRead: () => { shortRead = true; },
    bridge: () => {
      const { GameBridge } = load('game/GameBridge');
      const controller = { getLastJavascriptProxyCallingFrameUrl: () => GameSession.ORIGIN + '/index.html', runJavaScript: async (script) => {
        const prefix = 'window.__gardendlessTransport && window.__gardendlessTransport.resolve(';
        if (script.startsWith(prefix)) replies.push(JSON.parse(script.slice(prefix.length, -1)));
      } };
      return new GameBridge(controller, {}, session, () => {});
    },
  };
}

async function settle() { await new Promise((resolve) => setImmediate(resolve)); }

test('exact 64 KiB and final short chunk replace a file while an old reader keeps its version', async () => {
  const h = harness();
  try {
    h.file('save.bin', 'old-version');
    const reader = (await h.invoke('file:begin', { mode: 'read', destination: 'gp-next', path: 'gp-next/save.bin' })).value;
    const writer = (await h.invoke('file:begin', { mode: 'write', destination: 'gp-next', path: 'gp-next/save.bin', totalBytes: 65539 })).value;
    const first = Buffer.alloc(65536, 17); const tail = Buffer.from([3, 4, 5]);
    await h.invoke('file:chunk', { handle: writer.handle, index: 0, offset: 0, data: first.toString('base64') });
    await h.invoke('file:chunk', { handle: writer.handle, index: 1, offset: 65536, data: tail.toString('base64') });
    await h.invoke('file:finish', { handle: writer.handle, action: 'commit' });
    const read = await h.invoke('file:chunk', { handle: reader.handle, index: 0, offset: 0, length: reader.sizeBytes });
    assert.equal(Buffer.from(read.value.data, 'base64').toString(), 'old-version');
    assert.deepEqual(h.nodes.get('/sandbox/gp-next/save.bin').bytes, Buffer.concat([first, tail]));
    await h.invoke('file:finish', { handle: reader.handle, action: 'close' });
    await h.invoke('file:finish', { handle: writer.handle, action: 'commit' });
    assert.equal(h.descriptors.size, 0);
  } finally { h.core.destroy(); }
});

test('empty write creates or truncates with begin and commit only', async () => {
  const h = harness();
  try {
    h.file('empty.bin', 'before');
    const { handle } = (await h.invoke('file:begin', { mode: 'write', destination: 'gp-next', path: 'gp-next/empty.bin', totalBytes: 0 })).value;
    await h.invoke('file:finish', { handle, action: 'commit' });
    assert.equal(h.nodes.get('/sandbox/gp-next/empty.bin').bytes.length, 0);
  } finally { h.core.destroy(); }
});

test('incorrect ordering offsets encodings sizes and incomplete commits are rejected', async () => {
  const h = harness();
  try {
    const { handle } = (await h.invoke('file:begin', { mode: 'write', destination: 'gp-next', path: 'gp-next/save.bin', totalBytes: 3 })).value;
    for (const args of [{ index: 1, offset: 0, data: 'AQ==' }, { index: 0, offset: 1, data: 'AQ==' }, { index: 0, offset: 0, data: '%%%%' },
      { index: 0.5, offset: 0, data: 'AQ==' }, { index: 0, offset: 0, data: Buffer.alloc(65537).toString('base64') }, { index: 0, offset: 0, data: 'AQIDBA==' }]) {
      await assert.rejects(h.invoke('file:chunk', { handle, ...args }), { code: 'invalid_file_transfer' });
    }
    await assert.rejects(h.invoke('file:finish', { handle, action: 'commit' }), { code: 'invalid_file_transfer' });
    await h.invoke('file:finish', { handle, action: 'cancel' });
    assert.equal(h.nodes.has('/sandbox/gp-next/save.bin'), false);
  } finally { h.core.destroy(); }
});

test('short read fails explicitly rather than returning a partial successful buffer', async () => {
  const h = harness();
  try {
    h.file('short.bin', 'abcdef');
    const { handle } = (await h.invoke('file:begin', { mode: 'read', destination: 'gp-next', path: 'gp-next/short.bin' })).value;
    h.setShortRead();
    await assert.rejects(h.invoke('file:chunk', { handle, index: 0, offset: 0, length: 6 }), { code: 'io_failed' });
    await h.invoke('file:finish', { handle, action: 'cancel' });
  } finally { h.core.destroy(); }
});

test('standard sessions can export while GP file destinations and legacy commands are refused', async () => {
  const h = harness(false);
  try {
    await assert.rejects(h.invoke('file:begin', { mode: 'read', destination: 'gp-next', path: 'gp-next/a' }), { code: 'gp_next_unavailable' });
    const { handle } = (await h.invoke('file:begin', { mode: 'write', destination: 'export', totalBytes: 0, suggestedFilename: 'save.json' })).value;
    const commit = await h.invoke('file:finish', { handle, action: 'commit' });
    assert.equal(commit.exportHandle, handle); assert.equal(commit.suggestedFilename, 'save.json');
    await h.core.exportFinished(handle, true);
  } finally { h.core.destroy(); }
  const gp = harness();
  try {
    await assert.rejects(gp.invoke('plugin:fs|write_file', {}), { code: 'unsupported' });
    await assert.rejects(gp.invoke('plugin:fs|read_file', {}), { code: 'unsupported' });
  } finally { gp.core.destroy(); }
});

test('dialog save path selects the system export endpoint only on file commit', async () => {
  const h = harness();
  try {
    const save = await h.invoke('plugin:dialog|save', { options: { defaultPath: 'snapshot.json' } });
    const { handle } = (await h.invoke('file:begin', { mode: 'write', destination: 'gp-next', path: save.value, totalBytes: 0 })).value;
    const result = await h.invoke('file:finish', { handle, action: 'commit' });
    assert.equal(result.exportHandle, handle); assert.equal(result.suggestedFilename, 'snapshot.json');
    await h.invoke('file:finish', { handle, action: 'cancel' });
  } finally { h.core.destroy(); }
});

test('handle and file size budgets prevent additional descriptor acquisition', async () => {
  const h = harness();
  try {
    for (let index = 0; index < 8; index++) await h.invoke('file:begin', { mode: 'write', destination: 'gp-next', path: 'gp-next/file-' + index, totalBytes: 0 });
    await assert.rejects(h.invoke('file:begin', { mode: 'write', destination: 'export', totalBytes: 0 }), { code: 'resource_limit_exceeded' });
    assert.equal(h.descriptors.size, 8);
  } finally { h.core.destroy(); await settle(); }
  assert.equal(h.descriptors.size, 0);
});

test('cancel closes an in-flight descriptor and never commits its temporary contents', async () => {
  const h = harness(); const gate = deferred();
  try {
    h.file('read.bin', 'abc');
    const { handle } = (await h.invoke('file:begin', { mode: 'read', destination: 'gp-next', path: 'gp-next/read.bin' })).value;
    h.setReadGate(gate);
    const read = h.invoke('file:chunk', { handle, index: 0, offset: 0, length: 3 });
    const rejected = assert.rejects(read);
    await settle();
    await h.invoke('file:finish', { handle, action: 'cancel' });
    assert.equal(h.descriptors.size, 0);
    gate.resolve(); await rejected;
    await h.invoke('file:finish', { handle, action: 'cancel' });
  } finally { gate.resolve(); h.core.destroy(); }
});

test('bounded queue runs two tasks and admits cancellation when sixteen waiting tasks fill it', async () => {
  const h = harness(); const gate = deferred();
  try {
    const { handle } = (await h.invoke('file:begin', { mode: 'write', destination: 'export', totalBytes: 0 })).value;
    let active = 0; let maximum = 0;
    const work = async () => { active++; maximum = Math.max(maximum, active); await gate.promise; active--; };
    const running = [h.core.runIO(work), h.core.runIO(work)];
    const queued = Array.from({ length: 16 }, () => h.core.runIO(async () => {}));
    const displaced = assert.rejects(queued[15], { code: 'resource_limit_exceeded' });
    await assert.rejects(h.core.runIO(async () => {}), { code: 'resource_limit_exceeded' });
    const cancel = h.invoke('file:finish', { handle, action: 'cancel' });
    assert.equal(h.core.isFileActive(handle), false);
    gate.resolve();
    await Promise.all([...running, ...queued.slice(0, 15), cancel, displaced]);
    assert.equal(maximum, 2); assert.equal(h.descriptors.size, 0);
  } finally { gate.resolve(); h.core.destroy(); }
});

test('cancel after the atomic commit claim waits for the committed result', async () => {
  const h = harness(); const gate = deferred();
  try {
    const { handle } = (await h.invoke('file:begin', { mode: 'write', destination: 'gp-next', path: 'gp-next/committed.bin', totalBytes: 0 })).value;
    h.setRenameGate(gate);
    const commit = h.invoke('file:finish', { handle, action: 'commit' });
    await settle();
    const cancel = h.invoke('file:finish', { handle, action: 'cancel' });
    gate.resolve(); await Promise.all([commit, cancel]);
    assert.equal(h.nodes.has('/sandbox/gp-next/committed.bin'), true);
  } finally { gate.resolve(); h.core.destroy(); }
});

test('host namespace file export commit waits for the picker and actual document copy', async () => {
  const h = harness(false); const bridge = h.bridge();
  try {
    const send = (id, command, args) => bridge.postMessage(JSON.stringify({ id, namespace: 'host', command, args }));
    send('begin', 'file:begin', { mode: 'write', destination: 'export', totalBytes: 3, suggestedFilename: 'save.json' });
    await settle(); const handle = h.replies.find((reply) => reply.id === 'begin').value.handle;
    send('chunk', 'file:chunk', { handle, index: 0, offset: 0, data: 'AQID' }); await settle();
    send('commit', 'file:finish', { handle, action: 'commit' }); await settle();
    assert.equal(h.replies.some((reply) => reply.id === 'commit'), false);
    h.pickerResult.resolve(['file:///saved/save.json']); await settle(); await settle();
    assert.equal(h.replies.find((reply) => reply.id === 'commit').ok, true);
    assert.deepEqual(h.nodes.get('file:///saved/save.json').bytes, Buffer.from([1, 2, 3]));
  } finally { bridge.destroy(); h.core.destroy(); }
});

test('destroy rejects queued work closes descriptors and refuses late submissions', async () => {
  const h = harness(); const gate = deferred();
  const { handle } = (await h.invoke('file:begin', { mode: 'write', destination: 'export', totalBytes: 0 })).value;
  const work = [h.core.runIO(async () => gate.promise), h.core.runIO(async () => gate.promise), h.core.runIO(async () => {})];
  const rejected = work.map((promise) => assert.rejects(promise, { code: 'host_destroyed' }));
  h.core.destroy(); gate.resolve(); await Promise.all(rejected); await settle();
  assert.equal(h.descriptors.size, 0); assert.equal(h.core.isFileActive(handle), false);
  await assert.rejects(h.core.runIO(async () => {}), { code: 'host_destroyed' });
});

test('sandbox symlinks traversal duplicate writers and oversized files fail before commit', async () => {
  const h = harness();
  try {
    h.nodes.set('/sandbox/gp-next/link', { kind: 'link' });
    for (const name of ['gp-next/../outside', '/elsewhere/save.bin', 'gp-next/link/save.bin']) {
      await assert.rejects(h.invoke('file:begin', { mode: 'write', destination: 'gp-next', path: name, totalBytes: 0 }));
    }
    await assert.rejects(h.invoke('file:begin', { mode: 'read', destination: 'export' }), { code: 'unsupported' });
    await assert.rejects(h.invoke('file:begin', { mode: 'write', destination: 'export', totalBytes: 512 * 1024 * 1024 + 1 }));
    const { handle } = (await h.invoke('file:begin', { mode: 'write', destination: 'gp-next', path: 'gp-next/one.bin', totalBytes: 1 })).value;
    await assert.rejects(h.invoke('file:begin', { mode: 'write', destination: 'gp-next', path: 'gp-next/one.bin', totalBytes: 1 }), { code: 'invalid_file_transfer' });
    await h.invoke('file:finish', { handle, action: 'cancel' });
  } finally { h.core.destroy(); }
});

test('cancelled partial writes leave the previously committed contents intact', async () => {
  const h = harness();
  try {
    h.file('preserved.bin', 'previous');
    const { handle } = (await h.invoke('file:begin', { mode: 'write', destination: 'gp-next', path: 'gp-next/preserved.bin', totalBytes: 5 })).value;
    await h.invoke('file:chunk', { handle, index: 0, offset: 0, data: 'AQID' });
    await h.invoke('file:finish', { handle, action: 'cancel' });
    await assert.rejects(h.invoke('file:finish', { handle, action: 'commit' }), { code: 'cancelled' });
    assert.equal(h.nodes.get('/sandbox/gp-next/preserved.bin').bytes.toString(), 'previous');
  } finally { h.core.destroy(); }
});

test('native transfer deadline rejects work while still admitting cancellation', async () => {
  const h = harness(); const originalNow = Date.now;
  try {
    h.file('deadline.bin', 'abc');
    const { handle } = (await h.invoke('file:begin', { mode: 'read', destination: 'gp-next', path: 'gp-next/deadline.bin' })).value;
    const now = originalNow(); Date.now = () => now + 11 * 60 * 1000;
    await assert.rejects(h.invoke('file:chunk', { handle, index: 0, offset: 0, length: 3 }), { code: 'deadline_exceeded' });
    await h.invoke('file:finish', { handle, action: 'cancel' });
    assert.equal(h.descriptors.size, 0);
  } finally { Date.now = originalNow; h.core.destroy(); }
});

test('cancel while the picker is open rejects commit once and prevents a late document copy', async () => {
  const h = harness(false); const bridge = h.bridge();
  try {
    const send = (id, command, args) => bridge.postMessage(JSON.stringify({ id, namespace: 'host', command, args }));
    send('begin', 'file:begin', { mode: 'write', destination: 'export', totalBytes: 0 }); await settle();
    const handle = h.replies.find((reply) => reply.id === 'begin').value.handle;
    send('commit', 'file:finish', { handle, action: 'commit' }); await settle();
    send('cancel', 'file:finish', { handle, action: 'cancel' }); await settle();
    assert.equal(h.replies.find((reply) => reply.id === 'commit').error.code, 'cancelled');
    assert.equal(h.replies.find((reply) => reply.id === 'cancel').ok, true);
    h.pickerResult.resolve(['file:///saved/late.json']); await settle(); await settle();
    assert.equal(h.nodes.has('file:///saved/late.json'), false);
    assert.equal(h.replies.filter((reply) => reply.id === 'commit').length, 1);
  } finally { bridge.destroy(); h.core.destroy(); }
});

test('native bridge reserves eight close or cancel admissions after sixty four ordinary requests', async () => {
  const h = harness(); const bridge = h.bridge();
  try {
    const send = (id, command, args) => bridge.postMessage(JSON.stringify({ id, namespace: 'host', command, args }));
    for (let index = 0; index < 64; index++) send('normal-' + index, 'file:chunk', { handle: 'missing', index: 0, offset: 0, length: 1 });
    send('ordinary-full', 'file:finish', { handle: 'missing', action: 'commit' });
    for (let index = 0; index < 8; index++) send('control-' + index, 'file:finish', { handle: 'missing', action: 'cancel' });
    send('control-full', 'file:finish', { handle: 'missing', action: 'close' });
    assert.equal(h.replies.find((reply) => reply.id === 'ordinary-full').error.code, 'resource_limit_exceeded');
    assert.equal(h.replies.find((reply) => reply.id === 'control-full').error.code, 'resource_limit_exceeded');
    await settle(); await settle();
    for (let index = 0; index < 8; index++) assert.equal(h.replies.find((reply) => reply.id === 'control-' + index).error.code, 'invalid_file_transfer');
  } finally { bridge.destroy(); h.core.destroy(); }
});

test('resource resolver refuses literal and encoded reserved package metadata paths', () => {
  const h = harness();
  const { NativeGameResourceHandler } = h.load('game/NativeGameResourceHandler');
  const resolver = new NativeGameResourceHandler(h.session);
  try {
    h.nodes.set('/sandbox/docs/__gardendless', { kind: 'directory' });
    h.nodes.set('/sandbox/docs/__gardendless/package', { kind: 'directory' });
    h.nodes.set('/sandbox/docs/__gardendless/package/manifest.json', { kind: 'file', bytes: Buffer.from('private metadata') });
    for (const suffix of ['/__gardendless/package/manifest.json', '/%5F%5Fgardendless%2Fpackage%2Fmanifest.json']) {
      const responses = []; let bodyReceived = false;
      resolver.schemeHandler.start({ getRequestUrl: () => h.session.constructor.ORIGIN + suffix, getRequestMethod: () => 'GET', getHeader: () => [] },
        { didReceiveResponse: (response) => responses.push(response), didFinish() {}, didReceiveResponseBody() { bodyReceived = true; } });
      assert.equal(responses[0].status, 404); assert.equal(bodyReceived, false);
    }
  } finally { resolver.destroy(); h.core.destroy(); }
});

test('remote allowlist checks the parsed host and returns the URL it checked', () => {
  const h = harness();
  try {
    const { GameSession } = h.load('game/GameSession');
    const session = new GameSession(JSON.stringify({ schemaVersion: 1, sessionId: 'session-hosts', platform: 'ohos', origin: GameSession.ORIGIN,
      resourceRoot: '/sandbox/docs', entryUrl: GameSession.ORIGIN + '/index.html', activationGeneration: 1,
      hasGpNext: true, gpNextCompatible: true, watermarkEnabled: true, autoCollectSunEnabled: false,
      allowedRemoteHosts: ['pvzge.com', 'github.com'], gpNextRoot: '/sandbox/gp-next', exportTemporaryRoot: '/sandbox/gp-next/.exports' }));
    for (const raw of ['https://pvzge.com:x@evil.example/', 'https://evil.example?.pvzge.com', 'https://evil.example#.github.com',
      'https://evil.example\\.github.com', 'https://notpvzge.com/', 'http://pvzge.com/', 'not a url']) {
      assert.equal(session.allowedRemoteUrl(raw, ['https:']), null, raw);
    }
    assert.equal(session.allowedRemoteUrl('https://www.pvzge.com/mods', ['https:']), 'https://www.pvzge.com/mods');
    assert.equal(session.allowedRemoteUrl('http://github.com', ['https:', 'http:']), 'http://github.com/');
  } finally { h.core.destroy(); }
});

test('resource stop and host destruction close active readers before blocked IO returns', async () => {
  for (const action of ['stop', 'destroy']) {
    const h = harness(); const gate = deferred();
    const { NativeGameResourceHandler } = h.load('game/NativeGameResourceHandler');
    const resolver = new NativeGameResourceHandler(h.session);
    try {
      h.nodes.set('/sandbox/docs/index.html', { kind: 'file', bytes: Buffer.from('resource bytes') });
      h.setReadGate(gate);
      let received = 0; let finished = 0; let failed = 0;
      const request = { getRequestUrl: () => h.session.constructor.ORIGIN + '/', getRequestMethod: () => 'GET', getHeader: () => [] };
      resolver.schemeHandler.start(request, { didReceiveResponse() {}, didReceiveResponseBody() { received++; }, didFinish() { finished++; }, didFail() { failed++; } });
      await settle(); assert.equal(h.descriptors.size, 1);
      if (action === 'stop') resolver.schemeHandler.stop(request); else resolver.destroy();
      await settle(); assert.equal(h.descriptors.size, 0);
      gate.resolve(); await settle();
      assert.equal(received, 0); assert.equal(finished, 0); assert.equal(failed, 0);
    } finally { gate.resolve(); resolver.destroy(); h.core.destroy(); }
  }
});

test('Flutter launch adapter carries audio preference and optional package identity into the native session', async () => {
  const h = harness();
  try {
    const { GameHostPlugin } = h.load('plugins/GameHostPlugin');
    const plugin = new GameHostPlugin(); let forwarded;
    const context = { startAbility: async (want) => { forwarded = JSON.parse(want.parameters.gameSession); }, terminateSelf: async () => {} };
    plugin.onAttachedToAbility({ getAbility: () => ({ context }) });
    const values = { schemaVersion: 1, sessionId: 'launch', detailedAudioDiagnosticsEnabled: true, packageId: 'sha256:' + 'a'.repeat(64) };
    const result = deferred();
    plugin.onMethodCall({ method: 'launch', argument: (key) => values[key] ?? null }, { success: result.resolve, error: result.reject });
    await result.promise;
    assert.equal(forwarded.detailedAudioDiagnosticsEnabled, true);
    assert.equal(forwarded.packageId, values.packageId);
  } finally { h.core.destroy(); }
});

test('duplicate active request IDs leave the original pending file request unsettled until its single completion', async () => {
  const h = harness(); const bridge = h.bridge(); const gate = deferred();
  try {
    h.file('pending.bin', 'abc');
    const send = (id, command, args) => bridge.postMessage(JSON.stringify({ id, namespace: 'host', command, args }));
    send('begin-pending', 'file:begin', { mode: 'read', destination: 'gp-next', path: 'gp-next/pending.bin' });
    await settle();
    const handle = h.replies.find((reply) => reply.id === 'begin-pending').value.handle;
    h.setReadGate(gate);
    const args = { handle, index: 0, offset: 0, length: 3 };
    send('same-active-id', 'file:chunk', args);
    await settle();
    assert.equal(h.replies.filter((reply) => reply.id === 'same-active-id').length, 0);
    send('same-active-id', 'file:chunk', args);
    await settle();
    assert.equal(h.replies.filter((reply) => reply.id === 'same-active-id').length, 0);
    gate.resolve(); await settle(); await settle();
    const completed = h.replies.filter((reply) => reply.id === 'same-active-id');
    assert.equal(completed.length, 1);
    assert.equal(completed[0].ok, true);
    assert.equal(Buffer.from(completed[0].value.data, 'base64').toString(), 'abc');
  } finally { gate.resolve(); bridge.destroy(); h.core.destroy(); }
});
