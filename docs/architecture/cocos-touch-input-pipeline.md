# Cocos touch input pipeline

The compatibility target is the input observed by the game, not identical host
APIs on every operating system. A one-finger gesture must reach Cocos in this
order:

```text
MOUSE_MOVE(point, no button)
MOUSE_DOWN(point, left button)
MOUSE_MOVE(point, left button) *
MOUSE_UP(point, left button)
```

The leading move is required because the game updates its global mouse position
from `MOUSE_MOVE`. Lawn selection and the later `MOUSE_UP` planting path must
therefore use the current finger position rather than the previous mouse tile.

For standard resources, Android produces the sequence with mouse-source
`MotionEvent` objects in `MouseGameWebView`. The original touch is delivered
first so the document-start bridge can classify native form targets;
single-touch JavaScript mouse synthesis is disabled. GP-Next sessions stay on
the shared JavaScript mapper so their selector-scoped native controls cannot be
preempted by view-level mouse injection. iOS WKWebView and HarmonyOS ArkWeb use
the same shared mapper. It emits the leading move immediately and defers the
press to the next animation frame so the game consumes the new lawn position
first. Both paths produce the same Cocos-visible sequence and planting result.

The original game touch is consumed for game gestures, preventing Cocos from
processing both touch and mouse input. Native form controls and the scoped
GP-Next controls keep their native touch path. On Android, touch-derived native
mouse events are suppressed for those controls after classification.

Automated checks cover event order, coordinates, button state, duplicate-input
prevention, tap planting state, and drag planting state. Final planting feel and
WebView event translation still require the complete device matrix in
`docs/acceptance-checklist.md`.
