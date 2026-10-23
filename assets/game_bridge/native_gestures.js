(function () {
  "use strict";

  if (window.__gardendlessNativeGesturesInstalled) return;
  window.__gardendlessNativeGesturesInstalled = true;

  const host = window.__gardendlessHost;
  const config = host ? host.config : (window.__gardendlessHostConfig || {});
  // The simulated gesture mode keeps the mouse game as it is (ADR-0002).
  if (config.touchGestureMode !== "native") return;

  // Native mode plays the mouse game with one finger, the way a phone game
  // would (ADR-0003). Each rule reuses the game's own handler for the action:
  // - Drop: PvZGE picks things up with one press and applies them with the
  //   next press on the target. A press that picks something up and releases
  //   over another target runs that target's own press handler; an unused
  //   drag puts the thing back. This covers seed packets, the shovel, plant
  //   food, sandbox zombie cards and sniper aiming on the lawn, cards in the
  //   decoding minigame, and the Zen Garden glove and tools.
  // - Zen Garden: an empty-handed drag pans, like the right or middle button.
  // - Settings list: one finger scrolls the list the game made wheel-only,
  //   except when the touch starts on a slider.
  // - Sandbox swipe: swiping along the seed bank, the zombie cards or the
  //   zombie armor icon steps it like the wheel does.
  // - Long press: on a custom card deck, a sandbox lawn plant or a decoding
  //   slot, runs the game's right-button action for that target.
  // - Sandbox menu: the sandbox settings window lists keyboard shortcuts and
  //   closes only by key or by its toolbar button. A tap on a shortcut row
  //   closes it and sends that key; a tap outside the window closes it.
  // - Haptics: a drop and a long press tap the device; each sandbox swipe
  //   step ticks it.
  const checkIntervalMs = 250;
  const moduleIds = {
    ui: "chunks:///_virtual/UI.ts",
    square: "chunks:///_virtual/Square.ts",
    mouse: "chunks:///_virtual/Mouse.ts",
    level: "chunks:///_virtual/levelController.ts",
    cards: "chunks:///_virtual/Cards.ts",
    zombieCards: "chunks:///_virtual/SandBoxZombieCards.ts",
    cardDeck: "chunks:///_virtual/CardDeck.ts",
    decoding: "chunks:///_virtual/ArcadeDecodingPlants.ts",
    settingsList: "chunks:///_virtual/ScrollViewWithoutTouchevent.ts",
    zenGarden: "chunks:///_virtual/zenGardenScene.ts",
    keys: "chunks:///_virtual/KeyListener.ts"
  };
  // UIInGame.index: 0-8 seed packets (8 is the conveyor slot), 9 sandbox
  // zombie card, -2 shovel, -3 plant food, -4 sniper aiming. LnC.onMouseDown
  // applies each of these to the tile pressed next.
  const draggableIndexes = new Set([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -2, -3, -4]);
  // Pointer travel, in UI units, that turns a press into a drag.
  const dragDistance = 20;
  // Sandbox swipes, in CSS pixels: the travel that starts one and the travel
  // per wheel step.
  const swipeSlop = 16;
  const swipeStep = 40;
  // Long press: hold time and the CSS-pixel travel that cancels it.
  const longPressMilliseconds = 500;
  const longPressSlop = 12;
  const wheelNotchDeltaY = 100;
  const rightButton = 2;
  // Rows of the sandbox settings window and the key binding each one names.
  const sandboxShortcutRows = {
    StageEffect: "Sandbox_ChangeJam",
    PushTide: "Sandbox_PushTide",
    PullTide: "Sandbox_PullTide",
    SwitchMusic: "Sandbox_SwitchMusic",
    SuperSlow: "Sandbox_TimeFreeze",
    SpawnZombies: "Sandbox_SummonZombies",
    SwitchLawn: "Sandbox_ChangeLawn"
  };
  const keyHoldMilliseconds = 50;
  const failedRules = new Set();
  const game = {};
  let moduleCheckTimer = null;
  let stopped = false;
  let pressActive = false;
  let press = null;
  let pickup = null;
  let zenPan = null;
  let lastPointer = null;

  function stopRule(rule, error) {
    if (failedRules.has(rule)) return;
    failedRules.add(rule);
    if (rule === "drop") pickup = null;
    if (rule === "zen") endZenPan();
    console.error("[GardendlessLoader] 原生手势（" + rule + "）已停用：游戏接口不匹配。", error);
  }

  function ruleOn(rule) {
    return !stopped && !failedRules.has(rule);
  }

  // "impact" is a light tap, "selection" the tick of a step through a list.
  function haptic(kind) {
    if (!host) return;
    // A missed tap is not worth a log entry.
    host.invoke("host:haptic", {kind: kind}).catch(function () {});
  }

  // Square.update derives Mouse.mouseInLnC the same way, but only on the
  // next game frame. Mouse.position follows every MOUSE_MOVE synchronously.
  function tileUnderPointer() {
    const position = game.Mouse.position;
    const tile = game.Square.getLnC(
      game.Square.judgeLIndex(position.y),
      game.Square.judgeCIndex(position.x)
    );
    return tile && tile.isInLawn() ? tile : null;
  }

  function pointerOrigin() {
    const position = game.Mouse.positionOrg;
    return {x: position.x, y: position.y};
  }

  function pointerIn(node) {
    if (!node || !node.isValid || !node.activeInHierarchy) return false;
    const transform = node.getComponent("cc.UITransform");
    return !!transform && !!game.Mouse.judgeInUITransform(transform);
  }

  function buttonDown(button) {
    const event = new game.cc.EventMouse(game.cc.Input.EventType.MOUSE_DOWN, false);
    event.setButton(button);
    return event;
  }

  function rightButtonDown() {
    return buttonDown(rightButton);
  }

  function draggedFrom(origin) {
    const now = pointerOrigin();
    return Math.hypot(now.x - origin.x, now.y - origin.y) > dragDistance;
  }

  // Drop ---------------------------------------------------------------

  function installDrop(uiPrototype) {
    const originalTryChangingIndex = uiPrototype.tryChangingIndex;
    const originalOnMouseUp = uiPrototype.onMouseUp;

    uiPrototype.tryChangingIndex = function (index) {
      const result = originalTryChangingIndex.apply(this, arguments);
      if (pressActive && ruleOn("drop") && this.index === index &&
          draggableIndexes.has(index)) {
        try {
          pickup = {index: index, tile: tileUnderPointer(), origin: pointerOrigin()};
        } catch (error) {
          stopRule("drop", error);
        }
      }
      return result;
    };

    // UIInGame.start registers this method as the level's MOUSE_UP listener.
    uiPrototype.onMouseUp = function (event) {
      const current = pickup;
      pickup = null;
      let tile = null;
      let dragged = false;
      if (current && ruleOn("drop")) {
        try {
          tile = tileUnderPointer();
          const origin = pointerOrigin();
          dragged = Math.hypot(origin.x - current.origin.x,
            origin.y - current.origin.y) > dragDistance;
        } catch (error) {
          stopRule("drop", error);
        }
      }
      const result = originalOnMouseUp.apply(this, arguments);
      if (!current || !ruleOn("drop") || this.paused ||
          this.index !== current.index || event.getButton() !== 0) {
        return result;
      }
      try {
        if (tile && tile !== current.tile) {
          tile.onMouseDown(event, true);
          haptic("impact");
        } else if (tile || !dragged) {
          // Released where it was picked up: a tap keeps the tool in hand.
          return result;
        }
        if (this.index === current.index) this.tryChangingIndex(-1);
      } catch (error) {
        stopRule("drop", error);
      }
      return result;
    };
  }

  // Zen Garden ---------------------------------------------------------

  function endZenPan() {
    if (!zenPan) return;
    zenPan.pressed = false;
    zenPan = null;
  }

  function startZenPan() {
    if (!game.ZenGarden || !ruleOn("zen")) return;
    try {
      const garden = game.ZenGarden.component;
      if (!garden || !garden.node || !garden.node.isValid ||
          !garden.node.activeInHierarchy || garden.pressed ||
          garden.isShoveling || garden.isGloving || garden.isCarting ||
          garden.willMovePlantSlot) {
        return;
      }
      garden.pressed = true;
      zenPan = garden;
    } catch (error) {
      stopRule("zen", error);
    }
  }

  // Decoding minigame drop ---------------------------------------------

  function activeDecoding() {
    if (!game.cc || !game.ArcadeDecodingPlants) return null;
    const scene = game.cc.director.getScene();
    const decoding = scene &&
      scene.getComponentsInChildren(game.ArcadeDecodingPlants)[0];
    return decoding && decoding.node && decoding.node.activeInHierarchy
      ? decoding
      : null;
  }

  // A source card or a filled slot picked up by the press is placed by the
  // target slot's own left-press handler, which merges or swaps as a tap
  // would.
  function dropDecodingCard(current) {
    const decoding = current.decoding;
    const card = current.card;
    if (decoding.PickedCard !== card || decoding.confirming) return;
    for (const slot of decoding.MergedCards || []) {
      if (slot !== card && pointerIn(slot.node)) {
        slot.node.emit(game.cc.Node.EventType.MOUSE_DOWN, buttonDown(0));
        haptic("impact");
        return;
      }
    }
    if (draggedFrom(current.origin)) decoding.ReleaseCard();
  }

  // Zen Garden drop ----------------------------------------------------

  function zenTools(garden) {
    return {
      shoveling: !!garden.isShoveling,
      gloving: !!garden.isGloving,
      carting: !!garden.isCarting,
      plant: garden.willMovePlantSlot || null
    };
  }

  function zenSlotUnderPointer(garden) {
    const zen = garden.currentZen;
    if (!zen || !zen.slots) return null;
    const slots = zen.slots.concat().reverse();
    for (const slot of slots) {
      if (slot.judgeMouse()) return {zen: zen, slot: slot};
    }
    return null;
  }

  // The glove picks a plant on its first slot press and moves it on the
  // next; a tool taken from its button is applied by a slot press. Both run
  // ZenGarden.MouseDown, the game's slot press handler.
  function dropZen(current) {
    const garden = current.garden;
    if (!garden.node || !garden.node.isValid) return;
    const before = current.tools;
    const after = zenTools(garden);
    const pickedPlant = after.gloving && after.plant && after.plant !== before.plant;
    const pickedTool = (after.shoveling && !before.shoveling) ||
      (after.gloving && !before.gloving) || (after.carting && !before.carting);
    if (!pickedPlant && !pickedTool) return;
    const target = zenSlotUnderPointer(garden);
    if (target && !(pickedPlant && target.slot === after.plant)) {
      target.zen.MouseDown(target.slot);
      haptic("impact");
    } else if (!target && draggedFrom(current.origin)) {
      if (pickedTool) {
        garden.indexTo_1();
      } else {
        garden.setWillMovePlantSlot(null);
      }
    }
  }

  // Sandbox menu -------------------------------------------------------

  function openSandboxMenu() {
    const ui = game.UIInGame && game.UIInGame.component;
    const menu = ui && ui.sandBoxSettingWindow;
    return menu && menu.isValid && menu.activeInHierarchy ? {ui: ui, menu: menu} : null;
  }

  // The window's own full-screen mouse blocker swallows every press outside
  // its frame, except for buttons drawn above the window such as the toolbar
  // button that opened it. Full-screen effect layers above it take no input.
  function sandboxMenuTarget(open) {
    const frame = open.menu.getChildByName("windowCommon");
    if (frame && pointerIn(frame)) {
      const list = open.menu.getComponentInChildren(game.cc.ScrollView);
      const view = list && list.view && list.view.node;
      if (!list || !list.content || (view && !pointerIn(view))) return null;
      for (const row of list.content.children) {
        if (sandboxShortcutRows[row.name] && pointerIn(row)) {
          return {key: sandboxShortcutRows[row.name]};
        }
      }
      return null;
    }
    const parent = open.menu.parent;
    const above = parent ? parent.children.slice(open.menu.getSiblingIndex() + 1) : [];
    const onButton = above.some(function (node) {
      return node.activeInHierarchy &&
        node.getComponentsInChildren(game.cc.Button).some(function (button) {
          return button.enabledInHierarchy && button.interactable &&
            pointerIn(button.node);
        });
    });
    return onButton ? null : {outside: true};
  }

  // The engine maps DOM key events by KeyboardEvent.code through a private
  // table, so the key goes to the level's own KEY_DOWN and KEY_UP listeners
  // as the engine event. The game reads the player's current binding, and
  // ignores sandbox keys while the window is open, so the key follows the
  // close.
  function sendSandboxKey(ui, binding) {
    const keyCode = game.cc.KeyCode[game.KeyListener.KeyBinds[binding]];
    if (!Number.isFinite(keyCode)) {
      throw new Error("Sandbox key binding is missing: " + binding);
    }
    const types = game.cc.Input.EventType;
    ui.onKeyDown(new game.cc.EventKeyboard(keyCode, types.KEY_DOWN));
    setTimeout(function () {
      try {
        ui.onKeyUp(new game.cc.EventKeyboard(keyCode, types.KEY_UP));
      } catch (error) {
        stopRule("sandboxMenu", error);
      }
    }, keyHoldMilliseconds);
  }

  function tapSandboxMenu(current) {
    const open = openSandboxMenu();
    if (!open || open.menu !== current.menu) return;
    open.ui.showSBSettings();
    if (current.target.key) sendSandboxKey(open.ui, current.target.key);
  }

  // Settings list --------------------------------------------------------

  // ScrollView registers these four methods when it is enabled, so replacing
  // them on the prototype covers every settings window opened afterwards.
  function installSettingsList(listPrototype) {
    const base = Object.getPrototypeOf(listPrototype);
    const names = ["_onTouchBegan", "_onTouchMoved", "_onTouchEnded",
      "_onTouchCancelled"];
    for (const name of names) {
      if (typeof base[name] !== "function") {
        throw new Error("ScrollView touch handler is missing: " + name);
      }
    }
    const sliderTouches = new WeakMap();

    function startsOnSlider(event, listNode) {
      let node = event && event.target;
      while (node && node !== listNode) {
        if (node.getComponent && node.getComponent("cc.Slider")) return true;
        node = node.parent;
      }
      return false;
    }

    listPrototype._onTouchBegan = function (event) {
      const slider = ruleOn("settings") && startsOnSlider(event, this.node);
      sliderTouches.set(this, slider);
      if (!ruleOn("settings") || slider) return;
      return base._onTouchBegan.apply(this, arguments);
    };
    for (const name of names.slice(1)) {
      listPrototype[name] = function () {
        if (!ruleOn("settings") || sliderTouches.get(this) !== false) return;
        return base[name].apply(this, arguments);
      };
    }
  }

  // Sandbox swipe ------------------------------------------------------

  function swipeTargets() {
    const targets = [];
    if (!game.LevelPlay || !game.LevelPlay.sandBoxModeOn ||
        !game.LevelPlay.gameStarted) {
      return targets;
    }
    for (const owner of [game.Cards, game.SandBoxZombieCards]) {
      const component = owner && owner.component;
      if (component && component.uitransform &&
          component.node && component.node.activeInHierarchy) {
        targets.push(component.node);
      }
    }
    const ui = game.UIInGame.component;
    const armor = ui && ui.SBZombieArmorIconSlot;
    if (armor && armor.isValid && armor.activeInHierarchy && armor.parent) {
      targets.push(armor.parent);
    }
    return targets;
  }

  function swipeTargetUnderPointer() {
    for (const node of swipeTargets()) {
      if (pointerIn(node)) {
        const transform = node.getComponent("cc.UITransform");
        return {node: node, horizontal: transform.width >= transform.height};
      }
    }
    return null;
  }

  function dispatchWheel(deltaY) {
    const canvas = document.getElementById("GameCanvas");
    if (!canvas || !lastPointer) return;
    canvas.dispatchEvent(new WheelEvent("wheel", {
      deltaY: deltaY,
      deltaMode: 0,
      bubbles: true,
      cancelable: true,
      clientX: lastPointer.clientX,
      clientY: lastPointer.clientY,
      screenX: lastPointer.screenX,
      screenY: lastPointer.screenY
    }));
  }

  // The content follows the finger: swiping toward the start of the strip
  // shows the next cards, which is wheel-down for these handlers.
  function moveSwipe(event) {
    const swipe = press && press.swipe;
    if (!swipe || swipe.state === "drag") return;
    const along = swipe.horizontal
      ? event.clientX - swipe.start.clientX
      : event.clientY - swipe.start.clientY;
    const across = swipe.horizontal
      ? event.clientY - swipe.start.clientY
      : event.clientX - swipe.start.clientX;
    if (swipe.state === "pending") {
      let inside = false;
      try {
        inside = pointerIn(swipe.node);
      } catch (error) {
        stopRule("swipe", error);
        return;
      }
      if (!inside) {
        swipe.state = "drag";
        return;
      }
      if (Math.abs(along) <= swipeSlop || Math.abs(along) <= Math.abs(across)) {
        return;
      }
      // Steps count from the end of the slop.
      swipe.state = "cycling";
      swipe.stepped = Math.sign(along) * swipeSlop;
      cancelPressPickup();
    }
    while (Math.abs(along - swipe.stepped) >= swipeStep) {
      const direction = Math.sign(along - swipe.stepped);
      swipe.stepped += direction * swipeStep;
      dispatchWheel(direction < 0 ? wheelNotchDeltaY : -wheelNotchDeltaY);
      haptic("selection");
    }
  }

  // A swipe that started on a card must not leave that card in hand.
  function cancelPressPickup() {
    pickup = null;
    const ui = game.UIInGame.component;
    if (ui && press && ui.index !== press.indexBefore && ui.index !== -1) {
      ui.tryChangingIndex(-1);
    }
  }

  // Long press ---------------------------------------------------------

  function customDeckUnderPointer() {
    const level = game.LevelPlay && game.LevelPlay.component;
    const displayer = level && level.carddeck_displayer;
    const parent = displayer && displayer.CardDeckParent;
    if (!parent || !displayer.node || !displayer.node.activeInHierarchy) {
      return null;
    }
    for (const child of parent.children) {
      const deck = child.getComponent(game.CardDeck);
      if (deck && !deck.AddMode && !deck.ChallengingMode &&
          !deck.RecommendedMode && pointerIn(child)) {
        return child;
      }
    }
    return null;
  }

  function decodingSlotUnderPointer() {
    const scene = game.cc.director.getScene();
    const decoding = scene &&
      scene.getComponentsInChildren(game.ArcadeDecodingPlants)[0];
    if (!decoding || !decoding.node.activeInHierarchy || decoding.confirming) {
      return null;
    }
    for (const slot of decoding.MergedCards || []) {
      if (slot.currentPlant && !slot.isCorrect() && pointerIn(slot.node)) {
        return slot.node;
      }
    }
    return null;
  }

  function sandboxPlantTileUnderPointer() {
    const ui = game.UIInGame.component;
    if (!game.LevelPlay || !game.LevelPlay.sandBoxModeOn ||
        !game.LevelPlay.gameStarted || !ui || ui.paused || ui.index !== -1) {
      return null;
    }
    const tile = tileUnderPointer();
    return tile && tile.getAllPlants().length > 0 ? tile : null;
  }

  function fireLongPress() {
    if (!press || press.moved || !ruleOn("longPress")) return;
    press.longPressTimer = null;
    try {
      const deck = customDeckUnderPointer();
      if (deck) {
        deck.emit(game.cc.Node.EventType.MOUSE_DOWN, rightButtonDown());
        haptic("impact");
        return;
      }
      const slot = decodingSlotUnderPointer();
      if (slot) {
        slot.emit(game.cc.Node.EventType.MOUSE_DOWN, rightButtonDown());
        haptic("impact");
        return;
      }
      const tile = sandboxPlantTileUnderPointer();
      if (tile) {
        tile.plantMouseReact(rightButtonDown());
        haptic("impact");
      }
    } catch (error) {
      stopRule("longPress", error);
    }
  }

  // Press tracking -------------------------------------------------------

  function endPress() {
    if (press && press.longPressTimer !== null) {
      clearTimeout(press.longPressTimer);
    }
    press = null;
    endZenPan();
  }

  function rememberPointer(event) {
    lastPointer = {
      clientX: event.clientX,
      clientY: event.clientY,
      screenX: event.screenX,
      screenY: event.screenY
    };
  }

  // Cocos handles canvas mouse events synchronously and stops their
  // propagation, so the press is marked in the capture phase and the rest
  // runs in a task after the whole event dispatch: by then a tool button the
  // press hit has put its tool in hand. Every new press also drops a pickup
  // whose release never reached the level's MOUSE_UP listener.
  window.addEventListener("mousedown", function (event) {
    if (event.button !== 0) return;
    endPress();
    pickup = null;
    rememberPointer(event);
    const current = {
      start: lastPointer,
      moved: false,
      longPressTimer: null,
      swipe: null,
      indexBefore: game.UIInGame && game.UIInGame.component
        ? game.UIInGame.component.index
        : null
    };
    if (ruleOn("decoding")) {
      try {
        const decoding = activeDecoding();
        if (decoding) current.decoding = {decoding: decoding, before: decoding.PickedCard};
      } catch (error) {
        stopRule("decoding", error);
      }
    }
    if (game.ZenGarden && ruleOn("zen")) {
      try {
        const garden = game.ZenGarden.component;
        if (garden && garden.node && garden.node.isValid &&
            garden.node.activeInHierarchy) {
          current.zen = {garden: garden, tools: zenTools(garden), origin: pointerOrigin()};
        }
      } catch (error) {
        stopRule("zen", error);
      }
    }
    if (game.UIInGame && ruleOn("sandboxMenu")) {
      try {
        const open = openSandboxMenu();
        const target = open && sandboxMenuTarget(open);
        if (target) current.sandboxMenu = {menu: open.menu, target: target};
      } catch (error) {
        stopRule("sandboxMenu", error);
      }
    }
    press = current;
    pressActive = true;
    if (game.UIInGame && ruleOn("swipe")) {
      try {
        const target = swipeTargetUnderPointer();
        if (target) {
          current.swipe = {
            node: target.node,
            horizontal: target.horizontal,
            start: lastPointer,
            state: "pending",
            stepped: 0
          };
        }
      } catch (error) {
        stopRule("swipe", error);
      }
    }
    if (game.cc && ruleOn("longPress")) {
      current.longPressTimer = setTimeout(fireLongPress, longPressMilliseconds);
    }
    setTimeout(function () {
      pressActive = false;
      if (press !== current) return;
      const decoding = current.decoding;
      if (decoding && decoding.decoding.PickedCard &&
          decoding.decoding.PickedCard !== decoding.before) {
        try {
          current.decodingPickup = {
            decoding: decoding.decoding,
            card: decoding.decoding.PickedCard,
            origin: pointerOrigin()
          };
        } catch (error) {
          stopRule("decoding", error);
        }
      }
      startZenPan();
    }, 0);
  }, true);
  window.addEventListener("mousemove", function (event) {
    if (!press) return;
    rememberPointer(event);
    if (!press.moved && Math.hypot(event.clientX - press.start.clientX,
        event.clientY - press.start.clientY) > longPressSlop) {
      press.moved = true;
      if (press.longPressTimer !== null) {
        clearTimeout(press.longPressTimer);
        press.longPressTimer = null;
      }
    }
    if (ruleOn("swipe")) moveSwipe(event);
  }, true);
  // The decoding minigame and the Zen Garden act only on presses, so their
  // drops run before the release reaches the game.
  window.addEventListener("mouseup", function (event) {
    if (event.button !== 0) return;
    const current = press;
    if (current && current.decodingPickup && ruleOn("decoding")) {
      try {
        dropDecodingCard(current.decodingPickup);
      } catch (error) {
        stopRule("decoding", error);
      }
    }
    if (current && current.zen && ruleOn("zen")) {
      try {
        dropZen(current.zen);
      } catch (error) {
        stopRule("zen", error);
      }
    }
    if (current && current.sandboxMenu && !current.moved) {
      // After the release has reached the game, which still had the window.
      const menu = current.sandboxMenu;
      setTimeout(function () {
        if (!ruleOn("sandboxMenu")) return;
        try {
          tapSandboxMenu(menu);
        } catch (error) {
          stopRule("sandboxMenu", error);
        }
      }, 0);
    }
    endPress();
  }, true);
  window.addEventListener("blur", endPress);
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) endPress();
  });
  window.addEventListener("pagehide", function () {
    stopped = true;
    pickup = null;
    endPress();
    if (moduleCheckTimer !== null) {
      clearTimeout(moduleCheckTimer);
      moduleCheckTimer = null;
    }
  }, {once: true});

  // Installation ---------------------------------------------------------

  function moduleValue(module, name) {
    if (!module) return null;
    return module[name] || (module.default && module.default[name]) || null;
  }

  function scheduleModuleCheck() {
    if (stopped || moduleCheckTimer !== null) return;
    moduleCheckTimer = setTimeout(findGameModules, checkIntervalMs);
  }

  function findGameModules() {
    moduleCheckTimer = null;
    // Only read modules Cocos has already executed; importing them here
    // would run the game's circular module graph from another entry point.
    const system = window.System;
    const get = function (id) {
      return system && typeof system.get === "function" ? system.get(id) : null;
    };
    const modules = {};
    for (const key of Object.keys(moduleIds)) modules[key] = get(moduleIds[key]);
    if (!modules.ui || !modules.square || !modules.mouse || !modules.level) {
      scheduleModuleCheck();
      return;
    }
    // The game bundle registers all of its modules together.
    try {
      game.cc = system.get(system.resolve("cc"));
    } catch (_) {
      game.cc = null;
    }
    game.UIInGame = moduleValue(modules.ui, "UIInGame");
    game.Square = moduleValue(modules.square, "Square");
    game.Mouse = moduleValue(modules.mouse, "Mouse");
    game.LevelPlay = moduleValue(modules.level, "LevelPlay");
    game.Cards = moduleValue(modules.cards, "Cards");
    game.SandBoxZombieCards = moduleValue(modules.zombieCards, "SandBoxZombieCards");
    game.CardDeck = moduleValue(modules.cardDeck, "CardDeck");
    game.ArcadeDecodingPlants = moduleValue(modules.decoding, "ArcadeDecodingPlants");
    game.ZenGarden = moduleValue(modules.zenGarden, "zenGardenScene");
    game.KeyListener = moduleValue(modules.keys, "KeyListener");
    const settingsList = moduleValue(modules.settingsList, "ScrollViewWithoutTouchevent");
    const uiPrototype = game.UIInGame && game.UIInGame.prototype;
    const pointerReady = !!game.Mouse &&
      typeof game.Mouse.judgeInUITransform === "function" && !!game.Square &&
      typeof game.Square.getLnC === "function" &&
      typeof game.Square.judgeLIndex === "function" &&
      typeof game.Square.judgeCIndex === "function";

    try {
      if (!uiPrototype || typeof uiPrototype.tryChangingIndex !== "function" ||
          typeof uiPrototype.onMouseUp !== "function" || !pointerReady) {
        throw new Error("Drop game interfaces are missing");
      }
      installDrop(uiPrototype);
    } catch (error) {
      stopRule("drop", error);
    }
    if (!game.ZenGarden || !("component" in game.ZenGarden)) {
      stopRule("zen", new Error("Zen Garden game interface is missing"));
    }
    try {
      if (!settingsList || !settingsList.prototype) {
        throw new Error("Settings list game interface is missing");
      }
      installSettingsList(settingsList.prototype);
    } catch (error) {
      stopRule("settings", error);
    }
    if (!pointerReady || !game.LevelPlay || !game.Cards ||
        !game.SandBoxZombieCards || typeof WheelEvent !== "function") {
      stopRule("swipe", new Error("Sandbox swipe game interfaces are missing"));
    }
    if (!pointerReady || !game.cc || typeof game.cc.EventMouse !== "function" ||
        !game.cc.Node || !game.cc.director || !game.LevelPlay ||
        !game.CardDeck || !game.ArcadeDecodingPlants) {
      stopRule("longPress", new Error("Long press game interfaces are missing"));
    }
    if (!pointerReady || !game.cc || typeof game.cc.EventMouse !== "function" ||
        !game.cc.Node || !game.cc.director || !game.ArcadeDecodingPlants) {
      stopRule("decoding", new Error("Decoding drop game interfaces are missing"));
    }
    if (!pointerReady || !uiPrototype ||
        typeof uiPrototype.showSBSettings !== "function" ||
        typeof uiPrototype.onKeyDown !== "function" ||
        typeof uiPrototype.onKeyUp !== "function" || !game.cc ||
        !game.cc.ScrollView || !game.cc.Button || !game.cc.KeyCode ||
        typeof game.cc.EventKeyboard !== "function" || !game.KeyListener) {
      stopRule("sandboxMenu", new Error("Sandbox menu game interfaces are missing"));
    }
  }

  if (document.readyState === "complete") {
    findGameModules();
  } else {
    window.addEventListener("load", findGameModules, {once: true});
  }
})();
