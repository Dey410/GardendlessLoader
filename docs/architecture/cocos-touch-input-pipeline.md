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

Android, iOS WKWebView, and HarmonyOS ArkWeb all use the shared mapper. It emits
the leading move immediately, defers the press to the next animation frame, and
routes every game mouse event to `GameCanvas`, matching the APK instead of
retaining the DOM element touched at gesture start. When a moved gesture ends,
the mapper finishes the
drag with the APK-compatible `MOUSE_UP(buttons=1)`, then replays the same event
sequence as a successful manual tap: after one frame it emits
`MOUSE_MOVE(buttons=0)`, and after the next frame it emits
`MOUSE_DOWN(buttons=1)` plus `MOUSE_UP(buttons=1)` in the same batch. This is
deliberately different from the previous supplemental click, which omitted the
reset move or split the manual tap's down/up across frames. Stationary taps keep
their original direct path and are not replayed.

The original game touch is consumed for game gestures, preventing Cocos from
processing both touch and mouse input. Native form controls and the scoped
GP-Next controls keep their native touch path. On Android, touch-derived native
mouse events are suppressed for those controls after classification.

Automated checks cover event order, coordinates, button state, duplicate-input
prevention, tap planting state, and drag planting state. Final planting feel and
WebView event translation still require the complete device matrix in
`docs/acceptance-checklist.md`.
