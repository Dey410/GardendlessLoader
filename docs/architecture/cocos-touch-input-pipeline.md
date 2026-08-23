# Cocos touch input pipeline

The compatibility target is the input observed by the game, not identical host
APIs on every operating system. A one-finger gesture must reach Cocos in this
order:

```text
MOUSE_DOWN(point, buttons=1)
[MOUSE_MOVE(point, buttons=1)] *
MOUSE_UP(point, buttons=1)
```

This mirrors the supplied APK's `MouseGameWebView` DEX contract: single-touch
`ACTION_DOWN`, `ACTION_MOVE`, and `ACTION_UP` inject mouse actions `0`, `2`, and
`1` respectively with primary button state. The APK document-start extension
then consumes the original game touch stream.

Android, iOS WKWebView, and HarmonyOS ArkWeb all use this shared document-start
mapper. Android native single-touch mouse injection stays disabled so it cannot
duplicate the shared sequence. Mouse-down is immediate: there is no leading
positioning move, animation-frame delay, release replay, or synthetic click, so
a slow drag and a fast flick have the same game-visible ordering.

Game mouse events always target `GameCanvas`, while original game touches are
prevented and stopped like the APK extension. Native form controls and the
scoped GP-Next controls keep their native paths, while the existing two- and
three-finger mappings remain separately classified.

Automated checks cover the exact mouse-only event order, coordinates, button
state, original-touch suppression, tap planting, duration-independent drag
planting, and absence of delayed replay. Final planting feel and WebView event
translation still require the complete device matrix in
`docs/acceptance-checklist.md`.
