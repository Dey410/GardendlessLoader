(function () {
  "use strict";
  if (window.__gardendlessHost) return;
  const initial = window.__gardendlessHostConfig || {};
  const listeners = new Map();

  function emit(name, detail) {
    const callbacks = listeners.get(name);
    if (callbacks) {
      for (const callback of Array.from(callbacks)) callback(detail);
    }
    window.dispatchEvent(new CustomEvent("gardendless:" + name, { detail }));
  }

  window.__gardendlessHost = Object.freeze({
    config: Object.freeze(initial),
    invoke: function (command, payload) {
      return window.__gardendlessTransport.invoke(command, payload || {});
    },
    on: function (name, callback) {
      if (!listeners.has(name)) listeners.set(name, new Set());
      listeners.get(name).add(callback);
      return function () { listeners.get(name).delete(callback); };
    },
    emit: emit
  });
  window.__gardendlessNativeEvent = emit;
  window.dispatchEvent(new Event("gardendlessHostReady"));
})();
