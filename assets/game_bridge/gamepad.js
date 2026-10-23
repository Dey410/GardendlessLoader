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
  //   through the seed packets and Start pauses. Each goes to the level's own
  //   key handler with the key the player bound to it.
  // The cursor hides on the next touch or mouse input and comes back with
  // the controller. GP-Next pages are web pages over the canvas and stay
  // with touch. The first use in a session lists the buttons in the game's
  // tip bar.
  if (typeof navigator.getGamepads !== "function") return;

  const button = {
    a: 0, b: 1, x: 2, y: 3, lb: 4, rb: 5, start: 9,
    up: 12, down: 13, left: 14, right: 15
  };
  const deadZone = 0.2;
  // Canvas widths per second at full tilt, and for the D-pad.
  const stickSpeed = 1;
  const padSpeed = 0.2;
  // Wheel notches per second at full tilt.
  const wheelRate = 10;
  const wheelNotchDeltaY = 100;
  const seedPacketKeys = 8;
  const moduleIds = {
    ui: "chunks:///_virtual/UI.ts",
    keys: "chunks:///_virtual/KeyListener.ts"
  };
  const cursorSvg =
    "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24'>" +
    "<path d='M3 2v17l4.5-4.2 3.1 6.8 3-1.3-3.1-6.7 6.1-.2z' fill='#fff'" +
    " stroke='#000' stroke-width='1.6' stroke-linejoin='round'/></svg>";
  let frame = null;
  let lastTime = null;
  let pressed = [];
  let held = {left: false, right: false};
  let cursor = null;
  let cursorNode = null;
  let shown = false;
  let wheel = null;
  let stopped = false;
  let keysFailed = false;
  let introduced = false;

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
    // The arrow's tip is at (3, 2).
    cursorNode.style.transform =
      "translate(" + (cursor.x - 3) + "px," + (cursor.y - 2) + "px)";
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
      cursorNode.style.cssText =
        "position:fixed;left:0;top:0;width:24px;height:24px;" +
        "pointer-events:none;z-index:2147483647;";
      cursorNode.innerHTML = cursorSvg;
      (document.body || document.documentElement).appendChild(cursorNode);
    }
    shown = true;
    clampCursor(canvas);
    placeCursor();
    cursorNode.style.display = "block";
    mouse(canvas, "mousemove", 0);
  }

  // Until the game has loaded its tip bar, the next frame tries again.
  function introduce() {
    const tips = window.__gardendlessGameTip;
    return !!tips && tips.show({
      zh: "手柄：A 点击 · B 放回 · X 铲子 · Y 肥料 · LB/RB 换卡 · Start 暂停",
      en: "Controller: A click · B put back · X shovel · Y plant food · " +
        "LB/RB seed packets · Start pause"
    }, 6);
  }

  function hide() {
    if (!shown) return;
    shown = false;
    cursorNode.style.display = "none";
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

  // UIInGame.onKeyDown and onKeyUp are the level's KEY_DOWN and KEY_UP
  // listeners. Outside a level there is no live component and the buttons do
  // nothing.
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
      if (!cc || typeof cc.EventKeyboard !== "function" || !cc.KeyCode ||
          !cc.Input || !KeyListener || !KeyListener.KeyBinds ||
          typeof ui.onKeyDown !== "function" ||
          typeof ui.onKeyUp !== "function" || !ui.cards ||
          !Array.isArray(ui.cards.CFs)) {
        throw new Error("Level key game interfaces are missing");
      }
      return {ui: ui, cc: cc, binds: KeyListener.KeyBinds};
    } catch (error) {
      keysFailed = true;
      console.error("[GardendlessLoader] 手柄快捷键已停用：游戏接口不匹配。", error);
      return null;
    }
  }

  function sendKey(level, binding) {
    const keyCode = level.cc.KeyCode[level.binds[binding]];
    if (!Number.isFinite(keyCode)) {
      throw new Error("Key binding is missing: " + binding);
    }
    const types = level.cc.Input.EventType;
    level.ui.onKeyDown(new level.cc.EventKeyboard(keyCode, types.KEY_DOWN));
    level.ui.onKeyUp(new level.cc.EventKeyboard(keyCode, types.KEY_UP));
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

  function levelButton(index) {
    const level = currentLevel();
    if (!level) return;
    try {
      if (index === button.x) sendKey(level, "Game_Shovel");
      if (index === button.y) sendKey(level, "Game_Plantfood");
      if (index === button.start) sendKey(level, "Game_Pause");
      if (index === button.lb) stepSeedPacket(level, -1);
      if (index === button.rb) stepSeedPacket(level, 1);
    } catch (error) {
      keysFailed = true;
      console.error("[GardendlessLoader] 手柄快捷键已停用：游戏接口不匹配。", error);
    }
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
      releaseButtons();
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
    let moveX = 0;
    let moveY = 0;
    let scroll = 0;
    for (const pad of pads) {
      pad.buttons.forEach(function (state, index) {
        pressed[index] = pressed[index] || state.pressed;
      });
      const stick = tilt(pad.axes[0] || 0, pad.axes[1] || 0);
      moveX += stick.x * stickSpeed;
      moveY += stick.y * stickSpeed;
      scroll += tilt(0, pad.axes[3] || 0).y;
    }
    moveX += ((pressed[button.right] ? 1 : 0) - (pressed[button.left] ? 1 : 0)) * padSpeed;
    moveY += ((pressed[button.down] ? 1 : 0) - (pressed[button.up] ? 1 : 0)) * padSpeed;
    const canvas = gameCanvas();
    if (!canvas || isGpNextOpen()) {
      releaseButtons();
      hide();
      return;
    }
    const went = function (index) {
      return !!pressed[index] && !was[index];
    };
    if (!shown && !moveX && !moveY && !scroll && !pressed.some(Boolean)) return;
    show(canvas);
    if (!introduced) introduced = introduce();
    if (moveX || moveY) {
      const rect = clampCursor(canvas);
      cursor.x += moveX * rect.width * seconds;
      cursor.y += moveY * rect.width * seconds;
      clampCursor(canvas);
      placeCursor();
      mouse(canvas, "mousemove", 0);
    }
    setButton(canvas, "left", !!pressed[button.a]);
    setButton(canvas, "right", !!pressed[button.b]);
    turnWheel(canvas, scroll, seconds);
    for (const index of [button.x, button.y, button.start, button.lb, button.rb]) {
      if (went(index)) levelButton(index);
    }
  }

  // Touch and mouse input take the pointer back.
  for (const type of ["touchstart", "mousedown", "mousemove"]) {
    window.addEventListener(type, function (event) {
      if (event.isTrusted) hide();
    }, true);
  }
  window.addEventListener("gamepadconnected", schedule);
  window.addEventListener("blur", releaseButtons);
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) {
      releaseButtons();
      lastTime = null;
    }
  });
  window.addEventListener("pagehide", function () {
    stopped = true;
    releaseButtons();
    if (frame !== null) {
      cancelAnimationFrame(frame);
      frame = null;
    }
  }, {once: true});
  if (connectedPads().length) schedule();
})();
