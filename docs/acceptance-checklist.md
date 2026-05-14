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
- Background/foreground does not reload while server is alive.
- If server died while backgrounded, app restarts server, reloads once, and shows one notice.
- Returning home asks for confirmation, then stops server and destroys WebView.
- Relaunch validates `current`.
- Reimport keeps the same origin and does not clear WebView localStorage/IndexedDB.
- HarmonyOS build exports `ohos/entry/build/default/outputs/default/entry-default-signed.hap` when the OpenHarmony Flutter and DevEco command-line toolchain is configured.

## Failure paths

- Missing `import/docs/index.html` rejects import.
- Fingerprint mismatch rejects import.
- Copy/self-check failure leaves previous `current` intact when available.
- Port `26410` occupation retries once, then fails and rolls back.
- MIME self-check failure rolls back.
- Broken `current` at startup falls back to valid `previous`, or returns to import state if both are invalid.
- HarmonyOS CI fails with a clear setup error when `OHOS_COMMANDLINE_TOOLS_URL` is not configured.
