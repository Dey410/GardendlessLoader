(function () {
  if (window.__gardendlessTouchInputInstalled) {
    return;
  }
  window.__gardendlessTouchInputInstalled = true;

  const config = window.__gardendlessHostConfig || {};
  const frameSynchronizedJavascript = config.touchAdapter === "javascript";
  const diagnosticsEnabled = config.touchDiagnosticsEnabled === true;
  const touchActionStyleId = "gardendless-touch-action";
  const backdropMoveThreshold = 20;
  const backdropTapMaxDuration = 250;
  const backdropDoubleTapMaxDelay = 300;
  const backdropDoubleTapMaxDistance = 24;
  const dragCommitMinimumDelayMilliseconds = 50;
  const dragCommitMinimumFrames = 2;
  const wheelCssMultiplier = Number.isFinite(config.touchWheelCssMultiplier)
    ? config.touchWheelCssMultiplier
    : -4.5;
  const traceEntries = [];
  let owner = "idle";
  let backdropStartedAt = null;
  let backdropStartPoint = null;
  let backdropMoved = false;
  let backdropHadMultipleFingers = false;
  let lastBackdropTapAt = null;
  let lastBackdropTapPoint = null;
  let primaryCanvas = null;
  let primaryStartPoint = null;
  let primaryDownFrame = null;
  let primaryMoveFrame = null;
  let pendingPrimaryMovePoint = null;
  let primaryDownDispatched = false;
  let primaryMoved = false;
  let pendingPrimaryUpPoint = null;
  let pendingPrimaryUp = null;

  function recordTrace(entry) {
    if (!diagnosticsEnabled) {
      return;
    }
    traceEntries.push(Object.assign({
      sequence: traceEntries.length + 1,
      platform: String(config.platform || "unknown")
    }, entry));
    if (traceEntries.length > 256) {
      traceEntries.shift();
    }
  }

  if (diagnosticsEnabled) {
    window.__gardendlessTouchDiagnostics = Object.freeze({
      snapshot: function () {
        return traceEntries.map(function (entry) {
          return JSON.parse(JSON.stringify(entry));
        });
      }
    });
  }

  function reportFailure(code) {
    recordTrace({event: "touch_failure", code: code});
    const host = window.__gardendlessHost;
    if (!host || typeof host.invoke !== "function") {
      return;
    }
    try {
      const pending = host.invoke("host:log", {
        args: {
          event: "touch_input_failed",
          level: "ERROR",
          message: code,
          stack: "",
          page: "",
          line: 0,
          column: 0
        }
      });
      if (pending && typeof pending.catch === "function") {
        pending.catch(function () {});
      }
    } catch (_) {}
  }

  const module = window.__gardendlessTouchStateMachine;
  let machine = null;
  let machineFailureCode = "touch_state_machine_unavailable";
  if (module && typeof module.create === "function") {
    try {
      machine = module.create({
        trace: function (entry) {
          recordTrace(Object.assign({event: "touch_transition"}, entry));
        }
      });
    } catch (_) {
      machineFailureCode = "touch_state_machine_create_failed";
    }
  }
  if (!machine) {
    reportFailure(machineFailureCode);
  }

  function installTouchActionStyle() {
    if (document.getElementById(touchActionStyleId)) {
      return;
    }
    const parent = document.head || document.documentElement;
    if (!parent) {
      document.addEventListener("DOMContentLoaded", installTouchActionStyle, {
        once: true
      });
      return;
    }
    const style = document.createElement("style");
    style.id = touchActionStyleId;
    style.textContent =
      "#GameDiv, #Cocos3dGameContainer, #GameCanvas {" +
      " touch-action: none !important; }";
    parent.appendChild(style);
  }

  function gameCanvas() {
    const canvas = document.getElementById("GameCanvas");
    return canvas && canvas.isConnected !== false ? canvas : null;
  }

  function isNativeTouchTarget(target) {
    let current = target;
    while (current && current !== document) {
      if (current.id === "gp-overlay" || current.id === "ge-toast-wrap") {
        return true;
      }
      const className = typeof current.className === "string"
        ? current.className
        : "";
      if (className.split(/\s+/).includes("gp-f1-hint")) {
        return true;
      }
      const tagName = typeof current.tagName === "string"
        ? current.tagName.toUpperCase()
        : "";
      if (tagName === "INPUT" || tagName === "TEXTAREA" ||
          tagName === "SELECT" || current.isContentEditable === true) {
        return true;
      }
      if (typeof current.getAttribute === "function") {
        const editable = current.getAttribute("contenteditable");
        if (editable !== null && editable !== "false") {
          return true;
        }
      }
      current = current.parentElement;
    }
    return false;
  }

  function isGpNextOpen() {
    const overlay = document.getElementById("gp-overlay");
    return !!(overlay && overlay.classList &&
      overlay.classList.contains("gp-open"));
  }

  function pointFromTouch(touch) {
    return {
      id: Number(touch.identifier),
      screenX: Number(touch.screenX),
      screenY: Number(touch.screenY),
      clientX: Number(touch.clientX),
      clientY: Number(touch.clientY)
    };
  }

  function pointsFrom(list) {
    return Array.from(list || [], pointFromTouch);
  }

  function firstChangedTouch(event) {
    return event.changedTouches && event.changedTouches.length > 0
      ? event.changedTouches[0]
      : null;
  }

  function eventTarget(event) {
    const changed = firstChangedTouch(event);
    return changed && changed.target
      ? changed.target
      : event.target;
  }

  function pixelRatio() {
    const value = Number(window.devicePixelRatio);
    return Number.isFinite(value) && value > 0 ? value : 1;
  }

  function mouseEvent(type, point, button, buttons) {
    return new MouseEvent(type, {
      bubbles: true,
      cancelable: true,
      view: window,
      detail: 1,
      screenX: point.screenX,
      screenY: point.screenY,
      clientX: point.clientX,
      clientY: point.clientY,
      ctrlKey: false,
      altKey: false,
      shiftKey: false,
      metaKey: false,
      button: button,
      buttons: buttons,
      relatedTarget: null
    });
  }

  function dispatchMouse(canvas, type, point, button, buttons) {
    canvas.dispatchEvent(mouseEvent(type, point, button, buttons));
  }

  function clearPrimaryGestureState() {
    if (primaryMoveFrame !== null) {
      cancelAnimationFrame(primaryMoveFrame);
    }
    primaryCanvas = null;
    primaryStartPoint = null;
    primaryDownFrame = null;
    primaryMoveFrame = null;
    pendingPrimaryMovePoint = null;
    primaryDownDispatched = false;
    primaryMoved = false;
    pendingPrimaryUpPoint = null;
  }

  function finishPendingPrimaryUp() {
    if (!pendingPrimaryUp) {
      return;
    }
    const pending = pendingPrimaryUp;
    pendingPrimaryUp = null;
    cancelAnimationFrame(pending.frame);
    if (!pending.upDispatched) {
      dispatchMouse(pending.canvas, "mouseup", pending.point, 0, 1);
    }
  }

  function cancelJavascriptPrimary() {
    if (primaryDownFrame !== null) {
      cancelAnimationFrame(primaryDownFrame);
    }
    if (pendingPrimaryUp) {
      cancelAnimationFrame(pendingPrimaryUp.frame);
      pendingPrimaryUp = null;
    }
    clearPrimaryGestureState();
  }

  function updatePrimaryMoved(point) {
    if (!primaryStartPoint) {
      return;
    }
    const deltaX = point.clientX - primaryStartPoint.clientX;
    const deltaY = point.clientY - primaryStartPoint.clientY;
    primaryMoved = primaryMoved ||
      Math.hypot(deltaX, deltaY) * pixelRatio() > backdropMoveThreshold;
  }

  function scheduleDraggedPrimaryCommit(pending) {
    pending.frame = requestAnimationFrame(function () {
      if (pendingPrimaryUp !== pending) {
        return;
      }
      pending.framesAfterUp += 1;
      const elapsed = performance.now() - pending.upDispatchedAt;
      if (pending.framesAfterUp < dragCommitMinimumFrames ||
          elapsed < dragCommitMinimumDelayMilliseconds) {
        scheduleDraggedPrimaryCommit(pending);
        return;
      }
      pendingPrimaryUp = null;
      dispatchMouse(pending.canvas, "mousedown", pending.point, 0, 1);
      dispatchMouse(pending.canvas, "mouseup", pending.point, 0, 1);
    });
  }

  function releaseJavascriptPrimary(point) {
    if (!primaryCanvas) {
      return;
    }
    if (primaryMoveFrame !== null) {
      cancelAnimationFrame(primaryMoveFrame);
      primaryMoveFrame = null;
      pendingPrimaryMovePoint = null;
    }
    if (!primaryDownDispatched) {
      pendingPrimaryUpPoint = point;
      return;
    }
    const canvas = primaryCanvas;
    updatePrimaryMoved(point);
    if (!primaryMoved) {
      dispatchMouse(canvas, "mouseup", point, 0, 1);
      clearPrimaryGestureState();
      return;
    }
    dispatchMouse(canvas, "mousemove", point, 0, 1);
    clearPrimaryGestureState();
    const pending = {
      canvas: canvas,
      frame: null,
      point: point,
      upDispatched: false,
      upDispatchedAt: null,
      framesAfterUp: 0
    };
    pending.frame = requestAnimationFrame(function () {
      if (pendingPrimaryUp !== pending) {
        return;
      }
      dispatchMouse(canvas, "mouseup", point, 0, 1);
      pending.upDispatched = true;
      pending.upDispatchedAt = performance.now();
      scheduleDraggedPrimaryCommit(pending);
    });
    pendingPrimaryUp = pending;
  }

  function beginJavascriptPrimary(canvas, point) {
    finishPendingPrimaryUp();
    cancelJavascriptPrimary();
    primaryCanvas = canvas;
    primaryStartPoint = point;
    primaryMoved = false;
    dispatchMouse(canvas, "mousemove", point, 0, 0);
    primaryDownFrame = requestAnimationFrame(function () {
      primaryDownFrame = requestAnimationFrame(function () {
        primaryDownFrame = null;
        if (!primaryCanvas) {
          return;
        }
        dispatchMouse(primaryCanvas, "mousedown", point, 0, 1);
        primaryDownDispatched = true;
        if (pendingPrimaryUpPoint) {
          const upPoint = pendingPrimaryUpPoint;
          pendingPrimaryUpPoint = null;
          releaseJavascriptPrimary(upPoint);
        }
      });
    });
  }

  function moveJavascriptPrimary(point) {
    if (!primaryCanvas) {
      return;
    }
    updatePrimaryMoved(point);
    pendingPrimaryMovePoint = point;
    if (primaryMoveFrame !== null) {
      return;
    }
    primaryMoveFrame = requestAnimationFrame(function () {
      primaryMoveFrame = null;
      const pendingPoint = pendingPrimaryMovePoint;
      pendingPrimaryMovePoint = null;
      if (!primaryCanvas || !pendingPoint) {
        return;
      }
      dispatchMouse(
        primaryCanvas,
        "mousemove",
        pendingPoint,
        0,
        primaryDownDispatched ? 1 : 0
      );
    });
  }

  function executeCommands(commands) {
    const canvas = gameCanvas();
    if (!canvas) {
      cancelJavascriptPrimary();
      owner = "failed";
      reportFailure("touch_target_missing");
      return;
    }
    for (const command of commands) {
      recordTrace({
        event: "touch_output",
        command: command.type,
        x: command.point && command.point.clientX,
        y: command.point && command.point.clientY
      });
      if (command.type === "primaryDown") {
        if (frameSynchronizedJavascript) {
          beginJavascriptPrimary(canvas, command.point);
        } else {
          dispatchMouse(canvas, "mousedown", command.point, 0, 1);
        }
      } else if (command.type === "primaryMove") {
        if (frameSynchronizedJavascript) {
          moveJavascriptPrimary(command.point);
        } else {
          dispatchMouse(canvas, "mousemove", command.point, 0, 1);
        }
      } else if (command.type === "primaryUp") {
        if (frameSynchronizedJavascript) {
          releaseJavascriptPrimary(command.point);
        } else {
          dispatchMouse(canvas, "mouseup", command.point, 0, 1);
        }
      } else if (command.type === "neutralMove") {
        cancelJavascriptPrimary();
        dispatchMouse(canvas, "mousemove", command.point, 0, 0);
      } else if (command.type === "secondaryDown") {
        dispatchMouse(canvas, "mousedown", command.point, 2, 2);
      } else if (command.type === "secondaryUp") {
        dispatchMouse(canvas, "mouseup", command.point, 2, 0);
      } else if (command.type === "scroll") {
        const deltaY = command.physicalDeltaY / pixelRatio() *
          wheelCssMultiplier;
        canvas.dispatchEvent(new WheelEvent("wheel", {
          deltaY: deltaY,
          deltaMode: 0,
          bubbles: true,
          cancelable: true,
          screenX: command.point.screenX,
          screenY: command.point.screenY,
          clientX: command.point.clientX,
          clientY: command.point.clientY,
          relatedTarget: null
        }));
      }
    }
  }

  function handleGameEvent(phase, event) {
    if (!machine) {
      owner = "failed";
      return;
    }
    try {
      if (phase === "cancel") {
        cancelJavascriptPrimary();
      }
      const input = {
        phase: phase,
        points: pointsFrom(event.touches),
        changedPoints: pointsFrom(event.changedTouches),
        time: performance.now(),
        physicalPixelRatio: pixelRatio()
      };
      recordTrace({
        event: "touch_input",
        phase: phase,
        pointerCount: input.points.length,
        points: input.points.map(function (point) {
          return {id: point.id, x: point.clientX, y: point.clientY};
        })
      });
      executeCommands(machine.handle(input));
    } catch (_) {
      cancelJavascriptPrimary();
      owner = "failed";
      reportFailure("touch_adapter_execution_failed");
    }
  }

  function resetBackdropTouch() {
    backdropStartedAt = null;
    backdropStartPoint = null;
    backdropMoved = false;
    backdropHadMultipleFingers = false;
  }

  function resetBackdropCandidate() {
    lastBackdropTapAt = null;
    lastBackdropTapPoint = null;
  }

  function registerBackdropTap(point) {
    const now = performance.now();
    const doubleTap = lastBackdropTapAt !== null && lastBackdropTapPoint &&
      now - lastBackdropTapAt <= backdropDoubleTapMaxDelay &&
      Math.hypot(
        point.clientX - lastBackdropTapPoint.clientX,
        point.clientY - lastBackdropTapPoint.clientY
      ) <= backdropDoubleTapMaxDistance;
    if (doubleTap) {
      resetBackdropCandidate();
      if (isGpNextOpen() && window.gpNext &&
          typeof window.gpNext.hide === "function") {
        window.gpNext.hide();
      }
      return;
    }
    lastBackdropTapAt = now;
    lastBackdropTapPoint = point;
  }

  function consume(event) {
    event.preventDefault();
    event.stopImmediatePropagation();
  }

  document.addEventListener("touchstart", function (event) {
    if (owner === "native") {
      return;
    }
    if (owner === "backdrop") {
      if (event.touches.length > 1) {
        backdropHadMultipleFingers = true;
      }
      consume(event);
      return;
    }
    if (owner === "game" || owner === "failed") {
      if (owner === "game") {
        handleGameEvent("start", event);
      }
      consume(event);
      return;
    }

    const target = eventTarget(event);
    if (event.touches.length === 1 && isNativeTouchTarget(target)) {
      owner = "native";
      resetBackdropCandidate();
      recordTrace({event: "touch_owner", owner: owner});
      return;
    }
    if (event.touches.length === 1 && isGpNextOpen()) {
      owner = "backdrop";
      backdropStartedAt = performance.now();
      backdropStartPoint = pointFromTouch(firstChangedTouch(event));
      backdropMoved = false;
      backdropHadMultipleFingers = false;
      recordTrace({event: "touch_owner", owner: owner});
      consume(event);
      return;
    }
    if (!gameCanvas() || !machine) {
      owner = "failed";
      reportFailure(!machine
        ? "touch_state_machine_unavailable"
        : "touch_target_missing");
      consume(event);
      return;
    }
    owner = "game";
    recordTrace({event: "touch_owner", owner: owner});
    handleGameEvent("start", event);
    consume(event);
  }, {capture: true, passive: false});

  document.addEventListener("touchmove", function (event) {
    if (owner === "native" || owner === "idle") {
      return;
    }
    if (owner === "backdrop") {
      const changed = firstChangedTouch(event);
      if (changed && backdropStartPoint && Math.hypot(
        changed.clientX - backdropStartPoint.clientX,
        changed.clientY - backdropStartPoint.clientY
      ) > backdropMoveThreshold) {
        backdropMoved = true;
      }
      consume(event);
      return;
    }
    if (owner === "game") {
      handleGameEvent("move", event);
    }
    consume(event);
  }, {capture: true, passive: false});

  function finishTouch(phase, event) {
    if (owner === "native") {
      if (event.touches.length === 0) {
        owner = "idle";
      }
      return;
    }
    if (owner === "idle") {
      if (phase === "cancel" && !isNativeTouchTarget(eventTarget(event))) {
        consume(event);
      }
      return;
    }
    if (owner === "backdrop") {
      if (event.touches.length === 0) {
        const duration = backdropStartedAt === null
          ? Infinity
          : performance.now() - backdropStartedAt;
        if (phase === "end" && backdropStartPoint && !backdropMoved &&
            !backdropHadMultipleFingers &&
            duration <= backdropTapMaxDuration) {
          registerBackdropTap(backdropStartPoint);
        } else {
          resetBackdropCandidate();
        }
        resetBackdropTouch();
        owner = "idle";
      }
      consume(event);
      return;
    }
    if (owner === "game") {
      handleGameEvent(phase, event);
    }
    consume(event);
    if (event.touches.length === 0 || phase === "cancel") {
      owner = "idle";
    }
  }

  document.addEventListener("touchend", function (event) {
    finishTouch("end", event);
  }, {capture: true, passive: false});
  document.addEventListener("touchcancel", function (event) {
    finishTouch("cancel", event);
  }, {capture: true, passive: false});

  function interrupt() {
    cancelJavascriptPrimary();
    if (owner === "game" && machine) {
      try {
        executeCommands(machine.handle({
          phase: "cancel",
          points: [],
          changedPoints: [],
          time: performance.now(),
          physicalPixelRatio: pixelRatio()
        }));
      } catch (_) {
        owner = "failed";
        reportFailure("touch_adapter_execution_failed");
      }
    }
    owner = "idle";
    resetBackdropTouch();
  }

  window.addEventListener("blur", interrupt);
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) {
      interrupt();
    }
  });
  if (typeof MutationObserver === "function") {
    new MutationObserver(function () {
      if (!gameCanvas()) {
        interrupt();
      }
    }).observe(document.documentElement, {childList: true, subtree: true});
  }

  installTouchActionStyle();
})();
