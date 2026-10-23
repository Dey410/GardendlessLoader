(function () {
  "use strict";

  if (window.__gardendlessHapticEffectsInstalled) return;
  window.__gardendlessHapticEffectsInstalled = true;

  const host = window.__gardendlessHost;
  const config = host ? host.config : (window.__gardendlessHostConfig || {});
  if (!host || config.hapticEffectsEnabled !== true) return;

  // The game plays every sound effect through the static `sounds` facade of
  // SoundRescourses.ts. Wrapping a few of its methods lets the player feel
  // the big moments as well as hear them: a tick for each rhythm hit and for
  // "Ready" and "Set", a heavy hit for "Plant!" and for an explosion, a tap
  // when plant food kicks in, an alarm for the first zombies and each wave
  // warning, and a pattern for a level task done or failed. A controller
  // used in this session rumbles instead of the device.
  const checkIntervalMs = 250;
  const moduleId = "chunks:///_virtual/SoundRescourses.ts";
  // Native haptic kinds, with the milliseconds between them.
  const patterns = {
    tick: ["selection"],
    tap: ["impact"],
    hit: ["heavy"],
    alarm: ["heavy", 180, "heavy"],
    done: ["impact", 120, "heavy"],
    failed: ["heavy", 120, "heavy", 120, "heavy"]
  };
  const effects = {
    playRhythmHit: "tick",
    playReadyOrSet: "tick",
    playPlantFoodStart: "tap",
    playLetsRock: "tap",
    playExplosion: "hit",
    playSpudow: "hit",
    playGargantuarAsh: "hit",
    playShipDestroySound: "hit",
    // The level's warning label plays it for "Plant!" and for sandstorms.
    playSandStormWarn: "hit",
    playAwooga: "alarm",
    playHugeWave: "alarm",
    playFinalWave: "alarm",
    playZombossHPFillStart: "alarm",
    playLevelTaskComplete: "done",
    playLevelTaskFail: "failed"
  };
  // Controller rumble per kind: milliseconds, strong and weak motor.
  const rumbles = {
    selection: [20, 0, 0.4],
    impact: [50, 0.3, 0.6],
    heavy: [140, 1, 0.6]
  };
  // A burst of explosions is felt once.
  const quietMilliseconds = 100;
  let lastPatternAt = -Infinity;
  let moduleCheckTimer = null;
  let stopped = false;

  function stop(error) {
    if (stopped) return;
    stopped = true;
    console.error("[GardendlessLoader] 触感音效已停用：游戏接口不匹配。", error);
  }

  // The Gamepad API lists a controller only after its first input.
  function rumblingPads() {
    if (typeof navigator.getGamepads !== "function") return [];
    return Array.from(navigator.getGamepads() || []).filter(function (pad) {
      return pad && pad.connected && pad.vibrationActuator;
    });
  }

  // A missed pulse is not worth a log entry.
  function pulse(kind) {
    const pads = rumblingPads();
    if (!pads.length) {
      host.invoke("host:haptic", {kind: kind}).catch(function () {});
      return;
    }
    const rumble = rumbles[kind];
    for (const pad of pads) {
      pad.vibrationActuator.playEffect("dual-rumble", {
        duration: rumble[0],
        strongMagnitude: rumble[1],
        weakMagnitude: rumble[2]
      }).catch(function () {});
    }
  }

  function feel(effect) {
    const now = performance.now();
    if (now - lastPatternAt < quietMilliseconds) return;
    lastPatternAt = now;
    let delay = 0;
    for (const step of patterns[effect]) {
      if (typeof step === "number") {
        delay += step;
      } else if (delay === 0) {
        pulse(step);
      } else {
        setTimeout(pulse, delay, step);
      }
    }
  }

  // The sound always plays; a failure here only turns the haptics off.
  function install(sounds) {
    const missing = [];
    for (const name of Object.keys(effects)) {
      const original = sounds[name];
      if (typeof original !== "function") {
        missing.push(name);
        continue;
      }
      sounds[name] = function () {
        const result = original.apply(this, arguments);
        if (!stopped) {
          try {
            feel(effects[name]);
          } catch (error) {
            stop(error);
          }
        }
        return result;
      };
    }
    if (missing.length) {
      console.error("[GardendlessLoader] 触感音效找不到这些游戏音效：" + missing.join(", "));
    }
  }

  // Only a module Cocos has already executed is read; importing it here
  // would run the game's circular module graph from another entry point.
  function findSounds() {
    moduleCheckTimer = null;
    if (stopped) return;
    const system = window.System;
    const module = system && typeof system.get === "function"
      ? system.get(moduleId)
      : null;
    if (!module) {
      moduleCheckTimer = setTimeout(findSounds, checkIntervalMs);
      return;
    }
    const sounds = module.sounds || (module.default && module.default.sounds);
    if (!sounds) {
      stop(new Error("Sound effect facade is missing"));
      return;
    }
    install(sounds);
  }

  window.addEventListener("pagehide", function () {
    stopped = true;
    if (moduleCheckTimer !== null) {
      clearTimeout(moduleCheckTimer);
      moduleCheckTimer = null;
    }
  }, {once: true});
  if (document.readyState === "complete") {
    findSounds();
  } else {
    window.addEventListener("load", findSounds, {once: true});
  }
})();
