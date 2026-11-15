(function () {
  "use strict";

  // GP-Next 0.16.24 moved its installed-package store and local source capture
  // from Tauri fs plugin calls to desktop-only commands. They are emulated
  // here with the fs commands the native GP-Next core already serves, so the
  // native sandbox still checks every path. Directory walks follow GP-Next's
  // own pack-snapshot rules (hidden and OS junk names skipped, symlinks
  // rejected) so captured digests match what earlier versions produced.
  const internals = window.__TAURI_INTERNALS__;
  if (!internals || typeof internals.invoke !== "function" ||
      internals.__gardendlessStoreInstalled) return;

  const baseInvoke = internals.invoke;
  const appData = 14;
  const fsOptions = Object.freeze({baseDir: appData});
  const installedRoot = "gp-next/installed";
  const digestPattern = /^[a-f0-9]{64}$/;
  const captureSource = /^gp-next\/(?:packs\/[^/]+|patches|__gpn_edits)$/;
  const ignoredNames = new Set(["__macosx", "thumbs.db", "ehthumbs.db",
    "ehthumbs_vista.db", "desktop.ini", "$recycle.bin",
    "system volume information", "icon\r"]);
  const statConcurrency = 6;

  function call(command, args, options) {
    return baseInvoke.call(internals, command, args, options || {});
  }

  function exists(path) {
    return call("plugin:fs|exists", {path: path, options: fsOptions});
  }

  function lstat(path) {
    return call("plugin:fs|lstat", {path: path, options: fsOptions});
  }

  async function readDir(path) {
    const entries = await call("plugin:fs|read_dir", {path: path, options: fsOptions});
    if (!Array.isArray(entries)) throw new Error("Invalid directory listing: " + path);
    return entries;
  }

  function mkdir(path) {
    return call("plugin:fs|mkdir", {path: path, options: {baseDir: appData, recursive: true}});
  }

  function remove(path) {
    return call("plugin:fs|remove", {path: path, options: {baseDir: appData, recursive: true}});
  }

  function rename(from, to) {
    return call("plugin:fs|rename", {oldPath: from, newPath: to,
      options: {oldPathBaseDir: appData, newPathBaseDir: appData}});
  }

  async function readBytes(path) {
    const value = await call("plugin:fs|read_file", {path: path, options: fsOptions});
    if (value instanceof ArrayBuffer) return new Uint8Array(value);
    if (ArrayBuffer.isView(value)) {
      return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    }
    throw new Error("Invalid file read result: " + path);
  }

  // Tauri v2 sends file bytes as the request body and the path in headers;
  // the transport turns that into a chunked native file write.
  function writeBytes(path, bytes) {
    return call("plugin:fs|write_file", bytes, {headers: {
      path: encodeURIComponent(path), options: JSON.stringify(fsOptions)}});
  }

  function toBase64(bytes) {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 8192) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192));
    }
    return btoa(binary);
  }

  function fromBase64(text) {
    if (typeof text !== "string") throw new TypeError("Package file bytes are missing");
    const binary = atob(text);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  function sameBytes(a, b) {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
    return true;
  }

  function ignored(name) {
    return (name.startsWith(".") && name !== "." && name !== "..") ||
      ignoredNames.has(name.toLowerCase());
  }

  function requireDigest(value) {
    if (typeof value !== "string" || !digestPattern.test(value)) {
      throw new Error("Invalid package digest");
    }
    return value;
  }

  // Same rules as GP-Next's snapshot path check.
  function packagePath(value) {
    const text = String(value == null ? "" : value).trim().replace(/\\/g, "/");
    if (!text) throw new Error("snapshot path is required");
    if (text.startsWith("/") || /^[a-zA-Z]:/.test(text) || text.includes("\0")) {
      throw new Error("snapshot path must be relative to the pack root");
    }
    const parts = text.split("/").filter(function (part) { return part && part !== "."; });
    if (parts.some(function (part) { return part === ".."; })) {
      throw new Error("snapshot path cannot contain parent-directory segments");
    }
    const path = parts.join("/");
    if (!path) throw new Error("snapshot path is required");
    return path;
  }

  function entryName(entry) {
    const name = entry && entry.name;
    if (typeof name !== "string" || !name || /[\\/]/.test(name) || name === "." || name === "..") {
      throw new Error("Invalid directory entry name");
    }
    return name;
  }

  // Regular files below root, sorted by relative path.
  async function walk(root) {
    const files = [];
    const seen = new Set();
    async function visit(prefix, directory) {
      for (const entry of await readDir(directory)) {
        const name = entryName(entry);
        if (ignored(name)) continue;
        const relative = prefix ? prefix + "/" + name : name;
        if (seen.has(relative)) throw new Error("Duplicate directory path: " + relative);
        seen.add(relative);
        const full = directory + "/" + name;
        if (entry.isSymlink) throw new Error("Package path is a symlink: " + relative);
        if (entry.isDirectory) await visit(relative, full);
        else if (entry.isFile) files.push({path: relative, full: full});
        else throw new Error("Non-regular package entry: " + relative);
      }
    }
    await visit("", root);
    files.sort(function (a, b) { return a.path < b.path ? -1 : a.path > b.path ? 1 : 0; });
    return files;
  }

  async function encodeFiles(files) {
    const result = [];
    for (const file of files) {
      result.push({path: file.path, base64: toBase64(await readBytes(file.full))});
    }
    return result;
  }

  async function requireDirectory(path) {
    const info = await lstat(path);
    if (!info || info.isSymlink || !info.isDirectory) {
      throw new Error("Package root is not a directory: " + path);
    }
  }

  // True when directory holds exactly the incoming files, byte for byte.
  async function holdsFiles(directory, incoming) {
    const files = await walk(directory);
    if (files.length !== incoming.size) return false;
    for (const file of files) {
      const expected = incoming.get(file.path);
      if (!expected || !sameBytes(await readBytes(file.full), expected)) return false;
    }
    return true;
  }

  function randomId() {
    if (window.crypto && typeof window.crypto.randomUUID === "function") {
      return window.crypto.randomUUID();
    }
    const bytes = new Uint8Array(16);
    window.crypto.getRandomValues(bytes);
    return Array.from(bytes, function (byte) { return byte.toString(16).padStart(2, "0"); }).join("");
  }

  async function installedFiles(digest) {
    const target = installedRoot + "/" + requireDigest(digest);
    if (!await exists(target)) return null;
    await requireDirectory(target);
    return walk(target);
  }

  async function readInstalledPack(args) {
    const files = await installedFiles(args.digest);
    return files && encodeFiles(files);
  }

  // GP-Next 0.16.27 reads installed packages as an index plus file bytes so
  // the desktop app can defer large media. Every file is sent eagerly here:
  // the desktop app decides which files GP-Next may read synchronously
  // (pack.json, JS entries, thumbnails), and 0.16.24 already loaded whole
  // packages through gp_next_read_installed_pack.
  async function readPackageIndex(args) {
    const digest = requireDigest(args.digest);
    const files = await installedFiles(digest);
    if (!files) return null;
    const index = [];
    const eager = [];
    for (const file of files) {
      const bytes = await readBytes(file.full);
      index.push({path: file.path, length: bytes.length});
      eager.push({path: file.path, base64: toBase64(bytes)});
    }
    return {index: {digest: digest, files: index}, eager: eager};
  }

  // Only reached for files left out of the eager list.
  function readPackageFile(args) {
    return readBytes(installedRoot + "/" + requireDigest(args.digest) + "/" + packagePath(args.path));
  }

  // Returns true when the same bytes were already installed.
  async function installPack(args) {
    const digest = requireDigest(args.digest);
    if (!Array.isArray(args.files)) throw new TypeError("Package files are required");
    const incoming = new Map();
    for (const file of args.files) {
      const path = packagePath(file && file.path);
      if (incoming.has(path)) throw new Error("Duplicate package path: " + path);
      incoming.set(path, fromBase64(file.base64));
    }
    const target = installedRoot + "/" + digest;
    if (await exists(target)) {
      await requireDirectory(target);
      if (await holdsFiles(target, incoming)) return true;
    }
    await mkdir(installedRoot);
    const pending = installedRoot + "/pending-" + randomId();
    let pendingExists = false;
    try {
      if (await exists(pending)) throw new Error("Temporary cache path already exists");
      await mkdir(pending);
      pendingExists = true;
      const directories = new Set();
      for (const [path, bytes] of incoming) {
        const slash = path.lastIndexOf("/");
        if (slash > 0) {
          const directory = pending + "/" + path.slice(0, slash);
          if (!directories.has(directory)) {
            await mkdir(directory);
            directories.add(directory);
          }
        }
        await writeBytes(pending + "/" + path, bytes);
      }
      // A directory that differs from its digest is corrupt; replace it.
      if (await exists(target)) await remove(target);
      try {
        await rename(pending, target);
        pendingExists = false;
      } catch (error) {
        if (await exists(target) && await holdsFiles(target, incoming)) return true;
        throw error;
      }
      return false;
    } finally {
      if (pendingExists) {
        try { await remove(pending); } catch (_) { /* Keep the original failure. */ }
      }
    }
  }

  async function captureLocalPack(args) {
    const source = String(args.source == null ? "" : args.source).replace(/\\/g, "/");
    if (!captureSource.test(source) ||
        source.split("/").some(function (part) { return part === "." || part === ".."; })) {
      throw new Error("Unsupported package source: " + source);
    }
    if (!await exists(source)) return null;
    const info = await lstat(source);
    if (info.isSymlink) throw new Error("Package path is a symlink: " + source);
    if (info.isDirectory) return {zip: null, files: await encodeFiles(await walk(source))};
    if (info.isFile && /\.zip$/i.test(source)) {
      return {zip: toBase64(await readBytes(source)), files: []};
    }
    throw new Error("Expected a package directory or ZIP file");
  }

  async function mapLimited(items, limit, operation) {
    const results = new Array(items.length);
    let next = 0;
    async function worker() {
      while (next < items.length) {
        const index = next++;
        results[index] = await operation(items[index]);
      }
    }
    const workers = [];
    for (let i = 0; i < Math.min(limit, items.length); i++) workers.push(worker());
    await Promise.all(workers);
    return results;
  }

  async function sha256Hex(text) {
    const digest = await window.crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
    return Array.from(new Uint8Array(digest), function (byte) {
      return byte.toString(16).padStart(2, "0");
    }).join("");
  }

  function stamp(info) {
    return String(info && info.size) + ":" + String(info && info.mtime);
  }

  // Changes when a file under the source is added, removed, resized or touched.
  async function directoryFingerprint(path) {
    const files = await walk(path);
    const stats = await mapLimited(files, statConcurrency, function (file) { return lstat(file.full); });
    const lines = files.map(function (file, index) {
      return file.path + "\0" + stamp(stats[index]) + "\n";
    });
    return "dir:" + await sha256Hex(lines.join(""));
  }

  async function localPackageInventory() {
    const inventory = [];
    async function add(path, fingerprint) {
      try {
        inventory.push({path: path, fingerprint: await fingerprint()});
      } catch (error) {
        // Without a fingerprint GP-Next captures the source again and reports
        // the problem against that one package.
        console.warn("[GardendlessLoader] Local package fingerprint failed:", path, error);
      }
    }
    if (await exists("gp-next/packs")) {
      for (const entry of await readDir("gp-next/packs")) {
        let name;
        try { name = entryName(entry); } catch (_) { continue; }
        if (ignored(name) || entry.isSymlink) continue;
        const path = "gp-next/packs/" + name;
        if (entry.isDirectory) {
          await add(path, function () { return directoryFingerprint(path); });
        } else if (entry.isFile && /\.zip$/i.test(name)) {
          await add(path, async function () { return "zip:" + stamp(await lstat(path)); });
        }
      }
    }
    for (const path of ["gp-next/patches", "gp-next/__gpn_edits"]) {
      if (!await exists(path)) continue;
      const info = await lstat(path);
      if (info.isSymlink || !info.isDirectory) continue;
      await add(path, function () { return directoryFingerprint(path); });
    }
    return inventory;
  }

  const handlers = Object.freeze({
    gp_next_read_installed_pack: readInstalledPack,
    gp_next_read_package_index: readPackageIndex,
    gp_next_read_package_file: readPackageFile,
    gp_next_install_pack: installPack,
    gp_next_capture_local_pack: captureLocalPack,
    gp_next_local_package_inventory: localPackageInventory
  });

  internals.invoke = function (command, args) {
    if (Object.prototype.hasOwnProperty.call(handlers, command)) {
      const handler = handlers[command];
      return Promise.resolve().then(function () {
        return handler(args && typeof args === "object" ? args : {});
      });
    }
    return baseInvoke.apply(this, arguments);
  };
  Object.defineProperty(internals, "__gardendlessStoreInstalled", {value: true});
})();
