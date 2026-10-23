<div align="center">

<img src="tool/generated_icons/app_icon_readme.png" width="128" height="128" alt="GardendlessLoader icon">

# GardendlessLoader

**Play PvZ2 Gardendless on your phone and tablet**

Android · iOS / iPadOS · HarmonyOS

[![Build Artifacts](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml/badge.svg)](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml)
[![GitHub Release](https://img.shields.io/github/v/release/Dey410/GardendlessLoader?include_prereleases&sort=semver)](https://github.com/Dey410/GardendlessLoader/releases)
[![Commit Activity](https://img.shields.io/github/commit-activity/m/Dey410/GardendlessLoader)](https://github.com/Dey410/GardendlessLoader/commits/main)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[**Download**](https://github.com/Dey410/GardendlessLoader/releases) · [Quick start](#quick-start) · [Guide](#guide) · [FAQ](#faq) · [Report an issue](https://github.com/Dey410/GardendlessLoader/issues)

[简体中文](README.md) · **English**

</div>

---

[PvZ2 Gardendless](https://github.com/Gzh0821/pvzge_web) is a rewrite of *Plants vs. Zombies 2* built entirely with web technologies, including the Cocos engine. **GardendlessLoader** brings it to mobile: import a game resource ZIP and the game runs straight from local files in the system's native WebView, with no server to set up and no browser to keep open.

## Highlights

- 📦 **One-tap import**: pick a ZIP and the app extracts, validates, and self-checks it. You can also open a ZIP in the loader straight from another app.
- 🛡️ **Safe updates**: A/B slot updates replace the old resources only after the new ones pass validation. A failed or cancelled import never touches your current version.
- 👆 **Made for touch**: one- and two-finger gestures map to mouse input, and physical keyboards, mice, and game controllers work too.
- 🧩 **GP-Next ready**: supports patches, Mod installation, and JS Modding in GP-Next builds.
- 🎛️ **Adjustable display**: tune render resolution and screen fit, and turn on Auto Collect Sun or Quick launch.
- ⚡ **Runs natively**: uses WebView, WKWebView, and ArkWeb on each platform to load local resources directly.

## Quick start

### Step 1: Install the loader

Download the package for your platform from [GitHub Releases](https://github.com/Dey410/GardendlessLoader/releases):

| Platform | File | Requires | How to install |
| --- | --- | --- | --- |
| Android | `.apk` | Android 7.0+ | Install directly; you may need to allow installing unknown apps |
| iOS / iPadOS | `.ipa` | iOS 15.0+ | Unsigned; sign with a sideloading tool such as AltStore or your own developer certificate, then install |
| HarmonyOS | `.hap` | HarmonyOS 5.0+ | Unsigned; sign it yourself before installing |

Want to try what's in development? Open any successful run in [GitHub Actions](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml) to download the latest build.

### Step 2: Get the game resources

The loader ships without any game resources. Get a ZIP from one of these sources:

| Source | What you get | How |
| --- | --- | --- |
| **Quark Cloud Drive** (recommended) | Mobile-optimized package | [Open the link](https://pan.quark.cn/s/c3da839ca8b1?pwd=qLBU), extraction code `qLBU` |
| **extract-pvzge-gpnext** | Automatically built GP-Next package with mobile optimizations | Run GitHub Actions in [that repository](https://github.com/Dey410/extract-pvzge-gpnext) |
| **Upstream original** | Official web resources | In the [PvZ2 Gardendless repository](https://github.com/Gzh0821/pvzge_web), select `Code` → `Download ZIP` |

> [!NOTE]
> The cloud drive copies are uploaded by the loader author, are not affiliated with PvZ2 Gardendless, and may lag behind official releases. If an update is overdue, feel free to remind the author on [Bilibili](https://space.bilibili.com/523667580). Downloads through the cloud drive link may earn the author a small referral reward, which helps support development.

### Step 3: Import and play

1. Open GardendlessLoader, go to the **Resources** tab, and tap **Select ZIP to import**.
2. Wait for the four steps to finish: **Read → Extract → Validate → Self-check**.
3. Switch to the **Play** tab and tap **Start Game**. 🌻

## Guide

### Launch preferences

Adjust these under **Settings → Launch Preferences**; changes apply the next time the game starts:

| Option | What it does |
| --- | --- |
| **Quick launch** | Opens the game directly when the app starts |
| **Auto Collect Sun** | Presses `A` about every 3 seconds during play to collect sun; skipped while paused, in the background, or while you are typing |
| **Render resolution** | Renders at 100% / 75% / 50% of the screen's native resolution; lower uses less GPU memory but looks softer |
| **Screen fit** | **Balanced** (default) trims a little of the picture for smaller black bars; **Show all** keeps the whole picture with larger bars; **Stretch** fills the screen but may distort the picture |
| **Gestures (experimental)** | **Simulated** (default) uses the gestures below; **Native** is described after them |
| **Haptic effects** | The device vibrates with explosions, huge waves, plant food, rhythm hits and other big moments; a controller in use rumbles instead (on by default, follows the system haptics setting) |
| **Watermark** | Shows the loader name in a corner of the game |

### Touch controls

| Gesture | Action |
| --- | --- |
| One-finger tap or drag | Left click or drag |
| Two-finger tap | Right click at the midpoint between your fingers |
| Two-finger swipe | Mouse wheel |
| Three or more fingers | Cancels the current touch |
| Physical mouse and keyboard | Handled natively by the system WebView |

With **Gestures (experimental) → Native**, one finger does everything, like a phone game:
- Drop a seed packet, the shovel, plant food or a sandbox zombie card on the lawn to use it; a drag that isn't used puts it back. Decoding cards and the Zen Garden glove and tools drag onto their slots too.
- While you drag onto the lawn, the plant in hand and its target tile ride above your finger so it doesn't hide them, and the drop lands on the tile shown.
- One finger scrolls lists and the in-game settings, and pans the Zen Garden when nothing is in hand; dragging a volume slider doesn't move the list.
- In sandbox, swipe along the seed bank, zombie cards or armor icon to cycle them; in the sandbox settings, tap a row to run its shortcut (tides, summoning zombies, time freeze and more), and tap outside the window to close it.
- Long-press a custom card deck to edit it; in sandbox, long-press a plant with nothing in hand to switch the seed bank to it; in the decoding minigame, long-press a filled slot to clear it.
- In sandbox, long-press a seed packet, the shovel, plant food or a zombie card for its Ctrl shortcut: fill the lawn with that plant, remove every plant, feed every plant, or defeat every zombie.
- In the Zen Garden, long-press any plant or open ground with nothing in hand to meet every plant's need on the page (water, fertilizer and so on), like the `A` key.
- Pinch to zoom the Zen Garden.
- Dropping a card or tool and a long press that takes effect give a light tap, and each step of a sandbox swipe gives a tick; they follow the system haptics setting.

### Game controllers

With a Bluetooth controller connected, press any button or move a stick and a cursor appears over the game, and the game's tip bar lists the buttons; the cursor hides again when you touch the screen or use a mouse.

| Control | Action |
| --- | --- |
| Left stick / D-pad | Move the cursor (the D-pad fine-tunes it) |
| A | Left mouse button; hold to drag |
| B | Right mouse button |
| Right stick | Mouse wheel |
| X / Y | In a level, take the shovel / plant food |
| LB / RB | In a level, switch to the previous / next available seed packet |
| Start | In a level, pause |

X, Y, LB, RB, and Start use the key bindings you set in the game. Use touch for web pages such as the GP-Next panel.

- **Rhythm levels**: the five lanes, top to bottom, take LB/RB, D-pad up/Y, D-pad left or right/X/B, D-pad down/A, and LT/RT, so either hand can play; holding a button holds that lane, and Start still pauses. The tip bar lists them in your first rhythm level.
- **Air Raid**: the plane follows the cursor, so the stick flies it directly, the D-pad flies at full speed, and the cursor hides like the game's own pointer. After B switches the plane to keys, the stick and D-pad hold W/A/S/D; B switches back.

### Tips

- **Update resources**: on the **Resources** tab, tap **Select ZIP to update**. Export a save backup in the game first; the confirmation shows when you last exported a save in the loader and offers **Export in the game first**.
- **Import from another app**: open a ZIP with GardendlessLoader from a file manager or chat app (Android and iOS also accept it through Share). A ZIP received during play is imported once you return to the launcher.
- **Home-screen shortcuts**: long-press the app icon to jump straight to **Start Game** or **Import Resources**.
- **Back to the launcher**: use system Back on Android and HarmonyOS, swipe right from the left edge on iOS, or use the game's own quit button.
- **Pause when you leave**: switching apps, taking a call or locking the screen during a level opens the game's pause menu, so the zombies wait for you.

### GP-Next and Mods

- Save import/export, patches, and Mod installs all happen inside the game through the system file picker.
- Install ZIP Mods from the GP-Next Mods page. Once the Mod platform is active, the patch folder accepts only single-file JSON/JSON5 patches.
- A ZIP patch pack may keep `pack.json` at the archive root or inside exactly one wrapper folder; the loader handles the wrapper for you and ignores `.DS_Store` and `__MACOSX`.
- The JS Modding switch lives only in GP-Next inside the game. The loader never reads or changes it, so your choice survives loader updates.

> [!WARNING]
> JS Mods run code inside the game. Only install Mods from sources you trust.

## FAQ

<details>
<summary><b>Why do I have to sign the iOS package myself?</b></summary>

<br>

Apple requires every iOS app to be signed before it can be installed, and this repository contains no signing files, so the published IPA is unsigned. Sign it with a sideloading tool such as AltStore or with your own Apple developer certificate. Apps signed with a free Apple ID must be re-signed every 7 days. See the [iOS deployment guide](docs/deployment.md) for packaging and signing details.

</details>

<details>
<summary><b>Will updating resources wipe my save?</b></summary>

<br>

No. Your save lives in the game, and updating resources does not delete it. A new game version may still rewrite the save, and an error could corrupt it, so export a backup in the game before updating. Installed patches and Mods are kept as well.

</details>

<details>
<summary><b>The game stutters, runs hot, or crashes. What can I do?</b></summary>

<br>

Lower **Render resolution** to 75% or 50% under **Settings → Launch Preferences**; this noticeably reduces GPU memory use. After a crash, the **Play** tab explains what ended the game and offers to lower the resolution and start again in one tap. A mobile-optimized package also helps, since it uses lower-resolution textures and adjusted audio quality.

</details>

<details>
<summary><b>There are black bars, or the edges are cut off.</b></summary>

<br>

Change **Settings → Launch Preferences → Screen fit**: **Balanced** trades a small crop for smaller bars, **Show all** never crops, and **Stretch** removes the bars but may distort the picture.

</details>

<details>
<summary><b>Images in the game don't show up.</b></summary>

<br>

Some HarmonyOS/ArkWeb versions cannot decode AVIF images. Use a mobile-optimized package whose images have been converted to a compatible format.

</details>

<details>
<summary><b>The import failed. What now?</b></summary>

<br>

A failed or cancelled import never affects the resources you already have. Make sure the ZIP contains complete Gardendless web resources, then follow the error message in the app. If the problem persists, please [report it](#reporting-issues).

</details>

<details>
<summary><b>Which resource packages and GP-Next versions are supported?</b></summary>

<br>

Standard Cocos builds, GP-Next builds, and mobile lightweight packages are supported as long as they follow the Gardendless web resource layout and pass validation. GP-Next compatibility is detected from key fingerprints in the entry bundle and the local `gp-next-*.js` module it references, not from a hard-coded version number. The bridge implements the commands GP-Next 0.15 uses, so passing detection does not guarantee compatibility if a later version changes the protocol.

</details>

<details>
<summary><b>Why doesn't the loader include the game?</b></summary>

<br>

GardendlessLoader only loads and runs the game; it does not download or distribute game resources for you. The resources belong to the upstream project, so get them from one of the sources listed above.

</details>

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

**Known limitations**

- Media, audio, and input behavior can differ between system WebView implementations.
- HarmonyOS build and device compatibility depend on the OpenHarmony Flutter SDK and the DevEco toolchain.
- High-refresh-rate support on iOS relies on private WebKit SPI. It is meant only for sideloaded builds, may break after system updates, and is not guaranteed to pass App Store review.

## Reporting issues

Search the existing [Issues](https://github.com/Dey410/GardendlessLoader/issues) first. If nothing matches, open a new one and include:

- [ ] Device model and OS version
- [ ] Loader version and game resource version
- [ ] Steps to reproduce
- [ ] Diagnostics: tap **Copy diagnostics** on the app's **Logs** tab and paste the result

Please do not upload or attach game resource packages. Project introductions and tutorials are on the author's [Bilibili profile](https://space.bilibili.com/523667580).

## Development

GardendlessLoader uses Flutter for the launcher UI and a native GameHost on each platform. Code, documentation, bug reports, and feature ideas are all welcome.

<details>
<summary><b>Build requirements and commands</b></summary>

<br>

**Requirements**

- Flutter `3.41.9` (matches CI)
- Dart `>=3.5.0 <4.0.0`
- Android: JDK 17
- iOS: macOS, Xcode, and CocoaPods
- HarmonyOS: the OpenHarmony Flutter SDK, DevEco command-line tools, and JDK 17

**Clone and check**

```bash
git clone https://github.com/Dey410/GardendlessLoader.git
cd GardendlessLoader
flutter pub get
flutter analyze
```

**Android**

```bash
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. A release build requires signing in `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) and fails without it; without a signing key, use `flutter build apk --debug`.

**iOS**

```bash
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

The output is `build/ios/iphoneos/Runner.app` and must be signed before installation or distribution; see the [iOS deployment guide](docs/deployment.md) for unsigned IPA packaging. If Apple developer signing is already set up on your machine, run `flutter build ios --release` instead.

**HarmonyOS / OpenHarmony**

The official Flutter stable SDK does not support `flutter build hap`. CI uses the OpenHarmony Flutter SDK:

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

</details>

<details>
<summary><b>How resources are stored and updated</b></summary>

<br>

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

- **A/B updates**: normally only the active slot holds game files. An update writes the new resources to the idle slot, and `manifest.json` switches to it atomically only after validation and the self-check pass; the old slot is then cleaned up, so at most two copies exist at any time.
- **Patches and Mods live apart**: `gp-next/` sits outside both slots, so updating game resources never removes it.
- **GP-Next creates `gp-next/` itself**: GP-Next treats an existing `gp-next` folder as a legacy installation, so the loader never creates it in advance. A fresh install goes straight to GP-Next's Mod platform, and an existing legacy folder is upgraded through GP-Next's "Update mod management" step.
- **Wrapped ZIP patch packs**: the loader strips the wrapper folder only from its internal copy; the file you picked is never modified. Archives with several candidate folders, other files outside the wrapper, or deeper nesting are rejected.

</details>

**How to contribute**

1. Fork the repository and create a feature branch from the latest `main`.
2. Use two-space indentation and single quotes in Dart code.
3. After your changes, run `dart format lib` and `flutter analyze`, then build the affected platforms and verify on a real device. The project currently has no Flutter unit or widget tests.
4. Open a pull request that describes the change and how you verified it; include screenshots or recordings for UI changes.

Please keep the existing safety boundaries intact: resource paths stay confined to the active slot, A/B slots switch atomically, and the WebView blocks requests outside the allowlist by default.

## Roadmap

- [ ] Make the three native GameHosts more consistent, stable, and fast
- [ ] Improve import progress, error messages, and recovery for large resource packages
- [ ] Support newer GP-Next versions and smooth out mobile file workflows
- [ ] Strengthen automated checks, release artifacts, and device acceptance testing

Ideas and discussion are welcome in [Issues](https://github.com/Dey410/GardendlessLoader/issues).

## License and notices

GardendlessLoader is open source under the [GNU General Public License v3.0](LICENSE). You may use, study, modify, and redistribute it under the terms of that license.

- Game resources, the upstream project, and third-party components remain under their own licenses; this repository's GPL-3.0 license grants no additional rights to them.
- *Plants vs. Zombies* is a trademark of Electronic Arts Inc. GardendlessLoader is an unofficial project and is not affiliated with Electronic Arts or PopCap Games.
- Parts of this project's UI, logic, and platform adaptation were built with the help of AI tools and are continually improved through code review, automated checks, and device testing.

## Acknowledgements

- [PvZ2 Gardendless](https://github.com/Gzh0821/pvzge_web), the upstream game this loader serves.
- [Flutter](https://flutter.dev/) and Dart, which power the cross-platform launcher UI and app logic.
- Android WebView, Apple WebKit, and HarmonyOS ArkWeb, the foundations of each platform's native GameHost.
- Everyone who has contributed code, tested builds, reported issues, or shared feedback.

<div align="center">

<sub>If this project helps you, a ⭐ Star is always appreciated!</sub>

</div>
