import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const dartSource = fs.readFileSync(
  new URL('../lib/src/web/export_download_patch.dart', import.meta.url),
  'utf8',
);
const sourceMatch = dartSource.match(
  /const gardendlessExportDownloadPatchSource = r'''([\s\S]*?)''';/,
);
assert(sourceMatch, 'download patch source constant was not found');

let originalAnchorClicks = 0;
let objectUrlCounter = 0;
const revokedUrls = new Set();
const listeners = new Map();
const receivedPayloads = [];

function receiveFromBridge(name, payload) {
  receivedPayloads.push({name, payload});
  return Promise.resolve({accepted: true});
}

function browserSetTimeout(callback, delay, ...args) {
  const timer = setTimeout(callback, delay, ...args);
  timer.unref?.();
  return timer;
}

class FakeBlob {
  constructor(parts, options = {}) {
    this.text = parts.join('');
    this.type = options.type || '';
  }
}

class FakeFileReader {
  readAsDataURL(blob) {
    queueMicrotask(() => {
      this.result = `data:${blob.type || 'application/octet-stream'};base64,${Buffer.from(blob.text).toString('base64')}`;
      this.onloadend?.();
    });
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
    return `blob:http://127.0.0.1:26410/export-${objectUrlCounter}`;
  },
  revokeObjectURL(url) {
    revokedUrls.add(url);
  },
};

const context = {
  Blob: FakeBlob,
  Error,
  FileReader: FakeFileReader,
  HTMLAnchorElement: FakeAnchor,
  Map,
  Promise,
  String,
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
    addEventListener(type, listener) {
      listeners.set(type, listener);
    },
  },
};
context.globalThis = context;

vm.createContext(context);
vm.runInContext(sourceMatch[1], context);

const blob = new context.Blob(['{"coins":1}'], {
  type: 'application/json',
});
const url = context.window.URL.createObjectURL(blob);
const anchor = new context.HTMLAnchorElement();
anchor.href = url;
anchor.setAttribute('download', 'save.json');

anchor.click();
context.window.URL.revokeObjectURL(url);

await new Promise((resolve) => globalThis.setTimeout(resolve, 0));

assert.equal(originalAnchorClicks, 0, 'native anchor click should be bypassed');
assert(revokedUrls.has(url), 'original revokeObjectURL should still run');
assert.equal(receivedPayloads.length, 0, 'payload should wait for the bridge');

context.window.flutter_inappwebview = {
  callHandler: receiveFromBridge,
};
listeners.get('flutterInAppWebViewPlatformReady')?.();
await Promise.resolve();

assert.equal(receivedPayloads.length, 1, 'one export payload should be sent');
assert.equal(receivedPayloads[0].name, 'gardendlessDownloadExport');
assert.equal(receivedPayloads[0].payload.url, url);
assert.equal(receivedPayloads[0].payload.suggestedFilename, 'save.json');
assert.equal(receivedPayloads[0].payload.mimeType, 'application/json');
assert.equal(receivedPayloads[0].payload.source, 'anchor-blob');

const encoded = receivedPayloads[0].payload.dataUrl.split(',')[1];
assert.equal(Buffer.from(encoded, 'base64').toString('utf8'), '{"coins":1}');

console.log('export download patch captures revoked Blob anchor downloads');
