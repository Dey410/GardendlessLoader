<div align="center">

<img src="tool/generated_icons/app_icon_readme.png" width="128" height="128" alt="GardendlessLoader 图标">

# GardendlessLoader

**在手机和平板上畅玩 PvZ2 Gardendless**

Android · iOS / iPadOS · HarmonyOS

[![Build Artifacts](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml/badge.svg)](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml)
[![GitHub Release](https://img.shields.io/github/v/release/Dey410/GardendlessLoader?include_prereleases&sort=semver)](https://github.com/Dey410/GardendlessLoader/releases)
[![Commit Activity](https://img.shields.io/github/commit-activity/m/Dey410/GardendlessLoader)](https://github.com/Dey410/GardendlessLoader/commits/main)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[**下载应用**](https://github.com/Dey410/GardendlessLoader/releases) · [快速开始](#快速开始) · [使用指南](#使用指南) · [常见问题](#常见问题) · [问题反馈](https://github.com/Dey410/GardendlessLoader/issues)

**简体中文** · [English](README.en.md)

</div>

---

[PvZ2 Gardendless](https://github.com/Gzh0821/pvzge_web) 是一款完全使用 Web 技术（包括 Cocos 引擎）重写的《植物大战僵尸 2》。**GardendlessLoader** 把它带到了移动设备上：导入一份游戏资源 ZIP，就能在系统原生 WebView 中直接从本地运行游戏，无需搭建服务器，也不用开着浏览器。

## 功能亮点

- 📦 **一键导入**：选好 ZIP，自动完成解压、校验和自检；也能在其他应用里直接用加载器打开 ZIP。
- 🛡️ **安全更新**：A/B 双槽更新，新资源通过校验才会替换旧资源；导入失败或取消都不会影响当前版本。
- 👆 **触屏适配**：单指、双指手势映射为鼠标操作，同时支持实体键盘、鼠标和手柄。
- 🧩 **支持 GP-Next**：兼容 GP-Next 构建的补丁、Mod 安装与 JS Modding。
- 🎛️ **画面可调**：自由调整渲染分辨率和画面比例，还能开启自动收集阳光、快速启动。
- ⚡ **原生运行**：三个平台分别使用 WebView、WKWebView 和 ArkWeb，直接读取本地资源。

## 快速开始

### 第一步：安装加载器

从 [GitHub Releases](https://github.com/Dey410/GardendlessLoader/releases) 下载对应平台的安装包：

| 平台 | 文件 | 系统要求 | 安装方式 |
| --- | --- | --- | --- |
| Android | `.apk` | Android 7.0+ | 直接安装，可能需要允许“安装未知应用” |
| iOS / iPadOS | `.ipa` | iOS 15.0+ | 未签名，需用 AltStore 等侧载工具或自己的开发者证书签名后安装 |
| HarmonyOS | `.hap` | HarmonyOS 5.0+ | 未签名，需自行签名后安装 |

想抢先体验开发中的版本？在 [GitHub Actions](https://github.com/Dey410/GardendlessLoader/actions/workflows/build-mobile.yml) 中打开任意一次成功的运行，即可下载最新构建。

### 第二步：获取游戏资源

加载器本身不包含任何游戏资源，请从以下任一渠道获取 ZIP：

| 渠道 | 内容 | 获取方式 |
| --- | --- | --- |
| **夸克网盘**（推荐） | 移动端优化包 | [打开链接](https://pan.quark.cn/s/c3da839ca8b1?pwd=qLBU)，提取码 `qLBU` |
| **extract-pvzge-gpnext** | 自动打包的 GP-Next 移动端优化包 | 在 [该仓库](https://github.com/Dey410/extract-pvzge-gpnext) 中运行 GitHub Actions |
| **上游原版** | 官方原版 Web 资源 | 在 [PvZ2 Gardendless 仓库](https://github.com/Gzh0821/pvzge_web) 点击 `Code` → `Download ZIP` |

> [!NOTE]
> 网盘中的资源由加载器作者上传，与 PvZ2 Gardendless 官方无关，更新可能略晚于官方；如果迟迟没有更新，欢迎到 [B 站](https://space.bilibili.com/523667580)提醒。通过网盘链接下载时，作者可能获得少量推广收益，用于支持项目开发。

### 第三步：导入并开始游戏

1. 打开 GardendlessLoader，切换到 **资源** 页，点击 **选择 ZIP 导入**。
2. 等待 **读取 → 解压 → 校验 → 自检** 四个步骤完成。
3. 切换到 **游戏** 页，点击 **开始游戏**。🌻

## 使用指南

### 启动偏好

在 **设置 → 启动偏好** 中调整，下次启动游戏时生效：

| 选项 | 作用 |
| --- | --- |
| **快速启动** | 打开应用后直接进入游戏 |
| **自动收集** | 游戏进行中约每 3 秒模拟按一次 `A` 键收集阳光；暂停、切到后台或正在输入文字时不会触发 |
| **渲染分辨率** | 以屏幕原生分辨率的 100% / 75% / 50% 渲染；比例越低越省显存，画面也越模糊 |
| **画面比例** | **均衡比例**（默认）裁掉少量画面以缩小黑边；**完整显示**保留全部画面，黑边更大；**强制拉伸**铺满屏幕，但画面可能变形 |
| **手势（实验）** | **模拟**（默认）为下方的手势；**原生**见下方说明 |
| **触感音效** | 爆炸、一大波僵尸、植物使用肥料、节奏命中等时刻，设备跟着震动；用手柄时改为手柄震动（默认开启，遵循系统触感设置） |
| **游戏水印** | 在游戏画面角落显示加载器标识 |

### 触摸操作

| 手势 | 对应操作 |
| --- | --- |
| 单指轻点或拖动 | 鼠标左键点击或拖动 |
| 双指轻点 | 在两指中点执行鼠标右键点击 |
| 双指滑动 | 鼠标滚轮 |
| 三指及以上 | 取消当前触摸 |
| 实体鼠标和键盘 | 由系统 WebView 原生处理 |

选择 **手势（实验）→ 原生** 后，像手机游戏一样只用一根手指：
- 把卡片、铲子、肥料、沙盒僵尸卡拖到草坪上松手就会使用，没用上会自动放回；解码小游戏的卡片、禅境花园的手套和工具也能直接拖到格子上。
- 拖到草坪上时，手上的植物和目标格会浮在手指上方，不被手指挡住；松手时落在显示的那一格。
- 单指可以滚动列表和游戏内设置页，空手时还能平移禅境花园；拖动音量滑块不会带动列表。
- 沙盒里沿卡槽、僵尸卡片或护甲图标滑动可以切换；在沙盒设置页点某一行就执行对应的快捷键（推潮、召唤僵尸、时间冻结等），点窗口外即关闭。
- 长按自定义卡组打开编辑器；在沙盒里空手长按植物，把卡槽切到这种植物；在解码小游戏里长按已填的格子清空它。
- 沙盒里长按卡片、铲子、肥料或僵尸卡，相当于键盘上的 Ctrl 组合键：用这种植物种满草坪、铲除所有植物、给所有植物施肥、消灭所有僵尸。
- 禅境花园里空手长按任意一株植物或空地，一次满足本页所有植物的需求（浇水、施肥等），相当于键盘上的 `A`。
- 双指捏合缩放禅境花园。
- 放下卡片或工具、长按生效时会轻震一下，沙盒里每滑过一格会有一次轻微的触感反馈；关闭系统触感后不会震动。

### 手柄

连接蓝牙手柄后，按任意键或推动摇杆，画面上会出现一个光标，游戏的提示条会列出按键；再触摸屏幕或使用鼠标时，光标自动隐藏。

| 按键 | 操作 |
| --- | --- |
| 左摇杆 / 十字键 | 移动光标（十字键用于微调） |
| A | 鼠标左键，按住可拖动 |
| B | 鼠标右键 |
| 右摇杆 | 鼠标滚轮 |
| X / Y | 关卡中拿起铲子 / 肥料 |
| LB / RB | 关卡中切换上一张 / 下一张可用的卡片 |
| Start | 关卡中暂停 |

X、Y、LB、RB 和 Start 使用你在游戏里设置的快捷键。GP-Next 面板等网页界面请用触摸操作。

- **节奏关**：五路从上到下依次对应 LB/RB、十字键上/Y、十字键左右/X/B、十字键下/A、LT/RT，左右手都能按；按住就一直按着这一路，Start 仍是暂停。第一次进节奏关时，提示条会列出这些按键。
- **空袭关**：飞机跟着光标飞，所以摇杆直接驾驶飞机，十字键也是全速，光标会像游戏自己的指针一样隐藏。按 B 切换成按键驾驶后，摇杆和十字键改为按住 W/A/S/D；再按 B 切回来。

### 实用技巧

- **更新资源**：在 **资源** 页点击 **选择 ZIP 更新**。更新前建议先在游戏里导出存档备份；确认框会显示你上次在加载器里导出存档的时间，也可以点 **先进游戏导出**。
- **从其他应用导入**：在文件管理器、聊天软件中选择用 GardendlessLoader 打开 ZIP 即可导入；Android 和 iOS 还支持通过“分享”导入。游戏运行期间收到的 ZIP，会等你回到启动器后再导入。
- **桌面快捷方式**：长按应用图标，可以直接选择 **开始游戏** 或 **导入资源**。
- **返回启动器**：Android 和鸿蒙使用系统返回手势，iOS 从屏幕左边缘向右滑动，也可以点击游戏内的退出按钮。
- **节日跟着游戏走**：游戏自带的节日活动（万圣节、春节、圣诞、情人节、PvZ 生日等）期间，启动器会换上对应的颜色和小徽章，游戏页显示活动的标题和介绍。日期直接读取已导入的游戏资源，春节按农历计算，不需要联网。
- **切出应用自动暂停**：关卡进行中切到其他应用、接电话或锁屏，游戏会打开自己的暂停菜单，回来时僵尸还停在原地。

### GP-Next 与 Mod

- 存档导入导出、补丁和 Mod 安装都在游戏内完成，通过系统文件选择器选取文件。
- ZIP Mod 请在 GP-Next 的模组页安装。模组平台启用后，补丁目录只接受 JSON/JSON5 单文件补丁。
- ZIP 补丁包的 `pack.json` 可以放在压缩包根目录，也可以放在唯一的一层外层目录中；加载器会自动处理外层目录，并忽略 `.DS_Store` 与 `__MACOSX`。
- JS Modding 的开关只在游戏内的 GP-Next 中设置，加载器不会读取或修改它，升级加载器后你的选择保持不变。

> [!WARNING]
> JS Mod 会在游戏中执行代码，请只安装来源可信的 Mod。

## 常见问题

<details>
<summary><b>iOS 安装包为什么需要自己签名？</b></summary>

<br>

苹果要求 iOS 应用必须经过签名才能安装，而本仓库不包含任何签名文件，所以发布的 IPA 都是未签名的。你可以使用 AltStore 等侧载工具，或用自己的 Apple 开发者证书签名后安装。使用免费 Apple ID 签名的应用每 7 天需要重新签名一次。打包与签名的细节见 [iOS 部署说明](docs/deployment.md)。

</details>

<details>
<summary><b>更新资源会丢失存档吗？</b></summary>

<br>

不会。存档保存在游戏内，更新资源不会删除它。但新版本游戏可能会改写存档，出错时也有可能损坏存档，所以更新前最好先在游戏里导出一份备份。已安装的补丁和 Mod 也不会因为更新资源而丢失。

</details>

<details>
<summary><b>游戏卡顿、发热或者闪退怎么办？</b></summary>

<br>

先尝试在 **设置 → 启动偏好** 中把 **渲染分辨率** 调到 75% 或 50%，这能明显减少显存占用。游戏崩溃后回到启动器时，**游戏** 页会说明原因，并提供一键降低分辨率后重新开始的按钮。也推荐改用移动端优化包，它降低了贴图分辨率并调整了音频质量，更适合手机和平板。

</details>

<details>
<summary><b>画面有黑边，或者边缘被裁掉了？</b></summary>

<br>

在 **设置 → 启动偏好 → 画面比例** 中切换：**均衡比例**在黑边和完整画面之间取得平衡；**完整显示**不裁切任何画面；**强制拉伸**没有黑边，但画面可能变形。

</details>

<details>
<summary><b>游戏中的图片显示不出来？</b></summary>

<br>

部分 HarmonyOS/ArkWeb 版本无法解码 AVIF 图片。请改用已经把图片转换为兼容格式的移动端优化包。

</details>

<details>
<summary><b>导入失败了怎么办？</b></summary>

<br>

导入失败或中途取消都不会影响当前已导入的资源。请确认 ZIP 是完整的 Gardendless Web 资源，再根据界面上的错误提示处理。如果问题仍然存在，欢迎[反馈问题](#问题反馈)。

</details>

<details>
<summary><b>支持哪些资源包和 GP-Next 版本？</b></summary>

<br>

支持符合 Gardendless Web 资源结构、并能通过校验的标准 Cocos 构建、GP-Next 构建，以及各种移动端轻量包。加载器会检测入口脚本及其引用的本地 `gp-next-*.js` 模块中的关键特征来判断 GP-Next 兼容性，而不是硬编码版本号；桥接层实现的是 GP-Next 0.15 所用的命令，如果后续版本修改了通信协议，即使检测通过也不能保证完全兼容。

</details>

<details>
<summary><b>为什么加载器不直接内置游戏？</b></summary>

<br>

GardendlessLoader 只负责加载和运行，不会代为下载或分发游戏资源。游戏资源属于上游项目，请从上文列出的渠道获取。

</details>

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

**已知限制**

- 不同系统 WebView 在媒体、音频和输入方面的表现可能存在差异。
- HarmonyOS 的构建与设备兼容性取决于 OpenHarmony Flutter SDK 和 DevEco 工具链。
- iOS 的高刷新率支持依赖 WebKit 私有 SPI，仅适用于侧载安装，可能随系统更新失效，也无法保证通过 App Store 审核。

## 问题反馈

遇到问题时，请先搜索已有的 [Issues](https://github.com/Dey410/GardendlessLoader/issues)，没有找到再提交新问题，并附上以下信息：

- [ ] 设备型号与系统版本
- [ ] 加载器版本与游戏资源版本
- [ ] 问题的复现步骤
- [ ] 诊断信息：在应用 **日志** 页点击 **复制诊断** 后粘贴

请不要上传或附带游戏资源包。项目介绍和使用教程可以在作者的 [哔哩哔哩主页](https://space.bilibili.com/523667580) 找到。

## 参与开发

GardendlessLoader 使用 Flutter 编写启动器界面，并为每个平台实现了原生 GameHost。欢迎提交代码、文档、错误报告和功能建议。

<details>
<summary><b>构建环境与命令</b></summary>

<br>

**环境要求**

- Flutter `3.41.9`（与 CI 保持一致）
- Dart `>=3.5.0 <4.0.0`
- Android：JDK 17
- iOS：macOS、Xcode 与 CocoaPods
- HarmonyOS：OpenHarmony 版 Flutter SDK、DevEco 命令行工具与 JDK 17

**克隆并检查**

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

产物位于 `build/app/outputs/flutter-apk/app-release.apk`。Release 构建必须在 `android/key.properties` 中配置签名（`storeFile`、`storePassword`、`keyAlias`、`keyPassword`），否则构建会报错；没有签名密钥时请改用 `flutter build apk --debug`。

**iOS**

```bash
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

产物位于 `build/ios/iphoneos/Runner.app`，安装或分发前需要签名；打包未签名 IPA 的流程见 [iOS 部署说明](docs/deployment.md)。如果本机已配置 Apple 开发者签名，可以直接运行 `flutter build ios --release`。

**HarmonyOS / OpenHarmony**

官方 Flutter stable SDK 不支持 `flutter build hap`，CI 使用的是 OpenHarmony Flutter SDK：

```text
https://gitcode.com/openharmony-tpc/flutter_flutter.git
ref: oh-3.35.7-release
```

本地构建前先启用 OpenHarmony 依赖覆盖：

```bash
cp pubspec_overrides.ohos.yaml pubspec_overrides.yaml
flutter doctor -v
flutter pub get
flutter build hap --release --target-platform ohos-arm64
```

</details>

<details>
<summary><b>资源存储与更新机制</b></summary>

<br>

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

- **双槽更新**：平时只有激活槽中存放游戏文件。更新时，新资源写入空闲槽，通过校验和自检后，`manifest.json` 才会原子地切换到新槽，随后清理旧槽，所以最多同时保留新旧两份资源。
- **补丁与 Mod 独立存放**：`gp-next/` 位于两个资源槽之外，更新游戏资源不会删除它。
- **`gp-next/` 由 GP-Next 自行创建**：GP-Next 会把已存在的 `gp-next` 目录视为旧式安装，因此加载器不会预先创建它。全新安装会直接进入 GP-Next 的模组平台，已有的旧式目录则通过 GP-Next 的“更新模组管理”升级。
- **ZIP 补丁包的外层目录**：加载器只在内部副本中去掉外层目录，你选择的原始文件不会被修改。如果包含多个候选目录、外层目录之外还有其他文件，或嵌套超过一层，导入会被拒绝。

</details>

**贡献流程**

1. Fork 本仓库，并基于最新的 `main` 分支创建功能分支。
2. Dart 代码使用两空格缩进和单引号。
3. 修改后运行 `dart format lib` 与 `flutter analyze`，然后构建受影响的平台并在真机上验证。项目目前不包含 Flutter 单元测试和组件测试。
4. 提交 Pull Request，说明改动内容和验证方式；界面改动请附上截图或录屏。

请保持现有的安全边界：资源路径只能限定在激活槽内、A/B 槽必须原子切换、WebView 默认拦截白名单之外的请求。

## 路线图

- [ ] 提升三个平台原生 GameHost 的一致性、稳定性和性能
- [ ] 改善大体积资源包的导入进度显示、错误提示和失败恢复
- [ ] 兼容更新版本的 GP-Next，优化移动端的文件操作流程
- [ ] 完善自动化检查、发布产物和真机验收流程

欢迎在 [Issues](https://github.com/Dey410/GardendlessLoader/issues) 中提出建议、参与讨论。

## 许可证与声明

GardendlessLoader 基于 [GNU General Public License v3.0](LICENSE) 开源。在遵守许可证条款的前提下，你可以自由使用、研究、修改和再分发本项目。

- 游戏资源、上游项目和第三方组件仍受各自许可证约束，本仓库的 GPL-3.0 许可证不对它们授予任何额外权利。
- 《植物大战僵尸》（Plants vs. Zombies）是 Electronic Arts Inc. 的商标。GardendlessLoader 是非官方项目，与 Electronic Arts 和 PopCap Games 均无关联。
- 本项目的部分界面、逻辑和平台适配借助 AI 工具完成，并通过代码审查、自动化检查和真机验收持续改进。

## 致谢

- [PvZ2 Gardendless](https://github.com/Gzh0821/pvzge_web)：本加载器所服务的上游游戏项目。
- [Flutter](https://flutter.dev/) 与 Dart：跨平台启动器界面与业务逻辑。
- Android WebView、Apple WebKit 与 HarmonyOS ArkWeb：各平台原生 GameHost 的基础。
- 每一位贡献代码、参与测试、反馈问题和提出建议的朋友。

<div align="center">

<sub>如果这个项目对你有帮助，欢迎点一个 ⭐ Star 支持一下！</sub>

</div>
