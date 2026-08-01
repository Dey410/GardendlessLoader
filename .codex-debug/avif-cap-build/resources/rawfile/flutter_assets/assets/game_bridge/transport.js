(function () {
  "use strict";
  if (window.__gardendlessTransport) return;

  const pending = new Map();
  const seenIds = new Set();
  let nextId = 1;
  const defaultTimeoutMs = 15000;
  const userInteractionTimeoutMs = 5 * 60 * 1000;
  const maxMessageBytes = 1024 * 1024;

  function nativePostMessage(message) {
    if (window.gardendlessNative &&
        typeof window.gardendlessNative.postMessage === "function") {
      window.gardendlessNative.postMessage(message);
      return;
    }
    const iosHandler = window.webkit && window.webkit.messageHandlers &&
      window.webkit.messageHandlers.gardendlessNative;
    if (iosHandler && typeof iosHandler.postMessage === "function") {
      iosHandler.postMessage(message);
      return;
    }
    throw new Error("Gardendless native transport is unavailable");
  }

  function invoke(command, payload) {
    if (typeof command !== "string" || !command) {
      return Promise.reject(new Error("Bridge command is empty"));
    }
    const id = String(Date.now()) + "-" + String(nextId++);
    const body = payload && typeof payload === "object" ? payload : {};
    const request = {
      id: id,
      namespace: typeof body.namespace === "string" ? body.namespace : "host",
      command: command,
      args: body.args == null ? body : body.args,
      options: body.options == null ? {} : body.options
    };
    const encoded = JSON.stringify(request);
    if (encoded.length > maxMessageBytes) {
      return Promise.reject(new Error("Bridge request is too large"));
    }
    return new Promise(function (resolve, reject) {
      const waitsForUser = command === "host:export" ||
        command === "host:exportCommit" ||
        command === "plugin:opener|open_path" ||
        command === "plugin:fs|write_text_file";
      const timer = setTimeout(function () {
        pending.delete(id);
        reject(new Error("Bridge request timed out: " + command));
      }, waitsForUser ? userInteractionTimeoutMs : defaultTimeoutMs);
      pending.set(id, { resolve: resolve, reject: reject, timer: timer });
      try {
        nativePostMessage(encoded);
      } catch (error) {
        clearTimeout(timer);
        pending.delete(id);
        reject(error);
      }
    });
  }

  function resolveResponse(raw) {
    let response;
    try {
      response = typeof raw === "string" ? JSON.parse(raw) : raw;
    } catch (_) {
      return false;
    }
    if (!response || typeof response.id !== "string" ||
        seenIds.has(response.id)) {
      return false;
    }
    const callback = pending.get(response.id);
    if (!callback) return false;
    seenIds.add(response.id);
    if (seenIds.size > 2048) seenIds.clear();
    pending.delete(response.id);
    clearTimeout(callback.timer);
    if (response.ok === true) {
      callback.resolve(response.value);
    } else {
      const error = response.error || {};
      const failure = new Error(String(error.message || "Native bridge failed"));
      failure.code = String(error.code || "native_error");
      callback.reject(failure);
    }
    return true;
  }

  function rejectAll(code, message) {
    for (const callback of pending.values()) {
      clearTimeout(callback.timer);
      const error = new Error(message || "Game host was destroyed");
      error.code = code || "host_destroyed";
      callback.reject(error);
    }
    pending.clear();
  }

  window.__gardendlessTransport = Object.freeze({
    invoke: invoke,
    resolve: resolveResponse,
    rejectAll: rejectAll
  });
  window.dispatchEvent(new Event("gardendlessTransportReady"));
})();
