(function () {
  "use strict";
  // Cocos sizes the game canvas by window.devicePixelRatio, so capping the
  // value it reads shrinks the WebGL back buffer and its GPU memory. Injected
  // after touch_input_adapter.js, which keeps measuring the real ratio.
  const host = window.__gardendlessHost;
  const cap = host ? host.config.renderPixelRatioCap : null;
  if (typeof cap !== "number" || !(cap > 0)) return;
  const real = Object.getOwnPropertyDescriptor(window, "devicePixelRatio");
  Object.defineProperty(window, "devicePixelRatio", {
    configurable: true,
    enumerable: real.enumerable,
    get: function () {
      return Math.min(real.get.call(window), cap);
    }
  });
})();
