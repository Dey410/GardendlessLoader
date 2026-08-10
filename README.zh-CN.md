<h1 align="center">GardendlessLoader</h1>

<img src="tool/generated_icons/app_icon_master.png" align="left" width="150" height="150" style="border-radius: 17%" alt="GardendlessLoader 图标">

[![Build Artifacts](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml/badge.svg)](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml)
[![GitHub Release](https://img.shields.io/github/v/release/Dey410/GardendlessLoader?include_prereleases&sort=semver)](https://github.com/Dey410/GardendlessLoader/releases)
[![Commit Activity](https://img.shields.io/github/commit-activity/m/Dey410/GardendlessLoader)](https://github.com/Dey410/GardendlessLoader/commits/main)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

*让无花园在移动设备上继续生长。*

GardendlessLoader 是一款适用于 Android、iOS 和 HarmonyOS/OpenHarmony 的 `PvZ2 Gardendless` 本地资源加载器。

想了解更多，请查看下方的[简介](#简介)；也可以直接前往[下载](https://github.com/Dey410/GardendlessLoader/releases)或[问题反馈](https://github.com/Dey410/GardendlessLoader/issues)。

[English](README.md)

<br clear="left">

## 简介

GardendlessLoader 是一个使用 Flutter 开发的本地资源加载器，可用于加载 [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web)，适用于 Android、iOS 和 HarmonyOS/OpenHarmony。

该加载器支持符合 Gardendless Web 资源结构、且能够通过应用资源校验的标准 Cocos 构建与 GP-Next 构建。

应用也支持导入面向移动设备优化的资源包，例如降低贴图分辨率、调整音频质量或修改部分加载逻辑的轻量版本。

## 获取 GardendlessLoader

你可以通过以下方式获取应用：

1. **发布版本：** 前往 [GitHub Releases](https://github.com/Dey410/GardendlessLoader/releases) 下载最新发布版本。
2. **自动构建：** 在 [GitHub Actions](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml) 中选择一次成功运行并下载对应平台产物。
3. **从源代码构建：** 按照下方的 [构建说明](#构建) 操作。

> [!NOTE]
> iOS 自动构建产物未签名，需要自行签名后才能安装。
> HarmonyOS/OpenHarmony HAP 仅在 CI 已配置对应命令行工具时生成，产物同样未签名，需要签名后才能安装。

## 获取 Gardendless 资源包

你可以通过以下方式获得可导入的资源包：

- 使用面向移动设备优化的资源包：

  1. 通过[夸克网盘](https://pan.quark.cn/s/c3da839ca8b1?pwd=qLBU)下载（提取码：`qLBU`，推荐）。通过此链接下载时，我可能获得少量网盘推广收益，用于支持开发。

  2. 在 [extract-pvzge-gpnext](https://github.com/Dey410/extract-pvzge-gpnext) 中通过 GitHub Actions 自动构建 ZIP。该方式生成的资源包包含 GP-Next 和移动端优化内容。

- 使用上游原版资源：前往 [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web)，点击 `Code` → `Download ZIP` 下载仓库压缩包。

## 快速开始

1. 从 [`PvZ2 Gardendless` 上游项目](https://github.com/Gzh0821/pvzge_web) 或其他可信来源获取 Web 资源 ZIP。
2. 打开 GardendlessLoader，点击“选择 ZIP 导入”。
3. 等待应用完成解压、校验和资源槽切换。
4. 点击“开始游戏”，进入平台原生 GameHost。

更新资源时再次选择 ZIP 即可。新资源会写入空闲槽，只有通过校验和自检后才会成为激活资源。

### 游戏内触摸操作

| 操作 | 映射 |
| --- | --- |
| 单指轻点或拖动 | 鼠标左键点击或拖动 |
| 双指轻点 | 在双指中心执行鼠标右键点击 |
| 双指滑动 | 模拟鼠标滚轮 |
| 三指及以上 | 取消当前触摸映射 |
| 实体鼠标和键盘 | 交由系统 WebView 原生处理 |

启用游戏菜单中的“自动收集阳光”后，应用会在游戏进行中约每 3 秒模拟一次 `A` 键；游戏暂停、应用进入后台或输入框获得焦点时不会触发。

> [!IMPORTANT]
> 本项目的界面、逻辑和平台适配中有部分内容借助人工智能工具完成，并持续通过代码审查、自动化测试和设备验收改进。
> 若遇到异常，请附上诊断摘要提交问题反馈。

### 本地资源结构

应用会在平台私有目录中创建以下结构：

```text
GardendlessLoader/
  slot-a/          # 资源槽 A
  slot-b/          # 资源槽 B
  gp-next/
    packs/         # 持久化的 GP-Next ZIP 补丁包
    patches/       # 持久化的 JSON/JSON5 单文件补丁
  manifest.json    # 激活槽、事务状态、资源统计和游戏版本
```

常态下只有激活槽包含游戏文件。更新期间旧资源与候选资源最多各保留一份；候选槽通过校验后，清单才会原子切换，随后旧槽被清理。`gp-next` 位于双槽之外，因此更新游戏资源不会删除已导入的补丁和 Mod。

## 当前状态

| 能力 | Android | iOS | HarmonyOS / OpenHarmony |
| --- | :---: | :---: | :---: |
| ZIP 导入与资源校验 | ✅ | ✅ | ✅ |
| 原生 GameHost | ✅ WebView | ✅ WKWebView | ✅ ArkWeb |
| A/B 双槽更新与恢复 | ✅ | ✅ | ✅ |
| 触摸、键鼠与游戏桥 | ✅ | ✅ | ✅ |
| GP-Next 桥接与补丁导入 | ✅ | ✅ | ✅ |
| CI 构建产物 | APK | 未签名 IPA | 未签名 HAP |

> [!NOTE]
> 仓库只包含 Android、iOS 和 HarmonyOS/OpenHarmony 三个受维护的平台工程。
> 部分 HarmonyOS/ArkWeb 版本可能无法解码 AVIF 资源；遇到图片显示异常时，请使用已转换为兼容图片格式的移动端资源包。

## 已知限制

- 应用不会代替用户下载或分发游戏资源，使用前必须手动导入 ZIP。
- GP-Next 兼容性依据所需功能模块的指纹进行检测，不按版本号硬编码；已通过检测不代表所有功能都能兼容后续版本。
- HarmonyOS 的构建和设备兼容性取决于 OpenHarmony Flutter SDK 与 DevEco 工具链。
- 不同系统 WebView 的媒体、音频和输入行为可能存在平台差异。
- iOS 高刷新率兼容使用 WebKit 私有 SPI，仅适合侧载构建，可能随系统更新失效，也可能无法通过 App Store 审核。详情见 [iOS 部署说明](docs/deployment.md)。

如果你发现新的问题，请在提交前搜索 [Issue Tracker](https://github.com/Dey410/GardendlessLoader/issues)，并附上应用中的“诊断摘要”。

## 构建

### 环境要求

- Flutter `3.41.9`（与当前 CI 一致）
- Dart `>=3.5.0 <4.0.0`
- Android 构建需要 JDK 17
- iOS 构建需要 macOS、Xcode 和 CocoaPods
- HarmonyOS 构建需要兼容版 Flutter SDK、DevEco 命令行工具和 JDK 17

克隆并运行测试：

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

APK 默认输出到 `build/app/outputs/flutter-apk/app-release.apk`。

### iOS

生成未签名的 Release 构建：

```bash
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

默认产物为 `build/ios/iphoneos/Runner.app`。安装或分发前需要自行签名；完整的未签名 IPA 打包流程见 [iOS 部署说明](docs/deployment.md)。如果本机已经配置 Apple 开发者签名，也可以运行 `flutter build ios --release` 生成签名构建。

### HarmonyOS / OpenHarmony

官方 Flutter stable SDK 不提供 `flutter build hap`。本项目 CI 使用以下 OpenHarmony Flutter SDK：

```text
https://gitcode.com/openharmony-tpc/flutter_flutter.git
ref: oh-3.35.7-release
```

本地构建前启用 OpenHarmony 依赖覆盖：

```powershell
Copy-Item pubspec_overrides.ohos.yaml pubspec_overrides.yaml
flutter doctor -v
flutter pub get
flutter test
flutter build hap --release --target-platform ohos-arm64
```

## 路线图

项目目前重点关注：

- 提升三平台原生 GameHost 的一致性、稳定性和性能；
- 改善大体积资源包的导入进度、错误说明和恢复体验；
- 扩展对新版 GP-Next 的兼容与移动端文件工作流；
- 完善自动化测试、发布产物和设备验收流程。

欢迎在 [Issue Tracker](https://github.com/Dey410/GardendlessLoader/issues) 中提交建议并参与讨论。

## 贡献

欢迎提交代码、文档、测试、错误报告和功能建议。

1. Fork 本仓库并从最新主分支创建功能分支。
2. 保持 Dart 两空格缩进和单引号风格。
3. 修改后运行 `dart format lib test`、`flutter analyze` 和 `flutter test`。
4. 提交 Pull Request，说明改动内容、验证方式，并为 UI 变化附上截图或录屏。

提交代码时，请继续遵守资源路径限制、A/B 槽原子切换以及 WebView 非白名单请求默认阻止等安全边界。

## 支持

- 错误报告与功能建议：[GitHub Issues](https://github.com/Dey410/GardendlessLoader/issues)
- 源代码与版本发布：[GitHub 仓库](https://github.com/Dey410/GardendlessLoader)
- 项目介绍与教程：[哔哩哔哩主页](https://space.bilibili.com/523667580)

反馈运行问题时，请说明设备型号、系统版本、应用版本和资源版本，并粘贴应用提供的诊断摘要。请勿上传或附带游戏资源包。

## 许可证

GardendlessLoader 使用 [GNU General Public License v3.0](LICENSE) 开源。你可以在遵守许可证条款的前提下使用、研究、修改和再分发本项目。

游戏资源、上游项目以及第三方组件仍分别受其自身许可证约束；本仓库的 GPL-3.0 许可证不代表对这些内容授予额外权利。

## 致谢

- [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web)：本加载器所服务的上游 Web 项目。
- [Flutter](https://flutter.dev/) 与 Dart：跨平台启动器界面和业务层。
- Android WebView、Apple WebKit 与 HarmonyOS ArkWeb：各平台原生 GameHost 基础。
- 所有提交代码、测试、问题反馈和使用建议的贡献者。
