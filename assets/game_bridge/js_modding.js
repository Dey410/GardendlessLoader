(function () {
  "use strict";

  const config = window.__gardendlessHost?.config ||
    window.__gardendlessHostConfig || {};
  if (!config.hasGpNext || !config.gpNextCompatible) return;

  const storageKey = "gp-next-settings";
  try {
    let settings = {};
    const raw = window.localStorage.getItem(storageKey);
    if (raw) {
      try {
        const parsed = JSON.parse(raw);
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
          settings = parsed;
        }
      } catch (_) {
        // Replace malformed settings with the smallest valid settings object.
      }
    }

    const currentExperimental = settings.experimental;
    const experimental = currentExperimental &&
      typeof currentExperimental === "object" &&
      !Array.isArray(currentExperimental)
      ? currentExperimental
      : {};
    settings.experimental = {
      ...experimental,
      jsModding: config.jsModdingEnabled === true,
    };
    window.localStorage.setItem(storageKey, JSON.stringify(settings));
  } catch (_) {
    console.warn("[Gardendless] Unable to synchronize JS Modding setting");
  }
})();
