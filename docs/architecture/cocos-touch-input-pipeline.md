# Cocos touch input pipeline

The compatibility target is the input observed by the game. On Android, a
one-finger gesture reaches Cocos through host-injected mouse `MotionEvent`s in
this order:

```text
MOUSE_DOWN(point, buttons=1)
[MOUSE_MOVE(point, buttons=1)] *
MOUSE_UP(point, buttons=1)
```

This mirrors the supplied APK's `MouseGameWebView` DEX contract: single-touch
`ACTION_DOWN`, `ACTION_MOVE`, and `ACTION_UP` inject mouse actions `0`, `2`, and
`1` respectively with primary button state. The APK document-start extension
then consumes the original game touch stream.

Android uses `MouseGameWebView` for the mouse stream because JavaScript-created
`MouseEvent`s do not establish the WebView's native mouse gesture state. The
document-start patch consumes the original game touches and does not synthesize
a second mouse stream when `nativeSingleTouchMouse` is enabled. For native form
and GP-Next controls, the original touch remains browser-owned and the
host-injected compatibility mouse is suppressed.

iOS WKWebView and HarmonyOS ArkWeb retain the immediate JavaScript mouse
fallback. Their fallback has no release delay, second mouse-down, or synthetic
click. It is a separate host implementation of the same intended game-visible
ordering and still requires real-device acceptance.

Game mouse events always target `GameCanvas`, while original game touches are
prevented and stopped like the APK extension. Native form controls and the
scoped GP-Next controls keep their native paths, while the existing two- and
three-finger mappings remain separately classified.

Automated checks cover Android native-path activation, absence of duplicate JS
mouse input, mouse event coordinates and button state, original-touch
suppression, and absence of a click/down replay. Final planting feel and WebView
event translation still require the complete device matrix in
`docs/acceptance-checklist.md`.
