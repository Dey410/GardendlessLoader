# Cocos touch input pipeline

The compatibility target is the input observed by the game, not a shared
WebView implementation. `touch_state_machine.js` is the authoritative gesture
module. Its interface accepts normalized touch frames and returns only these
game commands: primary down/move/up, neutral move, secondary down/up, and
scroll. DOM ownership, platform event construction, and diagnostics stay
outside that interface.

A one-finger gesture reaches Cocos in this order on every platform:

```text
MOUSE_DOWN(point, buttons=1)
[MOUSE_MOVE(point, buttons=1)] *
MOUSE_UP(point, buttons=1)
```

The reference APK's JavaScript extension has its single-finger mouse synthesis
disabled. Android therefore keeps one uninterrupted native mouse stream:
`MouseGameWebView` executes primary down/move/up and two-finger scroll commands
with Android `MotionEvent`s, while `touch_input_adapter.js` suppresses the
original game touch stream and does not duplicate primary mouse events. iOS
WKWebView and OpenHarmony ArkWeb execute the same game command types with
JavaScript mouse and wheel events. Their primary adapter first emits a neutral
positioning move, waits one animation frame before mouse down, and defers a
dragged mouse up by one frame after the final move. This lets Cocos sample the
new pointer position before it consumes selection or planting input.

The DOM adapter assigns each gesture to one owner at its first touch. Inputs,
text areas, selects, editable content, and the explicit GP-Next selector list
remain browser-owned. Other touches are game-owned only when a connected
`GameCanvas` and the state-machine module are available. Ownership does not
change while fingers cross elements. Missing dependencies fail closed: the
touch is consumed, no target is guessed, and no old implementation is used.

Adding a second finger abandons primary drag without a primary up, emits a
neutral move at the two-finger center, and locks the gesture until all fingers
are lifted. Vertical center movement of at most 20 physical pixels remains a
secondary-click candidate. Movement beyond that threshold becomes scrolling;
platform adapters may use different conversion constants to produce the same
in-game distance and direction. Three or more fingers produce no game command.

Cancellation produces no compensating mouse up. It clears internal candidates,
ignores the interrupted gesture, and requires a fresh touch before input can
restart. Real mouse and trackpad events bypass touch mapping; stylus input uses
the single-touch path.

When `touchDiagnosticsEnabled` is true, a bounded in-memory trace records input
coordinates, owner decisions, state transitions, and output command names. It
never records DOM text, form values, game data, or storage. The setting is off
in release host configurations.

Executable checks cover the shared command contract, DOM ownership, failure
closure, Android reference-state transitions, target selection, original-touch
suppression, and absence of replay. WebView event translation and final game
feel still require the real-device matrix in `docs/acceptance-checklist.md`.
