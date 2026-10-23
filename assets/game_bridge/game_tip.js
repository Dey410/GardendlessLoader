(function () {
  "use strict";

  if (window.__gardendlessGameTip) return;

  // Loader messages appear in the game's own tip bar, the one its tutorial
  // speaks through. KeyListener.cp.gameTipString queues a line after the tips
  // already waiting, and MultiLanguage.getString picks the line for the
  // language set in the game. The other bridge scripts call
  // __gardendlessGameTip.show({zh, en}, seconds); it returns false while the
  // game has not loaded its tip bar yet.
  const moduleIds = {
    keys: "chunks:///_virtual/KeyListener.ts",
    language: "chunks:///_virtual/MultiLanguage.ts"
  };
  let failed = false;

  function moduleValue(id, name) {
    const system = window.System;
    const module = system && typeof system.get === "function"
      ? system.get(id)
      : null;
    if (!module) return null;
    return module[name] || (module.default && module.default[name]) || null;
  }

  function show(text, seconds) {
    if (failed) return false;
    const KeyListener = moduleValue(moduleIds.keys, "KeyListener");
    const bar = KeyListener && KeyListener.cp;
    if (!bar) return false;
    try {
      const MultiLanguage = moduleValue(moduleIds.language, "MultiLanguage");
      if (typeof bar.gameTipString !== "function" || !MultiLanguage ||
          typeof MultiLanguage.getString !== "function") {
        throw new Error("Game tip interfaces are missing");
      }
      bar.gameTipString(MultiLanguage.getString(text), seconds);
      return true;
    } catch (error) {
      failed = true;
      console.error("[GardendlessLoader] 游戏提示条已停用：游戏接口不匹配。", error);
      return false;
    }
  }

  window.__gardendlessGameTip = Object.freeze({show: show});
})();
