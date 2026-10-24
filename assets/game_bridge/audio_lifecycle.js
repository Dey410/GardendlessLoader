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
    return active ? nativeResume.call(context) : whenActive().then(() => nativeResume.call(context));
  };

  Media.prototype.play = function () {
    const element = this;
    if (!media.has(element)) {
      media.add(element);
      element.addEventListener("emptied", () => media.delete(element));
    }
    return active ? nativePlay.call(element) : whenActive().then(() => nativePlay.call(element));
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
