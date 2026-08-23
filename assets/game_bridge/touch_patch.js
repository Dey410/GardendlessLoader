(function () {
  if (window.__gardendlessTouchPatchInstalled) {
    return;
  }
  window.__gardendlessTouchPatchInstalled = true;

  const touchActionStyleId = "gardendless-touch-action";
  const touchMoveThreshold = 20;
  const twoFingerMoveThresholdPhysicalPixels = 20;
  const touchWheelMultiplier = -4.5;
  const gpNextBackdropTapMaxDuration = 250;
  const gpNextBackdropDoubleTapMaxDelay = 300;
  const gpNextBackdropDoubleTapMaxDistance = 24;
  const nativeSingleTouchMouse =
    window.__gardendlessHostConfig &&
    window.__gardendlessHostConfig.nativeSingleTouchMouse === true;
  let lastWheelY = null;
  let leftMouseActive = false;
  let leftMouseDownDispatched = false;
  let leftMouseTarget = null;
  let leftMouseDownPoint = null;
  let leftMouseMoved = false;
  let pendingLeftMouseDownFrame = null;
  let pendingLeftMouseUpPoint = null;
  let twoFingerStartPoint = null;
  let twoFingerTarget = null;
  let twoFingerMoved = false;
  let nativeTouchActive = false;
  let gpNextBackdropTouchActive = false;
  let gpNextBackdropTouchStartedAt = null;
  let gpNextBackdropTouchStartPoint = null;
  let gpNextBackdropTouchMoved = false;
  let gpNextBackdropTouchHadMultipleFingers = false;
  let lastGpNextBackdropTapAt = null;
  let lastGpNextBackdropTapPoint = null;
  let suppressNativeMouse = false;
  let nativeMouseTraceActive = false;
  let activeTouchTrace = null;
  let nextTouchTraceId = 1;
  let cocosInputTraceInstalled = false;
  let cocosInputTraceInstallStarted = false;

  if (nativeSingleTouchMouse) {
    for (const type of ["mousemove", "mousedown", "mouseup"]) {
      document.addEventListener(type, function (event) {
        if (!suppressNativeMouse) {
          return;
        }
        event.preventDefault();
        event.stopImmediatePropagation();
        if (type === "mouseup") {
          suppressNativeMouse = false;
        }
      }, { capture: true });
    }
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

  installTouchActionStyle();

  function firstChangedTouch(event) {
    return event.changedTouches && event.changedTouches.length > 0
      ? event.changedTouches[0]
      : null;
  }

  function averageTouchPoint(touches) {
    let screenX = 0;
    let screenY = 0;
    let clientX = 0;
    let clientY = 0;

    for (const touch of touches) {
      screenX += touch.screenX;
      screenY += touch.screenY;
      clientX += touch.clientX;
      clientY += touch.clientY;
    }

    const count = touches.length || 1;
    return {
      screenX: screenX / count,
      screenY: screenY / count,
      clientX: clientX / count,
      clientY: clientY / count
    };
  }

  function physicalPixelRatio() {
    const ratio = Number(window.devicePixelRatio);
    return Number.isFinite(ratio) && ratio > 0 ? ratio : 1;
  }

  function touchTarget(touch) {
    if (!touch) {
      return document.getElementById("GameCanvas") || document.body || document;
    }

    return touch.target ||
      document.elementFromPoint(touch.clientX, touch.clientY) ||
      document.getElementById("GameCanvas") ||
      document.body ||
      document;
  }

  function targetAtPoint(point) {
    return document.elementFromPoint(point.clientX, point.clientY) ||
      document.getElementById("GameCanvas") ||
      document.body ||
      document;
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
      if (tagName === "INPUT" ||
          tagName === "TEXTAREA" ||
          tagName === "SELECT") {
        return true;
      }
      if (current.isContentEditable === true) {
        return true;
      }
      if (typeof current.getAttribute === "function") {
        const contentEditable = current.getAttribute("contenteditable");
        if (contentEditable !== null && contentEditable !== "false") {
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

  function resetGpNextBackdropTapCandidate() {
    lastGpNextBackdropTapAt = null;
    lastGpNextBackdropTapPoint = null;
  }

  function resetGpNextBackdropTouchState() {
    gpNextBackdropTouchActive = false;
    gpNextBackdropTouchStartedAt = null;
    gpNextBackdropTouchStartPoint = null;
    gpNextBackdropTouchMoved = false;
    gpNextBackdropTouchHadMultipleFingers = false;
  }

  function registerGpNextBackdropTap(point) {
    const now = performance.now();
    const isDoubleTap = lastGpNextBackdropTapAt !== null &&
      lastGpNextBackdropTapPoint &&
      now - lastGpNextBackdropTapAt <= gpNextBackdropDoubleTapMaxDelay &&
      Math.hypot(
        point.clientX - lastGpNextBackdropTapPoint.clientX,
        point.clientY - lastGpNextBackdropTapPoint.clientY
      ) <= gpNextBackdropDoubleTapMaxDistance;
    if (isDoubleTap) {
      resetGpNextBackdropTapCandidate();
      if (isGpNextOpen() && window.gpNext &&
          typeof window.gpNext.hide === "function") {
        window.gpNext.hide();
      }
      return;
    }

    lastGpNextBackdropTapAt = now;
    lastGpNextBackdropTapPoint = point;
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
      button: button || 0,
      buttons: buttons || 0,
      relatedTarget: null
    });
  }

  function traceNumber(value) {
    return Number.isFinite(value) ? Math.round(value * 10) / 10 : null;
  }

  function traceInput(layer, type, point, button, buttons, phase) {
    if (!activeTouchTrace || activeTouchTrace.events.length >= 80) {
      return;
    }
    activeTouchTrace.events.push({
      at: traceNumber(performance.now() - activeTouchTrace.startedAt),
      layer: layer,
      type: type,
      phase: phase || "gesture",
      x: point ? traceNumber(point.clientX) : null,
      y: point ? traceNumber(point.clientY) : null,
      button: Number.isFinite(button) ? button : null,
      buttons: Number.isFinite(buttons) ? buttons : null
    });
  }

  function finishTouchTrace(completion) {
    if (!activeTouchTrace) {
      return;
    }
    const trace = activeTouchTrace;
    activeTouchTrace = null;
    const logEvent = window.__gardendlessLogEvent;
    if (typeof logEvent !== "function") {
      return;
    }
    logEvent("touch_input_trace", "INFO", JSON.stringify({
      version: 1,
      id: trace.id,
      path: trace.path,
      moved: trace.moved,
      completion: completion,
      cocosHook: cocosInputTraceInstalled,
      events: trace.events
    }), {});
  }

  function finishTouchTraceAfterFrames(completion, remainingFrames, traceId) {
    const expectedTraceId = traceId ||
      (activeTouchTrace && activeTouchTrace.id);
    if (!expectedTraceId) {
      return;
    }
    requestAnimationFrame(function () {
      if (!activeTouchTrace || activeTouchTrace.id !== expectedTraceId) {
        return;
      }
      if (remainingFrames > 1) {
        finishTouchTraceAfterFrames(
          completion,
          remainingFrames - 1,
          expectedTraceId
        );
        return;
      }
      finishTouchTrace(completion);
    });
  }

  function startTouchTrace(point, path) {
    finishTouchTrace("superseded");
    activeTouchTrace = {
      id: nextTouchTraceId++,
      path: path || "shared",
      startedAt: performance.now(),
      moved: false,
      events: []
    };
    traceInput("touch", "touchstart", point, null, null, "gesture");
  }

  function cocosEventPoint(event) {
    return {
      clientX: typeof event.getLocationX === "function"
        ? event.getLocationX() : null,
      clientY: typeof event.getLocationY === "function"
        ? event.getLocationY() : null
    };
  }

  function installCocosInputTrace() {
    if (cocosInputTraceInstalled || cocosInputTraceInstallStarted) {
      return;
    }
    const system = window.System;
    if (!system || typeof system.import !== "function") {
      window.setTimeout(installCocosInputTrace, 100);
      return;
    }
    cocosInputTraceInstallStarted = true;
    system.import("cc").then(function (engine) {
      const input = engine && engine.input;
      const eventTypes = engine && engine.Input && engine.Input.EventType;
      if (!input || typeof input.on !== "function" || !eventTypes) {
        cocosInputTraceInstallStarted = false;
        window.setTimeout(installCocosInputTrace, 100);
        return;
      }
      const types = [
        eventTypes.MOUSE_MOVE,
        eventTypes.MOUSE_DOWN,
        eventTypes.MOUSE_UP
      ];
      for (const type of types) {
        input.on(type, function (event) {
          const button = typeof event.getButton === "function"
            ? event.getButton() : event.button;
          traceInput(
            "cocos",
            type,
            cocosEventPoint(event),
            button,
            null,
            "observed"
          );
        });
      }
      cocosInputTraceInstalled = true;
    }).catch(function () {
      cocosInputTraceInstallStarted = false;
      window.setTimeout(installCocosInputTrace, 250);
    });
  }

  installCocosInputTrace();

  function dispatchMouse(target, type, point, button, buttons, phase) {
    traceInput("dispatch", type, point, button, buttons, phase);
    target.dispatchEvent(mouseEvent(type, point, button, buttons));
  }

  function schedulePlantingClick(target, point) {
    requestAnimationFrame(function () {
      dispatchMouse(target, "mousemove", point, 0, 0, "planting");
      dispatchMouse(target, "mousedown", point, 0, 1, "planting");
      requestAnimationFrame(function () {
        dispatchMouse(target, "mouseup", point, 0, 0, "planting");
        finishTouchTraceAfterFrames("planting_click_completed", 1);
      });
    });
  }

  function resetTwoFingerGesture() {
    lastWheelY = null;
    twoFingerStartPoint = null;
    twoFingerTarget = null;
    twoFingerMoved = false;
  }

  function clearLeftMouseState() {
    leftMouseActive = false;
    leftMouseDownDispatched = false;
    leftMouseTarget = null;
    leftMouseDownPoint = null;
    leftMouseMoved = false;
    pendingLeftMouseDownFrame = null;
    pendingLeftMouseUpPoint = null;
  }

  function beginLeftMouse(target, point) {
    startTouchTrace(point);
    leftMouseActive = true;
    leftMouseTarget = target;
    leftMouseDownPoint = point;
    leftMouseMoved = false;
    pendingLeftMouseUpPoint = null;
    dispatchMouse(target, "mousemove", point, 0, 0);
    pendingLeftMouseDownFrame = requestAnimationFrame(function () {
      pendingLeftMouseDownFrame = null;
      if (!leftMouseTarget || !leftMouseDownPoint) {
        return;
      }
      dispatchMouse(leftMouseTarget, "mousedown", leftMouseDownPoint, 0, 1);
      leftMouseDownDispatched = true;
      if (!leftMouseActive) {
        const upPoint = pendingLeftMouseUpPoint || leftMouseDownPoint;
        const shouldAddPlantingClick = leftMouseMoved;
        dispatchMouse(leftMouseTarget, "mouseup", upPoint, 0, 1);
        if (shouldAddPlantingClick) {
          schedulePlantingClick(leftMouseTarget, upPoint);
        } else {
          finishTouchTraceAfterFrames("tap_completed", 1);
        }
        clearLeftMouseState();
      }
    });
  }

  function releaseLeftMouse(point) {
    if (!leftMouseActive) {
      return;
    }
    leftMouseActive = false;
    if (pendingLeftMouseDownFrame !== null) {
      pendingLeftMouseUpPoint = point;
      return;
    }
    if (!leftMouseDownDispatched) {
      clearLeftMouseState();
      return;
    }
    const target = leftMouseTarget;
    const shouldAddPlantingClick = leftMouseMoved;
    dispatchMouse(target, "mouseup", point, 0, 1);
    if (shouldAddPlantingClick) {
      schedulePlantingClick(target, point);
    } else {
      finishTouchTraceAfterFrames("tap_completed", 1);
    }
    clearLeftMouseState();
  }

  function abandonLeftMouse() {
    if (pendingLeftMouseDownFrame !== null) {
      cancelAnimationFrame(pendingLeftMouseDownFrame);
    }
    finishTouchTrace("abandoned");
    clearLeftMouseState();
  }

  function cancelInteraction() {
    abandonLeftMouse();
    resetTwoFingerGesture();
  }

  document.addEventListener("touchstart", function (event) {
    const changedTouch = firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    const target = touchTarget(changedTouch);

    if (nativeTouchActive) {
      return;
    }

    if (gpNextBackdropTouchActive) {
      if (event.touches.length > 1) {
        gpNextBackdropTouchHadMultipleFingers = true;
      }
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    if (event.touches.length === 1 && isNativeTouchTarget(target)) {
      cancelInteraction();
      resetGpNextBackdropTapCandidate();
      nativeTouchActive = true;
      suppressNativeMouse = nativeSingleTouchMouse;
      return;
    }

    if (event.touches.length === 1 && isGpNextOpen()) {
      cancelInteraction();
      gpNextBackdropTouchActive = true;
      gpNextBackdropTouchStartedAt = performance.now();
      gpNextBackdropTouchStartPoint = point;
      gpNextBackdropTouchMoved = false;
      gpNextBackdropTouchHadMultipleFingers = false;
      suppressNativeMouse = nativeSingleTouchMouse;
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    if (event.touches.length >= 3) {
      abandonLeftMouse();
      resetTwoFingerGesture();
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    if (event.touches.length === 2) {
      if (nativeMouseTraceActive) {
        nativeMouseTraceActive = false;
        finishTouchTrace("native_multitouch");
      }
      abandonLeftMouse();
      twoFingerStartPoint = averageTouchPoint(event.touches);
      twoFingerTarget = targetAtPoint(twoFingerStartPoint);
      twoFingerMoved = false;
      lastWheelY = twoFingerStartPoint.clientY;
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    lastWheelY = null;
    suppressNativeMouse = false;
    if (nativeSingleTouchMouse) {
      nativeMouseTraceActive = true;
      startTouchTrace(point, "native");
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    beginLeftMouse(target, point);
    event.preventDefault();
    event.stopImmediatePropagation();
  }, { capture: true, passive: false });

  document.addEventListener("touchmove", function (event) {
    if (nativeTouchActive) {
      return;
    }

    if (gpNextBackdropTouchActive) {
      const changedTouch = firstChangedTouch(event);
      const point = changedTouch || averageTouchPoint(event.touches);
      if (gpNextBackdropTouchStartPoint &&
          Math.hypot(
            point.clientX - gpNextBackdropTouchStartPoint.clientX,
            point.clientY - gpNextBackdropTouchStartPoint.clientY
          ) > touchMoveThreshold) {
        gpNextBackdropTouchMoved = true;
      }
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    if (event.touches.length >= 3) {
      cancelInteraction();
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    if (event.touches.length === 2) {
      const point = averageTouchPoint(event.touches);
      if (twoFingerStartPoint) {
        const deltaY = point.clientY - twoFingerStartPoint.clientY;
        if (Math.abs(deltaY) * physicalPixelRatio() >
            twoFingerMoveThresholdPhysicalPixels) {
          twoFingerMoved = true;
        }
      }
      if (twoFingerMoved && lastWheelY !== null) {
        const wheelDelta =
          (point.clientY - lastWheelY) * touchWheelMultiplier;
        if (wheelDelta !== 0) {
          const wheelEvent = new WheelEvent("wheel", {
            deltaY: wheelDelta,
            deltaMode: 0,
            bubbles: true,
            cancelable: true,
            screenX: point.screenX,
            screenY: point.screenY,
            clientX: point.clientX,
            clientY: point.clientY,
            relatedTarget: null
          });
          const target = twoFingerTarget || targetAtPoint(point);
          target.dispatchEvent(wheelEvent);
        }
      }
      lastWheelY = point.clientY;
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    if (nativeSingleTouchMouse && nativeMouseTraceActive) {
      const changedTouch = firstChangedTouch(event);
      const point = changedTouch || averageTouchPoint(event.touches);
      if (activeTouchTrace) {
        activeTouchTrace.moved = true;
      }
      traceInput("touch", "touchmove", point, null, null, "gesture");
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    if (!leftMouseActive) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    const changedTouch = firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    leftMouseMoved = true;
    if (activeTouchTrace) {
      activeTouchTrace.moved = true;
    }
    traceInput("touch", "touchmove", point, null, null, "gesture");
    dispatchMouse(leftMouseTarget, "mousemove", point, 0,
      leftMouseDownDispatched ? 1 : 0);
    event.preventDefault();
    event.stopImmediatePropagation();
  }, { capture: true, passive: false });

  function endTouch(event) {
    if (nativeTouchActive) {
      if (event.touches.length === 0) {
        nativeTouchActive = false;
      }
      return;
    }

    if (gpNextBackdropTouchActive) {
      if (event.touches.length === 0) {
        const tapDuration = gpNextBackdropTouchStartedAt === null
          ? Infinity
          : performance.now() - gpNextBackdropTouchStartedAt;
        if (gpNextBackdropTouchStartPoint &&
            !gpNextBackdropTouchMoved &&
            !gpNextBackdropTouchHadMultipleFingers &&
            tapDuration <= gpNextBackdropTapMaxDuration) {
          registerGpNextBackdropTap(gpNextBackdropTouchStartPoint);
        } else {
          resetGpNextBackdropTapCandidate();
        }
        resetGpNextBackdropTouchState();
      }
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    const changedTouch = firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    lastWheelY = null;
    if (nativeSingleTouchMouse && nativeMouseTraceActive) {
      nativeMouseTraceActive = false;
      traceInput("touch", "touchend", point, null, null, "gesture");
      finishTouchTraceAfterFrames("native_gesture_completed", 2);
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    traceInput("touch", "touchend", point, null, null, "gesture");
    releaseLeftMouse(point);
    if (event.touches.length === 0 && twoFingerStartPoint) {
      if (!twoFingerMoved) {
        const target = document.getElementById("GameCanvas");
        if (target) {
          dispatchMouse(target, "mousemove", twoFingerStartPoint, 0, 0);
          dispatchMouse(target, "mousedown", twoFingerStartPoint, 2, 2);
          dispatchMouse(target, "mouseup", twoFingerStartPoint, 2, 0);
        }
      }
      resetTwoFingerGesture();
    } else if (event.touches.length === 0) {
      resetTwoFingerGesture();
    }
    event.preventDefault();
    event.stopImmediatePropagation();
  }

  function cancelTouch(event) {
    if (nativeTouchActive) {
      nativeTouchActive = false;
      return;
    }

    if (gpNextBackdropTouchActive) {
      resetGpNextBackdropTouchState();
      resetGpNextBackdropTapCandidate();
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    return;
  }

  document.addEventListener("touchend", endTouch, { capture: true, passive: false });
  document.addEventListener("touchcancel", cancelTouch, { capture: true, passive: false });
})();
