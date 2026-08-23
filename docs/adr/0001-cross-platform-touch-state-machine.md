# ADR-0001: Use one touch command contract with platform adapters

## Status

Superseded by ADR-0002

## Date

2026-08-23

## Context

The Android reference APK disables JavaScript single-finger mouse synthesis and
uses native WebView mouse down/move/up plus generic scroll events. Its
JavaScript extension still suppresses original game touches and synthesizes the
secondary click. Copying that implementation to iOS WKWebView and OpenHarmony
ArkWeb is not possible because their public input injection capabilities
differ. The Loader must also preserve native form and GP-Next interaction
instead of routing every WebView touch to the game.

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

- Android keeps the reference division: JavaScript owns right-click synthesis
  and touch suppression; a tested Kotlin state module drives one complete
  native primary down/move/up stream plus `AXIS_VSCROLL` events.
- iOS and OpenHarmony execute the same command types as JavaScript mouse and
  wheel events, with animation-frame boundaries around primary down and dragged
  primary up so Cocos samples the intended pointer coordinates first.

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
