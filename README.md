<h1 align="center">GardendlessLoader</h1>

<img src="tool/generated_icons/app_icon_master.png" align="left" width="150" height="150" style="border-radius: 17%" alt="GardendlessLoader icon">

[![Build Artifacts](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml/badge.svg)](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml)
[![GitHub Release](https://img.shields.io/github/v/release/Dey410/GardendlessLoader?include_prereleases&sort=semver)](https://github.com/Dey410/GardendlessLoader/releases)
[![Commit Activity](https://img.shields.io/github/commit-activity/m/Dey410/GardendlessLoader)](https://github.com/Dey410/GardendlessLoader/commits/main)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

*Let the gardendLess keep growing on your phone and tablet.*

GardendlessLoader is a mobile resource loader for [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web) on Android, iOS, and HarmonyOS/OpenHarmony. Import a game resource ZIP and play on your phone or tablet.

[Download](https://github.com/Dey410/GardendlessLoader/releases) · [Get the game](#get-the-game-resources) · [Quick start](#quick-start) · [Report an issue](https://github.com/Dey410/GardendlessLoader/issues) · [中文](README.zh-CN.md)

<br clear="left">

## Overview

GardendlessLoader has a Flutter launcher and runs the game in each platform's native system WebView. All game resources stay on the device, so there is no server to set up.

- **Simple import**: pick a ZIP and the app extracts, validates, and self-checks it for you. You can also open a ZIP in GardendlessLoader straight from another app.
- **Safe updates**: A/B slot updates replace the old resources only after the new ones pass validation. A failed or cancelled import never touches the version you can already play.
- **Touch-friendly**: one- and two-finger gestures map to mouse input, and physical keyboards and mice work too.
- **GP-Next ready**: supports patches, Mod installation, and JS Modding in GP-Next builds.
- **Adjustable**: tune render resolution and screen fit, and turn on Auto Collect Sun or Quick launch.

Importable resources include standard Cocos builds and GP-Next builds that follow the Gardendless web resource layout and pass validation, as well as lightweight mobile packages with lower-resolution textures, adjusted audio quality, or modified loading logic.

## Download

1. **Releases (recommended)**: get the latest version from [GitHub Releases](https://github.com/Dey410/GardendlessLoader/releases).
2. **Development builds**: open any successful run in [GitHub Actions](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml) and download the artifact for your platform.
3. **Build it yourself**: see [Build from source](#build-from-source) below.

> [!NOTE]
> The iOS and HarmonyOS/OpenHarmony packages are unsigned; sign them yourself before installing.
> The HAP package is built only when the HarmonyOS command-line tools are configured in CI.

## Get the game resources

GardendlessLoader ships without any game resources. Get an importable ZIP from one of these sources:

- **Mobile-optimized packages (recommended)**
  - [Quark Cloud Drive](https://pan.quark.cn/s/c3da839ca8b1?pwd=qLBU), extraction code `qLBU`. The author uploads these copies for convenience; they are not affiliated with PvZ2 Gardendless and may lag behind official releases. If an update is overdue, feel free to remind the author on Bilibili. Downloads through this link may earn the author a small referral reward, which helps support development.
  - Run the GitHub Actions workflow in [extract-pvzge-gpnext](https://github.com/Dey410/extract-pvzge-gpnext) to build a ZIP with GP-Next and mobile optimizations.
- **Original upstream resources**: open the [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web) repository and select `Code` → `Download ZIP`.

## Quick start

1. Get a game resource ZIP as described [above](#get-the-game-resources).
2. Open GardendlessLoader, go to the **Resources** tab, and tap **Select ZIP to import**.
3. Wait for the four steps to finish: Read, Extract, Validate, and Self-check.
4. Go back to the **Play** tab and tap **Start Game**.

A few everyday tips:

- **Update resources**: on the **Resources** tab, tap **Select ZIP to update**. Your save lives in the game and updating resources does not delete it, but a new version may rewrite it, so export a backup in the game first.
- **Import from another app**: open a ZIP with GardendlessLoader from a file manager, chat app, or similar (Android and iOS also accept it through Share). If the game is running, the import waits until you return to the launcher.
- **Home-screen shortcuts**: long-press the app icon to jump straight to **Start Game** or **Import Resources**.
- **Back to the launcher**: use system Back on Android and HarmonyOS, swipe right from the left edge on iOS, or use the game's own quit button.

### Launch preferences

These options live under **Settings → Launch Preferences** and take effect the next time the game starts:

| Option | What it does |
| --- | --- |
| Quick launch | Opens the game directly when the app starts |
| Auto Collect Sun | Presses `A` about every 3 seconds during play; skipped while the game is paused, the app is in the background, or you are typing |
| Render resolution | Renders at 100% / 75% / 50% of the screen's native resolution; lower uses less GPU memory but looks softer |
| Screen fit | **Balanced** (default) trims a little of the picture for smaller black bars; **Show all** keeps the whole picture with larger bars; **Stretch** fills the screen but may distort the picture |
| Watermark | Shows the loader name in a corner of the game |

### Touch controls

| Gesture | Action |
| --- | --- |
| One-finger tap or drag | Left click or drag |
| Two-finger tap | Right click at the midpoint between your fingers |
| Two-finger swipe | Mouse wheel |
| Three or more fingers | Cancels the current touch |
| Physical mouse and keyboard | Handled natively by the system WebView |

### GP-Next and Mods

- Save import/export, patches, and Mod installs all happen inside the game through the system file picker.
- Install ZIP Mods from the GP-Next Mods page. Once the Mod platform is active, the patch folder accepts only single-file JSON/JSON5 patches.
- A ZIP patch pack may keep `pack.json` at the archive root or inside exactly one top-level wrapper folder. For the wrapped form, the Loader strips that folder from its internal copy and ignores `.DS_Store` and `__MACOSX`; the file you picked is never modified. Archives with several candidate folders, other files outside the wrapper, or deeper nesting are rejected.
- The JS Modding switch lives only in GP-Next inside the game. The Loader never reads or changes it, so updating the Loader keeps your choice.
- JS Mods run code inside the game, so only install Mods from sources you trust.

## How resources are stored and updated

The app creates this layout in its platform-private directory:

```text
GardendlessLoader/
  slot-a/          # resource slot A
  slot-b/          # resource slot B
  gp-next/         # created by GP-Next on its first start
    configuration-state.json  # GP-Next Mod configuration
    installed/     # Mods installed from the Mods page, stored by content hash
    patches/       # single-file JSON/JSON5 patches
    packs/         # legacy ZIP packs, read only until GP-Next migrates them
  manifest.json    # active slot, transaction state, resource stats, and game version
```

- **A/B updates**: normally only the active slot holds game files. An update writes the new resources to the idle slot, and `manifest.json` switches to it atomically only after validation and the self-check pass; the old slot is then cleaned up. At most two copies, old and new, exist at any time.
- **Patches and Mods survive updates**: `gp-next/` sits outside both slots, so updating the game resources never removes installed patches or Mods.
- **GP-Next creates `gp-next/` itself**: GP-Next treats an existing `gp-next` folder as a legacy installation, so the Loader never creates it in advance. A fresh install goes straight to GP-Next's Mod platform, and an existing legacy folder is upgraded through GP-Next's "Update mod management" step.

## Platform support

| Feature | Android | iOS | HarmonyOS / OpenHarmony |
| --- | :---: | :---: | :---: |
| ZIP import and resource validation | ✅ | ✅ | ✅ |
| Native GameHost | ✅ WebView | ✅ WKWebView | ✅ ArkWeb |
| A/B slot updates and recovery | ✅ | ✅ | ✅ |
| Touch, keyboard/mouse, and game bridge | ✅ | ✅ | ✅ |
| GP-Next bridge and patch import | ✅ | ✅ | ✅ |
| GP-Next 0.15 ZIP/folder Mod installation | ✅ | ✅ | ✅ |
| In-game JS Modding control | ✅ | ✅ | ✅ |
| CI artifacts | APK | Unsigned IPA | Unsigned HAP (when CI is configured) |

> [!NOTE]
> Some HarmonyOS/ArkWeb versions cannot decode AVIF images. If images in the game fail to appear, use a mobile resource package whose images have been converted to a compatible format.

## Known limitations

- The app does not download or distribute game resources for you; import a ZIP manually before first use.
- GP-Next compatibility is detected from key fingerprints in the entry bundle and the local `gp-next-*.js` module it references, not from a hard-coded version number. The bridge implements the commands GP-Next 0.15 uses, so passing detection does not guarantee compatibility if a later version changes the protocol.
- HarmonyOS build and device compatibility depend on the OpenHarmony Flutter SDK and the DevEco toolchain.
- Media, audio, and input behavior can differ between system WebView implementations.
- High-refresh-rate support on iOS relies on private WebKit SPI. It is meant only for sideloaded builds, may break after system updates, and may not pass App Store review. See the [iOS deployment guide](docs/deployment.md).

## Reporting issues

Before opening a new issue, search the existing [Issues](https://github.com/Dey410/GardendlessLoader/issues). When you report a problem, include:

- Device model and OS version
- Loader version and game resource version
- Steps to reproduce
- The diagnostics from **Copy diagnostics** on the app's **Logs** tab

Please do not upload or attach game resource packages.

> [!NOTE]
> Parts of this project's UI, logic, and platform adaptation were built with the help of AI tools and are continually improved through code review, automated checks, and device testing. If something behaves unexpectedly, attaching the diagnostics helps us track it down faster.

Other channels:

- Source code and releases: [GitHub repository](https://github.com/Dey410/GardendlessLoader)
- Project introductions and tutorials: [Bilibili profile](https://space.bilibili.com/523667580)

## Build from source

### Requirements

- Flutter `3.41.9` (matches CI)
- Dart `>=3.5.0 <4.0.0`
- Android: JDK 17
- iOS: macOS, Xcode, and CocoaPods
- HarmonyOS: the OpenHarmony Flutter SDK, DevEco command-line tools, and JDK 17

Clone the repository and run static analysis:

```bash
git clone https://github.com/Dey410/GardendlessLoader.git
cd GardendlessLoader
flutter pub get
flutter analyze
```

### Android

```bash
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk` by default.

### iOS

Build an unsigned Release:

```bash
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

The output is `build/ios/iphoneos/Runner.app` by default and must be signed before installation or distribution. See the [iOS deployment guide](docs/deployment.md) for the full unsigned IPA packaging steps. If Apple developer signing is already set up on your machine, run `flutter build ios --release` to get a signed build.

### HarmonyOS / OpenHarmony

The official Flutter stable SDK does not support `flutter build hap`. This project's CI uses the following OpenHarmony Flutter SDK:

```text
https://gitcode.com/openharmony-tpc/flutter_flutter.git
ref: oh-3.35.7-release
```

Enable the OpenHarmony dependency overrides before building locally:

```bash
cp pubspec_overrides.ohos.yaml pubspec_overrides.yaml
flutter doctor -v
flutter pub get
flutter build hap --release --target-platform ohos-arm64
```

## Contributing

Code, documentation, bug reports, and feature ideas are all welcome.

1. Fork the repository and create a feature branch from the latest `main`.
2. Use two-space indentation and single quotes in Dart code.
3. After your changes, run `dart format lib` and `flutter analyze`, then build the affected platforms and verify on a real device. The project currently has no Flutter unit or widget tests.
4. Open a pull request that describes the change and how you verified it; include screenshots or recordings for UI changes.

Please keep the existing safety boundaries intact: resource paths stay confined to the active slot, A/B slots switch atomically, and the WebView blocks requests outside the allowlist by default.

## Roadmap

Current priorities:

- Make the three native GameHosts more consistent, stable, and fast.
- Improve import progress, error messages, and recovery for large resource packages.
- Support newer GP-Next versions and smooth out mobile file workflows.
- Strengthen automated checks, release artifacts, and device acceptance testing.

Ideas and discussion are welcome in [Issues](https://github.com/Dey410/GardendlessLoader/issues).

## License

GardendlessLoader is open source under the [GNU General Public License v3.0](LICENSE). You may use, study, modify, and redistribute it under the terms of that license.

Game resources, the upstream project, and third-party components remain under their own licenses; this repository's GPL-3.0 license grants no additional rights to them.

## Acknowledgements

- [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web), the upstream web project this loader serves.
- [Flutter](https://flutter.dev/) and Dart, which power the cross-platform launcher UI and app logic.
- Android WebView, Apple WebKit, and HarmonyOS ArkWeb, the foundations of each platform's native GameHost.
- Everyone who has contributed code, tested builds, reported issues, or shared feedback.
