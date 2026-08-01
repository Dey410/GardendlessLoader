(function () {
  "use strict";

  if (window.__gardendlessAutoSunInstalled) return;
  window.__gardendlessAutoSunInstalled = true;

  const host = window.__gardendlessHost;
  const config = host ? host.config : (window.__gardendlessHostConfig || {});
  if (!config.autoCollectSunEnabled || config.hasGpNext) return;

  const checkIntervalMs = 250;
  const collectIntervalMs = 3000;
  const keyHoldMs = 50;
  let levelController = null;
  let gameUI = null;
  let eligibleSince = null;
  let checkTimer = null;
  let keyUpTimer = null;
  let keyTarget = null;
  let keyIsDown = false;
  let stopped = false;
  let windowActive = true;
  let failureLogged = false;

  function now() {
    return performance.now();
  }

  function forceKeyCode(event) {
    for (const property of ["keyCode", "which"]) {
      if (event[property] === 65) continue;
      try {
        Object.defineProperty(event, property, {
          configurable: true,
          get: function () { return 65; }
        });
      } catch (_error) {
      }
    }
    return event;
  }

  function keyboardEvent(type) {
    return forceKeyCode(new KeyboardEvent(type, {
      key: "a",
      code: "KeyA",
      keyCode: 65,
      which: 65,
      repeat: false,
      bubbles: true,
      cancelable: true,
      composed: true
    }));
  }

  function releaseCollectKey() {
    if (!keyIsDown) return;
    keyIsDown = false;
    if (keyUpTimer !== null) {
      clearTimeout(keyUpTimer);
      keyUpTimer = null;
    }
    if (keyTarget) keyTarget.dispatchEvent(keyboardEvent("keyup"));
    keyTarget = null;
  }

  function pressCollectKey() {
    if (keyIsDown) return;
    keyTarget = document.getElementById("GameCanvas") ||
      document.activeElement || document;
    keyIsDown = true;
    keyTarget.dispatchEvent(keyboardEvent("keydown"));
    keyUpTimer = setTimeout(function () {
      keyUpTimer = null;
      releaseCollectKey();
    }, keyHoldMs);
  }

  function hasNativeTextFocus() {
    const active = document.activeElement;
    if (!active) return false;
    const tagName = String(active.tagName || "").toLowerCase();
    if (tagName === "input" || tagName === "select" ||
        tagName === "textarea") {
      return true;
    }
    if (active.isContentEditable) return true;
    if (typeof active.getAttribute !== "function") return false;
    const contentEditable = active.getAttribute("contenteditable");
    return contentEditable !== null && contentEditable !== "false";
  }

  function isEligible() {
    return !stopped &&
      windowActive &&
      !document.hidden &&
      !hasNativeTextFocus() &&
      levelController &&
      levelController.gaming === true &&
      !levelController.AirRaidProps &&
      gameUI &&
      gameUI.component?.paused !== true;
  }

  function resetCycle() {
    eligibleSince = null;
    releaseCollectKey();
  }

  function scheduleCheck() {
    if (stopped || checkTimer !== null) return;
    checkTimer = setTimeout(check, checkIntervalMs);
  }

  function check() {
    checkTimer = null;
    if (!isEligible()) {
      resetCycle();
      scheduleCheck();
      return;
    }
    const timestamp = now();
    if (eligibleSince === null) {
      eligibleSince = timestamp;
    } else if (timestamp - eligibleSince >= collectIntervalMs) {
      pressCollectKey();
      eligibleSince = timestamp;
    }
    scheduleCheck();
  }

  function logFailure(error) {
    if (failureLogged) return;
    failureLogged = true;
    console.error(
      "[GardendlessLoader] 自动收集阳光已停用：无法读取游戏状态。",
      error
    );
  }

  function moduleValue(module, name) {
    if (module && module[name]) return module[name];
    if (module && module.default && module.default[name]) {
      return module.default[name];
    }
    return module ? module.default : null;
  }

  async function start() {
    try {
      if (!window.System || typeof window.System.import !== "function") {
        throw new Error("System.import is unavailable");
      }
      const modules = await Promise.all([
        window.System.import("chunks:///_virtual/levelController.ts"),
        window.System.import("chunks:///_virtual/UI.ts")
      ]);
      levelController = moduleValue(modules[0], "levelController");
      gameUI = moduleValue(modules[1], "UI");
      if (!levelController || !gameUI) {
        throw new Error("Game state modules have unexpected exports");
      }
      check();
    } catch (error) {
      stopped = true;
      resetCycle();
      logFailure(error);
    }
  }

  function stop() {
    stopped = true;
    if (checkTimer !== null) {
      clearTimeout(checkTimer);
      checkTimer = null;
    }
    resetCycle();
  }

  document.addEventListener("visibilitychange", function () {
    resetCycle();
  });
  document.addEventListener("focusin", resetCycle, true);
  document.addEventListener("focusout", resetCycle, true);
  window.addEventListener("blur", function () {
    windowActive = false;
    resetCycle();
  });
  window.addEventListener("focus", function () {
    windowActive = true;
    resetCycle();
  });
  window.addEventListener("pagehide", stop, { once: true });

  if (document.readyState === "complete") {
    start();
  } else {
    window.addEventListener("load", start, { once: true });
  }
})();
