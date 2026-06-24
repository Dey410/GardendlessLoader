# GardendlessLoader MVP Acceptance Checklist

## Happy path

- First launch creates `GardendlessLoader/import/`.
- User copies extracted `docs` to `GardendlessLoader/import/docs/index.html`.
- App detects valid import source after checking import directory.
- Import shows progress and succeeds.
- Import self-check serves files from `http://127.0.0.1:26410`.
- Launch page shows resource imported and detected title.
- Start game opens landscape WebView.
- Game loads from `127.0.0.1:26410`.
- The in-game export button opens a save-location picker and writes a `.json` save file.
- The exported `.json` save file can be imported back by the game.
- iPad/iOS export uses the document picker instead of a share sheet.
- Android and HarmonyOS export use a document save picker instead of silently doing nothing.
- macOS, Windows, Linux, and Web export use the platform save dialog or browser download flow.
- Background/foreground does not reload while server is alive.
- If server died while backgrounded, app restarts server, reloads once, and shows one notice.
- Returning home asks for confirmation, then stops server and destroys WebView.
- Relaunch validates `current`.
- Reimport keeps the same origin and does not clear WebView localStorage/IndexedDB.
- HarmonyOS CI exports unsigned arm64 and x64 HAP artifacts under `build/ohos/unsigned/` when the OpenHarmony Flutter and DevEco command-line toolchain is configured.

## Failure paths

- Missing `import/docs/index.html` rejects import.
- Fingerprint mismatch rejects import.
- Copy/self-check failure leaves previous `current` intact when available.
- Port `26410` occupation retries once, then fails and rolls back.
- MIME self-check failure rolls back.
- Broken `current` at startup falls back to valid `previous`, or returns to import state if both are invalid.
- Cancelling game save export shows a cancellation notice instead of an export failure.
- HarmonyOS CI emits a skip notice instead of failing when `OHOS_COMMANDLINE_TOOLS_URL` is not configured.
