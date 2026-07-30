(function () {
  "use strict";
  if (window.__gardendlessGpNextCore) return;

  let nextEventId = 1;
  const nullCommands = new Set([
    "plugin:drpc|destroy_thread", "plugin:drpc|spawn_thread",
    "plugin:drpc|set_activity", "update_macos_menu",
    "plugin:event|unlisten", "plugin:event|emit", "plugin:event|emit_to",
    "plugin:resources|close", "plugin:deep-link|register",
    "plugin:deep-link|unregister", "plugin:window|set_size",
    "plugin:window|set_fullscreen", "plugin:window|center",
    "plugin:window|close", "open_devtools"
  ]);

  async function invoke(command, args, options, nativeInvoke) {
    const config = window.__gardendlessHostConfig || {};
    if (command === "plugin:path|resolve_directory") {
      if (!args || args.directory !== 14) {
        throw new Error("不允许解析 Tauri directory " + String(args && args.directory));
      }
      return String(config.gpNextBaseDirectory || "");
    }
    if (command === "plugin:event|listen") return nextEventId++;
    if (command === "plugin:drpc|is_running" ||
        command === "plugin:deep-link|is_registered") return false;
    if (command === "plugin:window|is_maximized") return false;
    if (command === "plugin:deep-link|get_current") return [];
    if (nullCommands.has(command)) return null;
    if (command.startsWith("plugin:window|") || command.startsWith("plugin:image|")) {
      throw new Error("移动平台不支持 " + command);
    }
    return nativeInvoke(command, args, options);
  }

  window.__gardendlessGpNextCore = Object.freeze({ invoke: invoke });
})();
