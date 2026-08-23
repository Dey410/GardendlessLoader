# Cocos touch input pipeline

The compatibility target is the input observed by the game, not identical host
APIs on every operating system. A one-finger gesture must reach Cocos in this
order:

```text
MOUSE_DOWN(point, buttons=1)
[MOUSE_MOVE(point, buttons=1)] *
MOUSE_MOVE(final point, buttons=1)
[one Cocos update frame]
MOUSE_UP(point, buttons=1)
```

This mirrors the supplied APK's `MouseGameWebView` DEX contract: single-touch
`ACTION_DOWN`, `ACTION_MOVE`, and `ACTION_UP` inject mouse actions `0`, `2`, and
`1` respectively with primary button state. The APK document-start extension
then consumes the original game touch stream.

Android, iOS WKWebView, and HarmonyOS ArkWeb all use this shared document-start
mapper. Android native single-touch mouse injection stays disabled so it cannot
duplicate the shared sequence. Mouse-down is immediate. Taps release
immediately. A moved gesture repeats its final pointer position and holds the
left button through the next Cocos update frame before releasing exactly once;
there is no second mouse-down or synthetic click.

The release frame is required by this game's input code. Its `UI.onMouseUp`
does not use the mouse-up coordinates to choose a lawn tile; it reads
`Mouse.mouseInLnC`, which `Square.update` derives from the last mouse move.
Releasing synchronously can therefore use the old tile and leave the plant in
hand until the next tap. The final held move plus one update frame makes slow
drags and fast flicks resolve the same final tile.

Game mouse events always target `GameCanvas`, while original game touches are
prevented and stopped like the APK extension. Native form controls and the
scoped GP-Next controls keep their native paths, while the existing two- and
three-finger mappings remain separately classified.

Automated checks cover the mouse-only event order, coordinates, button state,
original-touch suppression, immediate tap planting, the Cocos `mouseInLnC`
update boundary for drag planting, and absence of a click/down replay. Final
planting feel and WebView event translation still require the complete device matrix in
`docs/acceptance-checklist.md`.
