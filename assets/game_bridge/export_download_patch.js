(function () {
  "use strict";
  if (window.__gardendlessLoaderExportDownloadPatchInstalled) return;
  window.__gardendlessLoaderExportDownloadPatchInstalled = true;
  const objectUrlBlobs = new Map();

  function patchUrlApi(api) {
    if (!api || api.__gardendlessLoaderExportPatched) return;
    const create = api.createObjectURL;
    const revoke = api.revokeObjectURL;
    if (typeof create === "function") api.createObjectURL = function (value) {
      const url = create.apply(this, arguments);
      if (typeof Blob !== "undefined" && value instanceof Blob) objectUrlBlobs.set(url, value);
      return url;
    };
    if (typeof revoke === "function") api.revokeObjectURL = function (url) {
      objectUrlBlobs.delete(url);
      return revoke.apply(this, arguments);
    };
    api.__gardendlessLoaderExportPatched = true;
  }

  patchUrlApi(window.URL);
  patchUrlApi(window.webkitURL);
  window.addEventListener("pagehide", function () { objectUrlBlobs.clear(); }, {once: true});

  function href(anchor) { return anchor.href || anchor.getAttribute("href") || ""; }
  function filename(anchor) { return anchor.download || anchor.getAttribute("download") || null; }
  function shouldHandle(anchor) {
    if (!anchor) return false;
    const url = href(anchor).toLowerCase();
    return !!url && (anchor.hasAttribute("download") || !!filename(anchor) || url.startsWith("blob:") || url.startsWith("data:"));
  }

  async function exportAnchor(anchor) {
    const url = href(anchor);
    const lower = url.toLowerCase();
    const transport = window.__gardendlessTransport;
    if (!transport || typeof transport.writeFile !== "function") throw new Error("Native file transport is unavailable");
    const name = filename(anchor);
    let blob;
    if (lower.startsWith("blob:")) {
      blob = objectUrlBlobs.get(url);
      if (!blob) throw new Error("Export Blob URL is unavailable");
    } else if (lower.startsWith("data:")) {
      blob = await (await fetch(url)).blob();
    } else {
      return transport.invoke("host:export", {url: url, suggestedFilename: name});
    }
    return transport.writeFile(blob, {destination: "export", suggestedFilename: name,
      mimeType: blob.type || "application/octet-stream"});
  }

  function begin(anchor) {
    if (!shouldHandle(anchor)) return false;
    exportAnchor(anchor).catch(function (error) {
      console.error("[GardendlessLoader] File export failed:", error);
    });
    return true;
  }

  const originalClick = HTMLAnchorElement.prototype.click;
  if (typeof originalClick === "function") HTMLAnchorElement.prototype.click = function () {
    if (!begin(this)) return originalClick.apply(this, arguments);
  };
  document.addEventListener("click", function (event) {
    let target = event.target;
    while (target && !(target instanceof HTMLAnchorElement)) target = target.parentElement;
    if (!begin(target)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  }, true);
})();
