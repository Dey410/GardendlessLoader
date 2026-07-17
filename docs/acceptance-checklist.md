# GardendlessLoader MVP Acceptance Checklist

## Happy path

- First launch creates empty `GardendlessLoader/slot-a/` and `slot-b/` directories.
- Selecting a ZIP extracts its valid `docs` directly into the inactive slot.
- Import shows progress and succeeds.
- Import self-check serves files from `http://127.0.0.1:26410`.
- After the first import, manifest activates `slot-a` and `slot-b` remains empty.
- After an update, manifest activates the candidate slot and clears the old slot.
- Launch page shows resource imported and detected title.
- Start game opens landscape WebView.
- Game loads from `127.0.0.1:26410`.
- The in-game export button opens a save-location picker and writes a `.json` save file.
- The exported `.json` save file can be imported back by the game.
- iPad/iOS export uses the document picker instead of a share sheet.
- Android and HarmonyOS export use a document save picker instead of silently doing nothing.
- Web export uses the browser download flow.
- Background/foreground does not reload while server is alive.
- If server died while backgrounded, app restarts server, reloads once, and shows one notice.
- Returning home asks for confirmation, then stops server and destroys WebView.
- Relaunch validates the slot selected by `manifest.activeSlot`.
- Reimport keeps the same origin and does not clear WebView localStorage/IndexedDB.
- HarmonyOS CI exports unsigned arm64 and x64 HAP artifacts under `build/ohos/unsigned/` when the OpenHarmony Flutter and DevEco command-line toolchain is configured.

## Failure paths

- A ZIP without a valid `docs/index.html` rejects import and leaves the active slot unchanged.
- Fingerprint mismatch rejects import.
- Candidate self-check failure clears the candidate slot and leaves the active slot unchanged.
- Port `26410` occupation retries once, then rejects the candidate without changing the active slot.
- MIME self-check failure rejects the candidate without changing the active slot.
- An interruption before `readyToActivate` keeps the old active slot and clears the candidate.
- An interruption at `readyToActivate` completes activation on the next launch.
- Old-slot cleanup failure keeps the new slot active and retries cleanup on the next launch.
- A corrupt manifest is rebuilt from valid slot metadata using the greatest activation generation.
- Upgrade migration prefers valid legacy `current`, otherwise valid `previous`, and removes all legacy resource directories after success.
- Cancelling game save export shows a cancellation notice instead of an export failure.
- HarmonyOS CI emits a skip notice instead of failing when `OHOS_COMMANDLINE_TOOLS_URL` is not configured.
