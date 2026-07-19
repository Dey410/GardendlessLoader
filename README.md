<p align="center">
  <img src="tool/generated_icons/app_icon_master.png" alt="GardendlessLoader 图标" width="96" height="96">
</p>

# GardendlessLoader

[English](README.en.md)

`GardendlessLoader` 是一个 Flutter 本地加载器，用来在 Android、iOS 和 HarmonyOS/OpenHarmony 上加载用户自行提供的
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
- 自动识别 GP-Next 1.4.2 桌面构建，在不修改游戏资源的前提下注入移动端兼容桥，并在游戏菜单显示“打开 GP-Next”。
- 导入过程带进度显示；新资源直接写入空闲槽，失败时继续使用原激活槽，启动时恢复未完成事务。
- 提供可复制的诊断信息，方便排查资源、平台、WebView 和本地 server 状态。
- 游戏画面在 `16:10～17:9` 之间自适应屏幕，并支持首页公告、加载器与游戏资源双更新检查和自动收集阳光。
- 从资源页面标题识别本地游戏版本，以 [`pvzg_site` 稳定版 tags](https://github.com/Gzh0821/pvzg_site/tags) 检查游戏更新；发现更新时提供游戏 GitHub 与共享网盘入口。
- GitHub Actions 可产出 Android、iOS 和 HarmonyOS/OpenHarmony 产物。

## 使用方式

1. 从上游项目或可信来源获取 `PvZ2 Gardendless` 资源 ZIP。
2. 打开 `GardendlessLoader`，点击“选择 ZIP 导入”。
3. App 会在 ZIP 根目录或嵌套目录中查找有效的 `docs`，并直接解压到空闲资源槽。
4. 导入成功后点击“开始游戏”，游戏将从本地地址加载。

### 游戏内触摸操作

- 单指轻点或拖动：鼠标左键点击或拖动。
- 双指轻点：在双指中心位置执行鼠标右键点击。
- 双指滑动：模拟鼠标滚轮；移动超过阈值后，本次手势不再触发右键。
- 三指及以上：不执行鼠标映射，并取消当前触摸手势。
- 实体鼠标和键盘继续由系统 WebView 原生处理。

双指轻点需要在 250 毫秒内完成，且双指中心移动不超过 14 CSS 像素。游戏菜单中的“自动收集阳光”开启后，会每 1.5 秒模拟一次 `A` 键。游戏水印默认开启，可在菜单中关闭；应用会记住最后一次选择。

导入完成后，资源会被组织在应用创建的 `GardendlessLoader` 目录下：

```text
GardendlessLoader/
  slot-a/          # 资源槽 A
  slot-b/          # 资源槽 B
  gp-next/
    packs/         # 持久化的 GP-Next ZIP 补丁包
    patches/       # 持久化的 JSON/JSON5 单文件补丁
  manifest.json    # 激活槽、事务状态、资源统计和本地游戏版本
```

常态下只有激活槽包含游戏文件，另一个槽为空；更新期间旧激活槽和新候选槽最多各保留一份资源。新槽通过校验和本地自检后，manifest 才会切换激活槽，随后清空旧槽。资源根目录位置会因平台不同而不同，App 首页和诊断日志会显示当前设备上的完整路径及激活槽。

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
- 若标题包含 `0.11.0`、`v0.11.0` 或 `0.12.0-next` 形式的版本号，App 会识别并显示该游戏版本。
- `index.html` 包含 `pvzge` 或 `play.pvzge.com` 指纹。
- `src/settings.json` 是有效 JSON，并符合 Cocos 配置文件的基本形态。

### GP-Next 兼容

Loader 当前精确适配反编译资源中的 GP-Next `1.4.2`。识别到其他 GP-Next 版本时，游戏资源仍可正常导入和启动，但兼容桥与“打开 GP-Next”按钮会禁用并显示原因；普通 Web 构建继续使用原有流程。

GP-Next 明确定义的补丁发现、解析、加载、保存、重新加载和 JS Mod 开关行为保持不变。移动端仅替代桌面系统边界：AppData 文件 API 映射到 Loader 的 `gp-next` 沙箱，“打开补丁目录”映射为系统文件选择器，保存对话框映射为系统导出。选择器只接受根目录含 `pack.json` 的 ZIP、JSON 和 JSON5；裸 JavaScript 不可导入。重名文件必须确认后才以可回滚方式替换。JS Mod 仍按 GP-Next 默认关闭，需用户在 GP-Next 中明确开启。

`gp-next` 不属于双资源槽，因此游戏资源更新不会删除已导入补丁和 Mod。兼容桥拒绝访问该目录之外的路径和符号链接；WebView 仍默认阻止外部请求，只放行内置 GP-Next 使用的固定官方域名。

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
| `lib/src/services/import_service.dart` | 双槽导入、原子激活、旧结构迁移和启动恢复 |
| `lib/src/services/local_game_server.dart` | 本地 HTTP server、MIME 处理和自检 |
| `lib/src/services/resource_validator.dart` | 资源结构、标题和 Cocos 配置校验 |
| `lib/src/services/game_update_check_service.dart` | 本地游戏版本识别、稳定 tag 选择和版本比较 |
| `lib/src/services/gp_next_bridge_service.dart` | GP-Next 1.4.2 Tauri 文件、对话框和 opener 兼容层 |
| `lib/src/services/gp_next_package_importer.dart` | GP-Next 补丁选择、校验和事务替换 |
| `lib/src/ui/home_page.dart` | 导入、状态、公告、更新和诊断 UI |
| `lib/src/ui/game_page.dart` | 横屏 WebView 游戏页、菜单和游戏辅助开关 |
| `lib/src/web/touch_patch.dart` | 单指左键、双指右键/滚轮和触摸取消状态机 |
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
- 未签名 iOS IPA
- 未签名 HarmonyOS HAP（配置 `OHOS_COMMANDLINE_TOOLS_URL` 后启用）

HarmonyOS 工具未配置时，该任务会跳过，不影响其他平台构建。
