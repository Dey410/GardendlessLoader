# ADR-0001: Use one touch command contract with platform adapters

## Status

Accepted

## Date

2026-08-23

## Context

The Android reference APK combines JavaScript mouse down/up events with native
WebView mouse moves and generic scroll events. Copying that implementation to
iOS WKWebView and OpenHarmony ArkWeb is not possible because their public input
injection capabilities differ. The Loader must also preserve native form and
GP-Next interaction instead of routing every WebView touch to the game.

The compatibility target is therefore the event sequence observed by Cocos,
including gesture transitions, coordinates, button state, right-click
classification, and in-game scroll behavior.

## Decision

Use a deterministic touch state module whose interface is normalized touch
frames in and game commands out. The command vocabulary is primary
down/move/up, neutral move, secondary down/up, and scroll.

`touch_input_adapter.js` owns DOM classification, strict native-target
allowlisting, `GameCanvas` targeting, failure closure, and optional bounded
diagnostic traces. It runs the shared JavaScript state module on all platforms.

Platform adapters execute the commands according to host capability:

- Android keeps the reference hybrid: JavaScript targets down/up/right-click at
  `GameCanvas`; a tested Kotlin state module drives native mouse moves and
  `AXIS_VSCROLL` events.
- iOS and OpenHarmony execute the same command types as JavaScript mouse and
  wheel events.

Platform-specific scroll constants are allowed only to match the same in-game
direction and distance. They do not change gesture classification.

Native controls are a strict allowlist. Missing `GameCanvas`, missing state
module, or adapter failure consumes the game gesture and emits no fallback
event. The old touch implementation is not a runtime fallback.

## Alternatives considered

### Copy the Android implementation to every platform

Rejected because WKWebView and ArkWeb cannot reproduce Android WebView's native
event path with the same public interfaces. It would copy platform accidents
rather than preserve game behavior.

### Use JavaScript mouse events exclusively

Rejected because Chromium WebView requires native mouse movement and generic
scroll state for the reference Android behavior.

### Maintain three unrelated gesture implementations

Rejected because thresholds, cancellation, and multi-finger transitions would
drift. Shared executable traces and the small command interface keep those
rules reviewable and testable.

## Consequences

- All touch behavior is specified through one small command interface.
- Android retains a native mirror for the commands that require native WebView
  input; its transitions require focused Kotlin tests.
- Every platform still needs real-device calibration and acceptance.
- Diagnostics remain off by default and contain no page or game content.
