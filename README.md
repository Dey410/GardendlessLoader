<h1 align="center">GardendlessLoader</h1>

<img src="tool/generated_icons/app_icon_master.png" align="left" width="150" height="150" style="border-radius: 17%" alt="GardendlessLoader icon">

[![Build Artifacts](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml/badge.svg)](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml)
[![GitHub Release](https://img.shields.io/github/v/release/Dey410/GardendlessLoader?include_prereleases&sort=semver)](https://github.com/Dey410/GardendlessLoader/releases)
[![Commit Activity](https://img.shields.io/github/commit-activity/m/Dey410/GardendlessLoader)](https://github.com/Dey410/GardendlessLoader/commits/main)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

*Let the endless garden keep growing on mobile devices.*

GardendlessLoader is a local resource loader for `PvZ2 Gardendless` on Android, iOS, and HarmonyOS/OpenHarmony.

Read the [Introduction](#introduction) below to learn more, or go directly to [Downloads](https://github.com/Dey410/GardendlessLoader/releases) or [Issue Reporting](https://github.com/Dey410/GardendlessLoader/issues).

[中文](README.zh-CN.md)

<br clear="left">

## Introduction

GardendlessLoader is a local resource loader built with Flutter. It loads [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web) on Android, iOS, and HarmonyOS/OpenHarmony.

The loader supports standard Cocos and GP-Next builds that follow the Gardendless web resource structure and pass the app's resource validation.

It also supports resource packages optimized for mobile devices, such as lightweight builds with lower-resolution textures, adjusted audio quality, or modified loading logic.

## Get GardendlessLoader

You can obtain the app in the following ways:

1. **Published releases:** Download the latest published version from [GitHub Releases](https://github.com/Dey410/GardendlessLoader/releases).
2. **Automated builds:** Select a successful run in [GitHub Actions](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml) and download the artifact for your platform.
3. **Build from source:** Follow the [Build](#build) instructions below.

> [!NOTE]
> The automated iOS artifact is unsigned and must be signed before installation.
> The HarmonyOS/OpenHarmony HAP is generated only when the required command-line tools are configured in CI. It is also unsigned and must be signed before installation.

## Get a Gardendless Resource Package

You can obtain an importable resource package in the following ways:

- Use a package optimized for mobile devices:

  1. Download it from [Quark Cloud Drive](https://pan.quark.cn/s/c3da839ca8b1?pwd=qLBU) using extraction code `qLBU` (recommended). The project maintainer may receive a small referral reward when you download through this link, which helps support development.

  2. Use GitHub Actions in [extract-pvzge-gpnext](https://github.com/Dey410/extract-pvzge-gpnext) to build a ZIP automatically. The resulting package includes GP-Next and mobile optimizations.

- Use the original upstream resources: open [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web), then select `Code` → `Download ZIP`.

## Quick Start

1. Obtain a web resource ZIP from the [`PvZ2 Gardendless` upstream project](https://github.com/Gzh0821/pvzge_web) or another trusted source.
2. Open GardendlessLoader and select **Select ZIP to import**.
3. Wait for the app to finish extraction, validation, and resource-slot switching.
4. Select **Start Game** to enter the platform-native GameHost.

To update the resources, select another ZIP. New resources are written to the inactive slot and become active only after validation and the filesystem self-check succeed.

### In-game Touch Controls

| Gesture | Mapping |
| --- | --- |
| Single-finger tap or drag | Left mouse click or drag |
| Two-finger tap | Right mouse click at the center of both touches |
| Two-finger swipe | Mouse wheel |
| Three or more fingers | Cancel the current touch mapping |
| Physical mouse and keyboard | Handled natively by the system WebView |

When **Auto Collect Sun** is enabled in the game menu, the app simulates one `A` key press approximately every 3 seconds while gameplay is active. It does not trigger when the game is paused, the app is in the background, or a text input has focus.

> [!IMPORTANT]
> Some of the project's UI, logic, and platform adaptation were developed with the assistance of AI tools and are continually improved through code review, automated tests, and device acceptance testing. If you encounter unexpected behavior, include the diagnostic summary when reporting it.

### Local Resource Layout

The app creates the following layout in its platform-specific application directory:

```text
GardendlessLoader/
  slot-a/          # resource slot A
  slot-b/          # resource slot B
  gp-next/
    packs/         # persistent GP-Next ZIP patch packs
    patches/       # persistent JSON/JSON5 single-file patches
  manifest.json    # active slot, transaction state, resource stats, and game version
```

At rest, only the active slot contains game files. During an update, at most one copy of the old resources and one candidate copy are retained. The manifest switches atomically only after the candidate passes validation; the old slot is then cleaned. Because `gp-next` is outside both slots, updating game resources does not remove imported patches or Mods.

## Current Status

| Capability | Android | iOS | HarmonyOS / OpenHarmony |
| --- | :---: | :---: | :---: |
| ZIP import and resource validation | ✅ | ✅ | ✅ |
| Native GameHost | ✅ WebView | ✅ WKWebView | ✅ ArkWeb |
| A/B slot updates and recovery | ✅ | ✅ | ✅ |
| Touch, keyboard/mouse, and game bridge | ✅ | ✅ | ✅ |
| GP-Next bridge and patch import | ✅ | ✅ | ✅ |
| CI artifacts | APK | Unsigned IPA | Unsigned HAP (conditional) |

> [!NOTE]
> The repository contains only the maintained Android, iOS, and HarmonyOS/OpenHarmony platform projects.
> Some HarmonyOS/ArkWeb versions may not decode AVIF resources. If images fail to display, use a mobile resource package whose images have been converted to a compatible format.

## Known Limitations

- The app does not download or distribute game resources on the user's behalf. A ZIP must be imported manually before use.
- GP-Next compatibility is detected from required module fingerprints rather than a hard-coded version number. Passing detection does not guarantee that every feature will remain compatible with later versions.
- HarmonyOS build and device compatibility depend on the OpenHarmony Flutter SDK and DevEco toolchain.
- Media, audio, and input behavior may differ between system WebView implementations.
- The iOS high-refresh-rate compatibility layer uses private WebKit SPI. It is intended only for sideloaded builds, may stop working after system updates, and may not pass App Store review. See the [iOS deployment guide](docs/deployment.md).

Before reporting a new problem, search the [Issue Tracker](https://github.com/Dey410/GardendlessLoader/issues) and include the app's **Diagnostic Summary**.

## Build

### Requirements

- Flutter `3.41.9` (matching the current CI configuration)
- Dart `>=3.5.0 <4.0.0`
- JDK 17 for Android builds
- macOS, Xcode, and CocoaPods for iOS builds
- A compatible Flutter SDK, DevEco command-line tools, and JDK 17 for HarmonyOS builds

Clone the repository and run the tests:

```powershell
git clone https://github.com/Dey410/GardendlessLoader.git
Set-Location GardendlessLoader
flutter pub get
flutter analyze
flutter test
```

### Android

```powershell
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk` by default.

### iOS

Generate an unsigned Release build:

```bash
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

The default output is `build/ios/iphoneos/Runner.app`. It must be signed before installation or distribution. See the [iOS deployment guide](docs/deployment.md) for the complete unsigned IPA packaging process. If Apple developer signing is already configured locally, run `flutter build ios --release` to produce a signed build.

### HarmonyOS / OpenHarmony

The official Flutter stable SDK does not provide `flutter build hap`. This project's CI uses the following OpenHarmony Flutter SDK:

```text
https://gitcode.com/openharmony-tpc/flutter_flutter.git
ref: oh-3.35.7-release
```

Enable the OpenHarmony dependency overrides before building locally:

```powershell
Copy-Item pubspec_overrides.ohos.yaml pubspec_overrides.yaml
flutter doctor -v
flutter pub get
flutter test
flutter build hap --release --target-platform ohos-arm64
```

## Roadmap

The project currently focuses on:

- Improving consistency, stability, and performance across all three native GameHosts.
- Improving import progress, error messages, and recovery for large resource packages.
- Expanding compatibility with newer GP-Next versions and mobile file workflows.
- Improving automated tests, release artifacts, and device acceptance testing.

Suggestions and discussion are welcome in the [Issue Tracker](https://github.com/Dey410/GardendlessLoader/issues).

## Contributing

Code, documentation, tests, bug reports, and feature suggestions are welcome.

1. Fork the repository and create a feature branch from the latest main branch.
2. Keep Dart code at two-space indentation and use single quotes.
3. After making changes, run `dart format lib test`, `flutter analyze`, and `flutter test`.
4. Open a pull request describing the changes and validation performed. Include screenshots or recordings for UI changes.

When contributing code, preserve the resource path restrictions, atomic A/B slot switching, and default blocking of non-allowlisted WebView requests.

## Support

- Bug reports and feature requests: [GitHub Issues](https://github.com/Dey410/GardendlessLoader/issues)
- Source code and releases: [GitHub repository](https://github.com/Dey410/GardendlessLoader)
- Project introductions and tutorials: [Bilibili profile](https://space.bilibili.com/523667580)

When reporting a runtime problem, include the device model, operating-system version, app version, resource version, and the diagnostic summary provided by the app. Do not upload or attach game resource packages.

## License

GardendlessLoader is open source under the [GNU General Public License v3.0](LICENSE). You may use, study, modify, and redistribute this project in accordance with the license terms.

Game resources, the upstream project, and third-party components remain subject to their respective licenses. This repository's GPL-3.0 license does not grant additional rights to those materials.

## Acknowledgements

- [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web), the upstream web project served by this loader.
- [Flutter](https://flutter.dev/) and Dart, used for the cross-platform launcher UI and application logic.
- Android WebView, Apple WebKit, and HarmonyOS ArkWeb, which provide the native GameHost foundations on each platform.
- Everyone who has contributed code, tests, issue reports, and usage feedback.
