<p align="center">
  <img src="tool/generated_icons/app_icon_master.png" alt="GardendlessLoader 图标" width="96" height="96">
</p>

# GardendlessLoader

[English](README.en.md)

`GardendlessLoader` 是一个 Flutter 本地加载器，用来在移动端和 Web 端加载用户自行提供的
[`PvZ2 Gardendless`](https://github.com/Gzh0821/pvzge_web) 网页资源包。

App 会让用户选择资源 ZIP，自动解压并定位其中的 `docs` Web 构建目录，完成结构校验后通过本地 HTTP
服务提供文件，再用应用内 WebView 打开游戏。

> [!IMPORTANT]
> 本项目不内置、下载、更新或再分发 `PvZ2 Gardendless` 游戏资源。用户需要自行获取资源 ZIP，并在本地导入。

## 功能特性

- 从 ZIP 中自动查找并解压有效的 `docs` 资源目录。
- 校验 `PvZ2 Gardendless` Cocos Web 构建结构、标题和指纹。
- 使用 `http://127.0.0.1:26410` 提供本地静态资源服务。
- 游戏页固定横屏、沉浸式显示，并默认拦截非本地请求。
- 导入过程带进度显示，失败时回滚到旧资源，启动时恢复未完成事务。
- 提供可复制的诊断信息，方便排查资源、平台、WebView 和本地 server 状态。
- 支持公告弹窗、GitHub Release 更新检查、自动收集阳光和强制拉伸画面开关。
- GitHub Actions 可产出 Android、iOS、HarmonyOS/OpenHarmony 和 Web 产物。

## 使用方式

1. 从上游项目或可信来源获取 `PvZ2 Gardendless` 资源 ZIP。
2. 打开 `GardendlessLoader`，点击“选择 ZIP 导入”。
3. App 会在 ZIP 根目录或嵌套目录中查找有效的 `docs`，解压到应用资源目录并导入到 `current`。
4. 导入成功后点击“开始游戏”，游戏将从本地地址加载。

导入完成后，资源会被组织在应用创建的 `GardendlessLoader` 目录下：

```text
GardendlessLoader/
  import/docs/     # 最近一次从 ZIP 解压出的 docs
  current/         # 当前正在使用的资源
  previous/        # 回滚用的上一版资源
  staging/         # 导入事务临时目录
  manifest.json    # 导入状态、资源统计和公告状态
```

资源根目录位置会因平台不同而不同，App 首页会显示当前设备上的完整路径。

## 资源要求

ZIP 中必须包含一个有效的 `PvZ2 Gardendless` Web 构建目录。它可以位于 ZIP 根目录，也可以位于类似
`release/docs` 的嵌套路径。最低要求如下：

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

校验器还会检查：

- `index.html` 标题包含 `PvZ2 Gardendless`。
- `index.html` 包含 `pvzge` 或 `play.pvzge.com` 指纹。
- `src/settings.json` 是有效 JSON，并符合 Cocos 配置文件的基本形态。

## 开发

本仓库要求 Flutter 和 Dart `>=3.5.0 <4.0.0`。

```powershell
flutter pub get
flutter test
flutter run
```

关键文件：

| 路径 | 用途 |
| --- | --- |
| `lib/src/app_controller.dart` | App 状态、导入流程、server 生命周期、公告和更新检查编排 |
| `lib/src/services/resource_picker_service.dart` | ZIP 选择、路径安全检查、`docs` 自动定位和解压 |
| `lib/src/services/import_service.dart` | staging 导入、current 切换、失败回滚、启动恢复 |
| `lib/src/services/local_game_server.dart` | 本地 HTTP server、MIME 处理和自检 |
| `lib/src/services/resource_validator.dart` | 资源结构、标题和 Cocos 配置校验 |
| `lib/src/ui/home_page.dart` | 导入、状态、公告、更新和诊断 UI |
| `lib/src/ui/game_page.dart` | 横屏 WebView 游戏页、菜单和游戏辅助开关 |
| `announcements.json` | 远程公告配置 |

## 构建

### Android

```powershell
flutter build apk --release
```

CI 支持在配置以下仓库密钥后签名 release APK：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

未配置签名密钥时，CI 会使用 debug signing 继续产出 APK。

### iOS

```powershell
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

CI 会打包未签名 IPA，供后续手动签名或分发流程使用。

### HarmonyOS / OpenHarmony

HAP 构建需要 OpenHarmony 兼容 Flutter SDK，以及 DevEco Studio 或命令行工具中的 `ohpm`、`hvigor`、`node`
和 JDK 17。官方 Flutter stable SDK 不提供 `flutter build hap`。

CI 默认使用：

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
flutter build hap --release --target-platform ohos-x64
```

## CI

`.github/workflows/build-mobile.yml` 会运行测试并构建以下产物：

- Android release APK
- Web bundle
- 未签名 iOS IPA
- 未签名 HarmonyOS HAP（配置 `OHOS_COMMANDLINE_TOOLS_URL` 后启用）

HarmonyOS 工具未配置时，该任务会跳过，不影响其他平台构建。
