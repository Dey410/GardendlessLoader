(function () {
  "use strict";
  // Cocos sizes the game canvas by window.devicePixelRatio, so scaling the
  // value it reads shrinks the WebGL back buffer and its GPU memory. Injected
  // after touch_input_adapter.js, which keeps measuring the real ratio.
  const host = window.__gardendlessHost;
  const scale = host ? host.config.renderScale : null;
  if (typeof scale !== "number" || !(scale > 0)) return;
  const state = window.__gardendlessRenderScale;
  if (state) {
    // The script can be injected into the same document more than once. Only
    // the scale is replaced; the getter below still reads the real ratio, so
    // repeated injections cannot multiply the reported ratio.
    state.scale = scale;
    return;
  }
  const real = Object.getOwnPropertyDescriptor(window, "devicePixelRatio");
  const installed = {scale: scale};
  Object.defineProperty(window, "devicePixelRatio", {
    configurable: true,
    enumerable: real.enumerable,
    get: function () {
      return real.get.call(window) * installed.scale;
    }
  });
  Object.defineProperty(window, "__gardendlessRenderScale", {
    configurable: true,
    enumerable: false,
    value: installed
  });
})();
