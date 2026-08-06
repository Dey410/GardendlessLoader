(function () {
  "use strict";

  const config = window.__gardendlessHostConfig || {};
  const handler = window.webkit && window.webkit.messageHandlers
    ? window.webkit.messageHandlers.gardendlessAudio
    : null;
  if (!config.nativeSfxEnabled || !handler ||
      (window.__gardendlessNativeAudioInstalled &&
       window.__pvzgeAudioFacadeLoaded)) {
    return;
  }

  const sources = new WeakMap();
  const ids = new WeakMap();
  const elements = new Map();
  const nativeStates = new WeakMap();
  const originalPlay = HTMLMediaElement.prototype.play;
  const originalPause = HTMLMediaElement.prototype.pause;
  let nextId = 1;
  const diagnostics = window.__gardendlessAudioDiagnostics;

  function elementId(element) {
    let id = ids.get(element);
    if (!id) {
      id = String(nextId++);
      ids.set(element, id);
      elements.set(id, element);
    }
    return id;
  }

  function absoluteURL(value) {
    try {
      const url = new URL(String(value || ""), window.location.href);
      return url.protocol === "gardendless-game:" && url.hostname === "localhost"
        ? url.href
        : "";
    } catch (_) {
      return "";
    }
  }

  function post(message) {
    try {
      handler.postMessage(message);
      return true;
    } catch (_) {
      return false;
    }
  }

  function isNativeCandidate(element, url) {
    if (!url || element.loop || element.playbackRate !== 1) return false;
    let path = "";
    try { path = new URL(url).pathname.toLowerCase(); } catch (_) { return false; }
    const extension = path.slice(path.lastIndexOf(".") + 1);
    if (extension !== "mp3" && extension !== "m4a") return false;
    const tokens = path.split(/[^a-z0-9]+/);
    return !tokens.includes("bgm") && !tokens.includes("music");
  }

  Object.defineProperty(HTMLMediaElement.prototype, "__pvzgeLazySrc", {
    configurable: true,
    get: function () { return sources.get(this) || ""; },
    set: function (value) {
      const url = absoluteURL(value);
      sources.set(this, url);
      if (url) {
        if (diagnostics) {
          diagnostics.record("lazySrcSet", { url: url });
        }
      }
    }
  });

  HTMLMediaElement.prototype.play = function () {
    const url = sources.get(this);
    if (!isNativeCandidate(this, url)) {
      if (diagnostics) {
        diagnostics.record("webkitFallback", {
          url: url || this.currentSrc || this.src || "",
        });
      }
      return originalPlay.call(this);
    }
    const id = elementId(this);
    if (!post({
      command: "play",
      elementId: id,
      url: url,
      volume: this.muted ? 0 : this.volume,
      playbackRate: this.playbackRate,
      loop: this.loop
    })) {
      if (diagnostics) {
        diagnostics.record("nativePostFailed", { elementId: id, url: url });
      }
      return originalPlay.call(this);
    }
    if (diagnostics) {
      const pending = diagnostics.beginNativePlay();
      diagnostics.record("nativePlayPosted", {
        elementId: id,
        url: url,
        pendingNative: pending
      });
    }
    nativeStates.set(this, { playing: true });
    return Promise.resolve();
  };

  HTMLMediaElement.prototype.pause = function () {
    const state = nativeStates.get(this);
    if (!state || !state.playing) return originalPause.call(this);
    if (diagnostics) {
      diagnostics.endNativePlay();
      diagnostics.record("nativeStop", { elementId: elementId(this) });
    }
    post({ command: "stop", elementId: elementId(this) });
    state.playing = false;
  };

  window.__gardendlessNativeAudioEnded = function (id) {
    const element = elements.get(String(id));
    if (!element) return;
    const state = nativeStates.get(element);
    if (state) state.playing = false;
    if (diagnostics) {
      diagnostics.endNativePlay();
      diagnostics.record("nativeEnded", { elementId: String(id) });
    }
    element.dispatchEvent(new Event("ended"));
  };

  window.__gardendlessNativeAudioSilent = function (id) {
    const element = elements.get(String(id));
    if (!element) return;
    const state = nativeStates.get(element);
    if (state) state.playing = false;
    if (diagnostics) {
      diagnostics.endNativePlay();
      diagnostics.record("nativeSilent", { elementId: String(id) });
    }
    element.dispatchEvent(new Event("ended"));
  };

  window.__gardendlessNativeAudioSetMasterVolume = function (volume) {
    const normalized = Math.max(0, Math.min(1, Number(volume)));
    if (Number.isFinite(normalized)) {
      post({ command: "setMasterVolume", volume: normalized });
    }
  };

  window.addEventListener("pagehide", function () {
    if (diagnostics) {
      diagnostics.resetPendingNative();
      diagnostics.record("nativeStopAll", {});
    }
    post({ command: "stopAll" });
  }, { once: true });

  window.__gardendlessNativeAudioInstalled = true;
})();
