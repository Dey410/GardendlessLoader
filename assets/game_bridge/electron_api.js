(function () {
  "use strict";

  if (window.__gardendlessDialogs) return;

  // The game calls window.electronAPI methods that only the desktop app
  // provides. GP-Next's tmpPatch replaces the whole object and the resource
  // package adds music pack and document methods to it later, so electronAPI
  // is an accessor: every object assigned to it keeps the earlier methods and
  // gains the missing ones below. Methods that already exist are never
  // replaced.
  const githubCallbacks = {play: new Set(), content: new Set(), changed: new Set()};
  const shims = {};
  let current = {};

  function fill(target) {
    for (const key of Object.keys(shims)) {
      if (typeof target[key] !== "function") {
        try { target[key] = shims[key]; } catch (_) { /* A frozen object keeps its own API. */ }
      }
    }
    return target;
  }

  function adopt(value) {
    const next = value && (typeof value === "object" || typeof value === "function") ? value : {};
    if (next !== current) {
      for (const key of Object.keys(current)) {
        if (!(key in next)) {
          try { next[key] = current[key]; } catch (_) { /* See fill. */ }
        }
      }
    }
    current = fill(next);
  }

  function defineShims(methods) {
    Object.assign(shims, methods);
    fill(current);
  }

  function subscribe(set, callback) {
    if (typeof callback !== "function") return function () {};
    set.add(callback);
    return function () { set.delete(callback); };
  }

  function emit(set, value) {
    let delivered = false;
    for (const callback of Array.from(set)) {
      delivered = true;
      try {
        const result = callback(value);
        if (result && typeof result.catch === "function") {
          result.catch(function (error) { console.error("[GardendlessLoader] Game callback failed:", error); });
        }
      } catch (error) {
        console.error("[GardendlessLoader] Game callback failed:", error);
      }
    }
    return delivered;
  }

  // Shared dialog look, matching the resource package's music pack window.
  const styleId = "gardendless-dialog-style";
  const css = [
    ".gardendless-dialog{color:#eee;background:#202020;border:1px solid #555;border-radius:12px;",
    "padding:16px 20px;width:min(720px,92vw);max-height:86vh;font:16px system-ui,sans-serif;",
    "box-sizing:border-box;display:flex;flex-direction:column;gap:12px;}",
    ".gardendless-dialog:not([open]){display:none;}",
    ".gardendless-dialog::backdrop{background:#0009;}",
    ".gardendless-dialog header{display:flex;justify-content:space-between;align-items:center;gap:16px;}",
    ".gardendless-dialog h2{margin:0;font-size:20px;}",
    ".gardendless-dialog .gd-body{overflow:auto;min-height:0;flex:1 1 auto;}",
    ".gardendless-dialog .gd-row{display:flex;align-items:center;justify-content:space-between;gap:12px;",
    "padding:8px 0;border-bottom:1px solid #444;}",
    ".gardendless-dialog .gd-row>span:first-child{min-width:0;overflow-wrap:anywhere;}",
    ".gardendless-dialog .gd-actions{display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end;flex-shrink:0;}",
    ".gardendless-dialog button,.gardendless-dialog select{font:inherit;color:inherit;background:#333;",
    "border:1px solid #777;border-radius:6px;padding:6px 12px;min-height:38px;cursor:pointer;}",
    ".gardendless-dialog button:disabled{opacity:.5;cursor:default;}",
    ".gardendless-dialog button.gd-primary{background:#2d5a2d;border-color:#5a9a5a;}",
    ".gardendless-dialog .gd-group{margin:14px 0 4px;font-weight:600;color:#bbb;}",
    ".gardendless-dialog .gd-muted{color:#aaa;font-size:14px;}",
    ".gardendless-dialog .gd-status{min-height:1.2em;white-space:pre-wrap;color:#ccc;}",
    ".gardendless-dialog .gd-footer{display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end;}"
  ].join("");

  function ensureStyle() {
    if (document.getElementById(styleId)) return;
    const style = document.createElement("style");
    style.id = styleId;
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function button(text, onClick, className) {
    const node = element("button", className, text);
    node.type = "button";
    node.addEventListener("click", onClick);
    return node;
  }

  // A modal dialog that keeps keyboard input away from the game underneath.
  function createDialog(title, closeLabel) {
    ensureStyle();
    const dialog = element("dialog", "gardendless-dialog");
    dialog.setAttribute("aria-label", title);
    const header = element("header");
    const heading = element("h2", null, title);
    const close = button(closeLabel, function () { dialog.close(); });
    header.append(heading, close);
    const body = element("div", "gd-body");
    dialog.append(header, body);
    for (const type of ["keydown", "keyup", "keypress"]) {
      dialog.addEventListener(type, function (event) { event.stopPropagation(); });
    }
    dialog.addEventListener("close", function () { dialog.remove(); }, {once: true});
    return {dialog: dialog, header: header, heading: heading, body: body, closeButton: close};
  }

  function show(dialog) {
    (document.body || document.documentElement).appendChild(dialog);
    dialog.showModal();
  }

  // The game's own document window: an open dialog holding a srcdoc frame.
  function markdownDialog() {
    for (const dialog of document.querySelectorAll("dialog[open]")) {
      if (!dialog.classList.contains("gardendless-dialog") && dialog.querySelector("iframe[srcdoc]")) {
        return dialog;
      }
    }
    return null;
  }

  // Key binding editor --------------------------------------------------------

  const fallbackKeyNames = ["BACKSPACE", "TAB", "ENTER", "SHIFT_LEFT", "CTRL_LEFT", "ALT_LEFT",
    "PAUSE", "CAPS_LOCK", "ESCAPE", "SPACE", "PAGE_UP", "PAGE_DOWN", "END", "HOME", "ARROW_LEFT",
    "ARROW_UP", "ARROW_RIGHT", "ARROW_DOWN", "INSERT", "DELETE", "DIGIT_0", "DIGIT_1", "DIGIT_2",
    "DIGIT_3", "DIGIT_4", "DIGIT_5", "DIGIT_6", "DIGIT_7", "DIGIT_8", "DIGIT_9", "KEY_A", "KEY_B",
    "KEY_C", "KEY_D", "KEY_E", "KEY_F", "KEY_G", "KEY_H", "KEY_I", "KEY_J", "KEY_K", "KEY_L",
    "KEY_M", "KEY_N", "KEY_O", "KEY_P", "KEY_Q", "KEY_R", "KEY_S", "KEY_T", "KEY_U", "KEY_V",
    "KEY_W", "KEY_X", "KEY_Y", "KEY_Z", "NUM_0", "NUM_1", "NUM_2", "NUM_3", "NUM_4", "NUM_5",
    "NUM_6", "NUM_7", "NUM_8", "NUM_9", "NUM_MULTIPLY", "NUM_PLUS", "NUM_SUBTRACT", "NUM_DECIMAL",
    "NUM_DIVIDE", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    "NUM_LOCK", "SCROLL_LOCK", "SEMICOLON", "EQUAL", "COMMA", "DASH", "PERIOD", "SLASH",
    "BACK_QUOTE", "BRACKET_LEFT", "BACKSLASH", "BRACKET_RIGHT", "QUOTE", "SHIFT_RIGHT",
    "CTRL_RIGHT", "ALT_RIGHT", "NUM_ENTER"];

  const codeNames = {
    Space: "SPACE", Enter: "ENTER", NumpadEnter: "NUM_ENTER", Escape: "ESCAPE", Tab: "TAB",
    Backspace: "BACKSPACE", Delete: "DELETE", Insert: "INSERT", Home: "HOME", End: "END",
    PageUp: "PAGE_UP", PageDown: "PAGE_DOWN", ArrowLeft: "ARROW_LEFT", ArrowRight: "ARROW_RIGHT",
    ArrowUp: "ARROW_UP", ArrowDown: "ARROW_DOWN", ShiftLeft: "SHIFT_LEFT", ShiftRight: "SHIFT_RIGHT",
    ControlLeft: "CTRL_LEFT", ControlRight: "CTRL_RIGHT", AltLeft: "ALT_LEFT", AltRight: "ALT_RIGHT",
    CapsLock: "CAPS_LOCK", Backquote: "BACK_QUOTE", Minus: "DASH", Equal: "EQUAL",
    BracketLeft: "BRACKET_LEFT", BracketRight: "BRACKET_RIGHT", Backslash: "BACKSLASH",
    Semicolon: "SEMICOLON", Quote: "QUOTE", Comma: "COMMA", Period: "PERIOD", Slash: "SLASH",
    NumpadAdd: "NUM_PLUS", NumpadSubtract: "NUM_SUBTRACT", NumpadMultiply: "NUM_MULTIPLY",
    NumpadDivide: "NUM_DIVIDE", NumpadDecimal: "NUM_DECIMAL", Pause: "PAUSE",
    ScrollLock: "SCROLL_LOCK", NumLock: "NUM_LOCK"
  };

  const groupNames = {
    Game: ["游戏", "Game"], Plant: ["植物技能", "Plant abilities"], AirRaid: ["空袭", "Air Raid"],
    ZenGarden: ["禅境花园", "Zen Garden"], Sandbox: ["沙盒", "Sandbox"], Rhythm: ["节奏", "Rhythm"]
  };

  const gameActionNames = {
    Pause: "暂停", SpeedUp: "加速", Plantfood: "能量豆", Shovel: "铲子", CollectAll: "全部收集",
    UIUpper: "切换上层界面", ConveyorForward: "传送带前进", ConveyorBackward: "传送带后退",
    HideUI: "隐藏界面"
  };

  // Key names of the running engine's KeyCode enum, the table KeyBinds uses.
  function engineKeyCodes() {
    try {
      const system = window.System;
      const cc = system && typeof system.get === "function" ? system.get(system.resolve("cc")) : null;
      const codes = cc && cc.KeyCode;
      if (codes && typeof codes === "object") return codes;
    } catch (_) { /* Fall back to the Cocos 3.8 key list. */ }
    return null;
  }

  function keyNames(codes) {
    if (!codes) return fallbackKeyNames.slice();
    return Object.keys(codes).filter(function (name) {
      return typeof codes[name] === "number" && name !== "NONE" && !/^\d+$/.test(name);
    });
  }

  function keyNameForEvent(event, names, codes) {
    const code = String(event.code || "");
    let match;
    let name = null;
    if ((match = /^Key([A-Z])$/.exec(code))) name = "KEY_" + match[1];
    else if ((match = /^Digit(\d)$/.exec(code))) name = "DIGIT_" + match[1];
    else if ((match = /^Numpad(\d)$/.exec(code))) name = "NUM_" + match[1];
    else if ((match = /^F(\d{1,2})$/.exec(code))) name = "F" + match[1];
    else name = codeNames[code] || null;
    if (name && names.indexOf(name) >= 0) return name;
    if (codes && Number.isFinite(event.keyCode)) {
      for (const candidate of names) if (codes[candidate] === event.keyCode) return candidate;
    }
    return null;
  }

  function actionLabel(action, zh) {
    const separator = action.indexOf("_");
    const group = separator > 0 ? action.slice(0, separator) : "";
    const rest = separator > 0 ? action.slice(separator + 1) : action;
    if (zh && group === "Game") {
      let match;
      if (gameActionNames[rest]) return gameActionNames[rest];
      if ((match = /^Card(\d+)$/.exec(rest))) return "卡片 " + match[1];
      if ((match = /^Conveyor_Card(\d+)$/.exec(rest))) return "传送带卡片 " + match[1];
    }
    return rest.replace(/_/g, " ");
  }

  let keybindOpen = null;

  function openKeybindWindow(binds, language) {
    if (keybindOpen) return keybindOpen;
    const zh = language === "zh";
    const source = binds && typeof binds === "object" ? binds : {};
    const actions = Object.keys(source).filter(function (key) {
      return !key.startsWith("__") && typeof source[key] === "string";
    });
    const codes = engineKeyCodes();
    const names = keyNames(codes);
    const parts = createDialog(zh ? "按键绑定" : "Key bindings", zh ? "取消" : "Cancel");
    const dialog = parts.dialog;
    const selects = new Map();
    let capturing = null;
    let saved = null;

    const hint = element("div", "gd-muted", zh
      ? "从下拉框选择按键，或点“录入”后按下实体键盘上的键。"
      : "Pick a key from the list, or tap Record and press a key on a physical keyboard.");
    parts.body.appendChild(hint);

    let lastGroup = null;
    for (const action of actions) {
      const separator = action.indexOf("_");
      const group = separator > 0 ? action.slice(0, separator) : "";
      if (group !== lastGroup) {
        lastGroup = group;
        const labels = groupNames[group];
        parts.body.appendChild(element("div", "gd-group", labels ? labels[zh ? 0 : 1] : group || "-"));
      }
      const row = element("div", "gd-row");
      const label = element("span", null, actionLabel(action, zh));
      label.title = action;
      const controls = element("span", "gd-actions");
      const select = element("select");
      select.setAttribute("aria-label", action);
      const fallback = element("option", null, zh ? "（默认）" : "(default)");
      fallback.value = "";
      select.appendChild(fallback);
      for (const name of names) {
        const option = element("option", null, name);
        option.value = name;
        select.appendChild(option);
      }
      select.value = names.indexOf(source[action]) >= 0 ? source[action] : "";
      const record = button(zh ? "录入" : "Record", function () {
        if (capturing) capturing.button.textContent = zh ? "录入" : "Record";
        capturing = {select: select, button: record};
        record.textContent = zh ? "请按键…" : "Press a key…";
        record.focus();
      });
      controls.append(select, record);
      row.append(label, controls);
      parts.body.appendChild(row);
      selects.set(action, select);
    }

    dialog.addEventListener("keydown", function (event) {
      if (!capturing) return;
      event.preventDefault();
      const target = capturing;
      capturing = null;
      target.button.textContent = zh ? "录入" : "Record";
      // Space or Enter would otherwise press the focused button again on keyup.
      target.button.blur();
      if (event.key === "Escape") return;
      const name = keyNameForEvent(event, names, codes);
      if (name) target.select.value = name;
    }, true);
    // Escape cancels a pending capture instead of closing the window.
    dialog.addEventListener("cancel", function (event) {
      if (capturing) event.preventDefault();
    });

    const footer = element("div", "gd-footer");
    footer.append(
      button(zh ? "全部恢复默认" : "Reset all", function () {
        for (const select of selects.values()) select.value = "";
      }),
      button(zh ? "保存" : "Save", function () {
        const result = Object.assign({}, source);
        // An empty value makes the game fall back to that action's default key.
        for (const [action, select] of selects) result[action] = select.value;
        saved = result;
        dialog.close();
      }, "gd-primary"));
    dialog.appendChild(footer);

    keybindOpen = new Promise(function (resolve) {
      dialog.addEventListener("close", function () {
        keybindOpen = null;
        resolve(saved);
      }, {once: true});
    });
    show(dialog);
    return keybindOpen;
  }

  defineShims({
    // Resource updates are imported through the loader, not checked in game.
    checkRemoteUpdate: function () { return Promise.resolve(null); },
    closeUpdateWindow: function () {},
    isMarkdownWindowOpen: function () { return markdownDialog() !== null; },
    closeMarkdownWindow: function () {
      const dialog = markdownDialog();
      if (dialog) dialog.close();
    },
    openKeybindWindow: openKeybindWindow,
    onGithubPlayLevel: function (callback) { return subscribe(githubCallbacks.play, callback); },
    onGithubPlayLevelContent: function (callback) { return subscribe(githubCallbacks.content, callback); },
    onGithubChangedPaths: function (callback) { return subscribe(githubCallbacks.changed, callback); }
  });

  adopt(window.electronAPI);
  Object.defineProperty(window, "electronAPI", {
    configurable: true,
    enumerable: true,
    get: function () { return current; },
    set: adopt
  });

  Object.defineProperty(window, "__gardendlessDialogs", {value: Object.freeze({
    createDialog: createDialog,
    show: show,
    element: element,
    button: button,
    defineShims: defineShims,
    github: Object.freeze({
      hasPlayListener: function () { return githubCallbacks.play.size > 0; },
      hasContentListener: function () { return githubCallbacks.content.size > 0; },
      play: function (path) { return emit(githubCallbacks.play, path); },
      playContent: function (content) { return emit(githubCallbacks.content, content); },
      changed: function (paths) { return emit(githubCallbacks.changed, paths); }
    })
  })});
})();
