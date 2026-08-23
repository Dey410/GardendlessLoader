(function () {
  if (window.__gardendlessTouchStateMachine) {
    return;
  }

  const twoFingerMoveThresholdPhysicalPixels = 20;

  function copyPoint(value) {
    if (!value) {
      return null;
    }
    return {
      id: value.id,
      screenX: value.screenX,
      screenY: value.screenY,
      clientX: value.clientX,
      clientY: value.clientY
    };
  }

  function averagePoint(points) {
    let screenX = 0;
    let screenY = 0;
    let clientX = 0;
    let clientY = 0;
    for (const point of points) {
      screenX += point.screenX;
      screenY += point.screenY;
      clientX += point.clientX;
      clientY += point.clientY;
    }
    const count = points.length || 1;
    return {
      id: -1,
      screenX: screenX / count,
      screenY: screenY / count,
      clientX: clientX / count,
      clientY: clientY / count
    };
  }

  function positivePixelRatio(value) {
    const ratio = Number(value);
    return Number.isFinite(ratio) && ratio > 0 ? ratio : 1;
  }

  function create(options) {
    const trace = options && typeof options.trace === "function"
      ? options.trace
      : null;
    let state = "idle";
    let primaryPoint = null;
    let twoFingerStartPoint = null;
    let lastTwoFingerPoint = null;

    function reset(nextState) {
      state = nextState || "idle";
      primaryPoint = null;
      twoFingerStartPoint = null;
      lastTwoFingerPoint = null;
    }

    function beginTwoFinger(points, commands, hadPrimary) {
      const center = averagePoint(points);
      state = "secondaryCandidate";
      primaryPoint = null;
      twoFingerStartPoint = center;
      lastTwoFingerPoint = center;
      if (hadPrimary) {
        commands.push({type: "neutralMove", point: copyPoint(center)});
      }
    }

    function handle(input) {
      const phase = input && input.phase;
      const points = input && Array.isArray(input.points) ? input.points : [];
      const changedPoints = input && Array.isArray(input.changedPoints)
        ? input.changedPoints
        : [];
      const from = state;
      const commands = [];

      if (phase === "cancel") {
        reset(points.length === 0 ? "idle" : "blocked");
      } else if (state === "blocked") {
        if (points.length === 0) {
          reset("idle");
        }
      } else if (points.length >= 3) {
        reset("blocked");
      } else if (phase === "start") {
        if (state === "idle" && points.length === 1) {
          state = "primary";
          primaryPoint = copyPoint(points[0]);
          commands.push({type: "primaryDown", point: copyPoint(primaryPoint)});
        } else if (points.length === 2 &&
            (state === "primary" || state === "idle")) {
          beginTwoFinger(points, commands, state === "primary");
        }
      } else if (phase === "move") {
        if (state === "primary" && points.length === 1) {
          primaryPoint = copyPoint(points[0]);
          commands.push({type: "primaryMove", point: copyPoint(primaryPoint)});
        } else if ((state === "secondaryCandidate" ||
            state === "secondaryScroll") && points.length === 2) {
          const center = averagePoint(points);
          const ratio = positivePixelRatio(input.physicalPixelRatio);
          const totalPhysicalDelta = Math.abs(
            center.clientY - twoFingerStartPoint.clientY
          ) * ratio;
          if (state === "secondaryScroll" ||
              totalPhysicalDelta > twoFingerMoveThresholdPhysicalPixels) {
            state = "secondaryScroll";
            const physicalDeltaY =
              (center.clientY - lastTwoFingerPoint.clientY) * ratio;
            if (physicalDeltaY !== 0) {
              commands.push({
                type: "scroll",
                point: copyPoint(center),
                physicalDeltaY
              });
            }
          }
          lastTwoFingerPoint = center;
        }
      } else if (phase === "end") {
        if (state === "primary" && points.length === 0) {
          const endPoint = changedPoints[0] || primaryPoint;
          commands.push({type: "primaryUp", point: copyPoint(endPoint)});
          reset("idle");
        } else if (state === "secondaryCandidate" && points.length === 0) {
          commands.push({
            type: "secondaryDown",
            point: copyPoint(twoFingerStartPoint)
          });
          commands.push({
            type: "secondaryUp",
            point: copyPoint(twoFingerStartPoint)
          });
          reset("idle");
        } else if (state === "secondaryScroll" && points.length === 0) {
          reset("idle");
        }
      }

      if (trace) {
        trace({
          phase,
          from,
          to: state,
          pointerCount: points.length,
          commands: commands.map((command) => command.type)
        });
      }
      return commands;
    }

    return {handle};
  }

  window.__gardendlessTouchStateMachine = {create};
})();
