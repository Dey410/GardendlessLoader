(function () {
  "use strict";
  if (window.__gardendlessLoggingInstalled) return;
  window.__gardendlessLoggingInstalled = true;

  const recent = new Map();
  let windowStartedAt = Date.now();
  let emittedInWindow = 0;

  function text(value) {
    if (value instanceof Error) return value.message || String(value);
    if (typeof value === "string") return value;
    try { return JSON.stringify(value); } catch (_) { return String(value); }
  }

  function emit(event, level, message, details) {
    const now = Date.now();
    if (now - windowStartedAt >= 60000) {
      windowStartedAt = now;
      emittedInWindow = 0;
      recent.clear();
    }
    if (emittedInWindow >= 60) return;
    const fingerprint = event + "|" + message + "|" + String(details && details.line || 0);
    const previous = recent.get(fingerprint) || 0;
    if (now - previous < 10000) return;
    recent.set(fingerprint, now);
    emittedInWindow += 1;
    const host = window.__gardendlessHost;
    if (!host || typeof host.invoke !== "function") return;
    host.invoke("host:log", {
      args: {
        event: event,
        level: level,
        message: String(message || "").slice(0, 4096),
        stack: String(details && details.stack || "").slice(0, 8192),
        page: String(location.pathname || "/").slice(0, 1024),
        line: Number(details && details.line || 0),
        column: Number(details && details.column || 0)
      }
    }).catch(function () {});
  }

  window.addEventListener("error", function (event) {
    emit("javascript_uncaught_error", "ERROR", event.message, {
      stack: event.error && event.error.stack,
      line: event.lineno,
      column: event.colno
    });
  });

  window.addEventListener("unhandledrejection", function (event) {
    const reason = event.reason;
    emit("javascript_unhandled_rejection", "ERROR", text(reason), {
      stack: reason && reason.stack
    });
  });

  ["warn", "error"].forEach(function (name) {
    const original = console[name];
    console[name] = function () {
      const values = Array.prototype.slice.call(arguments);
      try {
        emit("javascript_console", name === "error" ? "ERROR" : "WARN",
          values.map(text).join(" "), {});
      } catch (_) {}
      return original.apply(console, values);
    };
  });
})();
