(function () {
  "use strict";

  // GP-Next 0.16.24 dropped the in-game GitHub level window for a desktop-only
  // one opened through electronAPI.openGithubWindow. This window takes its
  // place: it lists the community level repository through the same
  // levels.pvzge.com proxy the old in-game window used, caches each level with
  // tmpPatch's saveLevel, and hands it to the game's onGithubPlayLevel
  // listener, so progress is recorded under the level path as on desktop.
  const dialogs = window.__gardendlessDialogs;
  if (!dialogs || window.__gardendlessGithubLevels) return;
  Object.defineProperty(window, "__gardendlessGithubLevels", {value: true});

  const origin = "https://levels.pvzge.com";
  const treeUrl = origin + "/api/github-levels/git/trees/main?recursive=1";
  const rawPrefix = origin + "/api/github-levels/raw/main/";
  const repositoryUrl = "https://github.com/NanGarden31415926/PvZ2-Gardendless-GitHubLevels";
  const listKey = "gardendless.githubLevels.list.v1";
  const playedShaKey = "gardendless.githubLevels.playedSha.v1";
  // Written by the 0.16.15 in-game window; seeds change detection once.
  const legacyShaKey = "PvZ2_GitHubLevels_Sha";
  const folderKey = "gardendless.githubLevels.folder.v1";
  const requestTimeoutMs = 20000;
  const collator = typeof Intl === "object" && Intl.Collator
    ? new Intl.Collator("zh-CN", {numeric: true}) : null;

  let state = null;

  function compare(a, b) {
    return collator ? collator.compare(a, b) : (a < b ? -1 : a > b ? 1 : 0);
  }

  function storageGet(key, fallback) {
    try {
      const raw = window.localStorage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch (_) {
      return fallback;
    }
  }

  function storageSet(key, value) {
    try { window.localStorage.setItem(key, JSON.stringify(value)); } catch (_) { /* Cache only. */ }
  }

  function playedShas() {
    const stored = storageGet(playedShaKey, null);
    if (stored && typeof stored === "object") return stored;
    const legacy = storageGet(legacyShaKey, null);
    return legacy && typeof legacy === "object" ? legacy : {};
  }

  // tmpPatch's saveLevel accepts the same relative paths.
  function validLevelPath(path) {
    return typeof path === "string" && path.length < 1024 && /\.json$/i.test(path) &&
      path.split("/").every(function (part) {
        return part && part !== "." && part !== ".." && !/[:\\\0]/.test(part);
      });
  }

  function levelUrl(path, url) {
    if (typeof url === "string" && url.startsWith(origin + "/")) return url;
    return rawPrefix + path.split("/").map(encodeURIComponent).join("/");
  }

  function validLevel(level) {
    return level && validLevelPath(level.path) && typeof level.sha === "string" &&
      typeof level.url === "string" && level.url.startsWith(origin + "/");
  }

  function cachedLevels() {
    const cached = storageGet(listKey, null);
    return cached && Array.isArray(cached.levels) ? cached.levels.filter(validLevel) : [];
  }

  async function fetchJson(url) {
    const controller = typeof AbortController === "function" ? new AbortController() : null;
    const timer = controller ? setTimeout(function () { controller.abort(); }, requestTimeoutMs) : 0;
    try {
      const response = await fetch(url, {credentials: "omit",
        signal: controller ? controller.signal : undefined});
      if (!response.ok) throw new Error("HTTP " + response.status);
      return await response.json();
    } finally {
      if (timer) clearTimeout(timer);
    }
  }

  function errorText(error) {
    return error && error.message ? error.message : String(error);
  }

  function stem(path) {
    return path.slice(path.lastIndexOf("/") + 1).replace(/\.json$/i, "");
  }

  function displayName(level) {
    const names = state.names;
    const key = stem(level.path);
    const value = names[level.path] || names[key];
    return typeof value === "string" && value ? value : key;
  }

  function progressOf(path) {
    const record = state.progress[path];
    const played = !!record && record.last_played_time != null &&
      Number.isFinite(Number(record.last_played_time));
    return {played: played, won: !!(record && record.last_victory_time),
      time: played ? Number(record.last_played_time) : null};
  }

  function setStatus(text) {
    if (state) state.status.textContent = text;
  }

  function setBusy(busy) {
    if (!state) return;
    state.busy = busy;
    for (const control of state.list.querySelectorAll("button")) control.disabled = busy;
  }

  function navigate(folder) {
    if (!state || state.busy) return;
    state.folder = folder;
    storageSet(folderKey, folder);
    render();
  }

  function render() {
    if (!state) return;
    const zh = state.zh;
    const element = dialogs.element;
    const button = dialogs.button;
    let prefix = state.folder.length ? state.folder.join("/") + "/" : "";
    if (prefix && state.levels.length &&
        !state.levels.some(function (level) { return level.path.startsWith(prefix); })) {
      state.folder = [];
      prefix = "";
    }

    state.nav.replaceChildren();
    state.nav.appendChild(button(zh ? "上一级" : "Up", function () {
      navigate(state.folder.slice(0, -1));
    }));
    state.nav.lastChild.disabled = state.folder.length === 0;
    state.nav.appendChild(button(zh ? "全部" : "All", function () { navigate([]); }));
    state.folder.forEach(function (name, index) {
      state.nav.appendChild(button(name, function () { navigate(state.folder.slice(0, index + 1)); }));
    });

    const folders = new Map();
    const levels = [];
    for (const level of state.levels) {
      if (!level.path.startsWith(prefix)) continue;
      const rest = level.path.slice(prefix.length);
      const slash = rest.indexOf("/");
      if (slash < 0) {
        levels.push(level);
        continue;
      }
      const name = rest.slice(0, slash);
      const stats = folders.get(name) || {total: 0, played: 0, won: 0};
      const progress = progressOf(level.path);
      stats.total++;
      if (progress.played) stats.played++;
      if (progress.won) stats.won++;
      folders.set(name, stats);
    }

    state.list.replaceChildren();
    for (const name of Array.from(folders.keys()).sort(compare)) {
      const stats = folders.get(name);
      const row = element("div", "gd-row");
      const label = element("span", null, "📂 " + name);
      const actions = element("span", "gd-actions");
      actions.append(
        element("span", "gd-muted", stats.won + " / " + stats.played + " / " + stats.total),
        button(zh ? "打开" : "Open", function () { navigate(state.folder.concat(name)); }));
      row.append(label, actions);
      state.list.appendChild(row);
    }
    levels.sort(function (a, b) { return compare(stem(a.path), stem(b.path)); });
    for (const level of levels) {
      const progress = progressOf(level.path);
      const row = element("div", "gd-row");
      const label = element("span", null, (progress.won ? "✓ " : "▶ ") + displayName(level));
      label.title = level.path;
      const actions = element("span", "gd-actions");
      const date = progress.time ? new Date(progress.time).toLocaleDateString() : "";
      actions.append(element("span", "gd-muted", date),
        button(zh ? "开始" : "Play", function () { play(level); }, "gd-primary"));
      row.append(label, actions);
      state.list.appendChild(row);
    }
    if (!folders.size && !levels.length) {
      state.list.appendChild(element("div", "gd-muted", state.loading
        ? (zh ? "正在获取关卡列表…" : "Fetching the level list…")
        : (zh ? "没有关卡。" : "No levels.")));
    }
    if (state.busy) setBusy(true);
  }

  // Tells the game which played levels changed upstream so it drops their
  // stale progress, as the desktop window does.
  async function invalidateChanged(levels) {
    const played = playedShas();
    const latest = new Map(levels.map(function (level) { return [level.path, level.sha]; }));
    const changed = Object.keys(played).filter(function (path) { return latest.get(path) !== played[path]; });
    for (const path of changed) delete played[path];
    storageSet(playedShaKey, played);
    if (!changed.length) return;
    dialogs.github.changed(changed);
    if (state) for (const path of changed) delete state.progress[path];
    const api = window.electronAPI;
    if (typeof api.removeLevel !== "function") return;
    for (const path of changed) {
      try { await api.removeLevel(path); } catch (error) {
        console.warn("[GardendlessLoader] GitHub level cache removal failed:", path, error);
      }
    }
  }

  async function refresh() {
    if (!state || state.loading) return;
    const current = state;
    const zh = current.zh;
    current.loading = true;
    current.refreshButton.disabled = true;
    setStatus(zh ? "正在获取关卡列表…" : "Fetching the level list…");
    if (!current.levels.length) render();
    try {
      const json = await fetchJson(treeUrl);
      if (!json || !Array.isArray(json.tree)) throw new Error(zh ? "关卡列表格式无效" : "Invalid level list");
      const levels = [];
      for (const entry of json.tree) {
        if (!entry || entry.type !== "blob" || typeof entry.sha !== "string" ||
            !validLevelPath(entry.path)) continue;
        levels.push({path: entry.path, sha: entry.sha, url: levelUrl(entry.path, entry.url)});
      }
      storageSet(listKey, {levels: levels, fetchedAt: Date.now()});
      await invalidateChanged(levels);
      if (state !== current) return;
      current.levels = levels;
      setStatus(zh ? "共 " + levels.length + " 个关卡。" : levels.length + " levels.");
    } catch (error) {
      if (state !== current) return;
      setStatus(current.levels.length
        ? (zh ? "无法连接，显示上次获取的列表。" : "Offline; showing the last list.") + "\n" + errorText(error)
        : (zh ? "无法获取关卡列表：" : "Could not fetch the level list: ") + errorText(error));
    } finally {
      current.loading = false;
      if (state === current) {
        current.refreshButton.disabled = false;
        render();
      }
    }
  }

  async function play(level) {
    if (!state || state.busy) return;
    const current = state;
    const zh = current.zh;
    setBusy(true);
    setStatus(zh ? "正在载入关卡…" : "Loading the level…");
    try {
      const api = window.electronAPI;
      const played = playedShas();
      let levelData = null;
      if (played[level.path] === level.sha && typeof api.loadLevel === "function") {
        try {
          const cached = await api.loadLevel(level.path);
          const parsed = cached ? JSON.parse(cached) : null;
          if (parsed && Array.isArray(parsed.LevelData) && parsed.LevelData.length) levelData = parsed.LevelData;
        } catch (_) { /* Download it again. */ }
      }
      if (!levelData) {
        const json = await fetchJson(level.url);
        const objects = json && (Array.isArray(json.objects) ? json.objects : json.LevelData);
        if (!Array.isArray(objects) || !objects.length) throw new Error(zh ? "关卡数据无效" : "Invalid level data");
        levelData = objects;
      }
      if (typeof api.saveLevel === "function" && dialogs.github.hasPlayListener()) {
        await api.saveLevel(level.path, JSON.stringify({LevelData: levelData,
          Path: level.path.split("/"), Name: level.path}));
        played[level.path] = level.sha;
        storageSet(playedShaKey, played);
        dialogs.github.play(level.path);
      } else if (dialogs.github.hasContentListener()) {
        dialogs.github.playContent(JSON.stringify({LevelData: levelData}));
      } else {
        throw new Error(zh ? "游戏还没有准备好打开 GitHub 关卡" : "The game is not ready for GitHub levels");
      }
      // The game closes this window once the level starts.
      if (state === current) setStatus(zh ? "正在进入关卡…" : "Starting the level…");
    } catch (error) {
      if (state === current) setStatus((zh ? "无法开始关卡：" : "Could not start the level: ") + errorText(error));
    } finally {
      if (state === current) setBusy(false);
    }
  }

  function openRepository() {
    const api = window.electronAPI;
    try {
      if (typeof api.openUrl === "function") {
        const result = api.openUrl(repositoryUrl);
        if (result && typeof result.catch === "function") result.catch(function () {});
        return;
      }
    } catch (_) { /* Fall through. */ }
    window.open(repositoryUrl, "_blank");
  }

  function openGithubWindow(progress, language, levelNames) {
    if (state) {
      state.progress = progress && typeof progress === "object" ? progress : {};
      render();
      return;
    }
    const zh = language === "zh";
    const parts = dialogs.createDialog(zh ? "GitHub 关卡" : "GitHub levels", zh ? "关闭" : "Close");
    const element = dialogs.element;
    const refreshButton = dialogs.button(zh ? "刷新" : "Refresh", function () { refresh(); });
    const headerActions = element("span", "gd-actions");
    headerActions.append(refreshButton, parts.closeButton);
    parts.header.appendChild(headerActions);
    const nav = element("div", "gd-actions");
    nav.style.justifyContent = "flex-start";
    const status = element("div", "gd-status");
    const list = element("div");
    parts.body.append(nav, status, list);
    const footer = element("div", "gd-footer");
    footer.appendChild(dialogs.button(zh ? "在浏览器中打开关卡仓库" : "Open the level repository", openRepository));
    parts.dialog.appendChild(footer);

    const folder = storageGet(folderKey, []);
    state = {
      parts: parts, zh: zh, nav: nav, status: status, list: list, refreshButton: refreshButton,
      progress: progress && typeof progress === "object" ? progress : {},
      names: levelNames && typeof levelNames === "object" ? levelNames : {},
      folder: Array.isArray(folder) && folder.every(function (part) { return typeof part === "string" && part; })
        ? folder : [],
      levels: cachedLevels(), busy: false, loading: false
    };
    const opened = state;
    parts.dialog.addEventListener("close", function () {
      if (state === opened) state = null;
    }, {once: true});
    dialogs.show(parts.dialog);
    render();
    refresh();
  }

  dialogs.defineShims({
    openGithubWindow: openGithubWindow,
    closeGithubWindow: function () { if (state) state.parts.dialog.close(); },
    isGithubWindowOpen: function () { return state !== null; }
  });
})();
