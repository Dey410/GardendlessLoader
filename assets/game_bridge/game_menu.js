(function () {
  "use strict";
  let root = null;
  let autoTimer = null;

  function pressCollectKey() {
    const target = document.getElementById("GameCanvas") ||
      document.activeElement || document;
    const init = {
      key: "a", code: "KeyA", keyCode: 65, which: 65,
      bubbles: true, cancelable: true, composed: true
    };
    target.dispatchEvent(new KeyboardEvent("keydown", init));
    setTimeout(function () {
      target.dispatchEvent(new KeyboardEvent("keyup", init));
    }, 30);
  }

  function setAutoSun(enabled) {
    if (autoTimer !== null) clearInterval(autoTimer);
    autoTimer = enabled ? setInterval(pressCollectKey, 1500) : null;
  }

  function close() {
    if (root) root.remove();
    root = null;
  }

  function row(label, control) {
    const wrapper = document.createElement("label");
    wrapper.style.cssText = "display:flex;align-items:center;gap:16px;justify-content:space-between;padding:12px 0";
    const text = document.createElement("span");
    text.textContent = label;
    wrapper.append(text, control);
    return wrapper;
  }

  function toggle(value, onChange) {
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = value;
    input.addEventListener("change", function () { onChange(input.checked); });
    return input;
  }

  function open() {
    if (root) return;
    const config = window.__gardendlessHost.config;
    root = document.createElement("div");
    root.id = "gardendless-game-menu";
    root.style.cssText = "position:fixed;inset:0;z-index:2147483647;display:grid;place-items:center;background:rgba(0,0,0,.56);font:15px -apple-system,BlinkMacSystemFont,sans-serif;color:white";
    const panel = document.createElement("section");
    panel.style.cssText = "width:min(360px,calc(100vw - 32px));padding:22px;border-radius:18px;background:#202124;box-shadow:0 18px 60px rgba(0,0,0,.5)";
    const title = document.createElement("h2");
    title.textContent = "游戏菜单";
    title.style.margin = "0 0 10px";
    let watermark = config.watermarkEnabled !== false;
    panel.appendChild(title);
    panel.appendChild(row("显示水印", toggle(watermark, function (enabled) {
      watermark = enabled;
      window.__gardendlessHost.emit("watermark", enabled);
      window.__gardendlessHost.invoke("host:setWatermark", { enabled: enabled });
    })));
    if (!config.hasGpNext) {
      panel.appendChild(row("自动收集阳光", toggle(false, setAutoSun)));
    }
    const actions = document.createElement("div");
    actions.style.cssText = "display:flex;gap:10px;justify-content:flex-end;margin-top:16px";
    const continueButton = document.createElement("button");
    continueButton.textContent = "继续游戏";
    continueButton.onclick = close;
    const exitButton = document.createElement("button");
    exitButton.textContent = "返回首页";
    exitButton.onclick = function () {
      window.__gardendlessHost.invoke("host:returnHome", {}).catch(function () {});
    };
    for (const button of [continueButton, exitButton]) {
      button.style.cssText = "padding:9px 14px;border:0;border-radius:10px;font:inherit";
      actions.appendChild(button);
    }
    panel.appendChild(actions);
    root.appendChild(panel);
    root.addEventListener("click", function (event) {
      if (event.target === root) close();
    });
    (document.body || document.documentElement).appendChild(root);
  }

  window.__gardendlessMenu = Object.freeze({ open: open, close: close });
  window.addEventListener("gardendless:openMenu", open);
})();
