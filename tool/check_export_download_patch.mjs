import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(
  new URL('../assets/game_bridge/export_download_patch.js', import.meta.url),
  'utf8',
);

let originalAnchorClicks = 0;
let objectUrlCounter = 0;
const revokedUrls = new Set();
const listeners = new Map();
const invocations = [];

function browserSetTimeout(callback, delay, ...args) {
  const timer = setTimeout(callback, delay, ...args);
  timer.unref?.();
  return timer;
}

class FakeBlob {
  constructor(parts, options = {}) {
    this.bytes = Buffer.from(parts.join(''));
    this.size = this.bytes.length;
    this.type = options.type || '';
  }

  slice(start, end) {
    const bytes = this.bytes.subarray(start, end);
    return {
      arrayBuffer: async () => bytes.buffer.slice(
        bytes.byteOffset,
        bytes.byteOffset + bytes.byteLength,
      ),
    };
  }
}

class FakeAnchor {
  constructor() {
    this.href = '';
    this.download = '';
    this.parentElement = null;
    this.attributes = new Map();
  }

  getAttribute(name) {
    return this.attributes.get(name) ?? null;
  }

  hasAttribute(name) {
    return this.attributes.has(name);
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
    if (name === 'href') {
      this.href = String(value);
    }
    if (name === 'download') {
      this.download = String(value);
    }
  }

  click() {
    originalAnchorClicks += 1;
  }
}

const fakeUrl = {
  createObjectURL() {
    objectUrlCounter += 1;
    return `blob:https://appassets.androidplatform.net/export-${objectUrlCounter}`;
  },
  revokeObjectURL(url) {
    revokedUrls.add(url);
  },
};

const context = {
  Blob: FakeBlob,
  Error,
  HTMLAnchorElement: FakeAnchor,
  Map,
  Promise,
  String,
  Uint8Array,
  btoa(value) {
    return Buffer.from(value, 'binary').toString('base64');
  },
  console,
  document: {
    addEventListener(type, listener) {
      listeners.set(type, listener);
    },
  },
  queueMicrotask,
  setTimeout: browserSetTimeout,
  window: {
    URL: fakeUrl,
    webkitURL: null,
    __gardendlessTransport: {
      async invoke(command, payload) {
        invocations.push({command, payload});
        if (command === 'host:exportBegin') return 'export-token';
        return null;
      },
    },
    addEventListener(type, listener) {
      listeners.set(type, listener);
    },
  },
};
context.globalThis = context;

vm.createContext(context);
vm.runInContext(source, context);

const blob = new context.Blob(['{"coins":1}'], {
  type: 'application/json',
});
const url = context.window.URL.createObjectURL(blob);
const anchor = new context.HTMLAnchorElement();
anchor.href = url;
anchor.setAttribute('download', 'save.json');

anchor.click();
context.window.URL.revokeObjectURL(url);

await new Promise((resolve) => setImmediate(resolve));

assert.equal(originalAnchorClicks, 0, 'native anchor click should be bypassed');
assert(revokedUrls.has(url), 'original revokeObjectURL should still run');
assert.deepEqual(
  invocations.map((entry) => entry.command),
  ['host:exportBegin', 'host:exportChunk', 'host:exportCommit'],
);
assert.equal(invocations[0].payload.suggestedFilename, 'save.json');
assert.equal(invocations[0].payload.mimeType, 'application/json');
assert.equal(invocations[0].payload.totalBytes, Buffer.byteLength('{"coins":1}'));
assert.equal(invocations[1].payload.token, 'export-token');
assert.equal(invocations[1].payload.index, 0);
assert.equal(Buffer.from(invocations[1].payload.data, 'base64').toString('utf8'), '{"coins":1}');
assert.equal(invocations[2].payload.token, 'export-token');

console.log('export download patch streams revoked Blob downloads through native chunks');
