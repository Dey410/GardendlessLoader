import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(
  new URL("../assets/game_bridge/audio_diagnostic.js", import.meta.url),
  "utf8",
);

function install({ detailed, decodeImplementation, playImplementation }) {
  const listeners = new Map();
  const logs = [];

  class AudioContext {}
  AudioContext.prototype.decodeAudioData = decodeImplementation;

  class HTMLMediaElement {
    constructor() {
      this.currentSrc =
        "gardendless-game://localhost/audio/effects/click.mp3?generation=4";
      this.src = this.currentSrc;
      this.duration = 60;
      this.readyState = 1;
      this.networkState = 1;
      this.error = null;
      this.listeners = new Map();
    }
  }
  HTMLMediaElement.prototype.play = playImplementation;
  HTMLMediaElement.prototype.addEventListener = function (name, callback) {
    if (!this.listeners.has(name)) this.listeners.set(name, []);
    this.listeners.get(name).push(callback);
  };
  HTMLMediaElement.prototype.dispatchEvent = function (event) {
    for (const callback of this.listeners.get(event.type) || []) callback.call(this, event);
  };
  const documentObject = {createElement() {return new HTMLMediaElement();}};
  function Audio() {return new HTMLMediaElement();}
  Audio.prototype = HTMLMediaElement.prototype;

  const windowObject = {
    __gardendlessHostConfig: {
      detailedAudioDiagnosticsEnabled: detailed,
    },
    __gardendlessHost: {
      invoke(command, payload) {
        logs.push({ command, payload });
        return Promise.resolve();
      },
    },
    AudioContext,
    HTMLMediaElement,
    Audio,
    document: documentObject,
    location: {
      href: "gardendless-game://localhost/index.html",
      origin: "gardendless-game://localhost",
      pathname: "/index.html",
    },
    addEventListener(name, listener) {
      if (!listeners.has(name)) listeners.set(name, []);
      listeners.get(name).push(listener);
    },
    setInterval() {
      return 1;
    },
  };

  const context = vm.createContext({
    window: windowObject,
    document: documentObject,
    URL,
    Promise,
    Date,
    console,
    setInterval: windowObject.setInterval,
  });
  vm.runInContext(source, context);

  return {
    AudioContext,
    HTMLMediaElement,
    logs,
    createAudio() {return documentObject.createElement("audio");},
    createAudioConstructor() {return new windowObject.Audio();},
    dispatch(name, event = {}) {
      for (const listener of listeners.get(name) || []) listener(event);
    },
  };
}

const decoded = { duration: 0.75, length: 36000, numberOfChannels: 2, sampleRate: 48000 };
const decodePromise = Promise.resolve(decoded);
let receivedDecodeThis;
let receivedBuffer;
let receivedSuccess;
const detailed = install({
  detailed: true,
  decodeImplementation(buffer, success) {
    receivedDecodeThis = this;
    receivedBuffer = buffer;
    receivedSuccess = success;
    return decodePromise;
  },
  playImplementation() {
    return this.playPromise;
  },
});

const audioContext = new detailed.AudioContext();
const buffer = new ArrayBuffer(12);
let callbackValue;
const returnedDecodePromise = audioContext.decodeAudioData(
  buffer,
  (value) => {
    callbackValue = value;
  },
);
assert.equal(returnedDecodePromise, decodePromise, "decode promise identity changes");
assert.equal(receivedDecodeThis, audioContext, "decode receiver changes");
assert.equal(receivedBuffer, buffer, "decode buffer changes");
receivedSuccess(decoded);
assert.equal(callbackValue, decoded, "decode callback value changes");
await decodePromise;
await Promise.resolve();

const media = detailed.createAudio();
const playPromise = Promise.resolve("playing");
media.playPromise = playPromise;
assert.equal(media.play(), playPromise, "media play promise identity changes");
media.dispatchEvent({type: "loadstart"});
media.dispatchEvent({type: "playing"});
media.dispatchEvent({type: "loadedmetadata"});
await playPromise;
await Promise.resolve();

assert.ok(
  detailed.logs.some((item) =>
    item.payload.args.event === "audio_decode_succeeded"),
  "detailed decode success is not logged",
);
assert.ok(
  detailed.logs.some((item) =>
    item.payload.args.event === "audio_media_load_started"),
  "HTML media load is not logged",
);
const constructed = detailed.createAudioConstructor();
constructed.error = {code: 4};
constructed.dispatchEvent({type: "error"});
assert.ok(detailed.logs.some((item) => item.payload.args.event === "audio_media_failed" &&
  item.payload.args.context.errorCode === 4), "detached Audio constructor errors are not observed");
assert.ok(detailed.logs.some((item) => item.payload.args.event === "audio_media_ready" &&
  item.payload.args.context.duration === 60), "metadata state is not observed on detached media");
for (const item of detailed.logs) {
  const path = item.payload.args.context?.relativePath;
  if (path) {
    assert.ok(!path.includes("://"), "diagnostics leaked an absolute URL");
    assert.ok(!path.startsWith("/"), "diagnostics path is not relative");
  }
}

const thrown = new Error("decode exploded");
const normal = install({
  detailed: false,
  decodeImplementation() {
    throw thrown;
  },
  playImplementation() {
    return undefined;
  },
});
const normalContext = new normal.AudioContext();
assert.throws(
  () => normalContext.decodeAudioData(new ArrayBuffer(1)),
  (error) => error === thrown,
  "decode exception identity changes",
);
normal.dispatch("pagehide");
assert.ok(
  normal.logs.some((item) => item.payload.args.event === "audio_decode_failed"),
  "decode errors must always be logged",
);
assert.ok(
  normal.logs.some((item) => item.payload.args.event === "audio_summary"),
  "audio summary must always be logged",
);
assert.ok(
  !normal.logs.some((item) => item.payload.args.event === "audio_decode_started"),
  "verbose events must default to off",
);

const beforeInvalidReceiver = normal.logs.length;
assert.throws(() => normal.AudioContext.prototype.decodeAudioData.call(null, buffer),
  (error) => error === thrown, 'invalid receiver must preserve native exception');
assert.equal(normal.logs.length, beforeInvalidReceiver, 'invalid receiver must bypass instrumentation');

const unknown = detailed.createAudio();
unknown.duration = NaN;
unknown.dispatchEvent({type: 'loadedmetadata'});
assert.equal(detailed.logs.at(-1).payload.args.context.durationKnown, false);
const startDetails = detailed.logs.filter((item) => item.payload.args.event !== 'audio_summary' && item.payload.args.level === 'INFO').length;
for (let i = 0; i < 200; i++) media.dispatchEvent({type: 'playing'});
const detailCount = detailed.logs.filter((item) => item.payload.args.event !== 'audio_summary' && item.payload.args.level === 'INFO').length;
assert.equal(detailCount, 120, `verbose event budget is not bounded (${startDetails})`);
for (let i = 0; i < 50; i++) constructed.dispatchEvent({type: 'error'});
assert.equal(detailed.logs.filter((item) => item.payload.args.level === 'ERROR').length, 30);
detailed.dispatch('pagehide');
const stats = detailed.logs.at(-1).payload.args.context;
assert.equal(stats.decodeInFlight, 0);
assert.equal(stats.decodeSucceeded, 1, 'callback and Promise must count the decode once');
assert.equal(stats.decodedPcmBytesTotal, 288000);
assert(stats.eventsDropped > 0, 'summary must expose dropped events');

console.log("passive audio diagnostics contract passes");
