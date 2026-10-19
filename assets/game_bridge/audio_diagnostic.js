(function () {
  "use strict";
  if (window.__gardendlessBrowserAudioObserverInstalled) return;
  window.__gardendlessBrowserAudioObserverInstalled = true;
  const detailed = (window.__gardendlessHostConfig || {}).detailedAudioDiagnosticsEnabled === true;
  const counters = {decodeStarted: 0, decodeSucceeded: 0, decodeFailed: 0, decodeInFlight: 0,
    decodedPcmBytesTotal: 0, mediaLoadStarted: 0, mediaReady: 0, mediaPlayRequested: 0,
    mediaPlaying: 0, mediaEnded: 0, mediaFailed: 0, eventsDropped: 0};
  const observed = new WeakSet();
  let budgetStarted = Date.now();
  let detailsSent = 0;
  let failuresSent = 0;

  function number(value) { return Number.isFinite(Number(value)) ? Number(value) : 0; }
  function errorText(value) {
    try { return String(value && value.message || value || "Unknown audio error"); }
    catch (_) { return "Unknown audio error"; }
  }
  function relativePath(value) {
    if (!value || typeof value !== "string") return "";
    if (value.startsWith("blob:") || value.startsWith("data:")) return "[inline-audio]";
    try { return new URL(value, window.location.href).pathname.replace(/^\/+/, ""); }
    catch (_) { return value.split(/[?#]/, 1)[0].replace(/^\/+/, "").slice(0, 1024); }
  }
  function emit(event, level, outcome, message, context, verbose) {
    if (verbose && !detailed) return;
    const now = Date.now();
    if (now - budgetStarted >= 60000) { budgetStarted = now; detailsSent = 0; failuresSent = 0; }
    if (event !== "audio_summary") {
      if ((verbose && detailsSent >= 120) || (!verbose && failuresSent >= 30)) { counters.eventsDropped++; return; }
      if (verbose) detailsSent++; else failuresSent++;
    }
    try {
      const host = window.__gardendlessHost;
      if (host && typeof host.invoke === "function") host.invoke("host:log", {args: {
        event: event, level: level, outcome: outcome, message: String(message || "").slice(0, 1024), context: context || {}
      }}).catch(function () {});
    } catch (_) { /* Observability must not change browser API behavior. */ }
  }
  function summary() {
    emit("audio_summary", "INFO", "observed", "Browser audio diagnostics summary",
      Object.assign({detailed: detailed}, counters), false);
  }
  function mediaContext(element) {
    return {relativePath: relativePath(element.currentSrc || element.src || ""),
      readyState: number(element.readyState), networkState: number(element.networkState),
      duration: number(element.duration), durationKnown: Number.isFinite(element.duration),
      errorCode: number(element.error && element.error.code)};
  }
  function observe(element) {
    const Media = window.HTMLMediaElement;
    if (!Media || !(element instanceof Media) || observed.has(element) || typeof element.addEventListener !== "function") return element;
    observed.add(element);
    const events = {
      loadstart: ["mediaLoadStarted", "audio_media_load_started", "started"],
      loadedmetadata: ["mediaReady", "audio_media_ready", "succeeded"],
      loadeddata: ["mediaReady", "audio_media_ready", "succeeded"],
      playing: ["mediaPlaying", "audio_media_playing", "observed"],
      ended: ["mediaEnded", "audio_media_ended", "observed"]
    };
    Object.keys(events).forEach(function (name) {
      element.addEventListener(name, function () {
        const event = events[name]; counters[event[0]]++;
        emit(event[1], "INFO", event[2], "HTML media event: " + name, mediaContext(element), true);
      });
    });
    element.addEventListener("error", function () {
      counters.mediaFailed++;
      emit("audio_media_failed", "ERROR", "failed", "HTML media failed to load or play", mediaContext(element), false);
    });
    return element;
  }

  const Context = window.AudioContext || window.webkitAudioContext;
  if (Context && typeof Context.prototype.decodeAudioData === "function") {
    const decode = Context.prototype.decodeAudioData;
    Context.prototype.decodeAudioData = function () {
      const receiver = this;
      if (!(receiver instanceof Context)) return decode.apply(receiver, arguments);
      const args = Array.prototype.slice.call(arguments);
      let settled = false;
      counters.decodeStarted++; counters.decodeInFlight++;
      let byteLength = 0;
      try { byteLength = number(args[0] && args[0].byteLength); } catch (_) {}
      emit("audio_decode_started", "INFO", "started", "WebAudio decode started",
        {byteLength: byteLength, contextState: String(receiver.state || "unknown")}, true);
      function finish(ok, value) {
        if (settled) return;
        settled = true; counters.decodeInFlight--;
        if (ok) {
          counters.decodeSucceeded++;
          const length = number(value && value.length);
          const channels = number(value && value.numberOfChannels);
          const pcmBytes = length * channels * 4;
          counters.decodedPcmBytesTotal += pcmBytes;
          emit("audio_decode_succeeded", "INFO", "succeeded", "WebAudio decode succeeded",
            {duration: number(value && value.duration), sampleRate: number(value && value.sampleRate),
              channels: channels, pcmBytes: pcmBytes, contextState: String(receiver.state || "unknown")}, true);
        } else {
          counters.decodeFailed++;
          emit("audio_decode_failed", "ERROR", "failed", errorText(value),
            {contextState: String(receiver.state || "unknown")}, false);
        }
      }
      if (typeof args[1] === "function") {
        const callback = args[1]; args[1] = function () { finish(true, arguments[0]); return callback.apply(this, arguments); };
      }
      if (typeof args[2] === "function") {
        const callback = args[2]; args[2] = function () { finish(false, arguments[0]); return callback.apply(this, arguments); };
      }
      let result;
      try { result = decode.apply(receiver, args); } catch (error) { finish(false, error); throw error; }
      if (result && typeof result.then === "function") result.then(
        function (buffer) { finish(true, buffer); }, function (error) { finish(false, error); });
      return result;
    };
  }

  if (typeof document !== "undefined" && typeof document.createElement === "function") {
    const create = document.createElement;
    document.createElement = function () { return observe(create.apply(this, arguments)); };
  }
  if (typeof window.Audio === "function") {
    const Audio = window.Audio;
    function ObservedAudio() { return observe(Reflect.construct(Audio, Array.prototype.slice.call(arguments), new.target || Audio)); }
    ObservedAudio.prototype = Audio.prototype;
    Object.setPrototypeOf(ObservedAudio, Audio);
    window.Audio = ObservedAudio;
  }
  const Media = window.HTMLMediaElement;
  if (Media && typeof Media.prototype.play === "function") {
    const play = Media.prototype.play;
    Media.prototype.play = function () {
      if (!(this instanceof Media)) return play.apply(this, arguments);
      const element = observe(this);
      counters.mediaPlayRequested++;
      emit("audio_media_play_requested", "INFO", "started", "HTML media play requested", mediaContext(element), true);
      function failed(error) {
        counters.mediaFailed++;
        emit("audio_media_failed", "ERROR", "failed", errorText(error), mediaContext(element), false);
      }
      let result;
      try { result = play.apply(element, arguments); } catch (error) { failed(error); throw error; }
      if (result && typeof result.then === "function") result.then(function () {}, failed);
      return result;
    };
  }
  window.setInterval(summary, 30000);
  window.addEventListener("pagehide", summary, {once: true});
})();
