const gardendlessTouchPatchSource = r'''
(function () {
  if (window.__gardendlessTouchPatchInstalled) {
    return;
  }
  window.__gardendlessTouchPatchInstalled = true;

  const delayTime = 16;
  let lastWheelY = null;
  let leftMouseActive = false;
  let leftMouseTarget = null;

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

  function releaseLeftMouse(point) {
    if (!leftMouseActive) {
      return;
    }

    const target = leftMouseTarget || touchTarget(null);
    leftMouseActive = false;
    leftMouseTarget = null;
    setTimeout(function () {
      dispatchMouse(target, "mouseup", point, 0, 0);
    }, delayTime);
  }

  document.addEventListener("touchstart", function (event) {
    const changedTouch = firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    const target = touchTarget(changedTouch);

    if (event.touches.length === 3) {
      releaseLeftMouse(point);
      setTimeout(function () {
        dispatchMouse(target, "mousedown", point, 2, 2);
      }, delayTime);
      setTimeout(function () {
        dispatchMouse(target, "mouseup", point, 2, 0);
      }, delayTime * 2);
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    if (event.touches.length === 2) {
      releaseLeftMouse(point);
      lastWheelY = averageTouchPoint(event.touches).clientY;
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    lastWheelY = null;
    leftMouseActive = true;
    leftMouseTarget = target;
    dispatchMouse(target, "mousemove", point, 0, 0);
    setTimeout(function () {
      if (leftMouseActive) {
        dispatchMouse(target, "mousedown", point, 0, 1);
      }
    }, delayTime);
    event.preventDefault();
    event.stopPropagation();
  }, { capture: true, passive: false });

  document.addEventListener("touchmove", function (event) {
    if (event.touches.length === 2) {
      const point = averageTouchPoint(event.touches);
      if (lastWheelY !== null) {
        const wheelEvent = new WheelEvent("wheel", {
          deltaY: (point.clientY - lastWheelY) * -3,
          deltaMode: 0,
          bubbles: true,
          cancelable: true,
          screenX: point.screenX,
          screenY: point.screenY,
          clientX: point.clientX,
          clientY: point.clientY,
          relatedTarget: null
        });
        const target =
          document.elementFromPoint(point.clientX, point.clientY) ||
          document.getElementById("GameCanvas") ||
          touchTarget(null);
        target.dispatchEvent(wheelEvent);
      }
      lastWheelY = point.clientY;
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    const changedTouch = firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    const target = leftMouseTarget || touchTarget(changedTouch);
    setTimeout(function () {
      dispatchMouse(target, "mousemove", point, 0, leftMouseActive ? 1 : 0);
    }, delayTime);
    event.preventDefault();
    event.stopPropagation();
  }, { capture: true, passive: false });

  function endTouch(event) {
    const changedTouch = firstChangedTouch(event);
    const point = changedTouch || averageTouchPoint(event.touches);
    lastWheelY = null;
    releaseLeftMouse(point);
    event.preventDefault();
    event.stopPropagation();
  }

  document.addEventListener("touchend", endTouch, { capture: true, passive: false });
  document.addEventListener("touchcancel", endTouch, { capture: true, passive: false });
})();
''';
