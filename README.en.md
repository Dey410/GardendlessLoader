<p align="center">
  <img src="tool/generated_icons/app_icon_master.png" alt="GardendlessLoader icon" width="96" height="96">
</p>

# GardendlessLoader

[中文](README.md)

`GardendlessLoader` is a Flutter local loader for user-supplied
[`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web) web resource
packages on Android, iOS, and HarmonyOS/OpenHarmony.

The app lets users select a resource ZIP, extracts and locates the bundled
`docs` web build, and validates it. Flutter only owns import, two-slot
transactions, updates, settings, and diagnostics. Gameplay runs in a separate
native Android WebView, iOS WKWebView, or HarmonyOS ArkWeb page that streams the
active slot directly, without a local HTTP server or a Flutter game page.

> [!IMPORTANT]
> This project does not bundle, download, update, or redistribute
> `PvZ2 Gardendless` game resources. Users must provide their own resource ZIP
> and import it locally.

## Features

- Finds and extracts a valid `docs` resource directory from a selected ZIP.
- Validates the expected `PvZ2 Gardendless` Cocos web build shape, title, and fingerprints.
- Native GameHosts intercept a fixed synthetic origin and stream Range/ETag/MIME responses without opening a socket.
- Gameplay uses a full-screen, landscape native WebView; the launcher FlutterEngine is released while the game runs, and non-allowlisted remote requests are blocked.
- Detects the GP-Next 1.4.2 desktop build, injects a mobile compatibility bridge without modifying game resources, and conditionally exposes `Open GP-Next` in the game menu.
- Shows import progress, extracts directly into the inactive slot, keeps the active slot on failure, and recovers unfinished transactions at startup.
- Provides copyable diagnostics containing the native GameHost, synthetic origin, and `resourceServer: none`.
- Sends game input directly to the platform WebView and supports home-page announcements, independent loader/game update checks, and auto sunlight collection.
- Detects the imported game version from the page title and checks it against stable [`pvzg_site` tags](https://github.com/Gzh0821/pvzg_site/tags); available updates link to the game repository and the shared cloud drive.
- Builds Android, iOS, and HarmonyOS/OpenHarmony artifacts in GitHub Actions.

## Usage

1. Get a `PvZ2 Gardendless` resource ZIP from the upstream project or another trusted source.
2. Open `GardendlessLoader` and choose `Select ZIP to import`.
3. The app searches the ZIP root and nested directories for a valid `docs` and extracts it directly into the inactive resource slot.
4. After import succeeds, start the game. The Flutter launcher exits and the platform-native GameHost loads the active slot.

The fixed per-platform origins are Android `https://appassets.androidplatform.net`,
iOS `gardendless-game://localhost`, and HarmonyOS/OpenHarmony
`https://gardendless.invalid`. Resource generations only change the entry query
`?generation=N`; each platform keeps its origin stable across updates.

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
  gp-next/
    packs/         # persistent GP-Next ZIP packs
    patches/       # persistent JSON/JSON5 single-file patches
  manifest.json    # active slot, transaction state, stats, and game version
```

At rest, only the active slot contains game files and the other slot is empty.
During an update, at most the old active resource and the new candidate coexist.
The manifest switches only after validation and the filesystem self-check succeeds,
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

### GP-Next compatibility

The loader currently targets GP-Next `1.4.2` from the inspected desktop build. An unknown GP-Next version remains importable and playable, but its compatibility bridge and `Open GP-Next` action are disabled with a diagnostic reason. Standard web builds retain their original path.

GP-Next-defined patch discovery, parsing, loading, saving, reloading, and JS Mod switch behavior is preserved. Only desktop system boundaries are mapped on mobile: AppData file APIs use the loader's `gp-next` sandbox, `open patch folder` invokes the system file picker, and save dialogs invoke the system exporter. Imports accept ZIP packs with a root `pack.json`, JSON, and JSON5; naked JavaScript is rejected. Replacements require confirmation and use a rollback-safe file swap. JS Mods remain disabled by GP-Next by default until the user explicitly enables them there.

The persistent `gp-next` directory is outside both game resource slots, so resource updates do not remove installed patches or Mods. The bridge rejects paths outside this sandbox and symbolic links. External WebView traffic remains blocked except for the fixed official domains used by the built-in GP-Next module.

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
| `lib/src/app_controller.dart` | App state, import flow, native GameHost launch, announcements, and update checks |
| `lib/src/services/resource_picker_service.dart` | ZIP picking, path safety, `docs` discovery, and extraction |
| `lib/src/services/import_service.dart` | Two-slot import, atomic activation, legacy migration, and startup recovery |
| `lib/src/services/resource_self_check.dart` | Candidate-slot filesystem self-check without a network service |
| `lib/src/services/resource_validator.dart` | Resource shape, title, and Cocos config validation |
| `lib/src/services/game_update_check_service.dart` | Local game version detection, stable tag selection, and version comparison |
| `lib/src/game_host/` | Durable GameSession, platform routing, and exit-result contract |
| `lib/src/ui/home_page.dart` | Import, status, announcement, update, and diagnostics UI |
| `assets/game_bridge/` | Shared document-start transport, GP-Next, touch, export, watermark, and menu scripts |
| `android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/` | Android native WebView GameHost |
| `ios/Runner/GameViewController.swift` | iOS native WKWebView GameHost |
| `ohos/entry/src/main/ets/game/` | HarmonyOS/OpenHarmony ArkWeb GameHost boundaries |
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
