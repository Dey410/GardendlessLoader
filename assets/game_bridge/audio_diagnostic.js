(function () {
  "use strict";
  if (window.__gardendlessBrowserAudioObserverInstalled) return;
  window.__gardendlessBrowserAudioObserverInstalled = true;

  const config = window.__gardendlessHostConfig || {};
  const detailed = config.detailedAudioDiagnosticsEnabled === true;
  const counters = {
    decodeStarted: 0,
    decodeSucceeded: 0,
    decodeFailed: 0,
    mediaLoadStarted: 0,
    mediaReady: 0,
    mediaPlayRequested: 0,
    mediaPlaying: 0,
    mediaEnded: 0,
    mediaFailed: 0
  };

  function errorText(value) {
    if (value && typeof value.message === "string") return value.message;
    try { return String(value || "Unknown audio error"); } catch (_) {
      return "Unknown audio error";
    }
  }

  function relativePath(value) {
    if (typeof value !== "string" || !value) return "";
    if (value.indexOf("blob:") === 0 || value.indexOf("data:") === 0) {
      return "[inline-audio]";
    }
    try {
      const url = new URL(value, window.location.href);
      const path = String(url.pathname || "").replace(/^\/+/, "");
      return path || "[document]";
    } catch (_) {
      return value.split(/[?#]/, 1)[0].replace(/^\/+/, "").slice(0, 1024);
    }
  }

  function emit(event, level, outcome, message, context, detailedOnly) {
    if (detailedOnly && !detailed) return;
    const host = window.__gardendlessHost;
    if (!host || typeof host.invoke !== "function") return;
    host.invoke("host:log", {
      args: {
        event: event,
        level: level,
        outcome: outcome,
        message: String(message || "").slice(0, 1024),
        context: context || {}
      }
    }).catch(function () {});
  }

  function emitSummary() {
    emit(
      "audio_summary",
      "INFO",
      "observed",
      detailed ? "Detailed audio diagnostics summary" : "Audio diagnostics summary",
      Object.assign({ detailed: detailed }, counters),
      false
    );
  }

  function installDecodeObserver() {
    const Context = window.AudioContext || window.webkitAudioContext;
    const prototype = Context && Context.prototype;
    if (!prototype || typeof prototype.decodeAudioData !== "function") return;

    const original = prototype.decodeAudioData;
    prototype.decodeAudioData = function () {
      const receiver = this;
      const args = Array.prototype.slice.call(arguments);
      let settled = false;
      counters.decodeStarted += 1;
      emit(
        "audio_decode_started",
        "INFO",
        "started",
        "WebAudio decode started",
        { byteLength: args[0] && Number(args[0].byteLength || 0) },
        true
      );

      function finish(ok, reason) {
        if (settled) return;
        settled = true;
        if (ok) {
          counters.decodeSucceeded += 1;
          emit(
            "audio_decode_succeeded",
            "INFO",
            "succeeded",
            "WebAudio decode succeeded",
            {},
            true
          );
        } else {
          counters.decodeFailed += 1;
          emit(
            "audio_decode_failed",
            "ERROR",
            "failed",
            errorText(reason),
            {},
            false
          );
        }
      }

      if (typeof args[1] === "function") {
        const success = args[1];
        args[1] = function () {
          finish(true);
          return success.apply(this, arguments);
        };
      }
      if (typeof args[2] === "function") {
        const failure = args[2];
        args[2] = function () {
          finish(false, arguments[0]);
          return failure.apply(this, arguments);
        };
      }

      let result;
      try {
        result = original.apply(receiver, args);
      } catch (error) {
        finish(false, error);
        throw error;
      }
      if (result && typeof result.then === "function") {
        result.then(
          function () { finish(true); },
          function (reason) { finish(false, reason); }
        );
      }
      return result;
    };
  }

  function mediaContext(element) {
    return {
      relativePath: relativePath(
        element && (element.currentSrc || element.src || "")
      )
    };
  }

  function installMediaObserver() {
    const Media = window.HTMLMediaElement;
    const prototype = Media && Media.prototype;
    if (!prototype) return;

    const eventMap = {
      loadstart: ["mediaLoadStarted", "audio_media_load_started", "started"],
      loadeddata: ["mediaReady", "audio_media_ready", "succeeded"],
      canplay: ["mediaReady", "audio_media_ready", "succeeded"],
      playing: ["mediaPlaying", "audio_media_playing", "observed"],
      ended: ["mediaEnded", "audio_media_ended", "observed"]
    };
    Object.keys(eventMap).forEach(function (name) {
      window.addEventListener(name, function (event) {
        const element = event && event.target;
        if (!(element instanceof Media)) return;
        const definition = eventMap[name];
        counters[definition[0]] += 1;
        emit(
          definition[1],
          "INFO",
          definition[2],
          "HTML media event: " + name,
          mediaContext(element),
          true
        );
      }, true);
    });
    window.addEventListener("error", function (event) {
      const element = event && event.target;
      if (!(element instanceof Media)) return;
      counters.mediaFailed += 1;
      emit(
        "audio_media_failed",
        "ERROR",
        "failed",
        "HTML media failed to load or play",
        mediaContext(element),
        false
      );
    }, true);

    if (typeof prototype.play === "function") {
      const originalPlay = prototype.play;
      prototype.play = function () {
        const element = this;
        counters.mediaPlayRequested += 1;
        emit(
          "audio_media_play_requested",
          "INFO",
          "started",
          "HTML media play requested",
          mediaContext(element),
          true
        );
        let result;
        try {
          result = originalPlay.apply(element, arguments);
        } catch (error) {
          counters.mediaFailed += 1;
          emit(
            "audio_media_failed",
            "ERROR",
            "failed",
            errorText(error),
            mediaContext(element),
            false
          );
          throw error;
        }
        if (result && typeof result.then === "function") {
          result.then(
            function () {},
            function (reason) {
              counters.mediaFailed += 1;
              emit(
                "audio_media_failed",
                "ERROR",
                "failed",
                errorText(reason),
                mediaContext(element),
                false
              );
            }
          );
        }
        return result;
      };
    }
  }

  installDecodeObserver();
  installMediaObserver();
  window.setInterval(emitSummary, 30000);
  window.addEventListener("pagehide", emitSummary, { once: true });
})();
