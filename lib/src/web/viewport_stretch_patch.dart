String gardendlessViewportStretchToggleScript({required bool enabled}) {
  return 'window.__gardendlessSetViewportStretch?.($enabled);';
}

const gardendlessViewportStretchPatchSource = r'''
(function () {
  if (window.__gardendlessViewportStretchPatchInstalled) {
    return;
  }
  window.__gardendlessViewportStretchPatchInstalled = true;

  const styleElementId = "gardendless-viewport-stretch-style";
  const forcedStyles = new WeakMap();
  let enabled = false;
  let observer = null;
  let pendingApply = false;

  const cssText = `
html[data-gardendless-viewport-stretch="true"],
html[data-gardendless-viewport-stretch="true"] body {
  width: 100% !important;
  height: 100% !important;
  min-width: 100% !important;
  min-height: 100% !important;
  margin: 0 !important;
  padding: 0 !important;
  overflow: hidden !important;
  background: #000 !important;
}

html[data-gardendless-viewport-stretch="true"] #GameDiv,
html[data-gardendless-viewport-stretch="true"] #Cocos3dGameContainer,
html[data-gardendless-viewport-stretch="true"] #GameCanvas,
html[data-gardendless-viewport-stretch="true"] canvas {
  position: fixed !important;
  inset: 0 !important;
  width: 100vw !important;
  height: 100vh !important;
  min-width: 100vw !important;
  min-height: 100vh !important;
  max-width: none !important;
  max-height: none !important;
  margin: 0 !important;
  padding: 0 !important;
  object-fit: fill !important;
  transform: none !important;
  transform-origin: 0 0 !important;
}
`;

  const pageStyles = [
    ["width", "100%"],
    ["height", "100%"],
    ["min-width", "100%"],
    ["min-height", "100%"],
    ["margin", "0px"],
    ["padding", "0px"],
    ["overflow", "hidden"],
    ["background", "#000"]
  ];

  const frameStyles = [
    ["position", "fixed"],
    ["inset", "0px"],
    ["width", "100vw"],
    ["height", "100vh"],
    ["min-width", "100vw"],
    ["min-height", "100vh"],
    ["max-width", "none"],
    ["max-height", "none"],
    ["margin", "0px"],
    ["padding", "0px"],
    ["object-fit", "fill"],
    ["transform", "none"],
    ["transform-origin", "0 0"]
  ];

  function getStyleElement() {
    let styleElement = document.getElementById(styleElementId);
    if (styleElement) {
      return styleElement;
    }

    styleElement = document.createElement("style");
    styleElement.setAttribute("id", styleElementId);
    styleElement.textContent = cssText;
    const parent = document.head || document.documentElement || document.body;
    if (parent) {
      parent.appendChild(styleElement);
    }
    return styleElement;
  }

  function addUnique(targets, element) {
    if (element && targets.indexOf(element) === -1) {
      targets.push(element);
    }
  }

  function queryTargets(selector) {
    try {
      return Array.from(document.querySelectorAll(selector));
    } catch (_) {
      return [];
    }
  }

  function pageTargets() {
    const targets = [];
    addUnique(targets, document.documentElement);
    addUnique(targets, document.body);
    return targets;
  }

  function frameTargets() {
    const targets = [];
    addUnique(targets, document.getElementById("GameDiv"));
    addUnique(targets, document.getElementById("Cocos3dGameContainer"));
    addUnique(targets, document.getElementById("GameCanvas"));
    for (const canvas of queryTargets("canvas")) {
      addUnique(targets, canvas);
    }
    return targets;
  }

  function rememberStyle(element, property) {
    let saved = forcedStyles.get(element);
    if (!saved) {
      saved = new Map();
      forcedStyles.set(element, saved);
    }
    if (saved.has(property)) {
      return;
    }
    saved.set(property, {
      value: element.style.getPropertyValue(property),
      priority: element.style.getPropertyPriority(property)
    });
  }

  function forceStyle(element, property, value) {
    if (!element || !element.style) {
      return;
    }
    rememberStyle(element, property);
    element.style.setProperty(property, value, "important");
  }

  function applyStyleSet(element, styles) {
    for (const style of styles) {
      forceStyle(element, style[0], style[1]);
    }
  }

  function applyCocosExactFit() {
    const cc = window.cc;
    if (!cc || !cc.view || !cc.ResolutionPolicy) {
      return;
    }

    const policy = cc.ResolutionPolicy.EXACT_FIT;
    if (!policy || typeof cc.view.setDesignResolutionSize !== "function") {
      return;
    }

    try {
      const designSize = typeof cc.view.getDesignResolutionSize === "function"
        ? cc.view.getDesignResolutionSize()
        : null;
      const width = designSize && Number(designSize.width) > 0
        ? Number(designSize.width)
        : window.innerWidth;
      const height = designSize && Number(designSize.height) > 0
        ? Number(designSize.height)
        : window.innerHeight;

      cc.view.setDesignResolutionSize(width, height, policy);
      if (typeof cc.view.resizeWithBrowserSize === "function") {
        cc.view.resizeWithBrowserSize(true);
      }
    } catch (_) {}
  }

  function applyForcedStyles() {
    if (!enabled) {
      return;
    }

    const styleElement = getStyleElement();
    styleElement.disabled = false;
    if (document.documentElement) {
      document.documentElement.dataset.gardendlessViewportStretch = "true";
    }

    for (const element of pageTargets()) {
      applyStyleSet(element, pageStyles);
    }
    for (const element of frameTargets()) {
      applyStyleSet(element, frameStyles);
    }
    applyCocosExactFit();
  }

  function restoreElementStyles(element, saved) {
    for (const entry of saved.entries()) {
      const property = entry[0];
      const previous = entry[1];
      if (previous.value) {
        element.style.setProperty(
          property,
          previous.value,
          previous.priority || ""
        );
      } else {
        element.style.removeProperty(property);
      }
    }
  }

  function restoreForcedStyles() {
    const styleElement = getStyleElement();
    styleElement.disabled = true;
    if (document.documentElement) {
      delete document.documentElement.dataset.gardendlessViewportStretch;
    }

    for (const element of pageTargets()) {
      const saved = forcedStyles.get(element);
      if (saved) {
        restoreElementStyles(element, saved);
        forcedStyles.delete(element);
      }
    }
    for (const element of frameTargets()) {
      const saved = forcedStyles.get(element);
      if (saved) {
        restoreElementStyles(element, saved);
        forcedStyles.delete(element);
      }
    }
  }

  function scheduleApply() {
    if (!enabled || pendingApply) {
      return;
    }

    pendingApply = true;
    const run = function () {
      pendingApply = false;
      applyForcedStyles();
    };
    if (typeof window.requestAnimationFrame === "function") {
      window.requestAnimationFrame(run);
    } else {
      window.setTimeout(run, 16);
    }
  }

  function startObserver() {
    if (observer || typeof MutationObserver === "undefined") {
      return;
    }
    const root = document.documentElement || document.body;
    if (!root) {
      return;
    }
    observer = new MutationObserver(scheduleApply);
    observer.observe(root, {
      attributes: true,
      childList: true,
      subtree: true,
      attributeFilter: ["class", "style", "width", "height"]
    });
    if (typeof window.addEventListener === "function") {
      window.addEventListener("resize", scheduleApply);
      window.addEventListener("orientationchange", scheduleApply);
    }
  }

  function stopObserver() {
    if (observer) {
      observer.disconnect();
      observer = null;
    }
    if (typeof window.removeEventListener === "function") {
      window.removeEventListener("resize", scheduleApply);
      window.removeEventListener("orientationchange", scheduleApply);
    }
  }

  window.__gardendlessSetViewportStretch = function (nextEnabled) {
    enabled = nextEnabled === true;
    if (enabled) {
      getStyleElement().disabled = false;
      startObserver();
      applyForcedStyles();
      scheduleApply();
    } else {
      stopObserver();
      restoreForcedStyles();
    }
  };

  getStyleElement().disabled = true;
})();
''';
