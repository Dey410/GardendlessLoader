<p align="center">
  <img src="tool/generated_icons/app_icon_master.png" alt="GardendlessLoader icon" width="96" height="96">
</p>

# GardendlessLoader

[中文](README.md)

`GardendlessLoader` is a Flutter mobile loader for user-supplied
[`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web) web resources.

It imports an extracted `docs` resource directory, serves it from a local HTTP
server, and opens the game in an in-app WebView on Android, iOS, and
HarmonyOS/OpenHarmony builds.

> [!IMPORTANT]
> This app does not bundle, download, update, or redistribute `PvZ2 Gardendless`
> game resources. Users provide their own extracted resources and import them
> locally.

## Features

- Local resource import from `GardendlessLoader/import/docs`.
- Resource validation for the expected `PvZ2 Gardendless` Cocos web build shape.
- Local static server at `http://127.0.0.1:26410`.
- Landscape in-app WebView with external navigation blocked by default.
- Import progress, rollback on failed import, and startup recovery.
- Diagnostics copy panel for support/debugging.
- Optional in-game helpers such as auto sunlight collection and stretch mode.
- Remote announcement support through `announcements.json`.

## How It Works

On first launch, the app creates a resource root named `GardendlessLoader`.
Users copy the extracted `docs` folder into:

```text
GardendlessLoader/import/docs/index.html
```

The app validates the import source, stages it, switches it into:

```text
GardendlessLoader/current
```

Then it self-checks key files through:

```text
http://127.0.0.1:26410
```

The WebView only loads the local origin while gameplay is active.

## Resource Requirements

The imported `docs` directory must contain a valid `PvZ2 Gardendless` web build.
At minimum, the validator expects:

```text
docs/
  index.html
  assets/
  cocos-js/
  src/
    settings.json
    import-map.json
```

`index.html` must include a `PvZ2 Gardendless` title/fingerprint, and
`src/settings.json` must look like a Cocos configuration file.

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
| `lib/src/app_controller.dart` | App state, import flow, server lifecycle, diagnostics |
| `lib/src/services/import_service.dart` | Staged import, rollback, startup recovery |
| `lib/src/services/local_game_server.dart` | Local static HTTP server and MIME/self-checks |
| `lib/src/services/resource_validator.dart` | Resource shape and fingerprint validation |
| `lib/src/ui/home_page.dart` | Import/status UI |
| `lib/src/ui/game_page.dart` | Landscape WebView game shell |
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

Without signing secrets, CI falls back to debug signing.

### iOS

```powershell
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

The CI workflow packages an unsigned IPA artifact for manual signing or later
distribution work.

### HarmonyOS / OpenHarmony

HAP builds require an OpenHarmony-compatible Flutter SDK plus DevEco Studio or
command-line tools with `ohpm`, `hvigor`, `node`, and JDK 17 configured.

The stock Flutter stable SDK does not expose `flutter build hap`. CI uses:

```text
https://gitcode.com/openharmony-tpc/flutter_flutter.git
ref: oh-3.35.7-release
```

Before building locally, enable the OpenHarmony plugin overrides:

```powershell
Copy-Item pubspec_overrides.ohos.yaml pubspec_overrides.yaml
flutter doctor -v
flutter pub get
flutter test
flutter build hap --release --target-platform ohos-arm64
```

Expected signed HAP output from the OpenHarmony build layout:

```text
ohos/entry/build/default/outputs/default/entry-default-signed.hap
```

In GitHub Actions, set `OHOS_COMMANDLINE_TOOLS_URL` to a DevEco/OpenHarmony
command-line tools archive. If the secret is missing, the HarmonyOS job is
skipped while Android and iOS artifacts continue to build.

## CI

The workflow in `.github/workflows/build-mobile.yml` builds:

- Android release APK
- unsigned iOS IPA
- unsigned HarmonyOS HAP when OpenHarmony tools are configured

It also runs Flutter tests before packaging mobile artifacts.
