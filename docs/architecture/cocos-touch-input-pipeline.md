# Cocos touch input pipeline

The compatibility target is the input observed by the game, not identical host
APIs on every operating system. A one-finger gesture must reach Cocos in this
order:

```text
MOUSE_MOVE(point, buttons=1)
TOUCH_START(point)
[MOUSE_MOVE(point, buttons=1), TOUCH_MOVE(point)] *
MOUSE_UP(point, buttons=1)
TOUCH_END(point)
```

The supplemental mouse event is dispatched during document capture, before the
matching original touch continues to Cocos. The move keeps the game's global
mouse position on the current lawn tile while the original touch owns selection,
drag duration, and activation state.

Android, iOS WKWebView, and HarmonyOS ArkWeb all use this shared document-start
mapper. Android native single-touch mouse injection stays disabled so it cannot
duplicate the shared sequence. The mapper never synthesizes a single-touch
`MOUSE_DOWN` or delayed replay/click, so a slow drag and a fast flick have the
same game-visible ordering with no animation-frame race.

Supplemental game mouse events always target `GameCanvas`. Original one-finger
game touches are not prevented or stopped. Native form controls and the scoped
GP-Next controls keep their native paths, while the existing two- and
three-finger mappings remain separately classified.

Automated checks cover the layered event order, coordinates, button state,
original-touch propagation, absence of synthetic press/replay, tap planting,
and duration-independent drag planting. Final planting feel and WebView event
translation still require the complete device matrix in
`docs/acceptance-checklist.md`.
