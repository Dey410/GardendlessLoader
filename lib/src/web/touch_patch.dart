const gardendlessTouchPatchSource = r'''
(function () {
  if (window.__gardendlessTouchPatchInstalled) {
    return;
  }
  window.__gardendlessTouchPatchInstalled = true;

  const twoFingerMoveThreshold = 14;
  const twoFingerTapMaxDuration = 250;
  let lastWheelY = null;
  let leftMouseActive = false;
  let leftMouseTarget = null;
  let leftMouseDownPoint = null;
  let leftMouseDownDispatched = false;
  let pendingLeftMouseDownFrame = null;
  let pendingLeftMouseUpPoint = null;
  let twoFingerStartPoint = null;
  let twoFingerTarget = null;
  let twoFingerMoved = false;
  let twoFingerStartedAt = null;
  let pendingMoveFrame = null;
  let pendingMovePoint = null;
  let pendingMoveTarget = null;
  let lastTouchPoint = null;
  let nativeTouchActive = false;

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
    twoFingerStartedAt = null;
  }

  function clearLeftMouseState() {
    leftMouseActive = false;
    leftMouseTarget = null;
    leftMouseDownPoint = null;
    leftMouseDownDispatched = false;
    pendingLeftMouseDownFrame = null;
    pendingLeftMouseUpPoint = null;
  }

  function beginLeftMouse(target, point) {
    leftMouseActive = true;
    leftMouseTarget = target;
    leftMouseDownPoint = point;
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
    const point = lastTouchPoint || {
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

    if (event.touches.length === 1 && isNativeTouchTarget(target)) {
      cancelInteraction();
      nativeTouchActive = true;
      return;
    }

    if (event.touches.length >= 3) {
      cancelLeftMouse(point);
      resetTwoFingerGesture();
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    if (event.touches.length === 2) {
      cancelLeftMouse(point);
      twoFingerStartPoint = averageTouchPoint(event.touches);
      twoFingerTarget = targetAtPoint(twoFingerStartPoint);
      twoFingerMoved = false;
      twoFingerStartedAt = performance.now();
      lastWheelY = twoFingerStartPoint.clientY;
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    lastWheelY = null;
    beginLeftMouse(target, point);
    event.preventDefault();
    event.stopPropagation();
  }, { capture: true, passive: false });

  document.addEventListener("touchmove", function (event) {
    if (nativeTouchActive) {
      return;
    }

    if (event.touches.length >= 3) {
      cancelInteraction();
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    if (event.touches.length === 2) {
      const point = averageTouchPoint(event.touches);
      lastTouchPoint = point;
      if (twoFingerStartPoint) {
        const deltaX = point.clientX - twoFingerStartPoint.clientX;
        const deltaY = point.clientY - twoFingerStartPoint.clientY;
        if (Math.hypot(deltaX, deltaY) > twoFingerMoveThreshold) {
          twoFingerMoved = true;
        }
      }
      if (twoFingerMoved && lastWheelY !== null) {
        const wheelDelta = (point.clientY - lastWheelY) * -3;
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
      event.stopPropagation();
      return;
    }

    if (!leftMouseActive) {
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    const changedTouch = firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    const target = leftMouseTarget || touchTarget(changedTouch);
    lastTouchPoint = point;
    scheduleMouseMove(target, point);
    event.preventDefault();
    event.stopPropagation();
  }, { capture: true, passive: false });

  function endTouch(event) {
    if (nativeTouchActive) {
      if (event.touches.length === 0) {
        nativeTouchActive = false;
      }
      return;
    }

    const changedTouch = firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    lastTouchPoint = point;
    lastWheelY = null;
    releaseLeftMouse(point);
    const tapDuration = twoFingerStartedAt === null
      ? Infinity
      : performance.now() - twoFingerStartedAt;
    if (event.touches.length === 0 &&
        twoFingerStartPoint &&
        !twoFingerMoved &&
        tapDuration <= twoFingerTapMaxDuration) {
      const target = twoFingerTarget || targetAtPoint(twoFingerStartPoint);
      dispatchMouse(target, "mousemove", twoFingerStartPoint, 0, 0);
      dispatchMouse(target, "mousedown", twoFingerStartPoint, 2, 2);
      dispatchMouse(target, "mouseup", twoFingerStartPoint, 2, 0);
    }
    if (event.touches.length === 0) {
      resetTwoFingerGesture();
    }
    event.preventDefault();
    event.stopPropagation();
  }

  function cancelTouch(event) {
    if (nativeTouchActive) {
      nativeTouchActive = false;
      return;
    }

    const changedTouch = firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    lastTouchPoint = point;
    cancelLeftMouse(point);
    resetTwoFingerGesture();
    event.preventDefault();
    event.stopPropagation();
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
''';
