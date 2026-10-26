(function () {
  "use strict";

  if (window.__gardendlessGamepadInstalled) return;
  window.__gardendlessGamepadInstalled = true;

  // A game controller plays the mouse game through a cursor drawn over the
  // canvas, in the standard button layout:
  // - The left stick moves the cursor and the D-pad nudges it.
  // - A is the left button and B the right one; holding A drags.
  // - The right stick turns the wheel.
  // - In a level, X takes the shovel, Y the plant food, LB and RB step
  //   through the seed packets and Start pauses, each with the key the
  //   player bound to it.
  // - While a rhythm level plays, the five lanes take the buttons row by
  //   row, top to bottom: LB/RB, Up/Y, Left/Right/X/B, Down/A, LT/RT. A held
  //   button holds the lane's key, which makes that lane's Phat Beet bite.
  //   Start still pauses.
  // - In Air Raid the plane follows the mouse, so the stick flies it through
  //   the cursor, hidden like the game's own pointer. Once B has switched
  //   the plane to keys, the stick and D-pad hold its W/A/S/D keys.
  // The cursor hides on the next touch or mouse input and comes back with
  // the controller. GP-Next pages are web pages over the canvas and stay
  // with touch. The first use in a session lists the buttons in the game's
  // tip bar, and so does the first rhythm level.
  if (typeof navigator.getGamepads !== "function") return;

  const button = {
    a: 0, b: 1, x: 2, y: 3, lb: 4, rb: 5, lt: 6, rt: 7, start: 9,
    up: 12, down: 13, left: 14, right: 15
  };
  // Rhythm lanes from the top, each a row of buttons for either hand.
  const rhythmLanes = [
    [button.lb, button.rb],
    [button.up, button.y],
    [button.left, button.right, button.x, button.b],
    [button.down, button.a],
    [button.lt, button.rt]
  ];
  const deadZone = 0.2;
  // Stick tilt that holds an Air Raid key.
  const steerTilt = 0.5;
  // Canvas widths per second at full tilt, and for the D-pad.
  const stickSpeed = 1;
  const padSpeed = 0.2;
  // Wheel notches per second at full tilt.
  const wheelRate = 10;
  const wheelNotchDeltaY = 100;
  const seedPacketKeys = 8;
  const moduleIds = {
    ui: "chunks:///_virtual/UI.ts",
    keys: "chunks:///_virtual/KeyListener.ts",
    level: "chunks:///_virtual/levelController.ts"
  };
  // A frosted grey dot like the iPadOS pointer, centred on the pointer: the
  // controller aims at whole objects, not pixels. A light rim and a soft
  // shadow keep it visible on bright lawns and dark nights alike.
  const cursorSize = 20;
  const cursorStyle =
    "position:fixed;left:0;top:0;width:" + cursorSize + "px;height:" +
    cursorSize + "px;box-sizing:border-box;border-radius:50%;" +
    "background:rgba(99,99,102,.55);border:1px solid rgba(255,255,255,.6);" +
    "box-shadow:0 1px 6px rgba(0,0,0,.28);" +
    "-webkit-backdrop-filter:blur(6px) saturate(150%);" +
    "backdrop-filter:blur(6px) saturate(150%);" +
    "transition:scale .2s cubic-bezier(.3,1.5,.5,1);" +
    "pointer-events:none;z-index:2147483647;";
  let frame = null;
  let lastTime = null;
  let pressed = [];
  let held = {left: false, right: false};
  // Game keys held down, with the level they went to.
  const heldKeys = new Map();
  let cursor = null;
  let cursorNode = null;
  let shown = false;
  // null for the mouse game, else "rhythm", "flying" or "steering".
  let mode = null;
  let wheel = null;
  let stopped = false;
  let keysFailed = false;
  let introduced = false;
  let rhythmIntroduced = false;

  function gameCanvas() {
    const canvas = document.getElementById("GameCanvas");
    return canvas && canvas.isConnected !== false ? canvas : null;
  }

  function isGpNextOpen() {
    const overlay = document.getElementById("gp-overlay");
    return !!(overlay && overlay.classList &&
      overlay.classList.contains("gp-open"));
  }

  // Cursor -------------------------------------------------------------

  function placeCursor() {
    const offset = cursorSize / 2;
    cursorNode.style.transform =
      "translate(" + (cursor.x - offset) + "px," + (cursor.y - offset) + "px)";
  }

  // A rhythm level and a plane flown by the mouse show no pointer.
  function paintCursor() {
    cursorNode.style.display =
      shown && mode !== "rhythm" && mode !== "flying" ? "block" : "none";
  }

  function clampCursor(canvas) {
    const rect = canvas.getBoundingClientRect();
    if (!cursor) {
      cursor = {x: rect.left + rect.width / 2, y: rect.top + rect.height / 2};
    }
    cursor.x = Math.min(Math.max(cursor.x, rect.left), rect.right - 1);
    cursor.y = Math.min(Math.max(cursor.y, rect.top), rect.bottom - 1);
    return rect;
  }

  // Coming back moves the game's pointer to the cursor, wherever the last
  // touch left it.
  function show(canvas) {
    if (shown) return;
    if (!cursorNode) {
      cursorNode = document.createElement("div");
      cursorNode.style.cssText = cursorStyle;
      (document.body || document.documentElement).appendChild(cursorNode);
    }
    shown = true;
    clampCursor(canvas);
    placeCursor();
    paintCursor();
    mouse(canvas, "mousemove", 0);
  }

  function hide() {
    if (!shown) return;
    shown = false;
    paintCursor();
  }

  // Until the game has loaded its tip bar, the next frame tries again.
  function tip(text, seconds) {
    const tips = window.__gardendlessGameTip;
    return !!tips && tips.show(text, seconds);
  }

  function introduce() {
    return tip({
      zh: "手柄：A 点击 · B 放回 · X 铲子 · Y 肥料 · LB/RB 换卡 · Start 暂停",
      en: "Controller: A click · B put back · X shovel · Y plant food · " +
        "LB/RB seed packets · Start pause"
    }, 6);
  }

  function introduceRhythm() {
    return tip({
      zh: "节奏关从上到下五路：LB/RB · 上/Y · 左右/X/B · 下/A · LT/RT",
      en: "Rhythm lanes, top to bottom: LB/RB · Up/Y · Left/Right/X/B · " +
        "Down/A · LT/RT"
    }, 8);
  }

  // Mouse --------------------------------------------------------------

  function mouse(canvas, type, which) {
    canvas.dispatchEvent(new MouseEvent(type, {
      bubbles: true,
      cancelable: true,
      view: window,
      detail: 1,
      screenX: cursor.x,
      screenY: cursor.y,
      clientX: cursor.x,
      clientY: cursor.y,
      button: which,
      buttons: (held.left ? 1 : 0) | (held.right ? 2 : 0)
    }));
  }

  function setButton(canvas, side, down) {
    if (held[side] === down) return;
    held[side] = down;
    // The dot gives a little under a held button, like a pressed pointer.
    cursorNode.style.scale = held.left || held.right ? "0.8" : "1";
    mouse(canvas, down ? "mousedown" : "mouseup", side === "left" ? 0 : 2);
  }

  function releaseButtons() {
    const canvas = gameCanvas();
    if (!canvas || !cursor) {
      held = {left: false, right: false};
      return;
    }
    setButton(canvas, "left", false);
    setButton(canvas, "right", false);
  }

  // The first notch turns as the stick tips; holding it repeats them.
  function turnWheel(canvas, scroll, seconds) {
    if (!scroll) {
      wheel = null;
      return;
    }
    wheel = wheel === null ? Math.sign(scroll) : wheel + scroll * wheelRate * seconds;
    while (Math.abs(wheel) >= 1) {
      const direction = Math.sign(wheel);
      wheel -= direction;
      canvas.dispatchEvent(new WheelEvent("wheel", {
        deltaY: direction * wheelNotchDeltaY,
        deltaMode: 0,
        bubbles: true,
        cancelable: true,
        clientX: cursor.x,
        clientY: cursor.y,
        screenX: cursor.x,
        screenY: cursor.y
      }));
    }
  }

  // Level keys ---------------------------------------------------------

  function moduleValue(id, name) {
    const system = window.System;
    const module = system && typeof system.get === "function"
      ? system.get(id)
      : null;
    if (!module) return null;
    return module[name] || (module.default && module.default[name]) || null;
  }

  function stopKeys(error) {
    heldKeys.clear();
    if (keysFailed) return;
    keysFailed = true;
    console.error("[GardendlessLoader] 手柄快捷键已停用：游戏接口不匹配。", error);
  }

  // Outside a level there is no live UIInGame component.
  function currentLevel() {
    if (keysFailed) return null;
    const UIInGame = moduleValue(moduleIds.ui, "UIInGame");
    const ui = UIInGame && UIInGame.component;
    if (!ui || !ui.isValid || !ui.node || !ui.node.activeInHierarchy) {
      return null;
    }
    try {
      const system = window.System;
      const cc = system.get(system.resolve("cc"));
      const KeyListener = moduleValue(moduleIds.keys, "KeyListener");
      const LevelPlay = moduleValue(moduleIds.level, "LevelPlay");
      if (!cc || typeof cc.EventKeyboard !== "function" || !cc.KeyCode ||
          !cc.Input || !cc.input ||
          typeof cc.input._dispatchOrPushEvent !== "function" ||
          !Array.isArray(cc.input._eventKeyboardList) || !KeyListener ||
          !KeyListener.KeyBinds || !LevelPlay || !ui.cards ||
          !Array.isArray(ui.cards.CFs)) {
        throw new Error("Level key game interfaces are missing");
      }
      return {ui: ui, cc: cc, binds: KeyListener.KeyBinds, LevelPlay: LevelPlay};
    } catch (error) {
      stopKeys(error);
      return null;
    }
  }

  // Rhythm levels and Air Raid take the controller while they are played; a
  // paused or finished level is the mouse game again.
  function levelMode(level) {
    const LevelPlay = level.LevelPlay;
    const state = LevelPlay.component;
    if (level.ui.paused || !LevelPlay.gaming || !state) return null;
    if (state.rhythmGameProps) return "rhythm";
    const airRaid = LevelPlay.AirRaidProps;
    if (airRaid) return airRaid.mouse_binded ? "flying" : "steering";
    return null;
  }

  // A key reaches the game the way a keyboard sends it: the engine emits
  // KEY_DOWN or KEY_UP to every listener (the level, each Phat Beet,
  // KeyListener), with the key the player bound to the action.
  function gameKey(level, binding, down) {
    const keyCode = level.cc.KeyCode[level.binds[binding]];
    if (!Number.isFinite(keyCode)) {
      throw new Error("Key binding is missing: " + binding);
    }
    const types = level.cc.Input.EventType;
    const input = level.cc.input;
    input._dispatchOrPushEvent(
      new level.cc.EventKeyboard(keyCode, down ? types.KEY_DOWN : types.KEY_UP),
      input._eventKeyboardList
    );
  }

  function sendKey(level, binding) {
    gameKey(level, binding, true);
    gameKey(level, binding, false);
  }

  function holdKey(level, binding, down) {
    if (heldKeys.has(binding) === down) return;
    if (down) {
      heldKeys.set(binding, level);
    } else {
      heldKeys.delete(binding);
    }
    gameKey(level, binding, down);
  }

  function releaseKeys() {
    try {
      heldKeys.forEach(function (level, binding) {
        gameKey(level, binding, false);
      });
    } catch (error) {
      stopKeys(error);
    }
    heldKeys.clear();
  }

  function releaseAll() {
    releaseButtons();
    releaseKeys();
  }

  // Game_Card1 to Game_Card8 take the seed packets. The step skips packets
  // the level would refuse now, recharging or too expensive, so it never
  // plays the refusal.
  function stepSeedPacket(level, direction) {
    const packets = level.ui.cards.CFs.slice(0, seedPacketKeys);
    const count = packets.length;
    const index = level.ui.index;
    let next = index >= 0 && index < count ? index : (direction > 0 ? -1 : count);
    for (let tried = 0; tried < count; tried++) {
      next = (next + direction + count) % count;
      const packet = packets[next];
      if (next !== index && packet && packet.ca && packet.ca.getSelectable()) {
        sendKey(level, "Game_Card" + (next + 1));
        return;
      }
    }
  }

  function levelButton(level, index) {
    if (index === button.x) sendKey(level, "Game_Shovel");
    if (index === button.y) sendKey(level, "Game_Plantfood");
    if (index === button.start) sendKey(level, "Game_Pause");
    if (index === button.lb) stepSeedPacket(level, -1);
    if (index === button.rb) stepSeedPacket(level, 1);
  }

  // Polling ------------------------------------------------------------

  // Past the dead zone the response is quadratic, so a small tilt aims
  // finely.
  function tilt(x, y) {
    const length = Math.hypot(x, y);
    if (!(length > deadZone)) return {x: 0, y: 0};
    const strength = Math.pow(Math.min(1, (length - deadZone) / (1 - deadZone)), 2);
    return {x: x / length * strength, y: y / length * strength};
  }

  function connectedPads() {
    return Array.from(navigator.getGamepads() || []).filter(function (pad) {
      return pad && pad.connected;
    });
  }

  function schedule() {
    if (frame === null && !stopped) frame = requestAnimationFrame(poll);
  }

  function poll(time) {
    frame = null;
    const pads = connectedPads();
    if (!pads.length) {
      releaseAll();
      hide();
      pressed = [];
      lastTime = null;
      return;
    }
    schedule();
    const seconds = lastTime === null ? 0 : Math.min(0.1, (time - lastTime) / 1000);
    lastTime = time;
    const was = pressed;
    pressed = [];
    let stickX = 0;
    let stickY = 0;
    let scroll = 0;
    for (const pad of pads) {
      pad.buttons.forEach(function (state, index) {
        pressed[index] = pressed[index] || state.pressed;
      });
      stickX += pad.axes[0] || 0;
      stickY += pad.axes[1] || 0;
      scroll += tilt(0, pad.axes[3] || 0).y;
    }
    const stick = tilt(stickX, stickY);
    const padX = (pressed[button.right] ? 1 : 0) - (pressed[button.left] ? 1 : 0);
    const padY = (pressed[button.down] ? 1 : 0) - (pressed[button.up] ? 1 : 0);
    const canvas = gameCanvas();
    if (!canvas || isGpNextOpen()) {
      releaseAll();
      hide();
      return;
    }
    if (!shown && !stick.x && !stick.y && !padX && !padY && !scroll &&
        !pressed.some(Boolean)) {
      // A touch hid the cursor while something was held.
      releaseAll();
      return;
    }
    show(canvas);
    if (!introduced) introduced = introduce();
    const went = function (index) {
      return !!pressed[index] && !was[index];
    };
    const level = currentLevel();
    try {
      const next = level ? levelMode(level) : null;
      if (next !== mode) {
        releaseKeys();
        mode = next;
        paintCursor();
      }
      if (mode === "rhythm") {
        if (!rhythmIntroduced) rhythmIntroduced = introduceRhythm();
        setButton(canvas, "left", false);
        setButton(canvas, "right", false);
        rhythmLanes.forEach(function (buttons, lane) {
          holdKey(level, "Rhythm_PhatBeet" + (lane + 1), buttons.some(function (index) {
            return !!pressed[index];
          }));
        });
        if (went(button.start)) sendKey(level, "Game_Pause");
        return;
      }
      if (mode === "steering") {
        holdKey(level, "AirRaid_W", stickY < -steerTilt || padY < 0);
        holdKey(level, "AirRaid_S", stickY > steerTilt || padY > 0);
        holdKey(level, "AirRaid_A", stickX < -steerTilt || padX < 0);
        holdKey(level, "AirRaid_D", stickX > steerTilt || padX > 0);
      } else {
        // The plane follows the cursor, so the D-pad flies at full speed.
        const nudge = mode === "flying" ? stickSpeed : padSpeed;
        const moveX = stick.x * stickSpeed + padX * nudge;
        const moveY = stick.y * stickSpeed + padY * nudge;
        if (moveX || moveY) {
          const rect = clampCursor(canvas);
          cursor.x += moveX * rect.width * seconds;
          cursor.y += moveY * rect.width * seconds;
          clampCursor(canvas);
          placeCursor();
          mouse(canvas, "mousemove", 0);
        }
      }
      setButton(canvas, "left", !!pressed[button.a]);
      setButton(canvas, "right", !!pressed[button.b]);
      turnWheel(canvas, scroll, seconds);
      if (!level) return;
      for (const index of [button.x, button.y, button.start, button.lb, button.rb]) {
        if (went(index)) levelButton(level, index);
      }
    } catch (error) {
      stopKeys(error);
    }
  }

  // Touch and mouse input take the pointer back.
  for (const type of ["touchstart", "mousedown", "mousemove"]) {
    window.addEventListener(type, function (event) {
      if (event.isTrusted) hide();
    }, true);
  }
  window.addEventListener("gamepadconnected", schedule);
  window.addEventListener("blur", releaseAll);
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) {
      releaseAll();
      lastTime = null;
    }
  });
  window.addEventListener("pagehide", function () {
    stopped = true;
    releaseAll();
    if (frame !== null) {
      cancelAnimationFrame(frame);
      frame = null;
    }
  }, {once: true});
  if (connectedPads().length) schedule();
})();
