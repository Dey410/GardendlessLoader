(function () {
  "use strict";

  const config = window.__gardendlessHostConfig || {};
  const handler = window.webkit && window.webkit.messageHandlers
    ? window.webkit.messageHandlers.gardendlessAudio
    : null;
  if (!config.nativeSfxEnabled || !handler ||
      window.__gardendlessNativeAudioFacadeInstalled) {
    return;
  }

  const diagnostics = window.__gardendlessAudioDiagnostics;
  const SILENT_WINDOW_MS = 10000;
  const SILENT_TRIGGER = 3;
  const SILENT_SUPPRESS_MS = 30000;
  const MAX_HANDLES = 2048;
  const MAX_SILENT_URLS = 1024;
  const handles = new Map();
  const silentHistory = new Map();
  const dirtyHandles = new Map();
  const pendingReleases = [];
  let nextId = 1;
  let dirtyFlushScheduled = false;
  let releaseFlushScheduled = false;

  function now() {
    return window.performance && window.performance.now
      ? window.performance.now()
      : Date.now();
  }

  function record(type, details) {
    if (diagnostics) {
      diagnostics.record(type, details);
    }
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
      record("nativePostFailed", { requestId: message.requestId });
      return false;
    }
  }

  function markSilent(url) {
    if (!url) return;
    const timestamp = now();
    let entry = silentHistory.get(url);
    if (!entry) {
      entry = { times: [], suppressedUntil: 0 };
      silentHistory.set(url, entry);
      trimSilentHistory();
    }
    if (timestamp < entry.suppressedUntil) return;
    entry.times.push(timestamp);
    while (entry.times.length > 0 &&
           timestamp - entry.times[0] > SILENT_WINDOW_MS) {
      entry.times.shift();
    }
    if (entry.times.length >= SILENT_TRIGGER) {
      entry.suppressedUntil = timestamp + SILENT_SUPPRESS_MS;
      entry.times = [];
      record("silentThrottleArmed", { url: url });
    }
  }

  function isSuppressed(url) {
    if (!url) return false;
    const entry = silentHistory.get(url);
    return !!entry && now() < entry.suppressedUntil;
  }

  function scheduleDirtyFlush() {
    if (dirtyFlushScheduled) return;
    dirtyFlushScheduled = true;
    window.setTimeout(function () {
      dirtyFlushScheduled = false;
      flushDirty();
    }, 0);
  }

  function flushDirty() {
    for (const [id, handle] of dirtyHandles) {
      if (handle._dirtyVolume) {
        post({ command: "setVolume", requestId: id, volume: handle._volume });
        handle._dirtyVolume = false;
        record("setVolumePosted", { requestId: id, volume: handle._volume });
      }
      if (handle._dirtyRate) {
        post({ command: "setRate", requestId: id, rate: handle._playbackRate });
        handle._dirtyRate = false;
        record("setRatePosted", {
          requestId: id,
          rate: handle._playbackRate,
        });
      }
      if (handle._dirtyLoop) {
        post({ command: "setLoop", requestId: id, loop: handle._loop });
        handle._dirtyLoop = false;
        record("setLoopPosted", { requestId: id, loop: handle._loop });
      }
    }
    dirtyHandles.clear();
  }

  function markDirty(handle, property) {
    handle["_dirty" + property] = true;
    if (!dirtyHandles.has(handle.id)) {
      dirtyHandles.set(handle.id, handle);
      scheduleDirtyFlush();
    }
  }

  function scheduleReleaseFlush() {
    if (releaseFlushScheduled) return;
    releaseFlushScheduled = true;
    window.setTimeout(function () {
      releaseFlushScheduled = false;
      flushReleases();
    }, 0);
  }

  function flushReleases() {
    if (pendingReleases.length === 0) return;
    const ids = pendingReleases.splice(0);
    post({ command: "releaseMany", requestIds: ids });
    record("releasePosted", { count: ids.length });
  }

  function trimHandles() {
    if (handles.size <= MAX_HANDLES) return;
    for (const [id, handle] of handles) {
      if (handles.size <= MAX_HANDLES) break;
      if (handle._state !== "playing" && handle._state !== "paused") {
        handles.delete(id);
      }
    }
  }

  function trimSilentHistory() {
    if (silentHistory.size <= MAX_SILENT_URLS) return;
    const keys = silentHistory.keys();
    while (silentHistory.size > MAX_SILENT_URLS) {
      const url = keys.next().value;
      if (url === undefined) break;
      silentHistory.delete(url);
    }
  }

  function createNativeAudioHandle(urlValue, options) {
    window.__pvzgeAudioFacadeLoaded = 1;
    const url = absoluteURL(urlValue);
    const id = String(nextId++);
    const optionsObject = options && typeof options === "object" ? options : {};
    const role = optionsObject.role === "oneShot" ? "oneShot" : "continuous";
    const kind = optionsObject.kind === "music" ||
      optionsObject.kind === "ambience" ? optionsObject.kind : undefined;
    const handle = {
      id: id,
      url: url,
      role: role,
      kind: kind,
      _volume: 1,
      _loop: false,
      _playbackRate: 1,
      preservesPitch: false,
      _state: "init",
      _startedAt: 0,
      _startOffset: 0,
      _pausedPosition: 0,
      _duration: 0,
      __pvzgeLazySrc: url,
      _listeners: [],
      get src() {
        return this.url;
      },
      set src(value) {
        this.url = absoluteURL(value) || this.url;
        this.__pvzgeLazySrc = this.url;
      },
      get volume() {
        return this._volume;
      },
      set volume(value) {
        const normalized = Math.max(0, Math.min(1, Number(value) || 0));
        if (this._volume === normalized) return;
        this._volume = normalized;
        markDirty(this, "Volume");
      },
      get loop() {
        return this._loop;
      },
      set loop(value) {
        const normalized = !!value;
        if (this._loop === normalized) return;
        this._loop = normalized;
        markDirty(this, "Loop");
      },
      get playbackRate() {
        return this._playbackRate;
      },
      set playbackRate(value) {
        const normalized = Number(value) > 0 ? Number(value) : 1;
        if (this._playbackRate === normalized) return;
        this._playbackRate = normalized;
        markDirty(this, "Rate");
      },
      get duration() {
        return this._duration;
      },
      get currentTime() {
        if (this._state === "playing") {
          const elapsed =
            ((now() - this._startedAt) / 1000) * this._playbackRate +
            this._startOffset;
          if (this._loop && this._duration > 0) {
            return elapsed % this._duration;
          }
          return elapsed;
        }
        if (this._state === "paused") {
          return this._pausedPosition;
        }
        return 0;
      },
      set currentTime(value) {
        this.seek(value);
      },
      play: function () {
        if (isSuppressed(this.url)) {
          record("silentThrottled", { requestId: id, url: this.url });
          const self = this;
          window.setTimeout(function () {
            self._dispatchEnded();
          }, 0);
          return Promise.resolve();
        }
        const wasPaused = this._state === "paused";
        post({
          command: "play",
          requestId: id,
          url: this.url,
          role: this.role,
          kind: this.kind,
          volume: this._volume,
          loop: this._loop,
          rate: this._playbackRate,
          startTime: wasPaused ? this._pausedPosition : this._startOffset,
        });
        this._startOffset = wasPaused ? this._pausedPosition : this._startOffset;
        this._startedAt = now();
        this._state = "playing";
        this._dirtyVolume = false;
        this._dirtyRate = false;
        this._dirtyLoop = false;
        dirtyHandles.delete(id);
        record("playPosted", {
          requestId: id,
          url: this.url,
          role: this.role,
          rate: this._playbackRate,
          loop: this._loop,
        });
        return Promise.resolve();
      },
      pause: function () {
        if (this._state !== "playing") return;
        this._pausedPosition = this.currentTime;
        this._state = "paused";
        post({ command: "pause", requestId: id });
        record("pausePosted", { requestId: id });
      },
      stop: function () {
        this._state = "stopped";
        this._startOffset = 0;
        this._pausedPosition = 0;
        post({ command: "stop", requestId: id });
        record("stopPosted", { requestId: id });
      },
      seek: function (value) {
        const time = Math.max(0, Number(value) || 0);
        if (this._state === "playing") {
          this._startOffset = time;
          this._startedAt = now();
        } else if (this._state === "paused") {
          this._pausedPosition = time;
        } else {
          this._startOffset = time;
        }
        post({ command: "seek", requestId: id, time: time });
        record("seekPosted", { requestId: id, time: time });
      },
      release: function () {
        pendingReleases.push(id);
        handles.delete(id);
        dirtyHandles.delete(id);
        scheduleReleaseFlush();
      },
      addEventListener: function (type, callback) {
        if (type !== "ended" || typeof callback !== "function") return;
        if (this._listeners.indexOf(callback) === -1) {
          this._listeners.push(callback);
        }
      },
      removeEventListener: function (type, callback) {
        if (type !== "ended") return;
        const index = this._listeners.indexOf(callback);
        if (index !== -1) {
          this._listeners.splice(index, 1);
        }
      },
      _dispatchEnded: function () {
        this._state = "init";
        this._startOffset = 0;
        this._pausedPosition = 0;
        const callbacks = this._listeners.slice();
        for (let i = 0; i < callbacks.length; i += 1) {
          try {
            callbacks[i].call(this, new Event("ended"));
          } catch (_) {
            // A game listener must never break the facade event loop.
          }
        }
      }
    };
    handles.set(id, handle);
    trimHandles();
    record("facadeCreated", {
      requestId: id,
      url: url,
      role: role,
      kind: kind,
    });
    return handle;
  }

  function applyEvents(events) {
    if (!Array.isArray(events)) return;
    for (const event of events) {
      if (!event || typeof event.type !== "string") continue;
      const ids = Array.isArray(event.requestIds) ? event.requestIds : [];
      const reasons = Array.isArray(event.reasons) ? event.reasons : [];
      for (let i = 0; i < ids.length; i += 1) {
        const handle = handles.get(String(ids[i]));
        if (!handle) continue;
        const reason = String(reasons[i] || "unknown");
        switch (event.type) {
          case "ended":
            record("endedReceived", { requestId: handle.id, reason: reason });
            handle._dispatchEnded();
            break;
          case "silent":
            record("silentReceived", {
              requestId: handle.id,
              url: handle.url,
              reason: reason,
            });
            markSilent(handle.url);
            handle._dispatchEnded();
            break;
          case "stopped":
            record("stoppedReceived", {
              requestId: handle.id,
              reason: reason,
            });
            handle._dispatchEnded();
            break;
          default:
            break;
        }
      }
    }
  }

  window.addEventListener("pagehide", function () {
    record("nativeStopAll", {});
    post({ command: "stopAll" });
  }, { once: true });

  window.__gardendlessNativeAudio = Object.freeze({
    createNativeAudioHandle: createNativeAudioHandle
  });
  window.__gardendlessAudioEvents = applyEvents;
  window.__gardendlessNativeAudioFacadeInstalled = true;
})();
