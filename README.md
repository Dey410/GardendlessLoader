<p align="center">
  <img src="tool/generated_icons/app_icon_master.png" alt="GardendlessLoader 图标" width="96" height="96">
</p>

# GardendlessLoader

[English](README.en.md)

`GardendlessLoader` 是一个 Flutter 移动端本地加载器，用于加载用户自行提供的
[`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web) 网页资源。

它会导入解压后的 `docs` 资源目录，通过本地 HTTP 服务提供文件，并在 Android、
iOS、HarmonyOS/OpenHarmony 构建中使用应用内 WebView 打开游戏。

> [!IMPORTANT]
> 本 App 不内置、下载、更新或再分发 `PvZ2 Gardendless` 游戏资源。用户需要自行准备
> 解压后的资源，并在本地导入。

## 功能

- 从 `GardendlessLoader/import/docs` 导入本地资源。
- 校验 `PvZ2 Gardendless` Cocos 网页构建的目录结构和指纹。
- 通过 `http://127.0.0.1:26410` 提供本地静态服务。
- 横屏应用内 WebView，默认拦截非本地跳转。
- 显示导入进度，导入失败时回滚，启动时恢复未完成事务。
- 提供可复制的诊断信息，便于排查问题。
- 提供自动收集阳光、强制拉伸等可选游戏辅助开关。
- 支持通过 `announcements.json` 显示远程公告。

## 工作方式

首次启动时，App 会创建名为 `GardendlessLoader` 的资源根目录。用户需要把解压后的
`docs` 文件夹复制到：

```text
GardendlessLoader/import/docs/index.html
```

App 会校验导入源，将资源暂存并切换到：

```text
GardendlessLoader/current
```

随后通过本地服务自检关键文件：

```text
http://127.0.0.1:26410
```

游戏运行时，WebView 只加载这个本地地址。

## 资源要求

导入的 `docs` 目录必须是有效的 `PvZ2 Gardendless` 网页构建。校验器至少要求：

```text
docs/
  index.html
  assets/
  cocos-js/
  src/
    settings.json
    import-map.json
```

`index.html` 需要包含 `PvZ2 Gardendless` 标题/指纹，`src/settings.json` 需要符合
Cocos 配置文件的基本结构。

## 开发

本仓库要求 Flutter 使用 Dart `>=3.5.0 <4.0.0`。

```powershell
flutter pub get
flutter test
flutter run
```

关键项目文件：

| 路径 | 用途 |
| --- | --- |
| `lib/src/app_controller.dart` | App 状态、导入流程、服务生命周期、诊断信息 |
| `lib/src/services/import_service.dart` | 暂存导入、失败回滚、启动恢复 |
| `lib/src/services/local_game_server.dart` | 本地静态 HTTP 服务和 MIME/自检逻辑 |
| `lib/src/services/resource_validator.dart` | 资源结构和指纹校验 |
| `lib/src/ui/home_page.dart` | 导入和状态首页 |
| `lib/src/ui/game_page.dart` | 横屏 WebView 游戏页 |
| `announcements.json` | 远程公告内容 |

## 构建

### Android

```powershell
flutter build apk --release
```

GitHub Actions 在配置以下仓库密钥后可以签名 release APK：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

如果没有配置签名密钥，CI 会使用 debug signing。

### iOS

```powershell
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

CI 会打包未签名 IPA，供后续手动签名或分发流程使用。

### HarmonyOS / OpenHarmony

HAP 构建需要 OpenHarmony 兼容的 Flutter SDK，以及配置好的 DevEco Studio 或命令行工具：
`ohpm`、`hvigor`、`node` 和 JDK 17。

官方 Flutter stable SDK 不提供 `flutter build hap`。CI 默认使用：

```text
https://gitcode.com/openharmony-tpc/flutter_flutter.git
ref: oh-3.35.7-release
```

本地构建前，启用 OpenHarmony 插件覆盖：

```powershell
Copy-Item pubspec_overrides.ohos.yaml pubspec_overrides.yaml
flutter doctor -v
flutter pub get
flutter test
flutter build hap --release --target-platform ohos-arm64
```

OpenHarmony 构建布局下的预期签名 HAP 输出：

```text
ohos/entry/build/default/outputs/default/entry-default-signed.hap
```

在 GitHub Actions 中，将 `OHOS_COMMANDLINE_TOOLS_URL` 设置为 DevEco/OpenHarmony
命令行工具压缩包地址。未配置该密钥时，HarmonyOS 任务会跳过，Android 和 iOS
产物仍会继续构建。

## CI

`.github/workflows/build-mobile.yml` 会构建：

- Android release APK
- 未签名 iOS IPA
- 配置 OpenHarmony 工具后构建未签名 HarmonyOS HAP

打包移动端产物前，CI 会先运行 Flutter 测试。
