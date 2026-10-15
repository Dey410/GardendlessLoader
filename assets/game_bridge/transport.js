(function () {
  "use strict";
  if (window.__gardendlessTransport) return;

  const config = window.__gardendlessHostConfig || {};
  const native = config.platform === "ios"
    ? window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.gardendlessNative
    : (config.platform === "android" || config.platform === "ohos") ? window.gardendlessNative : null;
  const post = native && typeof native.postMessage === "function"
    ? native.postMessage.bind(native) : null;
  const pending = new Map();
  const fileQueue = [];
  const chunkBytes = 64 * 1024;
  const maxFileBytes = 512 * 1024 * 1024;
  let nextId = 1;
  let fileBusy = false;
  let destroyed = false;

  function failure(code, message) {
    const error = new Error(message);
    error.code = code;
    return error;
  }

  function invoke(command, payload) {
    if (destroyed) return Promise.reject(failure("host_destroyed", "Game host was destroyed"));
    if (!post) return Promise.reject(failure("transport_unavailable", "Gardendless native transport is unavailable"));
    if (typeof command !== "string" || !command) return Promise.reject(new Error("Bridge command is empty"));
    const body = payload && typeof payload === "object" ? payload : {};
    const terminal = command === "file:finish" && body.args &&
      (body.args.action === "cancel" || body.args.action === "close");
    if (pending.size >= (terminal ? 72 : 64)) return Promise.reject(failure("resource_limit_exceeded", "Too many pending bridge requests"));
    const id = String(Date.now()) + "-" + String(nextId++);
    const request = {id: id, namespace: body.namespace || "host", command: command,
      args: body.args == null ? body : body.args, options: body.options || {}};
    let encoded;
    try {
      encoded = JSON.stringify(request);
      if (new TextEncoder().encode(encoded).byteLength > 1024 * 1024) {
        return Promise.reject(failure("resource_limit_exceeded", "Bridge request is too large"));
      }
    } catch (error) { return Promise.reject(error); }
    const waitsForUser = command === "file:finish" || command === "plugin:dialog|open" ||
      command === "plugin:opener|open_path";
    return new Promise(function (resolve, reject) {
      const timer = setTimeout(function () {
        pending.delete(id);
        reject(failure("deadline_exceeded", "Bridge request timed out: " + command));
      }, waitsForUser ? 5 * 60 * 1000 : 15000);
      pending.set(id, {resolve: resolve, reject: reject, timer: timer});
      try { post(encoded); } catch (error) {
        clearTimeout(timer);
        pending.delete(id);
        reject(error);
      }
    });
  }

  function resolveResponse(raw) {
    let response;
    try { response = typeof raw === "string" ? JSON.parse(raw) : raw; } catch (_) { return false; }
    if (!response || typeof response.id !== "string") return false;
    const callback = pending.get(response.id);
    if (!callback) return false;
    pending.delete(response.id);
    clearTimeout(callback.timer);
    if (response.ok === true) callback.resolve(response.value);
    else {
      const error = response.error || {};
      callback.reject(failure(String(error.code || "native_error"), String(error.message || "Native bridge failed")));
    }
    return true;
  }

  function rejectAll(code, message) {
    destroyed = true;
    const error = failure(code || "host_destroyed", message || "Game host was destroyed");
    for (const callback of pending.values()) {
      clearTimeout(callback.timer);
      callback.reject(error);
    }
    pending.clear();
    for (const operation of fileQueue.splice(0)) operation.reject(error);
  }

  function runFiles() {
    if (fileBusy || destroyed || !fileQueue.length) return;
    fileBusy = true;
    const operation = fileQueue.shift();
    Promise.resolve().then(operation.run).then(operation.resolve, operation.reject).finally(function () {
      fileBusy = false;
      runFiles();
    });
  }

  function fileOperation(run) {
    if (destroyed) return Promise.reject(failure("host_destroyed", "Game host was destroyed"));
    if (fileQueue.length >= 16) return Promise.reject(failure("resource_limit_exceeded", "File request queue is full"));
    return new Promise(function (resolve, reject) {
      fileQueue.push({run: run, resolve: resolve, reject: reject});
      runFiles();
    });
  }

  function fileCall(command, args) {
    return invoke(command, {args: args});
  }

  function validSize(value) {
    if (!Number.isSafeInteger(value) || value < 0 || value > maxFileBytes) {
      throw failure("resource_limit_exceeded", "File size exceeds the transfer budget");
    }
    return value;
  }

  function base64(bytes) {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 8192) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192));
    }
    return btoa(binary);
  }

  async function cancel(handle) {
    if (!destroyed) {
      try { await fileCall("file:finish", {handle: handle, action: "cancel"}); }
      catch (_) { /* Preserve the original failure; Native owns its deadline and teardown. */ }
    }
  }

  async function readFile(spec) {
    const begin = await fileCall("file:begin", {mode: "read", destination: "gp-next", path: spec.path, options: spec.options});
    if (!begin || typeof begin.handle !== "string" || !begin.handle) throw new Error("Invalid native file handle");
    try {
      const size = validSize(begin.sizeBytes);
      const output = new Uint8Array(size);
      let index = 0;
      for (let offset = 0; offset < size; offset += chunkBytes) {
        const count = Math.min(chunkBytes, size - offset);
        const result = await fileCall("file:chunk", {handle: begin.handle, index: index++, offset: offset, length: count});
        if (!result || typeof result.data !== "string" || result.data.length > Math.ceil(chunkBytes / 3) * 4) {
          throw new Error("Invalid native read chunk");
        }
        const binary = atob(result.data);
        if (binary.length !== count) throw new Error("File read length mismatch");
        for (let i = 0; i < count; i++) output[offset + i] = binary.charCodeAt(i);
      }
      await fileCall("file:finish", {handle: begin.handle, action: "close"});
      return output.buffer;
    } catch (error) { await cancel(begin.handle); throw error; }
  }

  function binaryView(value) {
    if (value instanceof ArrayBuffer) return new Uint8Array(value);
    if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    throw new TypeError("File write requires an ArrayBuffer, a byte view or a Blob");
  }

  async function writeFile(value, spec) {
    const blob = typeof Blob !== "undefined" && value instanceof Blob;
    const view = blob ? null : binaryView(value);
    const size = validSize(blob ? value.size : view.byteLength);
    const begin = await fileCall("file:begin", Object.assign({}, spec, {mode: "write", totalBytes: size}));
    if (!begin || typeof begin.handle !== "string" || !begin.handle) throw new Error("Invalid native file handle");
    try {
      if (validSize(begin.sizeBytes) !== size) throw new Error("Native write size mismatch");
      let index = 0;
      for (let offset = 0; offset < size; offset += chunkBytes) {
        const end = Math.min(size, offset + chunkBytes);
        const bytes = blob ? new Uint8Array(await value.slice(offset, end).arrayBuffer()) : view.subarray(offset, end);
        await fileCall("file:chunk", {handle: begin.handle, index: index++, offset: offset, data: base64(bytes)});
      }
      await fileCall("file:finish", {handle: begin.handle, action: "commit"});
      return null;
    } catch (error) { await cancel(begin.handle); throw error; }
  }

  const transport = Object.freeze({invoke: invoke, resolve: resolveResponse, rejectAll: rejectAll,
    writeFile: function (value, spec) { return fileOperation(function () { return writeFile(value, spec); }); }});
  window.__gardendlessTransport = transport;
  window.__gardendlessHost = Object.freeze({config: Object.freeze(config), invoke: invoke});

  if (!config.hasGpNext || !config.gpNextCompatible) return;
  const callbacks = Object.create(null);
  let callbackId = 1;
  let eventId = 1;
  const disabled = new Set(["plugin:drpc|destroy_thread", "plugin:drpc|spawn_thread", "plugin:drpc|set_activity",
    "update_macos_menu", "plugin:event|unlisten", "plugin:event|emit", "plugin:event|emit_to",
    "plugin:resources|close", "plugin:deep-link|register", "plugin:deep-link|unregister",
    "plugin:window|set_size", "plugin:window|set_fullscreen", "plugin:window|center", "plugin:window|close", "open_devtools"]);

  function fileSpec(args, options) {
    const nested = args && args.options || options || {};
    const headers = nested.headers;
    if (headers && typeof headers.path === "string") {
      return {destination: "gp-next", path: decodeURIComponent(headers.path),
        options: headers.options && headers.options !== "undefined" ? JSON.parse(headers.options) : {}};
    }
    return {destination: "gp-next", path: args && args.path, options: nested};
  }

  async function tauriInvoke(command, args, options) {
    command = String(command || "");
    args = args == null ? {} : args;
    options = options || {};
    if (command === "plugin:path|resolve_directory") {
      if (args.directory !== 14) throw new Error("Only AppData directory 14 is supported");
      return String(config.gpNextBaseDirectory || "");
    }
    if (command === "plugin:event|listen") return eventId++;
    if (command === "plugin:drpc|is_running" || command === "plugin:deep-link|is_registered" || command === "plugin:window|is_maximized") return false;
    if (command === "plugin:deep-link|get_current") return [];
    if (disabled.has(command)) return null;
    if (command.startsWith("plugin:window|") || command.startsWith("plugin:image|")) throw new Error("Unsupported mobile command: " + command);
    if (command === "plugin:fs|read_file" || command === "plugin:fs|read_text_file") {
      const spec = fileSpec(args, options);
      return fileOperation(function () { return readFile(spec); });
    }
    if (command === "plugin:fs|write_file" || command === "plugin:fs|write_text_file") {
      const spec = fileSpec(args, options);
      return fileOperation(function () { return writeFile(args, spec); });
    }
    if (command === "plugin:fs|exists" && args.path === "patches" && args.options && args.options.baseDir === 14) {
      args = Object.assign({}, args, {path: "gp-next/patches"});
    }
    return invoke(command, {namespace: "gp-next", args: args, options: options});
  }

  window.__TAURI_INTERNALS__ = {invoke: tauriInvoke, callbacks: callbacks,
    transformCallback: function (callback, once) {
      const id = callbackId++;
      callbacks[id] = {callback: callback, once: once === true};
      return id;
    },
    runCallback: function (id, value) {
      const item = callbacks[id];
      if (!item) return;
      try { item.callback(value); } finally { if (item.once) delete callbacks[id]; }
    },
    metadata: {currentWindow: {label: "main"}, currentWebview: {label: "main"}}};
  window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {unregisterListener: function (_, id) { delete callbacks[id]; }};
})();
