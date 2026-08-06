(function () {
  "use strict";

  if (window.__gardendlessAutoSunInstalled) return;
  window.__gardendlessAutoSunInstalled = true;

  const host = window.__gardendlessHost;
  const config = host ? host.config : (window.__gardendlessHostConfig || {});
  if (!config.autoCollectSunEnabled) return;

  const checkIntervalMs = 250;
  const collectIntervalMs = 3000;
  const keyHoldMs = 50;
  const levelControllerModuleId =
    "chunks:///_virtual/levelController.ts";
  const uiModuleId = "chunks:///_virtual/UI.ts";
  let levelController = null;
  let gameUI = null;
  let eligibleSince = null;
  let moduleCheckTimer = null;
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

  function moduleValue(module, names) {
    if (!module) return null;
    for (const name of names) {
      if (module[name]) return module[name];
    }
    if (module.default) {
      for (const name of names) {
        if (module.default[name]) return module.default[name];
      }
      return module.default;
    }
    return null;
  }

  function isRegisteredForImport(system, moduleId) {
    if (typeof system.has === "function" && system.has(moduleId)) {
      return true;
    }
    return Boolean(
      system.registerRegistry && system.registerRegistry[moduleId]
    );
  }

  function scheduleModuleCheck() {
    if (stopped || moduleCheckTimer !== null) return;
    moduleCheckTimer = setTimeout(findGameModules, checkIntervalMs);
  }

  async function findGameModules() {
    moduleCheckTimer = null;
    try {
      const system = window.System;
      if (!system) {
        scheduleModuleCheck();
        return;
      }

      let levelControllerModule = typeof system.get === "function"
        ? system.get(levelControllerModuleId)
        : null;
      let uiModule = typeof system.get === "function"
        ? system.get(uiModuleId)
        : null;
      if (!levelControllerModule || !uiModule) {
        const canImport = typeof system.import === "function" &&
          isRegisteredForImport(system, levelControllerModuleId) &&
          isRegisteredForImport(system, uiModuleId);
        if (!canImport) {
          scheduleModuleCheck();
          return;
        }
        const modules = await Promise.all([
          system.import(levelControllerModuleId),
          system.import(uiModuleId)
        ]);
        if (stopped) return;
        levelControllerModule = modules[0];
        uiModule = modules[1];
      }

      levelController = moduleValue(levelControllerModule, [
        "LevelPlay",
        "levelController"
      ]);
      gameUI = moduleValue(uiModule, [
        "UIInGame",
        "UI"
      ]);
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
    if (moduleCheckTimer !== null) {
      clearTimeout(moduleCheckTimer);
      moduleCheckTimer = null;
    }
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
    findGameModules();
  } else {
    window.addEventListener("load", findGameModules, { once: true });
  }
})();
