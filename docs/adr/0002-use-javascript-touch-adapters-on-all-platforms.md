# ADR-0002: Use JavaScript touch adapters on all platforms

## Status

Accepted

## Date

2026-08-24

## Context

ADR-0001 kept the reference APK's Android split: JavaScript classified and
consumed touches while a custom Android WebView injected native mouse events.
iOS and OpenHarmony instead executed the shared gesture commands with
JavaScript mouse and wheel events.

Android device testing showed that the native path could leave the complete
game canvas unresponsive even though the shared JavaScript paths worked on the
other platforms. Source-contract tests could validate Kotlin state transitions
but could not prove that synthesized Android `MotionEvent`s reached Chromium
and Cocos. Maintaining two execution paths also allowed platform behavior to
diverge after the shared state machine had already classified the same gesture.

## Decision

Android, iOS, and OpenHarmony all select `touchAdapter: javascript`. The shared
adapter executes every game command with JavaScript mouse or wheel events on
`GameCanvas`.

Primary input uses the same frame-synchronized sequence on all three platforms:

1. Send a neutral positioning `mousemove`.
2. Cross two animation-frame boundaries before `mousedown`, so one complete
   Cocos `Square.update` can publish the new `mouseInLnC` regardless of callback
   registration order.
3. Send drag moves with the primary button held.
4. After a final drag move, wait one animation frame before the original
   `mouseup`.
5. For a gesture moved more than 20 physical pixels, let two game frames clear
   the game's click guard, then send one `mousedown`/`mouseup` pair at the
   release tile. PvZGE 0.13.0 plants from lawn `mousedown`, not from `mouseup`.
   Sub-threshold finger jitter remains a single click.

A fast tap that ends before the delayed down completes its down/up pair after
the positioning boundaries. Adding a second finger or cancelling the touch
clears a pending primary event without replay. Android uses a normal `WebView`;
the custom native mouse state machine is not part of the runtime path and is
not a fallback.

DOM ownership, the GP-Next and form-control allowlist, failure closure,
diagnostics, gesture classification, and physical-pixel thresholds remain in
the shared modules.

## Alternatives considered

### Continue repairing native Android mouse injection

Rejected because multiple source-level corrections did not restore Android
device input, while the JavaScript execution path already produced the required
plant-selection and drag-release timing on the other WebView engines.

### Fall back to native injection when JavaScript fails

Rejected because fallback would make failures device-dependent and could emit
duplicate or partial gestures. Missing dependencies continue to fail closed.

### Copy the reference APK's Android split exactly

Rejected because the compatibility target is the event result visible to the
game, not Android WebView implementation details from the reference package.

## Consequences

- One executable JavaScript behavior suite covers all three platforms.
- The behavior suite models the supplied PvZGE Lite 0.13.0 placement seam:
  `Mouse.position` is synchronous, lawn targeting is frame-derived, and plant
  placement is down-triggered.
- Android no longer depends on synthesized native mouse `MotionEvent`s.
- Platform-specific wheel calibration may still differ to produce the same
  in-game direction and distance.
- Real-device acceptance remains required because JavaScript event delivery can
  still differ between Chromium WebView, WKWebView, and ArkWeb.
