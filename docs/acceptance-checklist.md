# GardendlessLoader MVP Acceptance Checklist

## Happy path

- First launch creates empty `GardendlessLoader/slot-a/` and `slot-b/` directories.
- Selecting a ZIP extracts its valid `docs` directly into the inactive slot.
- Import shows progress and succeeds.
- Import self-check validates required files directly without opening a port.
- After the first import, manifest activates `slot-a` and `slot-b` remains empty.
- After an update, manifest activates the candidate slot and clears the old slot.
- Launch page shows resource imported and detected title.
- Start game destroys the Flutter launcher and opens a landscape native GameHost.
- Android loads from `https://appassets.androidplatform.net`, iOS from `gardendless-game://localhost`, and HarmonyOS from `https://gardendless.invalid`.
- The entry URL includes `?generation=<activationGeneration>` while the platform origin remains stable.
- The in-game export button opens a save-location picker and writes a `.json` save file.
- The exported `.json` save file can be imported back by the game.
- iPad/iOS export uses the document picker instead of a share sheet.
- Android and HarmonyOS export use a document save picker instead of silently doing nothing.
- Web export uses the browser download flow.
- Background/foreground preserves the native WebView session unless the renderer exits.
- Renderer exit returns an explicit failure result and recreates the Flutter launcher.
- Android back, HarmonyOS back, and the iOS left-edge gesture destroy the native WebView and return directly to the Flutter launcher.
- Relaunch validates the slot selected by `manifest.activeSlot`.
- Reimport keeps the same per-platform origin and does not clear WebView localStorage/IndexedDB.
- HarmonyOS CI exports unsigned arm64 and x64 HAP artifacts under `build/ohos/unsigned/` when the OpenHarmony Flutter and DevEco command-line toolchain is configured.

## Touch input

- On Android, one-finger taps plant on lawn tiles and collect suns exactly once.
- On Android, one-finger dragging keeps the left button pressed and follows the active finger without jumping to another finger.
- On Android, adding a second finger releases the left button at the first finger's last position.
- On Android, returning from two fingers to one does not restart a left-button gesture until every finger is lifted.
- On Android, two-finger center movement of at most 20 physical pixels vertically remains a right-click candidate, regardless of horizontal movement.
- On Android, a two-finger gesture whose center exceeds 20 physical pixels vertically scrolls at the configured `-4.5` multiplier and does not emit a right click.
- On Android, a stationary two-finger gesture emits one right click to `GameCanvas` when the first finger is lifted, even when held longer than 250 ms; lifting the remaining finger emits no second click.
- On Android, cancelling the gesture, backgrounding the app, removing the target, or losing focus never leaves a mouse button pressed.
- On Android, text inputs, selects, editable content, and GP-Next controls retain native touch behavior.
- Repeat the complete touch-input matrix above on iOS WKWebView before release.
- Repeat the complete touch-input matrix above on HarmonyOS ArkWeb before release.

## Automatic sun collection

- With any valid resource (standard or GP-Next), a gray `自动收集` panel is attached directly above `开始游戏`; only the panel's top corners and the button's bottom corners are rounded.
- The whole panel and its switch toggle the setting; the enabled switch uses the launcher's blue accent.
- With no valid resource, the panel is absent and the start button keeps all four rounded corners.
- During an import over an existing standard resource, the panel remains visible at reduced opacity and cannot be changed.
- Restarting the Loader preserves the current resource's choice; every successful import resets it to off, while failed or cancelled imports preserve it.
- When enabled, continuously valid gameplay waits three seconds before sending `A` keydown, sends keyup after 50 ms, then repeats every three seconds.
- Leaving gameplay, pausing, entering an air-raid/special stage, focusing a native input/select/editable element, backgrounding, or losing window focus cancels the pending cycle.
- Returning to valid foreground gameplay starts a fresh three-second wait with no catch-up presses.
- A GP-Next session starts Loader automatic collection when the manifest value is enabled, independently of GP-Next's own auto-collect control.
- Failure to import the game-state modules disables automatic collection and logs the failure once without affecting gameplay.
- The removed legacy in-game menu and its former 1.5-second unscoped collector are absent from Android, iOS, HarmonyOS, and shared assets.

## Failure paths

- A ZIP without a valid `docs/index.html` rejects import and leaves the active slot unchanged.
- Fingerprint mismatch rejects import.
- Candidate self-check failure clears the candidate slot and leaves the active slot unchanged.
- A required-file self-check failure rejects the candidate without changing the active slot.
- Encoded traversal, double encoding, symbolic links, and paths outside the active slot are rejected by every native resource handler.
- GET, HEAD, Range/206/416, ETag/304, MIME, Unicode names, concurrent reads, and cancellation work in every native resource handler.
- An interruption before `readyToActivate` keeps the old active slot and clears the candidate.
- An interruption at `readyToActivate` completes activation on the next launch.
- Old-slot cleanup failure keeps the new slot active and retries cleanup on the next launch.
- A corrupt manifest is rebuilt from valid slot metadata using the greatest activation generation.
- Upgrade migration prefers valid legacy `current`, otherwise valid `previous`, and removes all legacy resource directories after success.
- Cancelling game save export shows a cancellation notice instead of an export failure.
- HarmonyOS CI emits a skip notice instead of failing when `OHOS_COMMANDLINE_TOOLS_URL` is not configured.
