const gardendlessExportDownloadHandlerName = 'gardendlessDownloadExport';

const gardendlessExportDownloadPatchSource = r'''
(function () {
  const installedKey = "__gardendlessLoaderExportDownloadPatchInstalled";
  if (window[installedKey]) {
    return;
  }
  Object.defineProperty(window, installedKey, {
    value: true,
    configurable: false,
    enumerable: false,
    writable: false
  });

  const handlerName = "gardendlessDownloadExport";
  const pendingPayloads = [];
  const objectUrlBlobs = new Map();

  function bridgeReady() {
    return !!(
      window.flutter_inappwebview &&
      typeof window.flutter_inappwebview.callHandler === "function"
    );
  }

  function trySendToFlutter(payload) {
    if (bridgeReady()) {
      try {
        window.flutter_inappwebview.callHandler(handlerName, payload).catch(function () {});
        return true;
      } catch (_) {}
    }
    return false;
  }

  function sendToFlutter(payload) {
    if (!payload) {
      return;
    }

    if (!trySendToFlutter(payload)) {
      pendingPayloads.push(payload);
    }
  }

  function flushPendingPayloads() {
    if (!bridgeReady() || pendingPayloads.length === 0) {
      return;
    }
    const payloads = pendingPayloads.splice(0);
    for (const payload of payloads) {
      if (!trySendToFlutter(payload)) {
        pendingPayloads.push(payload);
      }
    }
  }

  window.addEventListener("flutterInAppWebViewPlatformReady", flushPendingPayloads);

  function isBlob(value) {
    return typeof Blob !== "undefined" && value instanceof Blob;
  }

  function rememberObjectUrl(url, value) {
    if (typeof url === "string" && isBlob(value)) {
      objectUrlBlobs.set(url, value);
    }
  }

  function forgetObjectUrlLater(url) {
    if (typeof url !== "string") {
      return;
    }
    setTimeout(function () {
      objectUrlBlobs.delete(url);
    }, 60000);
  }

  function patchUrlApi(urlApi) {
    if (!urlApi || urlApi.__gardendlessLoaderExportPatched) {
      return;
    }

    const originalCreateObjectURL = urlApi.createObjectURL;
    if (typeof originalCreateObjectURL === "function") {
      urlApi.createObjectURL = function (value) {
        const url = originalCreateObjectURL.apply(this, arguments);
        rememberObjectUrl(url, value);
        return url;
      };
    }

    const originalRevokeObjectURL = urlApi.revokeObjectURL;
    if (typeof originalRevokeObjectURL === "function") {
      urlApi.revokeObjectURL = function (url) {
        forgetObjectUrlLater(url);
        return originalRevokeObjectURL.apply(this, arguments);
      };
    }

    Object.defineProperty(urlApi, "__gardendlessLoaderExportPatched", {
      value: true,
      configurable: false,
      enumerable: false,
      writable: false
    });
  }

  patchUrlApi(window.URL);
  patchUrlApi(window.webkitURL);

  function readBlobAsDataUrl(blob) {
    return new Promise(function (resolve, reject) {
      const reader = new FileReader();
      reader.onloadend = function () {
        resolve(String(reader.result || ""));
      };
      reader.onerror = function () {
        reject(reader.error || new Error("Cannot read exported Blob"));
      };
      reader.readAsDataURL(blob);
    });
  }

  function anchorHref(anchor) {
    return anchor.href || anchor.getAttribute("href") || "";
  }

  function anchorFilename(anchor) {
    return anchor.download || anchor.getAttribute("download") || null;
  }

  function shouldHandleAnchor(anchor) {
    if (!anchor) {
      return false;
    }
    const href = anchorHref(anchor);
    if (!href) {
      return false;
    }
    const lowerHref = href.toLowerCase();
    return (
      anchor.hasAttribute("download") ||
      !!anchorFilename(anchor) ||
      lowerHref.startsWith("blob:") ||
      lowerHref.startsWith("data:")
    );
  }

  async function exportAnchor(anchor) {
    const href = anchorHref(anchor);
    const lowerHref = href.toLowerCase();
    const suggestedFilename = anchorFilename(anchor);

    try {
      if (lowerHref.startsWith("blob:")) {
        const blob = objectUrlBlobs.get(href);
        if (blob) {
          sendToFlutter({
            url: href,
            dataUrl: await readBlobAsDataUrl(blob),
            suggestedFilename: suggestedFilename,
            mimeType: blob.type || null,
            source: "anchor-blob"
          });
          return;
        }
      }

      if (lowerHref.startsWith("data:")) {
        sendToFlutter({
          url: href,
          dataUrl: href,
          suggestedFilename: suggestedFilename,
          mimeType: null,
          source: "anchor-data"
        });
        return;
      }

      sendToFlutter({
        url: href,
        suggestedFilename: suggestedFilename,
        mimeType: null,
        source: "anchor-url"
      });
    } catch (error) {
      sendToFlutter({
        url: href,
        suggestedFilename: suggestedFilename,
        mimeType: null,
        error: String(error),
        source: "anchor-error"
      });
    }
  }

  function beginAnchorExport(anchor) {
    if (!shouldHandleAnchor(anchor)) {
      return false;
    }
    exportAnchor(anchor);
    return true;
  }

  function closestAnchor(target) {
    let node = target;
    while (node) {
      if (node instanceof HTMLAnchorElement) {
        return node;
      }
      node = node.parentElement;
    }
    return null;
  }

  const originalAnchorClick = HTMLAnchorElement.prototype.click;
  if (typeof originalAnchorClick === "function") {
    HTMLAnchorElement.prototype.click = function () {
      if (beginAnchorExport(this)) {
        return;
      }
      return originalAnchorClick.apply(this, arguments);
    };
  }

  document.addEventListener(
    "click",
    function (event) {
      const anchor = closestAnchor(event.target);
      if (!beginAnchorExport(anchor)) {
        return;
      }
      event.preventDefault();
      event.stopImmediatePropagation();
    },
    true
  );
})();
''';
