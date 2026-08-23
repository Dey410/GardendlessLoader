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
single-touch JavaScript mouse synthesis is disabled. This native path remains
enabled for GP-Next resources; the document-start bridge suppresses injected
mouse events only for selector-scoped native controls. iOS WKWebView and
HarmonyOS ArkWeb use the shared mapper. It emits the leading move immediately,
defers the press to the next animation frame, and keeps move/up events on the
original game canvas even if another DOM element covers the release point.
Both paths produce the same Cocos-visible sequence and planting result.

The original game touch is consumed for game gestures, preventing Cocos from
processing both touch and mouse input. Native form controls and the scoped
GP-Next controls keep their native touch path. On Android, touch-derived native
mouse events are suppressed for those controls after classification.

Automated checks cover event order, coordinates, button state, duplicate-input
prevention, tap planting state, and drag planting state. Final planting feel and
WebView event translation still require the complete device matrix in
`docs/acceptance-checklist.md`.
