(function () {
  "use strict";

  if (window.__gardendlessPauseOnReturnInstalled) return;
  window.__gardendlessPauseOnReturnInstalled = true;

  // Leaving the app freezes a level mid-wave. When the page is hidden during
  // play, the level opens its own pause menu, so the player comes back to it
  // instead of to zombies already on the move. UIInGame.pauseMenu is what
  // the pause button runs; it also stops rhythm music and releases the Air
  // Raid mouse binding. The pause key would instead advance a tutorial flow
  // or close the deck window first.
  const moduleIds = {
    ui: "chunks:///_virtual/UI.ts",
    level: "chunks:///_virtual/levelController.ts"
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

  // Outside a level there is no live UIInGame component.
  function pauseLevel() {
    if (failed) return;
    const UIInGame = moduleValue(moduleIds.ui, "UIInGame");
    const ui = UIInGame && UIInGame.component;
    if (!ui || !ui.isValid || !ui.node || !ui.node.activeInHierarchy) return;
    try {
      const LevelPlay = moduleValue(moduleIds.level, "LevelPlay");
      const level = LevelPlay && LevelPlay.component;
      if (!level || typeof ui.pauseMenu !== "function") {
        throw new Error("Level pause game interfaces are missing");
      }
      if (ui.paused || !LevelPlay.gameStarted || level.gameWon || level.gameLost) {
        return;
      }
      ui.pauseMenu();
    } catch (error) {
      failed = true;
      console.error("[GardendlessLoader] 回来先暂停已停用：游戏接口不匹配。", error);
    }
  }

  document.addEventListener("visibilitychange", function () {
    if (document.hidden) pauseLevel();
  });
})();
