<p align="center">
  <img src="tool/generated_icons/app_icon_master.png" alt="GardendlessLoader icon" width="96" height="96">
</p>

# GardendlessLoader

[中文](README.md)

`GardendlessLoader` is a Flutter local loader for user-supplied
[`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web) web resource
packages on mobile and web platforms.

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
- Shows import progress, rolls back failed imports, and recovers unfinished startup transactions.
- Provides copyable diagnostics for resource, platform, WebView, and local server state.
- Supports inline home-page announcements, GitHub Release update checks, auto sunlight collection, and stretch mode.
- Builds Android, iOS, HarmonyOS/OpenHarmony, and Web artifacts in GitHub Actions.

## Usage

1. Get a `PvZ2 Gardendless` resource ZIP from the upstream project or another trusted source.
2. Open `GardendlessLoader` and choose `Select ZIP to import`.
3. The app searches the ZIP root and nested directories for a valid `docs`, extracts it, and imports it into `current`.
4. After import succeeds, start the game. It loads from the local origin.

Imported resources are stored under an app-created `GardendlessLoader` directory:

```text
GardendlessLoader/
  import/docs/     # latest docs extracted from ZIP
  current/         # active resources
  previous/        # previous resources used for rollback
  staging/         # temporary import transaction directory
  manifest.json    # import state, resource stats, and announcement state
```

The exact resource root depends on the platform. The home screen shows the full
path for the current device.

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
| `lib/src/services/import_service.dart` | Staged import, current switching, rollback, and startup recovery |
| `lib/src/services/local_game_server.dart` | Local HTTP server, MIME handling, and self-checks |
| `lib/src/services/resource_validator.dart` | Resource shape, title, and Cocos config validation |
| `lib/src/ui/home_page.dart` | Import, status, announcement, update, and diagnostics UI |
| `lib/src/ui/game_page.dart` | Landscape WebView shell, menu, and helper toggles |
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
- Web bundle
- unsigned iOS IPA
- unsigned HarmonyOS HAPs when `OHOS_COMMANDLINE_TOOLS_URL` is configured

When HarmonyOS tools are not configured, that job is skipped without blocking
other platform artifacts.
