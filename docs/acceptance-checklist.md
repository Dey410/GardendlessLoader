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
- A GP-Next ZIP with root `pack.json` is stored unchanged, while a ZIP whose complete meaningful payload is inside one wrapper directory is stored with that directory removed.
- Wrapped GP-Next normalization ignores `.DS_Store` and `__MACOSX`, never changes the selected source file, and leaves an existing installed pack unchanged when validation fails or replacement is declined.
- A GP-Next ZIP with multiple wrapper candidates, meaningful files outside the wrapper, deeper nesting, unsafe paths, symbolic links, or normalized path collisions is rejected.
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

- Android, iOS, and OpenHarmony all execute game touch commands through the shared JavaScript adapter; Android does not inject native mouse `MotionEvent`s or fall back to that path.
- Each one-finger gesture positions the Cocos pointer and crosses two animation-frame boundaries before JavaScript `MOUSE_DOWN`, allowing `Square.update` to publish the intended `mouseInLnC` first.
- Two-tap planting works as two independent JavaScript clicks: the first tap selects the plant card and the second tap plants on the chosen lawn tile immediately.
- Drag planting that moves more than 20 physical pixels starts with JavaScript `MOUSE_DOWN` on the plant card, emits every current-point `MOUSE_MOVE(buttons=1)`, ends the original drag, then emits one delayed `MOUSE_DOWN → MOUSE_UP` pair at the release tile because PvZGE 0.13.0 does not plant from lawn `MOUSE_UP`; sub-threshold finger jitter remains one click.
- The release-tile pair waits for at least two animation-frame boundaries and 50 ms after the original `MOUSE_UP`; the executable model covers a 60 Hz WebView with a 30 Hz Cocos loop, while higher refresh-rate ratios require device acceptance.
- A fast drag whose WebView reports only the distant `touchend` coordinate, with no intermediate `touchmove`, still plants at that release tile without another tap.
- A slow drag, long hold, and fast flick each plant exactly once at the current release tile; the delayed release-tile pair is cancelled rather than replayed if a new gesture, cancellation, or second-finger transition takes ownership.
- Every game mouse event targets `GameCanvas`, even if the touch starts on or ends over another non-native DOM element; native form and GP-Next controls remain excluded before mapping.
- Adding a second finger stops the left drag without synthesizing `MOUSE_UP`, and returning to one finger does not restart the gesture before every finger is lifted.
- `ACTION_CANCEL`/`touchcancel` does not synthesize `MOUSE_UP`; it clears internal candidates, consumes residual game touches, and requires a fresh gesture.
- Two-finger center movement of at most 20 physical pixels vertically remains a right-click candidate, regardless of horizontal movement.
- A two-finger gesture whose center exceeds 20 physical pixels vertically scrolls and does not emit a right click; calibrate each platform for the same in-game direction and distance rather than the same raw constant.
- A stationary two-finger gesture emits one right click to `GameCanvas` after both fingers are lifted, even when held longer than 250 ms.
- Text inputs, selects, editable content, and GP-Next controls retain native touch behavior on every platform.
- Real mouse and trackpad input remain native and are never mapped a second time; stylus input follows the one-finger path.
- Removing `GameCanvas` or withholding the state-machine asset consumes game touches, emits no mouse events, records the failure, and never guesses another target.
- With touch diagnostics enabled, the bounded trace contains input coordinates, owners, transitions, and command names, but no DOM text, form value, storage, or game data.
- On Android Chromium WebView, iOS WKWebView, and OpenHarmony ArkWeb, confirm a fast first tap selects a plant card, the second tap plants on the chosen lawn tile, and a card-to-lawn drag plants on release without another tap.
- Repeat the complete touch-input matrix on all three WebView engines before release; every adapter must let the game publish the positioning/final move before consuming the placement down/up pair.

## Automatic sun collection

- With any valid resource, launch controls start collapsed and neither `自动收集` nor `JS Modding` is present in the widget or semantics tree.
- The separate 56-by-72 arrow region on the right of `开始游戏` expands or collapses the controls without starting the game; its tooltip and icon reflect the current state.
- Expanding a standard resource shows only `自动收集`; the gray panel is attached directly above `开始游戏`, with only the panel's top corners and the button's bottom corners rounded.
- The whole panel and its switch toggle the setting; the enabled switch uses the launcher's blue accent.
- With no valid resource, the panel is absent, the arrow is disabled, and the start button keeps all four rounded corners.
- During an import over an existing standard resource, an already expanded panel remains visible at reduced opacity and cannot be changed.
- Collapsing hides every setting row, and re-entering the Loader home page always restores the collapsed presentation without changing persisted setting values.
- Restarting the Loader preserves the current resource's choice; every successful import resets it to off, while failed or cancelled imports preserve it.
- When enabled, continuously valid gameplay waits three seconds before sending `A` keydown, sends keyup after 50 ms, then repeats every three seconds.
- Leaving gameplay, pausing, entering an air-raid/special stage, focusing a native input/select/editable element, backgrounding, or losing window focus cancels the pending cycle.
- Returning to valid foreground gameplay starts a fresh three-second wait with no catch-up presses.
- A GP-Next session starts Loader automatic collection when the manifest value is enabled, independently of GP-Next's own auto-collect control.
- Failure to import the game-state modules disables automatic collection and logs the failure once without affecting gameplay.
- The removed legacy in-game menu and its former 1.5-second unscoped collector are absent from Android, iOS, HarmonyOS, and shared assets.

## GP-Next JS Modding

- `JS Modding` defaults to off for new, old, and malformed Loader preference/session data.
- The row appears only after expanding controls for a compatible GP-Next resource whose fingerprint includes the JS Mod loader; standard and incompatible resources never show it.
- The whole row and its switch update the Loader-owned choice without a confirmation dialog, and the enabled switch uses the launcher's blue accent.
- The choice survives Loader restarts and successful game-resource updates, but takes effect only on the next game launch.
- Android, iOS, and HarmonyOS pass the same boolean through `GameSession` and load `js_modding.js` only for a compatible GP-Next session.
- At document start, before GP-Next initializes, the shared script changes only `gp-next-settings.experimental.jsModding` and preserves all other valid settings and experimental flags.
- Enabling writes exact boolean `true`; disabling writes exact boolean `false`; malformed settings JSON is replaced with the smallest valid settings object without blocking game startup.
- Standard and incompatible resources do not read or write `gp-next-settings`, even if the Loader preference remains enabled from an earlier compatible resource.
- The locked in-game JS Modding control never overrides the Loader choice; there is no bidirectional synchronization.
- Imported JS Mods are treated as executable game content and are not evaluated by the Loader itself; device acceptance uses only trusted test packages.

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
