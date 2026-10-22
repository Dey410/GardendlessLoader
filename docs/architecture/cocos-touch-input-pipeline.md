# Cocos touch input pipeline

The compatibility target is the input observed by the game, not a shared
WebView implementation. `touch_state_machine.js` is the authoritative gesture
module. Its interface accepts normalized touch frames and returns only these
game commands: primary down/move/up, neutral move, secondary down/up, and
scroll. DOM ownership, platform event construction, and diagnostics stay
outside that interface.

The settings option Gestures (experimental) selects the mode through
`__gardendlessHostConfig.touchGestureMode`. The sections below describe the
default "simulated" mode. The experimental "native" mode (ADR-0003) is
described at the end.

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
`LnC.onMouseDown`; `LnC.onMouseUp` does not place it. After the original mouse
up, the adapter waits for at least two animation-frame boundaries and 50 ms
before completing one down/up pair at the release tile. The elapsed-time guard
lets two Cocos `lateUpdate` ticks clear `UI.MouseClickCoolingDown` in the
validated 60 Hz WebView / 30 Hz game-loop model. Higher display-to-game refresh
ratios retain a narrower timing margin and require device acceptance. This is
the game-visible equivalent of
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
text areas, selects, editable content, the explicit GP-Next selector list, and
the full-screen GP-Next startup recovery surface remain browser-owned. The
recovery surface must keep native button, details, toggle, and scrolling
behavior even though `GameCanvas` still exists behind it. Other touches are
game-owned only when a connected `GameCanvas` and the state-machine module are
available. Ownership does not change while fingers cross elements. Missing
dependencies fail closed: the touch is consumed, no target is guessed, and no
old implementation is used.

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

## Native gesture mode (experimental)

### One finger
- Taps keep the same positioning move and two frame boundaries before the
  press.
- A drag reaches Cocos one to one: the delayed press, held moves at most once
  per animation frame, then, in the `touchend` task, a final move to the
  release point followed by the original release. The adapter adds no click,
  so Cocos `ScrollView`s scroll with their own inertia.
- `native_gestures.js` gives one-finger gestures their game meaning. A seed
  packet, shovel or plant food picked up by a press applies to the lawn tile
  it is released on. It finds the tile from
  `Mouse.position` and calls that tile's own `onMouseDown`.
- A drag that is refused, or that ends off the lawn, puts the tool back with
  `tryChangingIndex(-1)`. Sandbox zombie cards and sniper aiming drop the
  same way.
- The decoding minigame and the Zen Garden glove and tools also pick on one
  press and apply on the next. A drop over another slot runs that slot's own
  press handler: a left-button `cc.EventMouse` on a decoding slot, or
  `ZenGarden.MouseDown`. An unused drag puts the card, plant or tool back.
- In the Zen Garden, an empty-handed left drag sets the garden's own `pressed`
  switch, so it pans.
- The settings window's `ScrollViewWithoutTouchevent` runs the base
  `ScrollView` touch handlers again, unless the touch starts on a slider.
- In sandbox levels, a swipe along the seed bank, the zombie cards or the
  armor slot steps it with wheel events at the finger.
- In the sandbox settings window, a tap on a shortcut row closes the window
  and passes that row's key binding to `UIInGame.onKeyDown/onKeyUp` as a
  `cc.EventKeyboard`. A tap outside the window closes it.
- A 500 ms long press runs the game's right-button handler on a custom card
  deck or a filled decoding slot, by emitting `cc.EventMouse` on that node, or
  on a sandbox lawn plant, through the tile's `plantMouseReact`. It never
  synthesizes a DOM right click.

### Two fingers
- A two-finger gesture stays a right-click candidate while both center travel
  in any direction and the change in finger distance stay within 20 physical
  pixels.
- Past that, it locks to a pinch (by distance change; spreading counts as
  moving down) or a swipe (by vertical center movement).
- The adapter sends scrolls as whole `deltaY = ±100` wheel notches.

Executable checks cover the shared command contract, DOM ownership, failure
closure, Android reference-state transitions, target selection, original-touch
suppression, absence of replay, and both gesture modes. WebView event translation and final game
feel still require the real-device matrix in `docs/acceptance-checklist.md`.
