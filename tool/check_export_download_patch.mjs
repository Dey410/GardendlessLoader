import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const transport = fs.readFileSync(new URL('../assets/game_bridge/transport.js', import.meta.url), 'utf8');
const patch = fs.readFileSync(new URL('../assets/game_bridge/export_download_patch.js', import.meta.url), 'utf8');
const calls = [];
const revoked = new Set();
const handles = new Map();
const exports = [];
let clicks = 0;
let nextUrl = 0;
class FakeBlob {
  constructor(parts, options = {}) { this.bytes = Buffer.from(parts.join('')); this.size = this.bytes.length; this.type = options.type || ''; }
  slice(start, end) { const b = this.bytes.subarray(start, end); return {arrayBuffer: async () => b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength)}; }
}
class FakeAnchor {
  constructor() { this.href = ''; this.download = ''; this.parentElement = null; this.attributes = new Map(); }
  getAttribute(n) { return this.attributes.get(n) ?? null; }
  hasAttribute(n) { return this.attributes.has(n); }
  setAttribute(n, v) { this.attributes.set(n, String(v)); if (n === 'href' || n === 'download') this[n] = String(v); }
  click() { clicks++; }
}
const listeners = new Map();
const window = {__gardendlessHostConfig: {platform: 'android', hostAbi: 1, hasGpNext: false},
  URL: {createObjectURL() { return `blob:game/${++nextUrl}`; }, revokeObjectURL(url) { revoked.add(url); }},
  webkitURL: null, addEventListener(n, fn) { listeners.set(n, fn); }, dispatchEvent() {}};
window.gardendlessNative = {postMessage(raw) {
  const r = JSON.parse(raw); calls.push(r); const a = r.args;
  let value = null; let ok = true;
  try {
    if (r.command === 'file:begin') {
      assert.equal(a.destination, 'export');
      const handle = `export-${handles.size}`;
      handles.set(handle, {bytes: Buffer.alloc(a.totalBytes), offset: 0, filename: a.suggestedFilename});
      value = {handle, sizeBytes: a.totalBytes};
    } else if (r.command === 'file:chunk') {
      const h = handles.get(a.handle); const b = Buffer.from(a.data, 'base64');
      assert.equal(a.offset, h.offset); assert(b.length <= 65536);
      b.copy(h.bytes, h.offset); h.offset += b.length;
    } else if (r.command === 'file:finish') {
      const h = handles.get(a.handle);
      if (a.action === 'commit') { assert.equal(h.offset, h.bytes.length); exports.push(h); }
      handles.delete(a.handle);
    } else throw new Error(`legacy export command ${r.command}`);
  } catch (error) { ok = false; value = error.message; }
  queueMicrotask(() => window.__gardendlessTransport.resolve({id: r.id, ok,
    ...(ok ? {value} : {error: {code: 'test_failure', message: value}})}));
}};
const context = vm.createContext({window, document: {addEventListener(n, fn) {listeners.set(n, fn);}},
  Blob: FakeBlob, HTMLAnchorElement: FakeAnchor, ArrayBuffer, Uint8Array, TextEncoder, TextDecoder,
  URL, Map, Set, JSON, Date, Math, Promise, Object, String, Error, console, queueMicrotask,
  btoa: (v) => Buffer.from(v, 'binary').toString('base64'), atob: (v) => Buffer.from(v, 'base64').toString('binary'),
  setTimeout(fn, delay) {const t = setTimeout(fn, delay); t.unref(); return t;}, clearTimeout});
vm.runInContext(transport, context);
vm.runInContext(patch, context);

const payload = '界'.repeat(70001);
const blob = new FakeBlob([payload], {type: 'application/json'});
const url = window.URL.createObjectURL(blob);
const anchor = new FakeAnchor(); anchor.href = url; anchor.setAttribute('download', 'save.json');
anchor.click(); window.URL.revokeObjectURL(url);
await new Promise((resolve) => setImmediate(resolve));
assert.equal(clicks, 0);
assert(revoked.has(url));
assert.equal(exports.length, 1, 'standard no-GP session must export via the unified file protocol');
assert.equal(exports[0].filename, 'save.json');
assert.equal(exports[0].bytes.toString('utf8'), payload);
assert(calls.every((r) => ['file:begin','file:chunk','file:finish'].includes(r.command)));
assert.equal(calls.filter((r) => r.command === 'file:chunk').length, Math.ceil(blob.size / 65536));
assert.equal(handles.size, 0);
console.log('standard-game Blob export shares bounded file transactions, preserves revoked URL bytes and UTF-8');
