(function () {
  "use strict";

  const config = window.__gardendlessHostConfig || {};
  const enabled = config.audioDiagnosticsEnabled === true;
  const maxEvents = 6000;
  const maxFrames = 6000;
  const longFrameThresholdMs = 100;

  const counters = {
    domPlay: 0,
    domPause: 0,
    lazySrcSet: 0,
    facadeCreated: 0,
    playPosted: 0,
    pausePosted: 0,
    stopPosted: 0,
    seekPosted: 0,
    setVolumePosted: 0,
    setLoopPosted: 0,
    setRatePosted: 0,
    releasePosted: 0,
    endedReceived: 0,
    silentReceived: 0,
    stoppedReceived: 0,
    silentThrottled: 0,
    silentThrottleArmed: 0,
    webkitFallback: 0,
    nativePlayPosted: 0,
    nativePostFailed: 0,
    nativeEnded: 0,
    nativeSilent: 0,
    nativeStop: 0,
    nativeStopAll: 0,
    webAudioDecodeStart: 0,
    webAudioDecodeEnd: 0,
    webAudioStart: 0,
  };

  let pendingNative = 0;
  const events = [];
  const frameTimes = [];
  let lastAutoSaveAt = 0;

  const audioHandler =
    window.webkit && window.webkit.messageHandlers
      ? window.webkit.messageHandlers.gardendlessAudio
      : null;

  function now() {
    return window.performance && window.performance.now
      ? window.performance.now()
      : Date.now();
  }

  function pushEvent(type, details) {
    if (events.length >= maxEvents) {
      events.shift();
    }
    const event = { t: Math.round(now()), type: type };
    if (details) {
      for (const key of Object.keys(details)) {
        if (details[key] !== undefined) {
          event[key] = details[key];
        }
      }
    }
    events.push(event);
  }

  function record(type, details) {
    if (!enabled) return;
    if (counters[type] !== undefined) {
      counters[type] += 1;
    }
    pushEvent(type, details);
  }

  function beginNativePlay() {
    pendingNative += 1;
    return pendingNative;
  }

  function endNativePlay() {
    pendingNative = Math.max(0, pendingNative - 1);
    return pendingNative;
  }

  function resetPendingNative() {
    pendingNative = 0;
  }

  function computeFps() {
    if (frameTimes.length < 2) {
      return { frameCount: frameTimes.length, gaps: [] };
    }
    const durations = [];
    const gaps = [];
    for (let i = 1; i < frameTimes.length; i += 1) {
      const duration = frameTimes[i] - frameTimes[i - 1];
      durations.push(duration);
      if (duration > longFrameThresholdMs) {
        gaps.push({
          t: Math.round(frameTimes[i - 1]),
          durationMs: Math.round(duration),
        });
      }
    }
    durations.sort((a, b) => a - b);
    const total = durations.reduce((sum, value) => sum + value, 0);
    const p95Index = Math.min(
      durations.length - 1,
      Math.floor(durations.length * 0.95),
    );
    return {
      frameCount: frameTimes.length,
      avgFrameMs: Math.round((total / durations.length) * 10) / 10,
      p95FrameMs: Math.round(durations[p95Index]),
      maxFrameMs: Math.round(durations[durations.length - 1]),
      gaps: gaps,
    };
  }

  function exportJson() {
    const data = {
      schemaVersion: 2,
      enabled: enabled,
      collectedAt: new Date().toISOString(),
      build: {
        userAgent: navigator.userAgent,
        platform: navigator.platform,
        hardwareConcurrency: navigator.hardwareConcurrency || null,
      },
      patch: {
        lazySrcSetCount: counters.lazySrcSet,
        facadeInstalled: !!window.__gardendlessNativeAudioFacadeInstalled,
        audioFacadeLoaded: window.__pvzgeAudioFacadeLoaded || 0,
        facadeCreatedCount: counters.facadeCreated,
        nativeAudioInstalled: !!window.__gardendlessNativeAudioInstalled,
        audioPatchMarker: window.__pvzgeAudioPatchLoaded || 0,
      },
      fps: computeFps(),
      audio: {
        counters: Object.assign({}, counters, { pendingNative: pendingNative }),
        events: events.slice(),
      },
    };
    return JSON.stringify(data);
  }

  function exportJsonString() {
    return exportJson();
  }

  function saveToNative() {
    if (!enabled || !audioHandler) return false;
    try {
      audioHandler.postMessage({
        command: "writeDiagnostics",
        json: exportJsonString(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  function frameLoop(timestamp) {
    if (frameTimes.length >= maxFrames) {
      frameTimes.shift();
    }
    frameTimes.push(timestamp);
    const current = now();
    if (current - lastAutoSaveAt >= 10000) {
      lastAutoSaveAt = current;
      saveToNative();
    }
    window.requestAnimationFrame(frameLoop);
  }

  function wrapDecode(original) {
    return function (buffer, success, error) {
      const self = this;
      let settled = false;
      function mark(ok) {
        if (settled) return;
        settled = true;
        counters.webAudioDecodeEnd += 1;
        pushEvent("webAudioDecodeEnd", { ok: ok });
      }
      counters.webAudioDecodeStart += 1;
      pushEvent("webAudioDecodeStart", {});
      let result;
      try {
        result = original.call(
          self,
          buffer,
          function (decoded) {
            mark(true);
            if (typeof success === "function") {
              success(decoded);
            }
          },
          function (reason) {
            mark(false);
            if (typeof error === "function") {
              error(reason);
            }
          },
        );
      } catch (errorValue) {
        mark(false);
        throw errorValue;
      }
      if (result && typeof result.then === "function") {
        return result.then(
          function (decoded) {
            mark(true);
            return decoded;
          },
          function (reason) {
            mark(false);
            throw reason;
          },
        );
      }
      return result;
    };
  }

  function installWebAudioProbe() {
    const Context = window.AudioContext || window.webkitAudioContext;
    if (Context && Context.prototype && Context.prototype.decodeAudioData) {
      Context.prototype.decodeAudioData = wrapDecode(
        Context.prototype.decodeAudioData,
      );
    }
    if (
      window.AudioBufferSourceNode &&
      window.AudioBufferSourceNode.prototype
    ) {
      const originalStart = window.AudioBufferSourceNode.prototype.start;
      if (typeof originalStart === "function") {
        window.AudioBufferSourceNode.prototype.start = function () {
          const buffer = this && this.buffer;
          const duration =
            buffer && typeof buffer.duration === "number"
              ? Math.round(buffer.duration * 1000)
              : null;
          counters.webAudioStart += 1;
          pushEvent("webAudioStart", { durationMs: duration });
          return originalStart.apply(this, arguments);
        };
      }
    }
  }

  function installDomProbe() {
    const proto =
      window.HTMLMediaElement && window.HTMLMediaElement.prototype;
    if (!proto) return;
    const originalPlay = proto.play;
    if (typeof originalPlay === "function") {
      proto.play = function () {
        const element = this;
        counters.domPlay += 1;
        pushEvent("domPlay", {
          url:
            element.__pvzgeLazySrc ||
            element.currentSrc ||
            element.src ||
            "",
          loop: !!element.loop,
          rate: element.playbackRate || 1,
        });
        return originalPlay.apply(element, arguments);
      };
    }
    const originalPause = proto.pause;
    if (typeof originalPause === "function") {
      proto.pause = function () {
        counters.domPause += 1;
        pushEvent("domPause", {});
        return originalPause.apply(this, arguments);
      };
    }
  }

  const api = {
    enabled: enabled,
    record: record,
    beginNativePlay: beginNativePlay,
    endNativePlay: endNativePlay,
    resetPendingNative: resetPendingNative,
    export: function () {
      saveToNative();
      return exportJsonString();
    },
    dump: function () {
      return exportJsonString();
    },
  };

  window.__gardendlessAudioDiagnostics = api;

  if (enabled) {
    installDomProbe();
    installWebAudioProbe();
    window.requestAnimationFrame(frameLoop);
    window.addEventListener(
      "pagehide",
      function () {
        saveToNative();
        try {
          console.info("GDL_AUDIO_DIAG", exportJsonString());
        } catch (_) {
          // Diagnostics must never break page teardown.
        }
      },
      { once: true },
    );
  }
})();
