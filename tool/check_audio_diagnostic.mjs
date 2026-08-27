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
    }
  }
  HTMLMediaElement.prototype.play = playImplementation;

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
    dispatch(name, event = {}) {
      for (const listener of listeners.get(name) || []) listener(event);
    },
  };
}

const decoded = { duration: 0.75 };
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

const media = new detailed.HTMLMediaElement();
const playPromise = Promise.resolve("playing");
media.playPromise = playPromise;
assert.equal(media.play(), playPromise, "media play promise identity changes");
detailed.dispatch("loadstart", { target: media });
detailed.dispatch("playing", { target: media });
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

console.log("passive audio diagnostics contract passes");
