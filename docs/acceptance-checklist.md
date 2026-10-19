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
- Android inlines the shared bridge scripts as the first `<head>` script of every HTML document it serves, so a System WebView without `DOCUMENT_START_SCRIPT` still starts the game; a GameHost launch failure logs the WebView package and version.
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
- The choice only changes when the player toggles it: restarting the Loader, a successful, failed or cancelled import, and a legacy resource migration all preserve it.
- When enabled, continuously valid gameplay waits three seconds before sending `A` keydown, sends keyup after 50 ms, then repeats every three seconds.
- Leaving gameplay, pausing, entering an air-raid/special stage, focusing a native input/select/editable element, backgrounding, or losing window focus cancels the pending cycle.
- Returning to valid foreground gameplay starts a fresh three-second wait with no catch-up presses.
- A GP-Next session starts Loader automatic collection when the manifest value is enabled, independently of GP-Next's own auto-collect control.
- Automatic collection only reads game modules Cocos has already executed (`System.get`) and never imports them; with it enabled, turning on JS Modding and letting the game restart does not fail project startup (`v.createLineLenDir`).
- Failure to import the game-state modules disables automatic collection and logs the failure once without affecting gameplay.
- The removed legacy in-game menu and its former 1.5-second unscoped collector are absent from Android, iOS, HarmonyOS, and shared assets.

## GP-Next 0.15 and JS Modding ownership

- A 0.15 resource whose entry bundle explicitly references a local `gp-next-*.js` bundle is detected as GP-Next when the required patcher and file-loader fingerprints are in that referenced bundle.
- A missing JS Mod loader fingerprint does not make the resource incompatible; a missing patcher or file-loader fingerprint still does.
- Expanding Loader launch controls never shows `JS Modding`, including for a compatible GP-Next resource.
- Legacy Manifest and prepared-session JSON containing `jsModdingEnabled` is accepted, but the field is ignored and omitted from the next persisted value.
- Android, iOS, and HarmonyOS do not pass a JS Modding field through `GameSession`, do not load `js_modding.js`, and never read or write `gp-next-settings`.
- An existing game-owned enabled or disabled state remains unchanged. The user manages all later changes with the in-game switch.
- Android, iOS, and HarmonyOS expose the same 0.15 command set: `plugin:dialog|open`, `plugin:fs|lstat`, `plugin:fs|stat`, `plugin:fs|rename`, and `plugin:fs|write_file`. `lstat`/`stat` report `mtime` in milliseconds.
- Neither the launcher nor a GameHost creates `gp-next` before GP-Next starts. On a fresh install GP-Next creates `gp-next/configuration-state.json` itself and its Mods page offers installation, not "更新模组管理".
- With an existing legacy `gp-next`, "更新模组管理" → 保存配置 → restart succeeds, and later Mod enable/disable/order changes persist across restarts.
- After `configuration-state.json` exists, the patch-folder import (`plugin:opener|open_path`) rejects ZIP packs with a message pointing to the GP-Next Mods page; JSON/JSON5 patches are still accepted.
- `plugin:dialog|open` supports one ZIP or one folder. Native code copies it into the GP-Next sandbox and returns a path ending in `selection.zip` or `selection` respectively.
- The previous selection is removed before the next picker opens. Cancellation, staging failure, and GameHost exit also remove selection staging; cancellation resolves to `null`.
- Selected content rejects symbolic links, invalid names, more than 10,000 entries, or more than 512 MiB before the game installs it.
- File operations remain confined to AppData base directory 14 and the `gp-next` root; traversal, foreign base directories, and root moves/removals are rejected consistently. Like Tauri's `std::fs::rename`, `plugin:fs|rename` atomically replaces an existing destination file.
- Android, iOS, and HarmonyOS resolve `AppData/gp-next/...` directly from the session's explicit `gpNextRoot`; resolution does not depend on the resource slot's parent path matching that root.
- Large binary writes are split into 96 KiB bridge requests, committed only after every byte arrives, and abandoned transfers are cleaned on failure or GameHost exit.
- On a real device for each maintained platform, install the same trusted test Mod once from ZIP and once from a folder, restart the game, and verify GP-Next can load the installed content from `gp-next/installed`.
- Imported JS Mods are executable game content and are not evaluated by the Loader itself; device acceptance uses only trusted test packages.

## Garden extras

- Seven quick taps on the sidebar icon (under 0.8 s apart) find the tool shed: taps four to six count down, the seventh opens the Logs page with a 工具棚 section. Seven more taps, or 收起工具棚, put it away. The choice survives a restart.
- With 触摸轨迹记录 on and the tool shed found, the next game writes `game.touch` / `touch_trace` INFO events about every 2 s while touching; each message is a JSON array within 1,900 characters and no entry repeats. With either off, no `touch_trace` events appear.
- 本地数据 in the tool shed shows `manifest.json`, `app_settings.json` and `journal.json` as the launcher holds them.
- After returning from a game, the Play page shows 上次游玩 (today/yesterday/date and time), that session's length and the total. Time with the app in the background does not count; a launch failure records nothing.
- The Resources page shows 版本年轮 once a resource exists: an existing install starts with its current version, each successful import adds a ring at the right, and at most 30 are kept.
- Importing a newer game version keeps the completed panel open with a growing sprout, `old → new`, and 更新说明 opening `github.com/Gzh0821/pvzg_site/releases/tag/<version>` for public x.y.z releases; dismissing it closes the panel. Same-version and first imports finish as before.
- Importing an older game version asks before replacing the active one after validation. 取消 keeps the current game and slot, shows 已取消导入, and records no error; 仍然导入 activates it.
- Each import shows one tip under its progress steps, unchanged until the import ends.
- During a `theme` window in the remote `announcements.json` the accent colour (`accentDark` in dark mode) and the badge on the sidebar icon change; outside the window, offline with no cached feed, or with a malformed theme the launcher stays green and the announcement still works. Clients without theme support ignore the field.
- `urls` in the remote `announcements.json` replaces the launcher's links: `loaderGithub` and `bilibili` (About panel and announcement dialog), `gameGithub` (About panel and the resources page GitHub download), `loaderCloudDrive` (Settings 网盘更新), `gameCloudDrive` (resources page 网盘下载) and `gameReleaseNotes` (the upgrade's 更新说明, which must contain `{version}`). A fetched link replaces the built-in one for good: a later file that leaves the entry out or makes it non-https keeps the last fetched link, and only a newer valid entry replaces it.
- After a successful fetch the feed is saved as `announcements.json` in the app root with every link fetched so far, so an offline start keeps those links and the last announcement and theme; before the first successful fetch the built-in links apply. When `raw.githubusercontent.com` fails the loader reads the same file from jsDelivr, which can lag behind GitHub; purge it at `https://purge.jsdelivr.net/gh/Dey410/GardendlessLoader@main/announcements.json` after an urgent change.
- The first game launch after install shows the gesture hint at the bottom of the game: three touch mappings and the platform's way back. The first touch or click fades it; later launches never show it.

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
- Every Loader error, in the SnackBar, the failed import panel, the resource card's 最近错误 and GP-Next rows, and the logs page, shows the fix hint that `userErrorCatalog` gives its error code.
- ZIP import failures report their cause to Flutter on every platform: `zip_docs_missing`, `zip_invalid`, `zip_encrypted`, `zip_unsupported`, `zip_path_unsafe` or `zip_write_failed`, with `zip_import_failed` for anything else. Each cause shows its own hint.
- An Android System WebView without `WEB_MESSAGE_LISTENER` writes exit-result code `webview_unsupported`, and the launcher tells the user to update the WebView.
- HarmonyOS CI emits a skip notice instead of failing when `OHOS_COMMANDLINE_TOOLS_URL` is not configured.
