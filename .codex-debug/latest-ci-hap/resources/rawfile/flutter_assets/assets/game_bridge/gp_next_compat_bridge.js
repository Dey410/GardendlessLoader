(function () {
  const installedKey = "__gardendlessGpNextCompatInstalled";
  if (window[installedKey]) {
    return;
  }
  Object.defineProperty(window, installedKey, {
    value: true,
    configurable: false,
    enumerable: false,
    writable: false
  });

  const handlerName = "gardendlessGpNextBridge";
  const callbacks = Object.create(null);
  let nextCallbackId = 1;

  function bridgeReady() {
    return !!(
      window.__gardendlessTransport &&
      typeof window.__gardendlessTransport.invoke === "function"
    );
  }

  function waitForBridge() {
    if (bridgeReady()) {
      return Promise.resolve();
    }
    return Promise.reject(
      new Error("GardendlessLoader GP-Next bridge is unavailable")
    );
  }

  function serialize(value) {
    if (value == null) {
      return value;
    }
    if (value instanceof ArrayBuffer) {
      return { __gardendlessBytes: Array.from(new Uint8Array(value)) };
    }
    if (ArrayBuffer.isView(value)) {
      return {
        __gardendlessBytes: Array.from(
          new Uint8Array(value.buffer, value.byteOffset, value.byteLength)
        )
      };
    }
    if (Array.isArray(value)) {
      return value.map(serialize);
    }
    if (typeof value === "object") {
      const result = {};
      for (const key of Object.keys(value)) {
        result[key] = serialize(value[key]);
      }
      return result;
    }
    return value;
  }

  function transformCallback(callback, once) {
    const id = nextCallbackId++;
    callbacks[id] = { callback: callback, once: once === true };
    return id;
  }

  function runCallback(id, payload) {
    const registered = callbacks[id];
    if (!registered) {
      return;
    }
    try {
      registered.callback(payload);
    } finally {
      if (registered.once) {
        delete callbacks[id];
      }
    }
  }

  async function invoke(command, args, options) {
    await waitForBridge();
    const normalizedCommand = String(command || "");
    const normalizedArgs = serialize(args == null ? {} : args);
    const normalizedOptions = serialize(options == null ? null : options);
    return window.__gardendlessGpNextCore.invoke(
      normalizedCommand,
      normalizedArgs,
      normalizedOptions,
      function (nativeCommand, nativeArgs, nativeOptions) {
        return window.__gardendlessTransport.invoke(nativeCommand, {
        namespace: "gp-next",
          args: nativeArgs,
          options: nativeOptions
        });
      }
    );
  }

  window.__TAURI_INTERNALS__ = {
    invoke: invoke,
    transformCallback: transformCallback,
    runCallback: runCallback,
    callbacks: callbacks,
    metadata: {
      currentWindow: { label: "main" },
      currentWebview: { label: "main" }
    }
  };

  window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {
    unregisterListener: function (_, eventId) {
      delete callbacks[eventId];
    }
  };
})();
