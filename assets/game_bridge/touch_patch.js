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
  let lastWheelY = null;
  let leftTouchIdentifier = null;
  let leftMouseActive = false;
  let leftMouseTarget = null;
  let leftMouseDownPoint = null;
  let leftMouseLastPoint = null;
  let leftMouseDownDispatched = false;
  let pendingLeftMouseDownFrame = null;
  let pendingLeftMouseUpPoint = null;
  let twoFingerStartPoint = null;
  let twoFingerTarget = null;
  let twoFingerMoved = false;
  let pendingMoveFrame = null;
  let pendingMovePoint = null;
  let pendingMoveTarget = null;
  let lastTouchPoint = null;
  let nativeTouchActive = false;
  let gpNextBackdropTouchActive = false;
  let gpNextBackdropTouchStartedAt = null;
  let gpNextBackdropTouchStartPoint = null;
  let gpNextBackdropTouchMoved = false;
  let gpNextBackdropTouchHadMultipleFingers = false;
  let lastGpNextBackdropTapAt = null;
  let lastGpNextBackdropTapPoint = null;

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

  function touchWithIdentifier(touches, identifier) {
    if (identifier === null || !touches) {
      return null;
    }
    for (const touch of touches) {
      if (touch.identifier === identifier) {
        return touch;
      }
    }
    return null;
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

  function scheduleMouseMove(target, point) {
    pendingMoveTarget = target;
    pendingMovePoint = point;
    if (pendingMoveFrame !== null) {
      return;
    }

    pendingMoveFrame = requestAnimationFrame(function () {
      const nextTarget = pendingMoveTarget;
      const nextPoint = pendingMovePoint;
      pendingMoveFrame = null;
      pendingMoveTarget = null;
      pendingMovePoint = null;
      if (nextTarget && nextPoint) {
        dispatchMouse(nextTarget, "mousemove", nextPoint, 0,
          leftMouseDownDispatched ? 1 : 0);
      }
    });
  }

  function cancelPendingMouseMove() {
    if (pendingMoveFrame !== null) {
      cancelAnimationFrame(pendingMoveFrame);
    }
    pendingMoveFrame = null;
    pendingMoveTarget = null;
    pendingMovePoint = null;
  }

  function resetTwoFingerGesture() {
    lastWheelY = null;
    twoFingerStartPoint = null;
    twoFingerTarget = null;
    twoFingerMoved = false;
  }

  function clearLeftMouseState() {
    leftTouchIdentifier = null;
    leftMouseActive = false;
    leftMouseTarget = null;
    leftMouseDownPoint = null;
    leftMouseLastPoint = null;
    leftMouseDownDispatched = false;
    pendingLeftMouseDownFrame = null;
    pendingLeftMouseUpPoint = null;
  }

  function beginLeftMouse(target, point, identifier) {
    leftTouchIdentifier = identifier;
    leftMouseActive = true;
    leftMouseTarget = target;
    leftMouseDownPoint = point;
    leftMouseLastPoint = point;
    leftMouseDownDispatched = false;
    pendingLeftMouseUpPoint = null;
    dispatchMouse(target, "mousemove", point, 0, 0);
    pendingLeftMouseDownFrame = requestAnimationFrame(function () {
      pendingLeftMouseDownFrame = null;
      if (!leftMouseTarget || !leftMouseDownPoint) {
        return;
      }

      const downTarget = leftMouseTarget;
      dispatchMouse(downTarget, "mousedown", leftMouseDownPoint, 0, 1);
      leftMouseDownDispatched = true;
      if (!leftMouseActive) {
        const upPoint = pendingLeftMouseUpPoint || leftMouseDownPoint;
        dispatchMouse(downTarget, "mouseup", upPoint, 0, 0);
        clearLeftMouseState();
      }
    });
  }

  function releaseLeftMouse(point) {
    cancelPendingMouseMove();
    if (!leftMouseTarget) {
      return;
    }

    leftMouseActive = false;
    if (pendingLeftMouseDownFrame !== null) {
      pendingLeftMouseUpPoint = point;
      return;
    }

    const target = leftMouseTarget;
    if (leftMouseDownDispatched) {
      dispatchMouse(target, "mouseup", point, 0, 0);
    }
    clearLeftMouseState();
  }

  function cancelLeftMouse(point) {
    cancelPendingMouseMove();
    if (pendingLeftMouseDownFrame !== null) {
      cancelAnimationFrame(pendingLeftMouseDownFrame);
    }

    const target = leftMouseTarget || touchTarget(null);
    const shouldRelease = leftMouseDownDispatched;
    clearLeftMouseState();
    if (shouldRelease) {
      dispatchMouse(target, "mouseup", point, 0, 0);
    }
  }

  function cancelInteraction() {
    const point = leftMouseLastPoint || lastTouchPoint || {
      screenX: 0,
      screenY: 0,
      clientX: 0,
      clientY: 0
    };
    cancelLeftMouse(point);
    resetTwoFingerGesture();
  }

  document.addEventListener("touchstart", function (event) {
    const changedTouch = firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    const target = touchTarget(changedTouch);
    lastTouchPoint = point;

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
      return;
    }

    if (event.touches.length === 1 && isGpNextOpen()) {
      cancelInteraction();
      gpNextBackdropTouchActive = true;
      gpNextBackdropTouchStartedAt = performance.now();
      gpNextBackdropTouchStartPoint = point;
      gpNextBackdropTouchMoved = false;
      gpNextBackdropTouchHadMultipleFingers = false;
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    if (event.touches.length >= 3) {
      cancelLeftMouse(leftMouseLastPoint || point);
      resetTwoFingerGesture();
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    if (event.touches.length === 2) {
      cancelLeftMouse(leftMouseLastPoint || point);
      twoFingerStartPoint = averageTouchPoint(event.touches);
      twoFingerTarget = targetAtPoint(twoFingerStartPoint);
      twoFingerMoved = false;
      lastWheelY = twoFingerStartPoint.clientY;
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    lastWheelY = null;
    beginLeftMouse(
      target,
      point,
      changedTouch ? changedTouch.identifier : null
    );
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
      lastTouchPoint = point;
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

    const changedTouch =
      touchWithIdentifier(event.changedTouches, leftTouchIdentifier) ||
      touchWithIdentifier(event.touches, leftTouchIdentifier);
    if (leftTouchIdentifier !== null && !changedTouch) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    const point = changedTouch || averageTouchPoint(event.touches);
    const target = leftMouseTarget || touchTarget(changedTouch);
    lastTouchPoint = point;
    leftMouseLastPoint = point;
    scheduleMouseMove(target, point);
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

    const capturedTouch =
      touchWithIdentifier(event.changedTouches, leftTouchIdentifier);
    if (leftTouchIdentifier !== null && leftMouseTarget && !capturedTouch) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    const changedTouch = capturedTouch || firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    lastTouchPoint = point;
    lastWheelY = null;
    releaseLeftMouse(point);
    if (event.touches.length <= 1 && twoFingerStartPoint) {
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

    const changedTouch =
      touchWithIdentifier(event.changedTouches, leftTouchIdentifier) ||
      firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    lastTouchPoint = point;
    cancelLeftMouse(point);
    resetTwoFingerGesture();
    event.preventDefault();
    event.stopImmediatePropagation();
  }

  document.addEventListener("touchend", endTouch, { capture: true, passive: false });
  document.addEventListener("touchcancel", cancelTouch, { capture: true, passive: false });
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) {
      cancelInteraction();
    }
  });
  window.addEventListener("blur", cancelInteraction);

  if (typeof MutationObserver === "function") {
    const observer = new MutationObserver(function () {
      const leftTargetRemoved = leftMouseTarget &&
        leftMouseTarget.isConnected === false;
      const twoFingerTargetRemoved = twoFingerTarget &&
        twoFingerTarget.isConnected === false;
      if (leftTargetRemoved || twoFingerTargetRemoved) {
        cancelInteraction();
      }
    });
    observer.observe(document.documentElement || document, {
      childList: true,
      subtree: true
    });
  }
})();

