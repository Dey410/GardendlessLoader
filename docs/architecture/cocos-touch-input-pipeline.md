# Cocos touch input pipeline

The compatibility target is the input observed by the game, not a shared
WebView implementation. `touch_state_machine.js` is the authoritative gesture
module. Its interface accepts normalized touch frames and returns only these
game commands: primary down/move/up, neutral move, secondary down/up, and
scroll. DOM ownership, platform event construction, and diagnostics stay
outside that interface.

A one-finger tap reaches Cocos in this order on every platform:

```text
MOUSE_MOVE(point, buttons=0)
two animation-frame boundaries
MOUSE_DOWN(point, buttons=1)
MOUSE_UP(point, buttons=1)
```

A card-to-lawn gesture that moves more than 20 physical pixels first selects
the card with that delayed mouse down, forwards held-button moves, and sends
the original mouse up after the final positioning move. Smaller motion remains
a single tap, so normal finger jitter cannot create a duplicate click. PvZGE
0.13.0 places a selected plant only from
`LnC.onMouseDown`; `LnC.onMouseUp` does not place it. After two game frames have
cleared `UI.MouseClickCoolingDown`, the adapter therefore completes one
down/up pair at the release tile. This is the game-visible equivalent of
selecting the card and clicking the target tile, without asking the user for a
second physical tap. Both intermediate moves and the final release coordinate
participate in the physical-distance test, so a WebView-coalesced fast drag
does not degrade into a tap.

The reference APK's JavaScript extension has its single-finger mouse synthesis
disabled, but Loader does not copy that Android WebView implementation detail.
Android Chromium WebView, iOS WKWebView, and OpenHarmony ArkWeb all execute the
shared commands with JavaScript mouse and wheel events. The primary adapter
first emits a neutral positioning move and crosses two animation-frame
boundaries before mouse down. The first boundary is not sufficient: `Mouse.ts`
accepts the move synchronously, but `Square.ts` derives `Mouse.mouseInLnC` only
in its next component update, and request-animation-frame callback order varies
between engines. A fast tap that has already ended completes its down/up pair
after those boundaries.

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
the single-touch path. Android uses a normal WebView and has no native
touch-to-mouse runtime fallback.

When `touchDiagnosticsEnabled` is true, a bounded in-memory trace records input
coordinates, owner decisions, state transitions, and output command names. It
never records DOM text, form values, game data, or storage. The setting is off
in release host configurations.

Executable checks cover the shared command contract, DOM ownership, failure
closure, Android reference-state transitions, target selection, original-touch
suppression, and absence of replay. WebView event translation and final game
feel still require the real-device matrix in `docs/acceptance-checklist.md`.
