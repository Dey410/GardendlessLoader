# ADR-0003: Add an experimental native gesture mode

## Status

Accepted as an experimental setting. ADR-0002 remains the default
"simulated" mode.

## Date

2026-10-19

## Context

PvZGE is a mouse game:

- It applies a held seed packet, shovel or plant food when the left button
  goes down on a lawn tile (`UI.onMouseDown` → `Mouse.mouseInLnC.onMouseDown`
  → `LnC.PlaceUIPlant`). `LnC.onMouseUp` only handles minecarts.
- In levels, `UI.onMouseScroll` accepts at most one wheel event per game frame
  and steps once per event, whatever its size.
- The Zen Garden pans only while the right or middle button is held, and the
  wheel zooms it.

The simulated mode in ADR-0002 makes a card-to-lawn drag plant by clicking the
release point after the original mouse up. That click has side effects off
the lawn:

- In a Cocos `ScrollView` (almanac, seed chooser, store, player list), its
  touch start stops inertia in `_handlePressLogic`.
- Its touch end selects whichever item is under the finger, because those
  items select on `TOUCH_END`.
- Its frame and time guards depend on the ratio between the WebView refresh
  rate and the game's `game.frameRate`, which players can change.

Two fingers also stand in for every wheel use and every right-button action,
so sandbox card cycling jumps once per `touchmove`. A sideways two-finger slide
still ends in a right click, and the Zen Garden cannot be panned at all.

The goal of native mode is that a player never needs two fingers, the way a
game made for phones plays:

- **Wheel-only actions:**
  - the settings window, whose `ScrollViewWithoutTouchevent` turns touch
    scrolling off because of its sliders;
  - sandbox cycling of the seed bank, zombie cards and zombie armor;
  - Zen Garden zoom.
- **Right-button-only actions:**
  - editing a custom card deck;
  - setting the sandbox seed bank from a lawn plant;
  - clearing a slot in the decoding minigame.
- **Already one-finger:** putting down a held tool (tap it again), Zen Garden
  tool cancel (tap the tool again) and Air Raid steering (the game binds the
  mouse when the level starts).

A browser run of the 0.15.0 GP-Next package confirmed that a plain
`mousedown → mousemove → mouseup` card-to-lawn drag does not plant.

## Decision

Settings gain **Gestures (experimental)**: *Simulated* (default, ADR-0002) or
*Native*. The launcher passes the value as the session field
`touchGestureMode`, and each native host copies it into
`__gardendlessHostConfig.touchGestureMode`. Every behavior below applies only
in native mode.

### One finger: one-to-one mouse

`touch_input_adapter.js` keeps the positioning move and the two
animation-frame boundaries before `mousedown`, because tap planting still uses
the frame-derived `mouseInLnC`. On release it sends the final move, if the
point changed, and then the original `mouseup` in the same task. It never adds
a click.

### Game meaning of a one-finger gesture: `native_gestures.js`

The script reads only modules Cocos has already executed (`System.get`). Each
rule reuses the game's own handler for the action it maps.

**Drag and drop.**
- A capture-phase `mousedown` listener on the window marks the press. A
  wrapper around `UIInGame.prototype.tryChangingIndex` records a pickup when
  that press puts a seed packet (0–8), the shovel (-2) or plant food (-3) in
  hand, together with the lawn tile and pointer position at that moment.
- A wrapper around `UIInGame.prototype.onMouseUp`, which each level registers
  as its `MOUSE_UP` listener, runs the game's handler. It then finds the
  release tile from `Mouse.position` with `Square.judgeLIndex`,
  `Square.judgeCIndex`, `Square.getLnC` and `LnC.isInLawn`.
  `Mouse.position` follows every `MOUSE_MOVE` synchronously, so the lookup
  does not depend on whether a game frame ran after the final move.
- Released over a different lawn tile: the wrapper calls that tile's own
  `onMouseDown(event, true)`. Sandbox zombie cards (9) and sniper aiming (-4)
  drop the same way, because the game also applies them on the next tile
  press.
- If the tool is still in hand afterwards, or the drag ended off the lawn more
  than 20 UI units from where it started, the wrapper puts the tool back with
  the game's `tryChangingIndex(-1)`.
- A release where the tool was picked up is a tap and keeps it in hand.

**Drag lift.** A finger covers the tile under it, and the plant in hand
(`plantInHandLayer`) and the lawn highlight both follow `Mouse.position`.
- While a press that a touch started carries a pickup and has moved more than
  12 CSS pixels, the capture listeners give each `mousemove` and the
  `mouseup` a `clientY` 48 CSS pixels higher. Cocos reads the location from
  `clientX` and `clientY` after them, so the game draws the hand above the
  finger and the drop lands on the tile shown there.
- The script marks the press as a touch from a window capture `touchstart`,
  which runs before `touch_input_adapter.js` consumes the touch on the
  document. A tap, a mouse, a controller and a sandbox swipe keep the real
  location.

**Decoding minigame.** The game picks a card on one press (`PickCard`) and
places, merges or swaps it on the next press on a merged slot. When a press
picked a card and the release lands on a different merged slot, the script
emits a left-button `cc.EventMouse` `mouse-down` on that slot node, so the
slot's own handler runs. A drag that ends elsewhere calls the game's
`ReleaseCard()`; a tap keeps the card picked.

**Zen Garden.**
- After a left press is dispatched, if the Zen Garden is active and no
  shovel, glove, cart or plant move is in hand, the script sets
  `zenGardenScene.component.pressed`, the same switch a right press sets. The
  garden's own `MOUSE_MOVE` handler then pans until the left release, a window
  blur or the page being hidden.
- `ZenGarden.MouseDown(slot)` applies the tool in hand to a slot. With the
  glove, it picks a plant and then moves it. If a press picked a plant with
  the glove, or took a tool from its button, and the release is over a
  different slot (found with each slot's `judgeMouse()`), the script calls
  `MouseDown` for that slot.
- An unused drag drops the plant (`setWillMovePlantSlot(null)`) or puts the
  tool back (`indexTo_1()`).

**Settings list.** The script replaces the four touch handlers that
`ScrollViewWithoutTouchevent` overrides with empty functions:
- A touch that starts on a node with a `cc.Slider`, or on a node inside one,
  stays with the slider.
- Any other touch runs the base `cc.ScrollView` handler, which scrolls with
  inertia and cancels a button the finger drags across.
- `ScrollView` registers these handlers when it is enabled, which covers every
  settings window opened after start-up.

**Sandbox swipe.** In sandbox levels, a press that starts on the seed bank
(`Cards.component`), the zombie cards (`SandBoxZombieCards.component`) or the
zombie armor slot follows the strip's long axis.
- Once the finger moves more than 16 CSS pixels along that axis, more than
  across it, and is still inside the strip, the press becomes a swipe. The
  press's selection goes back to the game with `tryChangingIndex(-1)`.
- Every further 40 CSS pixels dispatches one `deltaY = ±100` wheel event at
  the finger. The game's own wheel handlers step the strip, and the content
  follows the finger.
- Leaving the strip first keeps an ordinary drag, so a card dragged toward the
  lawn still plants.

**Long press.** A finger held within 12 CSS pixels for 500 ms acts on these
targets only:
- A custom card deck, not built-in or "add" decks: emits a right-button
  `cc.EventMouse` `mouse-down` on the deck node, so the game's own listener
  opens the editor.
- A filled decoding slot: the same right-button event on the slot node clears
  it.
- A sandbox lawn plant with nothing in hand: the tile's own
  `plantMouseReact` with that right-button event switches the seed bank.

The press still reaches the game first, so a long-pressed deck is also used.
No DOM right click is synthesized: Cocos would turn it into a second touch and
press a button again.

The same long press also stands in for two keyboard-only actions:
- **Sandbox shortcuts.** In a started sandbox level, a long press on what the
  press picked up (a seed packet 0–7, the shovel, plant food or a sandbox
  zombie card) puts it back with `tryChangingIndex(-1)`. It then sets
  `KeyListener.ctrlDown` and passes the player's card, shovel or plant food
  key, or `KEY_K` for a zombie card, to `UIInGame.onKeyDown`, and restores
  `ctrlDown` even if the handler throws. The level then fills every tile with
  that packet's plant, removes or feeds every plant, or defeats every zombie.
- **Zen Garden care.** On a plant or on open ground, with no tool or plant
  in hand and the shovel and medal windows closed, a long press calls
  `fulfillRequire()` on every slot of the page. That is what the care-all key
  (`ZenGarden_DealWithAll`) does. Pots fill almost the whole page, so a plant
  counts as a target; its press already met its own need, and the count of
  plants cared for starts from the needs at the press. An empty or locked pot
  is left to its own press, which plants or buys.

Both say what they did in the game's own tip bar (`game_tip.js`) and tap the
device.

**Sandbox menu.** The sandbox settings window lists keyboard shortcuts as
plain rows, and its only buttons are four toggles. It closes by key or by
the toolbar button that opened it, and while it is open the game ignores
sandbox keys.
- A tap on a shortcut row (switch eighties effects, push or pull the tide,
  switch music, time freeze, summon zombies, switch lawn) closes the window
  with `UIInGame.showSBSettings()`. It then passes a `cc.EventKeyboard` with
  that row's current key binding (`KeyListener.KeyBinds`) to
  `UIInGame.onKeyDown` and `onKeyUp`.
- The engine maps DOM key events by `KeyboardEvent.code` through a private
  table, so the key does not go through the DOM.
- A tap outside the window frame, where its full-screen mouse blocker
  swallows input, closes the window. A tap on an active button drawn above
  the window, such as the toolbar button, is left to that button.

Each rule checks its own interfaces. If one is missing, the script logs once
and leaves that rule off; it never falls back to a synthesized click.

### Two fingers: tap, swipe or pinch

`touch_state_machine.js`, created with `twoFingerGestures: "native"`, keeps a
two-finger gesture a right-click candidate while both the center travel (any
direction) and the change in finger distance stay within 20 physical pixels.

Past that, it locks the gesture:
- **Pinch**, when the distance changed more than the center moved. It scrolls
  by the change in finger distance, spreading counting as moving down, so a
  spread zooms in the Zen Garden.
- **Swipe**, otherwise. It scrolls by vertical center movement.

The adapter adds these scroll deltas up on the existing
`touchWheelCssMultiplier` scale and sends one `deltaY = ±100` wheel event per
whole notch, like a mouse wheel. A new gesture discards the remainder.

Only the pinch is part of the native gesture set. Two-finger taps and swipes
keep working, but nothing requires them. The two things they alone still do are
the cheat sun counter's −1000, where a press has already added 1000, and the
cosmetic sandbox costume roll.

## Alternatives considered

### Replace the simulated mode outright

Rejected for now. The native mode depends on internal game members and has
not yet passed device acceptance, so it ships behind a setting.

### Long press as a general right button

Rejected. The game reacts on button down (picking a card, using a deck,
planting a tapped tile). A general long press would have to delay every left
press until the finger moves or lifts. Long press therefore only adds the
right-button action of the three targets that have no other one-finger path,
and the keyboard-only sandbox shortcuts and Zen Garden care.

### Synthesize a right click for long press

Rejected. The engine turns a DOM right-button press into a touch as well, so
it would press a button under the finger a second time.

## Consequences

- In native mode:
  - One-finger drags in Cocos `ScrollView`s scroll with the engine's inertia
    and no longer select the item under the finger.
  - Card, shovel, plant-food, sandbox-zombie and sniper drags apply on drop,
    and so do decoding cards, the Zen Garden glove and Zen Garden tools.
    Unused drags put things back. Tapping first and then tapping the target
    still works.
  - The settings window scrolls with one finger; its sliders still drag.
  - Swiping along the sandbox seed bank, zombie cards or armor slot steps
    them.
  - A long press edits a custom deck, sets the sandbox bank from a plant, or
    clears a decoding slot. In sandbox it runs the Ctrl shortcut of a seed
    packet, the shovel, plant food or a zombie card, and in the Zen Garden it
    cares for every plant on the page.
  - The Zen Garden pans with one finger and zooms with a pinch.
  - The sandbox settings window runs a shortcut when its row is tapped, and
    closes when a finger taps outside it.
  - Two-finger wheel steps follow whole notches, and a sideways two-finger
    slide neither scrolls nor right clicks.
- Mouse and trackpad players get drag and drop, the put-back, and left-drag
  Zen Garden panning in native mode too.
- The hooks depend on these game members; check them on every game update:
  - `UIInGame.tryChangingIndex/onMouseUp/index/paused/SBZombieArmorIconSlot`
  - `Square.judgeLIndex/judgeCIndex/getLnC`
  - `Mouse.position/positionOrg/judgeInUITransform`
  - `LnC.isInLawn/onMouseDown/getAllPlants/plantMouseReact`
  - `zenGardenScene.component.pressed/isShoveling/isGloving/isCarting/willMovePlantSlot`
  - `ScrollViewWithoutTouchevent` and the base `ScrollView` touch handlers it
    overrides
  - `LevelPlay.sandBoxModeOn/gameStarted/component.carddeck_displayer.CardDeckParent`
  - `UIInGame.sandBoxSettingWindow/showSBSettings/onKeyDown/onKeyUp`, the
    window's `windowCommon` frame and the shortcut row names
  - `KeyListener.KeyBinds`
  - `CardDeck.AddMode/ChallengingMode/RecommendedMode`
  - `ArcadeDecodingPlants.MergedCards/PickedCard/ReleaseCard/confirming`
    and each slot's `currentPlant/isCorrect`
  - `zenGardenScene.component.currentZen.slots/MouseDown`, each slot's
    `judgeMouse`, and the component's `setWillMovePlantSlot/indexTo_1`
  - `Cards.component` and `SandBoxZombieCards.component` (`uitransform`,
    `node`)
  - the engine's `EventMouse`, `EventKeyboard`, `KeyCode`, `Button`,
    `ScrollView`, `Node` and `director`
- The wheel calibration, the 20-unit drag distance, the swipe step and the
  long-press time need device tuning.
