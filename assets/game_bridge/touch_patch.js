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

  function dispatchMouse(target, type, point, button, buttons) {
    target.dispatchEvent(mouseEvent(type, point, button, buttons));
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
    pendingLeftMouseDownFrame = null;
    pendingLeftMouseUpPoint = null;
  }

  function beginLeftMouse(target, point) {
    leftMouseActive = true;
    leftMouseTarget = target;
    leftMouseDownPoint = point;
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
        dispatchMouse(leftMouseTarget, "mouseup", upPoint, 0, 1);
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
    dispatchMouse(leftMouseTarget, "mouseup", point, 0, 1);
    clearLeftMouseState();
  }

  function abandonLeftMouse() {
    if (pendingLeftMouseDownFrame !== null) {
      cancelAnimationFrame(pendingLeftMouseDownFrame);
    }
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

    if (!leftMouseActive) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    const changedTouch = firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
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
