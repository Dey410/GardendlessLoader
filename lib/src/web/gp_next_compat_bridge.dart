const gardendlessGpNextBridgeHandlerName = 'gardendlessGpNextBridge';

const gardendlessGpNextCompatBridgeSource = r'''
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
      window.flutter_inappwebview &&
      typeof window.flutter_inappwebview.callHandler === "function"
    );
  }

  function waitForBridge() {
    if (bridgeReady()) {
      return Promise.resolve();
    }
    return new Promise(function (resolve, reject) {
      const startedAt = Date.now();
      const timer = setInterval(function () {
        if (bridgeReady()) {
          clearInterval(timer);
          resolve();
          return;
        }
        if (Date.now() - startedAt > 15000) {
          clearInterval(timer);
          reject(new Error("GardendlessLoader GP-Next bridge is unavailable"));
        }
      }, 25);
    });
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
    const response = await window.flutter_inappwebview.callHandler(
      handlerName,
      {
        command: String(command || ""),
        args: serialize(args == null ? {} : args),
        options: serialize(options == null ? null : options)
      }
    );
    if (!response || response.ok !== true) {
      throw new Error(
        response && response.error
          ? String(response.error)
          : "Unsupported GP-Next bridge command: " + command
      );
    }
    return response.value;
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
''';
