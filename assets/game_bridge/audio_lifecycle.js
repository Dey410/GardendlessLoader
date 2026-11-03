(function () {
  "use strict";
  // When the app goes to the background, iOS interrupts the web view's audio
  // session and WebKit does not reactivate it on return. A resume() or media
  // play() before the scene is active again is refused, and WebKit, which has
  // already marked the session active, never retries: the page stays silent.
  // Audio is suspended when the host reports the scene inactive, while the app
  // is still in the foreground, so WebKit deactivates the session itself;
  // resume()/play() calls wait while it is inactive, and everything resumes
  // once it is active, when WebKit activates the session again.
  // On the session WebKit picks by default ("auto"), the game's audio can run
  // and still be silent: every package in an app linked against the iOS 27
  // SDK, and the 0.16 Web Audio engine with older SDKs too. The game
  // asks for playback, as the <audio> playback it replaced did.
  const session = window.navigator.audioSession;
  if (session) session.type = "playback";
  const Base = window.AudioContext;
  const Media = window.HTMLMediaElement;
  if (!Base || !Media) return;
  const nativeResume = Base.prototype.resume;
  const nativeSuspend = Base.prototype.suspend;
  const nativePlay = Media.prototype.play;
  const nativePause = Media.prototype.pause;
  const contexts = new Set();
  const media = new Set();
  const suspendedContexts = new Set();
  const pausedMedia = new Set();
  // A game's own stop overrides automatic restoration and any earlier start
  // deferred while inactive. Host suspension calls the native methods directly.
  const contextStops = new WeakMap();
  const mediaStops = new WeakMap();
  let active = true;
  let waiting = [];

  function whenActive() {
    return active ? Promise.resolve() : new Promise(resolve => waiting.push(resolve));
  }

  class TrackedAudioContext extends Base {
    constructor(...args) {
      super(...args);
      contexts.add(this);
      this.addEventListener("statechange", () => {
        if (this.state === "closed") contexts.delete(this);
      });
    }
  }
  window.AudioContext = TrackedAudioContext;
  if (window.webkitAudioContext === Base) window.webkitAudioContext = TrackedAudioContext;

  Base.prototype.resume = function () {
    const context = this;
    const stop = contextStops.get(context);
    return active ? nativeResume.call(context) : whenActive().then(() => {
      if (contextStops.get(context) === stop) return nativeResume.call(context);
    });
  };

  Base.prototype.suspend = function () {
    suspendedContexts.delete(this);
    contextStops.set(this, (contextStops.get(this) || 0) + 1);
    return nativeSuspend.call(this);
  };

  Media.prototype.play = function () {
    const element = this;
    if (!media.has(element)) {
      media.add(element);
      element.addEventListener("emptied", () => media.delete(element));
    }
    const stop = mediaStops.get(element);
    return active ? nativePlay.call(element) : whenActive().then(() => {
      if (mediaStops.get(element) !== stop) {
        throw new DOMException("The play() request was interrupted by pause().", "AbortError");
      }
      return nativePlay.call(element);
    });
  };

  Media.prototype.pause = function () {
    pausedMedia.delete(this);
    mediaStops.set(this, (mediaStops.get(this) || 0) + 1);
    return nativePause.call(this);
  };

  window.__gardendlessSetSceneActive = function (isActive) {
    if (isActive === active) return;
    active = isActive;
    if (!active) {
      contexts.forEach(context => {
        if (context.state !== "running") return;
        suspendedContexts.add(context);
        nativeSuspend.call(context).catch(() => {});
      });
      media.forEach(element => {
        if (element.paused) return;
        pausedMedia.add(element);
        nativePause.call(element);
      });
      return;
    }
    waiting.splice(0).forEach(resolve => resolve());
    suspendedContexts.forEach(context => nativeResume.call(context).catch(() => {}));
    suspendedContexts.clear();
    pausedMedia.forEach(element => nativePlay.call(element).catch(() => {}));
    pausedMedia.clear();
  };
})();
