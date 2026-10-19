(function () {
  "use strict";
  // Names the loader's touch mappings once, the first time a player opens the
  // game. It never takes input and fades out on the first touch or click, so
  // it can be read during the game's own loading screen.
  if (window.__gardendlessGestureHintInstalled) return;
  window.__gardendlessGestureHintInstalled = true;
  const host = window.__gardendlessHost;
  const lines = host && host.config.gestureHint;
  if (!Array.isArray(lines) || !lines.length) return;
  const inputs = ["pointerdown", "touchstart", "mousedown"];
  let node = null;

  function hide() {
    if (!node) return;
    const shown = node;
    node = null;
    inputs.forEach(function (type) { window.removeEventListener(type, hide, true); });
    shown.style.opacity = "0";
    setTimeout(function () { shown.remove(); }, 400);
  }

  function show() {
    node = document.createElement("div");
    node.id = "gardendless-gesture-hint";
    lines.forEach(function (line) {
      const row = document.createElement("div");
      row.textContent = String(line);
      node.appendChild(row);
    });
    Object.assign(node.style, {
      position: "fixed",
      left: "50%",
      bottom: "24px",
      transform: "translateX(-50%)",
      zIndex: "2147483646",
      pointerEvents: "none",
      userSelect: "none",
      padding: "12px 18px",
      borderRadius: "14px",
      background: "rgba(0,0,0,.66)",
      color: "#fff",
      font: "500 14px/1.65 -apple-system,BlinkMacSystemFont,sans-serif",
      whiteSpace: "nowrap",
      transition: "opacity .4s ease"
    });
    (document.body || document.documentElement).appendChild(node);
    inputs.forEach(function (type) {
      window.addEventListener(type, hide, {capture: true, passive: true});
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", show, {once: true});
  } else {
    show();
  }
})();
