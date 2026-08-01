(function () {
  "use strict";
  const id = "gardendless-native-watermark";

  function render() {
    let node = document.getElementById(id);
    if (!node) {
      node = document.createElement("div");
      node.id = id;
      node.textContent = "GardendlessLoader";
      Object.assign(node.style, {
        position: "fixed",
        right: "12px",
        bottom: "10px",
        zIndex: "2147483646",
        pointerEvents: "none",
        userSelect: "none",
        color: "rgba(255,255,255,.48)",
        font: "600 12px -apple-system,BlinkMacSystemFont,sans-serif",
        textShadow: "0 1px 2px rgba(0,0,0,.7)"
      });
      (document.body || document.documentElement).appendChild(node);
    }
    const enabled = window.__gardendlessHost &&
      window.__gardendlessHost.config.watermarkEnabled !== false;
    node.style.display = enabled ? "block" : "none";
  }

  function setEnabled(enabled) {
    const node = document.getElementById(id);
    if (node) node.style.display = enabled ? "block" : "none";
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", render, { once: true });
  } else {
    render();
  }
  window.addEventListener("gardendless:watermark", function (event) {
    setEnabled(event.detail !== false);
  });
})();
