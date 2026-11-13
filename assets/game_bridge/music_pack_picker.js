(function () {
  "use strict";

  // Music packs (0.16.15+) import a folder through <input webkitdirectory>
  // and read each file's webkitRelativePath. No mobile WebView returns a
  // folder there, so folder inputs use GP-Next's native folder picker instead:
  // the host stages the chosen folder inside the GP-Next sandbox, and its
  // files are handed back to the input as File objects with relative paths.
  if (window.__gardendlessMusicPackPicker) return;
  Object.defineProperty(window, "__gardendlessMusicPackPicker", {value: true});

  const proto = window.HTMLInputElement && window.HTMLInputElement.prototype;
  if (!proto) return;
  const nativeClick = proto.click;
  const nativeShowPicker = proto.showPicker;
  const maxEntries = 10000;
  const maxBytes = 512 * 1024 * 1024;
  const ignoredNames = new Set(["__macosx", "thumbs.db", "ehthumbs.db",
    "ehthumbs_vista.db", "desktop.ini", "$recycle.bin",
    "system volume information", "icon\r"]);
  const mimeTypes = {
    json: "application/json", json5: "application/json", txt: "text/plain",
    mp3: "audio/mpeg", ogg: "audio/ogg", oga: "audio/ogg", opus: "audio/ogg",
    wav: "audio/wav", m4a: "audio/mp4", aac: "audio/aac", flac: "audio/flac",
    png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp"
  };
  let busy = false;

  function tauri() {
    const internals = window.__TAURI_INTERNALS__;
    return internals && typeof internals.invoke === "function" ? internals : null;
  }

  function wantsFolder(input) {
    return input instanceof window.HTMLInputElement && input.type === "file" &&
      (input.webkitdirectory === true || input.hasAttribute("webkitdirectory"));
  }

  function language() {
    const lang = String(document.documentElement.lang || navigator.language || "").toLowerCase();
    return lang.startsWith("zh");
  }

  function ignored(name) {
    return (name.startsWith(".") && name !== "." && name !== "..") ||
      ignoredNames.has(name.toLowerCase());
  }

  // A modal progress window; a plain overlay would sit below the game's
  // modal music pack dialog.
  function progressWindow(zh) {
    const dialogs = window.__gardendlessDialogs;
    if (!dialogs) {
      return {update: function () {}, fail: function (text) { window.alert(text); }, close: function () {}};
    }
    const parts = dialogs.createDialog(zh ? "导入音乐包" : "Import music pack", zh ? "关闭" : "Close");
    parts.closeButton.disabled = true;
    const status = dialogs.element("div", "gd-status", zh ? "正在读取文件夹…" : "Reading the folder…");
    parts.body.appendChild(status);
    parts.dialog.addEventListener("cancel", function (event) {
      if (parts.closeButton.disabled) event.preventDefault();
    });
    dialogs.show(parts.dialog);
    return {
      update: function (text) { status.textContent = text; },
      fail: function (text) {
        status.textContent = text;
        parts.closeButton.disabled = false;
      },
      close: function () { parts.dialog.close(); }
    };
  }

  async function readFolder(api, root, onProgress) {
    const entries = [];
    let total = 0;
    async function visit(prefix, directory) {
      const children = await api.invoke("plugin:fs|read_dir", {path: directory, options: {}});
      if (!Array.isArray(children)) throw new Error("Invalid directory listing");
      for (const child of children) {
        const name = child && child.name;
        if (typeof name !== "string" || !name || /[\\/]/.test(name) || name === "." || name === "..") {
          throw new Error("Invalid directory entry name");
        }
        if (ignored(name) || child.isSymlink) continue;
        const relative = prefix ? prefix + "/" + name : name;
        if (entries.length >= maxEntries) throw new Error("Too many files in the folder");
        if (child.isDirectory) await visit(relative, directory + "/" + name);
        else if (child.isFile) entries.push({path: relative, full: directory + "/" + name, name: name});
      }
    }
    await visit("", root);
    const files = [];
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      onProgress(i, entries.length);
      const buffer = await api.invoke("plugin:fs|read_file", {path: entry.full, options: {}});
      if (!(buffer instanceof ArrayBuffer)) throw new Error("Invalid file read result: " + entry.path);
      total += buffer.byteLength;
      if (total > maxBytes) throw new Error("The folder exceeds 512 MiB");
      const extension = entry.name.includes(".") ? entry.name.slice(entry.name.lastIndexOf(".") + 1).toLowerCase() : "";
      const file = new File([buffer], entry.name, {type: mimeTypes[extension] || "", lastModified: Date.now()});
      // The game drops the first segment, the picked folder's own name.
      Object.defineProperty(file, "webkitRelativePath", {value: "selection/" + entry.path, configurable: true});
      files.push(file);
    }
    onProgress(entries.length, entries.length);
    return files;
  }

  async function pickFolder(input) {
    const api = tauri();
    if (busy || !api) return;
    busy = true;
    const zh = language();
    let progress = null;
    try {
      const staged = await api.invoke("plugin:dialog|open", {options: {directory: true}});
      if (typeof staged !== "string" || !staged) return;
      progress = progressWindow(zh);
      const files = await readFolder(api, staged.replace(/\/+$/, ""), function (done, count) {
        progress.update((zh ? "正在读取音乐包 " : "Reading music pack ") + done + " / " + count);
      });
      if (!files.length) throw new Error(zh ? "文件夹是空的" : "The folder is empty");
      progress.close();
      progress = null;
      Object.defineProperty(input, "files", {configurable: true, get: function () { return files; }});
      input.dispatchEvent(new Event("input", {bubbles: true}));
      input.dispatchEvent(new Event("change", {bubbles: true}));
    } catch (error) {
      const text = (zh ? "无法读取音乐包文件夹：" : "Could not read the music pack folder: ") +
        (error && error.message ? error.message : String(error));
      if (!progress) progress = progressWindow(zh);
      progress.fail(text);
    } finally {
      busy = false;
    }
  }

  proto.click = function () {
    if (wantsFolder(this) && tauri()) {
      pickFolder(this);
      return;
    }
    return nativeClick.apply(this, arguments);
  };

  if (typeof nativeShowPicker === "function") {
    proto.showPicker = function () {
      if (wantsFolder(this) && tauri()) {
        pickFolder(this);
        return;
      }
      return nativeShowPicker.apply(this, arguments);
    };
  }

  // A tap on a visible folder input opens the native picker the same way.
  document.addEventListener("click", function (event) {
    const target = event.target;
    if (!event.isTrusted || !wantsFolder(target) || !tauri()) return;
    event.preventDefault();
    pickFolder(target);
  }, true);
})();
