<p align="center">
  <img src="tool/generated_icons/app_icon_master.png" alt="GardendlessLoader icon" width="96" height="96">
</p>

# GardendlessLoader

[中文](README.md)

`GardendlessLoader` is a Flutter local loader for user-supplied
[`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web) web resource
packages on Android, iOS, and HarmonyOS/OpenHarmony.

The app lets users select a resource ZIP, extracts and locates the bundled
`docs` web build, validates it, serves it from a local HTTP server, and opens
the game in an in-app WebView.

> [!IMPORTANT]
> This project does not bundle, download, update, or redistribute
> `PvZ2 Gardendless` game resources. Users must provide their own resource ZIP
> and import it locally.

## Features

- Finds and extracts a valid `docs` resource directory from a selected ZIP.
- Validates the expected `PvZ2 Gardendless` Cocos web build shape, title, and fingerprints.
- Serves static files from `http://127.0.0.1:26410`.
- Uses a landscape, immersive WebView and blocks non-local requests by default.
- Shows import progress, extracts directly into the inactive slot, keeps the active slot on failure, and recovers unfinished transactions at startup.
- Provides copyable diagnostics for resource, platform, WebView, and local server state.
- Adapts the game viewport between `16:10` and `17:9`, and supports inline home-page announcements, independent loader/game update checks, and auto sunlight collection.
- Detects the imported game version from the page title and checks it against stable [`pvzg_site` tags](https://github.com/Gzh0821/pvzg_site/tags); available updates link to the game repository and the shared cloud drive.
- Builds Android, iOS, and HarmonyOS/OpenHarmony artifacts in GitHub Actions.

## Usage

1. Get a `PvZ2 Gardendless` resource ZIP from the upstream project or another trusted source.
2. Open `GardendlessLoader` and choose `Select ZIP to import`.
3. The app searches the ZIP root and nested directories for a valid `docs` and extracts it directly into the inactive resource slot.
4. After import succeeds, start the game. It loads from the local origin.

### In-game touch controls

- Single-finger tap or drag: left mouse click or drag.
- Two-finger tap: right mouse click at the center of both touches.
- Two-finger swipe: mouse wheel; after movement crosses the threshold, the gesture can no longer right-click.
- Three or more touches: no mouse mapping; the current touch gesture is cancelled.
- Physical mice and keyboards continue through the platform WebView unchanged.

A two-finger tap must finish within 250 milliseconds without moving its center more than 14 CSS pixels. When enabled in the game menu, auto sunlight collection simulates one `A` key press every 1.5 seconds. The game watermark is enabled by default, can be disabled from the menu, and remembers the last choice.

Imported resources are stored under an app-created `GardendlessLoader` directory:

```text
GardendlessLoader/
  slot-a/          # resource slot A
  slot-b/          # resource slot B
  manifest.json    # active slot, transaction state, stats, and game version
```

At rest, only the active slot contains game files and the other slot is empty.
During an update, at most the old active resource and the new candidate coexist.
The manifest switches only after validation and the local self-check succeed,
then the old slot is cleared. The home screen and diagnostics show the resource
root and active slot for the current device.

## Resource Requirements

The selected ZIP must contain a valid `PvZ2 Gardendless` web build directory.
It can be at the ZIP root or under a nested path such as `release/docs`.

Minimum expected shape:

```text
docs/
  index.html
  assets/
  cocos-js/
    cc.js
  src/
    settings.json
    import-map.json
```

The validator also checks that:

- `index.html` has a title containing `PvZ2 Gardendless`.
- A title version such as `0.11.0`, `v0.11.0`, or `0.12.0-next` is detected and shown as the imported game version.
- `index.html` contains a `pvzge` or `play.pvzge.com` fingerprint.
- `src/settings.json` is valid JSON and looks like a Cocos configuration file.

## Development

This repository expects Flutter with Dart `>=3.5.0 <4.0.0`.

```powershell
flutter pub get
flutter test
flutter run
```

Useful project files:

| Path | Purpose |
| --- | --- |
| `lib/src/app_controller.dart` | App state, import flow, server lifecycle, announcements, and update checks |
| `lib/src/services/resource_picker_service.dart` | ZIP picking, path safety, `docs` discovery, and extraction |
| `lib/src/services/import_service.dart` | Two-slot import, atomic activation, legacy migration, and startup recovery |
| `lib/src/services/local_game_server.dart` | Local HTTP server, MIME handling, and self-checks |
| `lib/src/services/resource_validator.dart` | Resource shape, title, and Cocos config validation |
| `lib/src/services/game_update_check_service.dart` | Local game version detection, stable tag selection, and version comparison |
| `lib/src/ui/home_page.dart` | Import, status, announcement, update, and diagnostics UI |
| `lib/src/ui/game_page.dart` | Landscape WebView shell, menu, and helper toggles |
| `lib/src/web/touch_patch.dart` | Single-finger left click, two-finger right click/wheel, and cancellation state machine |
| `announcements.json` | Remote announcement payload |

## Build

### Android

```powershell
flutter build apk --release
```

GitHub Actions can sign the release APK when these repository secrets are set:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Without signing secrets, CI keeps building with debug signing.

### iOS

```powershell
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

CI packages an unsigned IPA artifact for manual signing or later distribution.

### HarmonyOS / OpenHarmony

HAP builds require an OpenHarmony-compatible Flutter SDK plus DevEco Studio or
command-line tools with `ohpm`, `hvigor`, `node`, and JDK 17 configured. The
stock Flutter stable SDK does not provide `flutter build hap`.

CI uses:

```text
https://gitcode.com/openharmony-tpc/flutter_flutter.git
ref: oh-3.35.7-release
```

Enable OpenHarmony dependency overrides before local builds:

```powershell
Copy-Item pubspec_overrides.ohos.yaml pubspec_overrides.yaml
flutter doctor -v
flutter pub get
flutter test
flutter build hap --release --target-platform ohos-arm64
flutter build hap --release --target-platform ohos-x64
```

## CI

`.github/workflows/build-mobile.yml` runs tests and builds:

- Android release APK
- unsigned iOS IPA
- unsigned HarmonyOS HAPs when `OHOS_COMMANDLINE_TOOLS_URL` is configured

When HarmonyOS tools are not configured, that job is skipped without blocking
other platform artifacts.
