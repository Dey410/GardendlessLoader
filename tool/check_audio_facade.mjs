import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(
  new URL("../assets/game_bridge/ios_audio_facade.js", import.meta.url),
  "utf8",
);

const posts = [];
const records = [];
const timers = [];
let now = 1000;

function runTimer() {
  const fn = timers.shift();
  if (fn) fn();
}

const windowObject = {
  __gardendlessHostConfig: { nativeSfxEnabled: true },
  __gardendlessAudioDiagnostics: {
    record(type, details) {
      records.push({ type, details });
    },
  },
  webkit: {
    messageHandlers: {
      gardendlessAudio: {
        postMessage(message) {
          posts.push(message);
        },
      },
    },
  },
  location: { href: "gardendless-game://localhost/index.html" },
  performance: {
    now() {
      return now;
    },
  },
  setTimeout(fn) {
    timers.push(fn);
  },
  addEventListener() {},
};

const context = vm.createContext({
  window: windowObject,
  URL,
  Event,
  Promise,
  setTimeout: windowObject.setTimeout,
  console,
});
vm.runInContext(source, context);

const audio = windowObject.__gardendlessNativeAudio;
assert.ok(audio, "facade factory is installed");

const handle = audio.createNativeAudioHandle(
  "gardendless-game://localhost/sfx/click.mp3",
  { role: "oneShot" },
);
assert.ok(handle, "facade handle is created");
assert.equal(handle.role, "oneShot");
assert.equal(handle.src, "gardendless-game://localhost/sfx/click.mp3");
assert.ok(records.some((r) => r.type === "facadeCreated"), "facadeCreated recorded");

handle.volume = 0.5;
runTimer();
const volumePost = posts[posts.length - 1];
assert.equal(volumePost.command, "setVolume");
assert.equal(volumePost.requestId, handle.id);
assert.equal(volumePost.volume, 0.5);

const playPromise = handle.play();
assert.equal(typeof playPromise.then, "function", "play returns a promise");
const playPost = posts[posts.length - 1];
assert.equal(playPost.command, "play");
assert.equal(playPost.requestId, handle.id);
assert.equal(playPost.role, "oneShot");
assert.equal(playPost.volume, 0.5);

const volumePostsForHandle = () =>
  posts.filter((p) => p.command === "setVolume" && p.requestId === handle.id)
    .length;
const volumePostsBefore = volumePostsForHandle();
handle.volume = 0.5;
runTimer();
assert.equal(
  volumePostsForHandle(),
  volumePostsBefore,
  "unchanged volume must not repost setVolume",
);

handle.play();
handle.pause();
const seekPostsForHandle = () =>
  posts.filter((p) => p.command === "seek" && p.requestId === handle.id)
    .length;
const seekPostsBefore = seekPostsForHandle();
handle.seek(0.5);
assert.equal(
  seekPostsForHandle(),
  seekPostsBefore + 1,
  "seek while paused must be posted to native",
);
handle.stop();

let endedCount = 0;
handle.addEventListener("ended", () => {
  endedCount += 1;
});
windowObject.__gardendlessAudioEvents([
  { type: "ended", requestIds: [handle.id], reasons: [""] },
]);
assert.equal(endedCount, 1, "ended event is dispatched to the facade listener");
assert.ok(
  records.some((r) => r.type === "endedReceived"),
  "endedReceived is recorded",
);

const burst = audio.createNativeAudioHandle(
  "gardendless-game://localhost/sfx/burst.mp3",
  { role: "oneShot" },
);
let burstEndedCount = 0;
burst.addEventListener("ended", () => {
  burstEndedCount += 1;
});
const playCountBefore = posts.filter((p) => p.command === "play").length;
burst.play();
windowObject.__gardendlessAudioEvents([
  { type: "silent", requestIds: [burst.id], reasons: ["duration_limit"] },
]);
burst.play();
now += 100;
windowObject.__gardendlessAudioEvents([
  { type: "silent", requestIds: [burst.id], reasons: ["duration_limit"] },
]);
burst.play();
now += 100;
windowObject.__gardendlessAudioEvents([
  { type: "silent", requestIds: [burst.id], reasons: ["duration_limit"] },
]);
assert.ok(
  records.some((r) => r.type === "silentThrottleArmed"),
  "silent throttle is armed after three silents",
);

const suppressed = posts.filter((p) => p.command === "play").length;
burst.play();
assert.equal(
  posts.filter((p) => p.command === "play").length,
  suppressed,
  "suppressed URL does not post another play",
);
assert.ok(
  records.some((r) => r.type === "silentThrottled"),
  "silentThrottled is recorded",
);
assert.equal(
  burstEndedCount,
  3,
  "each silent event dispatches one ended to the wrapper",
);
runTimer();
assert.equal(
  burstEndedCount,
  4,
  "suppressed play dispatches ended asynchronously",
);

const releaseHandles = ["r1", "r2", "r3"].map((name) =>
  audio.createNativeAudioHandle(
    `gardendless-game://localhost/sfx/${name}.mp3`,
    { role: "oneShot" },
  ),
);
releaseHandles.forEach((h) => h.release());
assert.equal(
  posts.filter((p) => p.command === "releaseMany").length,
  0,
  "releases are batched until the flush timer",
);
runTimer();
const releaseMany = posts.filter((p) => p.command === "releaseMany").pop();
assert.ok(releaseMany, "releaseMany is posted");
assert.equal(
  releaseMany.requestIds.length,
  3,
  "releaseMany carries every released request id",
);

console.log("audio facade contract passes");
