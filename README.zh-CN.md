<h1 align="center">GardendlessLoader</h1>

<img src="tool/generated_icons/app_icon_master.png" align="left" width="150" height="150" style="border-radius: 17%" alt="GardendlessLoader 图标">

[![Build Artifacts](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml/badge.svg)](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml)
[![GitHub Release](https://img.shields.io/github/v/release/Dey410/GardendlessLoader?include_prereleases&sort=semver)](https://github.com/Dey410/GardendlessLoader/releases)
[![Commit Activity](https://img.shields.io/github/commit-activity/m/Dey410/GardendlessLoader)](https://github.com/Dey410/GardendlessLoader/commits/main)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

*让「无花园」在手机和平板上继续生长。*

GardendlessLoader 是 [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web) 的移动端本地资源加载器，支持 Android、iOS 与 HarmonyOS/OpenHarmony。导入一份游戏资源 ZIP，即可在手机或平板上畅玩。

[下载应用](https://github.com/Dey410/GardendlessLoader/releases) · [获取游戏资源](#获取游戏资源) · [快速上手](#快速上手) · [问题反馈](https://github.com/Dey410/GardendlessLoader/issues) · [English](README.md)

<br clear="left">

## 简介

GardendlessLoader 使用 Flutter 开发启动器界面，并在每个平台上用系统原生的 WebView 运行游戏。游戏资源全部保存在本地，无需另行搭建服务器。

- **导入简单**：选择一个 ZIP，应用会自动完成解压、校验和自检；也可以直接在其他应用中用 GardendlessLoader 打开 ZIP。
- **更新安全**：采用 A/B 双槽更新，新资源通过校验后才会替换旧资源；导入失败或中途取消都不会影响当前可玩的版本。
- **触屏友好**：单指、双指手势会映射为鼠标操作，同时支持实体键盘与鼠标。
- **支持 GP-Next**：兼容 GP-Next 构建的补丁、Mod 安装和 JS Modding。
- **按需调节**：可以调整渲染分辨率、画面比例，并开启自动收集阳光、快速启动等选项。

支持导入的资源包括：符合 Gardendless Web 资源结构并能通过校验的标准 Cocos 构建、GP-Next 构建，以及降低贴图分辨率、调整音频质量或改写部分加载逻辑的移动端轻量包。

## 下载应用

1. **正式版（推荐）**：前往 [GitHub Releases](https://github.com/Dey410/GardendlessLoader/releases) 下载最新版本。
2. **开发构建**：在 [GitHub Actions](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml) 中打开任意一次成功的运行，下载对应平台的构建产物。
3. **自行构建**：参见下方的[从源码构建](#从源码构建)。

> [!NOTE]
> iOS 与 HarmonyOS/OpenHarmony 的安装包均未签名，需要自行签名后才能安装。
> HAP 安装包仅在 CI 配置了鸿蒙命令行工具时才会生成。

## 获取游戏资源

GardendlessLoader 本身不包含任何游戏资源。你可以从以下渠道获取可导入的 ZIP：

- **移动端优化包（推荐）**
  - [夸克网盘](https://pan.quark.cn/s/c3da839ca8b1?pwd=qLBU)，提取码 `qLBU`。网盘资源由作者上传，与 PvZ2 Gardendless 官方无关，更新可能略晚于官方；如果迟迟没有更新，欢迎到 B 站提醒。通过此链接下载时，作者可能获得少量网盘推广收益，用于支持项目开发。
  - 在 [extract-pvzge-gpnext](https://github.com/Dey410/extract-pvzge-gpnext) 中运行 GitHub Actions，自动打包出包含 GP-Next 与移动端优化的 ZIP。
- **上游原版资源**：打开 [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web) 仓库，点击 `Code` → `Download ZIP`。

## 快速上手

1. 按[上一节](#获取游戏资源)获取游戏资源 ZIP。
2. 打开 GardendlessLoader，在 **资源** 页点击 **选择 ZIP 导入**。
3. 等待读取、解压、校验、自检四个步骤完成。
4. 回到 **游戏** 页，点击 **开始游戏**。

日常使用中的几个小技巧：

- **更新资源**：在 **资源** 页点击 **选择 ZIP 更新**。存档保存在游戏内，更新资源不会删除它，但新版本有可能改写存档，建议更新前先在游戏中导出备份。
- **从其他应用导入**：在文件管理器、聊天软件等应用中选择用 GardendlessLoader 打开 ZIP，即可直接导入（Android 与 iOS 还支持通过“分享”导入）。如果游戏正在运行，导入会等你回到启动器后再开始。
- **桌面快捷方式**：长按应用图标，可以直接选择“开始游戏”或“导入资源”。
- **返回启动器**：Android 与鸿蒙使用系统返回手势，iOS 从屏幕左边缘向右滑动，也可以点击游戏内的退出按钮。

### 启动偏好

在 **设置 → 启动偏好** 中可以调整以下选项，修改将在下次启动游戏时生效：

| 选项 | 说明 |
| --- | --- |
| 快速启动 | 打开应用后直接进入游戏 |
| 自动收集 | 游戏进行中约每 3 秒模拟按一次 `A` 键；游戏暂停、应用切到后台或正在输入文字时不会触发 |
| 渲染分辨率 | 以屏幕原生分辨率的 100% / 75% / 50% 渲染；比例越低越省显存，画面也越模糊 |
| 画面比例 | **均衡比例**（默认）裁掉少量画面以缩小黑边；**完整显示**保留全部画面，黑边更大；**强制拉伸**铺满屏幕，但画面可能变形 |
| 游戏水印 | 在游戏画面角落显示加载器标识 |

### 触摸操作

| 手势 | 对应操作 |
| --- | --- |
| 单指轻点或拖动 | 鼠标左键点击或拖动 |
| 双指轻点 | 在两指中点执行鼠标右键点击 |
| 双指滑动 | 鼠标滚轮 |
| 三指及以上 | 取消当前触摸 |
| 实体鼠标和键盘 | 由系统 WebView 原生处理 |

### GP-Next 与 Mod

- 存档导入导出、补丁和 Mod 安装都在游戏内完成，通过系统文件选择器选取文件。
- ZIP Mod 请在 GP-Next 的模组页安装。模组平台启用后，补丁目录只接受 JSON/JSON5 单文件补丁。
- ZIP 补丁包的 `pack.json` 可以放在压缩包根目录，也可以放在唯一的一层外层目录中。对于后者，Loader 会在内部副本中去掉这层目录，并忽略 `.DS_Store` 与 `__MACOSX`，你选择的原始文件不会被修改。如果包含多个候选目录、外层目录之外还有其他文件，或嵌套超过一层，导入会被拒绝。
- JS Modding 的开关只在游戏内的 GP-Next 中设置，Loader 不会读取或修改它，因此升级 Loader 不会改变你原来的选择。
- JS Mod 会在游戏中执行代码，请只安装来源可信的 Mod。

## 资源存储与更新机制

应用会在平台私有目录中创建如下结构：

```text
GardendlessLoader/
  slot-a/          # 资源槽 A
  slot-b/          # 资源槽 B
  gp-next/         # 由 GP-Next 首次启动时创建
    configuration-state.json  # GP-Next 模组配置
    installed/     # 在模组页安装的 Mod，按内容摘要存放
    patches/       # JSON/JSON5 单文件补丁
    packs/         # 旧式 ZIP 补丁包，仅在 GP-Next 迁移前读取
  manifest.json    # 激活槽、事务状态、资源统计与游戏版本
```

- **双槽更新**：平时只有激活槽中存放游戏文件。更新时，新资源写入空闲槽，通过校验和自检后，`manifest.json` 才会原子地切换到新槽，随后清理旧槽。因此整个过程中最多同时保留新旧两份资源。
- **补丁与 Mod 不受影响**：`gp-next/` 独立于两个资源槽，更新游戏资源不会删除已安装的补丁和 Mod。
- **`gp-next/` 由 GP-Next 自行创建**：GP-Next 会把已存在的 `gp-next` 目录视为旧式安装，所以 Loader 不会预先创建它。全新安装会直接进入 GP-Next 的模组平台；已有的旧式目录则可通过 GP-Next 的“更新模组管理”完成升级。

## 平台支持

| 功能 | Android | iOS | HarmonyOS / OpenHarmony |
| --- | :---: | :---: | :---: |
| ZIP 导入与资源校验 | ✅ | ✅ | ✅ |
| 原生 GameHost | ✅ WebView | ✅ WKWebView | ✅ ArkWeb |
| A/B 双槽更新与恢复 | ✅ | ✅ | ✅ |
| 触摸、键鼠与游戏桥接 | ✅ | ✅ | ✅ |
| GP-Next 桥接与补丁导入 | ✅ | ✅ | ✅ |
| GP-Next 0.15 ZIP / 文件夹 Mod 安装 | ✅ | ✅ | ✅ |
| 游戏内管理 JS Modding | ✅ | ✅ | ✅ |
| CI 构建产物 | APK | 未签名 IPA | 未签名 HAP（视 CI 配置） |

> [!NOTE]
> 部分 HarmonyOS/ArkWeb 版本无法解码 AVIF 图片。如果游戏中的图片显示异常，请改用已将图片转换为兼容格式的移动端资源包。

## 已知限制

- 应用不会代为下载或分发游戏资源，首次使用前需要手动导入 ZIP。
- GP-Next 兼容性通过检测入口脚本及其引用的本地 `gp-next-*.js` 模块中的关键特征来判断，而不是硬编码版本号。桥接层实现的是 GP-Next 0.15 所用的命令；如果后续版本修改了通信协议，即使检测通过，也不能保证完全兼容。
- HarmonyOS 的构建与设备兼容性取决于 OpenHarmony Flutter SDK 和 DevEco 工具链。
- 不同系统 WebView 在媒体、音频和输入方面的表现可能存在差异。
- iOS 的高刷新率支持依赖 WebKit 私有 SPI，仅适用于侧载安装，可能随系统更新失效，也可能无法通过 App Store 审核。详见 [iOS 部署说明](docs/deployment.md)。

## 问题反馈

遇到问题时，请先在 [Issues](https://github.com/Dey410/GardendlessLoader/issues) 中搜索是否已有相同反馈。提交新问题时，请写明：

- 设备型号与系统版本
- Loader 版本与游戏资源版本
- 问题的复现步骤
- 在应用 **日志** 页点击 **复制诊断** 得到的诊断信息

请不要上传或附带游戏资源包。

> [!NOTE]
> 本项目的部分界面、逻辑和平台适配借助 AI 工具完成，并通过代码审查、自动化检查和真机验收持续改进。如果遇到异常表现，附上诊断信息能帮助我们更快定位问题。

其他渠道：

- 源代码与版本发布：[GitHub 仓库](https://github.com/Dey410/GardendlessLoader)
- 项目介绍与使用教程：[哔哩哔哩主页](https://space.bilibili.com/523667580)

## 从源码构建

### 环境要求

- Flutter `3.41.9`（与 CI 保持一致）
- Dart `>=3.5.0 <4.0.0`
- Android：JDK 17
- iOS：macOS、Xcode 与 CocoaPods
- HarmonyOS：OpenHarmony 版 Flutter SDK、DevEco 命令行工具与 JDK 17

克隆仓库并运行静态分析：

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

APK 默认输出到 `build/app/outputs/flutter-apk/app-release.apk`。

### iOS

生成未签名的 Release 构建：

```bash
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

产物默认位于 `build/ios/iphoneos/Runner.app`，安装或分发前需要先签名。打包未签名 IPA 的完整流程见 [iOS 部署说明](docs/deployment.md)。如果本机已配置 Apple 开发者签名，可以直接运行 `flutter build ios --release` 生成已签名的构建。

### HarmonyOS / OpenHarmony

官方 Flutter stable SDK 不支持 `flutter build hap`。本项目 CI 使用以下 OpenHarmony Flutter SDK：

```text
https://gitcode.com/openharmony-tpc/flutter_flutter.git
ref: oh-3.35.7-release
```

本地构建前，先启用 OpenHarmony 依赖覆盖：

```bash
cp pubspec_overrides.ohos.yaml pubspec_overrides.yaml
flutter doctor -v
flutter pub get
flutter build hap --release --target-platform ohos-arm64
```

## 参与贡献

欢迎提交代码、文档、错误报告和功能建议。

1. Fork 本仓库，并基于最新的 `main` 分支创建功能分支。
2. Dart 代码使用两空格缩进和单引号。
3. 修改后运行 `dart format lib` 与 `flutter analyze`，然后构建受影响的平台并在真机上验证。项目目前不包含 Flutter 单元测试和组件测试。
4. 提交 Pull Request，说明改动内容和验证方式；涉及界面的改动请附上截图或录屏。

请保持现有的安全边界：资源路径只能限定在激活槽内、A/B 槽必须原子切换、WebView 默认拦截白名单之外的请求。

## 路线图

目前的工作重点：

- 提升三个平台原生 GameHost 的一致性、稳定性和性能；
- 改善大体积资源包的导入进度显示、错误提示和失败恢复；
- 兼容更新版本的 GP-Next，优化移动端的文件操作流程；
- 完善自动化检查、发布产物和真机验收流程。

欢迎在 [Issues](https://github.com/Dey410/GardendlessLoader/issues) 中提出建议、参与讨论。

## 许可证

GardendlessLoader 基于 [GNU General Public License v3.0](LICENSE) 开源。在遵守许可证条款的前提下，你可以自由使用、研究、修改和再分发本项目。

游戏资源、上游项目和第三方组件仍受各自许可证约束，本仓库的 GPL-3.0 许可证不对它们授予任何额外权利。

## 致谢

- [`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web)：本加载器所服务的上游 Web 项目。
- [Flutter](https://flutter.dev/) 与 Dart：跨平台启动器界面与业务逻辑。
- Android WebView、Apple WebKit 与 HarmonyOS ArkWeb：各平台原生 GameHost 的基础。
- 每一位贡献代码、参与测试、反馈问题和提出建议的朋友。
