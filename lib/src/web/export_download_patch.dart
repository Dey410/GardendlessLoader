const gardendlessExportDownloadHandlerName = 'gardendlessDownloadExport';

const gardendlessExportDownloadPatchSource = r'''
(function () {
  const runtimeInstalledKey = "__gardendlessLoaderRuntimeLoggingInstalled";
  if (!window[runtimeInstalledKey]) {
    Object.defineProperty(window, runtimeInstalledKey, {
      value: true,
      configurable: false,
      enumerable: false,
      writable: false
    });

    const runtimeLogEndpoint = "/__gardendless/runtime-log";
    const maxTextLength = 4000;
    let reportingRuntimeLog = false;

    function limitedText(value) {
      let text;
      try {
        if (value instanceof Error) {
          text = value.stack || value.message || String(value);
        } else if (typeof value === "string") {
          text = value;
        } else {
          text = JSON.stringify(value);
        }
      } catch (_) {
        try {
          text = String(value);
        } catch (_) {
          text = "<unprintable>";
        }
      }
      if (typeof text !== "string") {
        text = String(text);
      }
      return text.length <= maxTextLength
        ? text
        : text.slice(0, maxTextLength) + "…";
    }

    function reportRuntimeLog(payload) {
      if (reportingRuntimeLog || !payload) {
        return;
      }
      reportingRuntimeLog = true;
      try {
        const normalized = {
          level: limitedText(payload.level || "ERROR"),
          type: limitedText(payload.type || "runtime"),
          message: limitedText(payload.message || "Web runtime event"),
          source: limitedText(payload.source || location.pathname || "-"),
          line: Number.isFinite(payload.line) ? payload.line : null,
          column: Number.isFinite(payload.column) ? payload.column : null,
          stack: payload.stack ? limitedText(payload.stack) : null,
          page: limitedText(location.pathname || "/")
        };
        fetch(runtimeLogEndpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(normalized),
          cache: "no-store",
          credentials: "same-origin",
          keepalive: true
        }).catch(function () {});
      } catch (_) {
        // Logging must never break the game runtime.
      } finally {
        reportingRuntimeLog = false;
      }
    }

    window.addEventListener("error", function (event) {
      const target = event.target;
      const isResourceError = target && target !== window;
      reportRuntimeLog({
        level: "ERROR",
        type: isResourceError ? "resource-error" : "javascript-error",
        message: isResourceError
          ? "Failed to load " + limitedText(target.src || target.href || target.tagName)
          : limitedText(event.message || event.error || "Unknown JavaScript error"),
        source: event.filename || (target && (target.src || target.href)) || location.pathname,
        line: event.lineno,
        column: event.colno,
        stack: event.error && event.error.stack
      });
    }, true);

    window.addEventListener("unhandledrejection", function (event) {
      const reason = event.reason;
      reportRuntimeLog({
        level: "ERROR",
        type: "unhandled-promise-rejection",
        message: limitedText(reason || "Unhandled Promise rejection"),
        source: location.pathname,
        stack: reason && reason.stack
      });
    });

    if (window.console) {
      ["warn", "error"].forEach(function (method) {
        const original = window.console[method];
        if (typeof original !== "function") {
          return;
        }
        window.console[method] = function () {
          const args = Array.prototype.slice.call(arguments);
          reportRuntimeLog({
            level: method === "error" ? "ERROR" : "WARN",
            type: "console-" + method,
            message: args.map(limitedText).join(" "),
            source: location.pathname,
            stack: method === "error" ? (new Error()).stack : null
          });
          return original.apply(this, arguments);
        };
      });
    }

    reportRuntimeLog({
      level: "INFO",
      type: "runtime-logging-ready",
      message: "Web runtime logging installed",
      source: location.pathname
    });
  }

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
