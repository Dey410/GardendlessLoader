# Shredder Report — GardendlessLoader iOS 端 Clean-Slate 重建

> 阶段状态：**Phase 1 完整分析（只读）**
> 本文件是 Shredder Skill 的阶段性报告。当前只描述现状、保留项、候选架构与重建计划；未修改任何生产代码，未删除任何文件，未开始实现。

## 0. 当前 Git 事实（2026-08-05 检查）

- 仓库：`Dey410/GardendlessLoader`（origin: git@github.com:Dey410/GardendlessLoader.git）
- 当前分支：`codex/native-sfx-exception-guard`（工作树干净，与 `origin/codex/native-sfx-exception-guard` 同步）
- 其他分支：`main`、`codex/native-gamehost-refactor`、`origin/*` 对应远端
- 最近提交：iOS 原生 SFX 异常保护与音频桥修复（`30a56c9` 等）
- ⚠️ 待确认：当前分支名不是独立的“重建/Shredder”分支名。本阶段假设用户所说“独立重建分支”就是当前分支；若实际应在其他分支上重建，请指出，报告可整体迁移。
- 本阶段不合并、不 force push、不改写历史、不删除原始分支。

## 1. 现有行为地图

### 1.1 语言 / 框架 / 构建

| 层 | 技术 | 关键事实 |
| --- | --- | --- |
| 启动器（Dart） | Flutter 3.x（本地 3.44.3，CI 固定 3.41.9），Dart SDK `>=3.5.0 <4.0.0` | Material 3、ChangeNotifier；`flutter_lints` + `prefer_single_quotes` |
| iOS 原生 | Swift 5.0，最低 iOS 14.5 | WKWebView、WKURLSchemeHandler、WKScriptMessageHandlerWithReply、AVAudioEngine、zlib |
| iOS 插件集成 | Flutter Swift Package Manager（`FlutterGeneratedPluginSwiftPackage`，ephemeral 生成） | package_info_plus、wakelock_plus；path_provider_foundation 亦在插件列表 |
| iOS 单元测试 | 仓库内 `ios/Package.swift`（GardendlessNativeCore SwiftPM 测试包） | 覆盖资源处理器、路径定位器、视口、网络策略、JS 参数编码 |
| Android / HarmonyOS | Kotlin WebView / ArkWeb（ETS） | 与 iOS 共享 Dart 启动器和 JS 桥资产 |
| 其余平台 | linux/、macos/、web/、windows/ | AGENTS.md 声明为“已退役平台生成目录，保留但不支持” |
| CI/CD | `.github/workflows/build-mobile.yml` | push/workflow_dispatch；Android APK、iOS 无签名 IPA、OHOS 无签名 HAP |

### 1.2 入口点

- Flutter：`lib/main.dart` → `NativeAppLogger.initialize` → `runZonedGuarded` → `GardendlessLoaderApp` → `AppController.initialize` → `HomePage`。
- iOS 原生：`@main AppDelegate` → `showLauncher()` 创建 launcher `FlutterEngine` + `FlutterViewController`，注册 4 个 MethodChannel 服务；`game_host#launch` → 编译网络策略 → 创建 `GameViewController`，销毁 launcher engine。
- 游戏页：`GameViewController` 持有单 `WKWebView`，注入共享 JS，挂载 scheme handler / 内容规则 / 脚本桥 / 音频桥。

### 1.3 模块总览与依赖方向

```text
Flutter launcher (lib/)
  AppController（状态编排：导入、启动、更新、日志、设置）
    ├─ services：AppPathsService / ManifestStore / ImportService / ResourceValidator /
    │            ResourceSelfCheck / ResourcePickerService / AppSettingsStore /
    │            UpdateCheckService / GameUpdateCheckService / AnnouncementService /
    │            AboutContentService / DiagnosticsService / ImportProgressMeter
    ├─ game_host：GameSession / GameHostRouter / MethodChannelGameHost / GameSessionStore
    └─ logging：AppLogger / NativeAppLogger / LogEventCatalog
          ↓ MethodChannel（4 个）
iOS native (ios/Runner/)
  AppDelegate（channel 注册 + ZIP 导入 + 游戏宿主切换 + 外链）
  GameViewController（WKWebView 生命周期、脚本注入、导出、GP-Next 选择器、退出）
    ├─ GameResourceSchemeHandler + GameResourceLocator（gardendless-game:// 资源服务）
    ├─ GameScriptBridge（JSON 请求/响应桥）
    ├─ GameAudioBridge + NativeSfxEngine（短音效原生播放）
    ├─ GpNextNativeCore（GP-Next 沙箱 FS/导出/导入）
    ├─ GameNavigationDelegate（导航策略 + 渲染进程退出）
    └─ AppLogStore（JSONL 持久化日志）
shared JS (assets/game_bridge/)
  bootstrap / transport / logging / touch_patch / auto_sun / export_download_patch /
  gp_next_core / gp_next_compat_bridge / watermark / ios_audio_proxy
```

依赖方向：Dart UI → AppController → services/game_host → MethodChannel → iOS native；iOS native 不反向依赖 Dart 业务逻辑（只通过通道回传事件/结果）。JS 桥资产由 iOS 原生在创建 WebView 时从 Flutter asset 读取后注入。

### 1.4 主要用户流程

1. **首次启动**：创建 `Documents/GardendlessLoader/{slot-a,slot-b,gp-next/packs,gp-next/patches}`，初始化空 manifest，静默检查更新。
2. **导入 ZIP**：点击“选择 ZIP 导入” → 原生文档选择器（iOS `UTType.zip`、`asCopy: true`）→ Swift 流式解压到空闲槽 → Dart 校验（目录/文件/指纹/Cocos settings）→ 文件系统自检 → manifest 激活 → 清理旧槽 → 展示进度 → 刷新游戏更新状态。
3. **启动游戏**：校验激活槽 → `GameSession` 写入 `game_session.json` → MethodChannel `launch` → iOS 编译 WKContentRuleList → `GameViewController` 全屏横屏加载 `gardendless-game://localhost/index.html?generation=N` → 释放 Flutter launcher engine。
4. **游戏内**：触摸映射、自动收集阳光、存档导出（分块传输 + 文档保存选择器）、GP-Next 打开/导入/导出、水印开关、返回启动器（左边缘手势）、渲染进程退出恢复。
5. **更新中心**：分别检查加载器（GitHub Releases latest）与游戏（pvzg_site tags 稳定版）；提供网盘/GitHub 入口与“稍后提醒”。
6. **日志与诊断**：结构化日志浏览/筛选/复制/删除历史；诊断摘要复制。
7. **关于与公告**：远程公告（含 fallback）、远程关于内容（本地缓存 + bundled fallback）。

### 1.5 UI 页面与面板

- `HomePage`：资源区（`_LauncherSection.resources`）与诊断区（`_LauncherSection.diagnostics`）双栏目。
- 资源区：`_ResourceHeroCard`（标题/状态/版本）、`_ResourceDetailsCard`（路径、槽、统计、自检）、`_QuickActionsCard`（导入/打开 GitHub）、`_ImportProgressRegion`、`_AutoCollectSunControl`（仅标准资源显示，GP-Next/无资源隐藏）、`_StartGameButton`、`_UpdateCenter`、公告面板、启动健康面板。
- 诊断区：`_StructuredLogBrowser`（级别筛选、只看错误、事件/操作过滤、单条复制）、日志状态、复制诊断摘要、删除历史日志。
- 关于：`AlertDialog` 显示远程关于内容。

### 1.6 数据模型与存储

`Documents/GardendlessLoader/`（iOS；Android/OHOS 为各自应用私有目录）：

| 文件/目录 | 用途 | Schema |
| --- | --- | --- |
| `manifest.json` | 激活槽、事务状态、统计、版本、偏好 | schema v4（`generation`、`activeSlot`、`transaction.slot/state`、`buildProfile`、`gpNext*`、`autoCollectSunEnabled` 等） |
| `slot-a/`、`slot-b/` | 双资源槽；激活槽放完整 Web 构建 | 每槽 `.slot-metadata.json`（generation/gameVersion/importedAt/lastSelfCheckAt） |
| `gp-next/packs/`、`gp-next/patches/` | GP-Next 补丁包与 JSON/JSON5 补丁 | 文件名即标识；ZIP 根须含 `pack.json` |
| `app_settings.json` | `watermarkEnabled` | 单键对象 |
| `game_session.json`（+`.tmp`） | 待启动会话 | `GameSession.schemaVersion=1` |
| `game_exit_result.json` | 上次退出原因 | schema v1（`reason` ∈ normal/userReturned/rendererGone/launchFailed/systemTerminated） |
| `about_content.json` | 远程关于内容缓存 | schema v1 |
| 旧迁移目录 `import/ current/ previous/ staging/` | 旧版资源布局（一次性迁移用） | 迁移完成后删除 |
| `Application Support/GardendlessLoader/logs/` | 结构化日志 JSONL | `LogEvent.schemaVersion=1`；2MB/段、500 条内存环、7 天/5 组/10MB 清理 |

Dart 端模型：`ResourceStatus`、`ResourceBuildProfile`、`ResourceSlot`、`TransactionState`、`ImportPhase`、`ResourceManifest`、`GameSession`、`GameExitResult`、`Announcement`、`AboutContent`、`ImportProgress`、`DiagnosticSnapshot`、`LogEvent`。

### 1.7 平台通道与 Bridge 契约

MethodChannel（Dart ↔ iOS）：

| Channel | 方法 | 方向 |
| --- | --- | --- |
| `io.github.dey410.gardendlessloader/resource_zip_importer` | `pickAndExtractDocsZip` + `progress` 事件（receiving/extracting） | Dart→iOS / iOS→Dart |
| `io.github.dey410.gardendlessloader/game_host` | `launch(sessionJson)` | Dart→iOS |
| `io.github.dey410.gardendlessloader/external_browser` | `open(url)`（仅 http/https） | Dart→iOS |
| `io.github.dey410.gardendlessloader/app_logger` | `initialize` / `emit` / `snapshot` / `flush` / `deleteHistory` / `endSession` | 双向 |

JS Bridge（页面 ↔ iOS，`gardendlessNative` 消息处理器 + 请求 ID 响应）：

- 宿主命令：`host:returnHome` / `host:return_home`、`host:setWatermark` / `host:set_watermark`、`host:log`、`host:export`、`host:exportBegin` / `exportChunk` / `exportCommit` / `exportAbort`。
- GP-Next 命名空间：`plugin:fs|mkdir`、`read_dir`、`read_file` / `read_text_file`、`exists`、`remove`、`write_text_file`；`plugin:dialog|save`；`plugin:opener|open_url` / `open_path`。
- JS 侧本地兼容：`plugin:path|resolve_directory`、`plugin:event|listen`、`plugin:drpc|is_running`、`plugin:deep-link|*`、`plugin:window|*`、`plugin:image|*` 等。
- 响应上限 1MB、请求超时 15s（用户交互类 5min）、重复 ID 拒绝、销毁时 `rejectAll`。

### 1.8 外部系统契约

| 外部 | 用途 | 约束 |
| --- | --- | --- |
| `https://api.github.com/repos/Dey410/GardendlessLoader/releases/latest` | 加载器更新 | 5s 超时、64KB 上限、版本归一化后比较 |
| `https://api.github.com/repos/Gzh0821/pvzg_site/tags?per_page=100` | 游戏更新 | 只取 `^\d+\.\d+\.\d+$` 稳定 tag |
| `https://raw.githubusercontent.com/Dey410/GardendlessLoader/main/announcements.json` | 公告 | schema v1、3s 超时、32KB 上限、离线 fallback |
| `https://raw.githubusercontent.com/Dey410/GardendlessLoader/main/about_content.json` | 关于内容 | schema v1、3s 超时、16KB 上限、版本号升级才覆盖缓存 |
| 外链 | 网盘（quark）、B站、GitHub、游戏 GitHub | 仅 http/https 外开 |
| GP-Next 白名单 | `pvzge.com`、`github.com`、`discord.gg` | WKContentRuleList：默认全拦 http/https，仅白名单主机放行 |

### 1.9 配置与环境

- 编译期：`APP_VERSION`（默认 `0.7.2`，与 pubspec 一致）。
- 运行时：iOS `UserDefaults.nativeSfxEnabled`（默认 true）、`app_settings.json#watermarkEnabled`（默认 true）。
- CI secrets：`ANDROID_KEYSTORE_*`、`OHOS_COMMANDLINE_TOOLS_URL`；无 iOS 签名秘密（unsigned IPA）。
- 仓库不提交：签名文件、key、`.env*`、生成目录、资源 ZIP。

### 1.10 错误处理与日志

- 导入：`ImportFailure(code, message)`、`ResourcePickerFailure(code)`；事务失败清理候选槽、保留旧激活槽。
- 游戏宿主：`GameSessionError.invalid`；启动失败写 `game_exit_result.json`，返回启动器并提示。
- WebView：`didFailProvisionalNavigation`（初始导航失败→launchFailed）、`webViewWebContentProcessDidTerminate`（→rendererGone）。
- 结构化日志：跨 Dart/iOS/JS 四通道统一事件模型（level/source/category/event/outcome/appSessionId/gameSessionId/operationId/code/durationMs/context/error），本地 JSONL 持久化、脱敏（token/password/路径）、丢弃保护（1000 pending 后仅 ERROR/FATAL，1100 全丢）、单事件 16KB 截断。

### 1.11 构建 / 测试 / 发布

- 本地：`flutter pub get`、`flutter analyze`、`flutter test`（并发 1）、`dart format lib test`、`git diff --check`。
- iOS：`pod install`（当前实际走 SPM 插件包）、`flutter build ios --release --no-codesign`、zip 成 `GardendlessLoader-unsigned.ipa`。
- Swift 测试：`ios/Package.swift` 中 `GardendlessNativeCoreTests`（资源处理器/定位器/视口/网络策略/JS 编码）。
- 检查脚本：`tool/check_*.mjs`（game bridge / touch patch / auto sun / export download patch 静态校验）。
- CI：push 触发三平台构建；OHOS 无 secret 时跳过并输出 notice。
- 发布习惯：版本号同步 pubspec + constants；远端 `announcements.json` 更新；draft PR 由用户确认后发布。

## 2. 必须保留的产品能力（已确认）

1. 用户自备 PvZ2 Gardendless 资源 ZIP 的本地导入与双槽事务管理（进度、失败保留旧槽、启动恢复）。
2. 资源校验：`index.html`、`assets/`、`cocos-js/`、`src/settings.json`、`src/import-map.json`；标题含 `PvZ2 Gardendless`；`pvzge` 指纹；Cocos settings 形态。
3. 原生 GameHost：零 HTTP 服务器、固定合成 Origin、全屏横屏、沉浸式、Range/ETag/MIME/流式资源服务。
4. iOS 固定 Origin `gardendless-game://localhost` + `?generation=N` 入口。
5. 游戏内触摸映射完整矩阵（单指左键、双指右键候选/滚轮、取消/丢失焦点不卡键、编辑区与 GP-Next 原生豁免）。
6. 自动收集阳光（仅标准资源、GP-Next 禁用；3 秒周期、A 键 keydown/keyup、暂停/后台/特殊关卡取消）。
7. 水印默认开启、可关闭、持久化。
8. 存档导出（分块、系统保存选择器、取消/中止清理）与 GP-Next 文件导入/替换确认/回滚。
9. GP-Next 1.4.x 兼容桥与 `gp-next` 沙箱（packs/patches，禁止越界与符号链接）。
10. 加载器/游戏双更新检查、更新中心、公告、关于内容。
11. 跨平台结构化本地日志 + 诊断摘要复制。
12. 加载器与游戏资源状态独立显示；导入期间禁用相关操作。
13. 渲染进程退出/启动失败/正常返回三类退出结果可被启动器识别。
14. 三平台 CI 产物（iOS unsigned IPA 是本次范围直接相关项）。

## 3. 核心业务规则（代码证据）

### 3.1 ZIP 导入（iOS 原生）
- `UIDocumentPickerViewController(forOpeningContentTypes: [.zip], asCopy: true)`；单文件；formSheet。
- 只支持经典 ZIP（拒绝 ZIP64：EOCD/中央目录 32 位极限值）、拒绝加密（flag bit 0）、拒绝符号链接（unix mode 0o120000）。
- 路径安全：反斜线转 `/`、拒绝绝对路径、`.`/`..`、空段；输出路径必须位于目标槽内。
- `docs` 定位：候选为所有含 `index.html` 的目录；要求 `index.html`、`src/settings.json`、`src/import-map.json` 与 `assets/`、`cocos-js/`、`src/` 齐备；优先 basename 恰为 `docs` 的目录，其次最短路径。
- 流式解压：64KB 缓冲、deflate 用 zlib `inflateInit2_(..., -MAX_WBITS)`、stored 直拷；进度事件节流 100ms。

### 3.2 校验与事务（Dart）
- 校验链：必需目录 → 必需文件 → 标题指纹 → `pvzge`/`play.pvzge.com` 指纹（GP-Next 检出时豁免）→ settings JSON 形态。
- GP-Next 检出：模块入口脚本含 `GP-Next loading` + `window.gpNext` + `loadAllPatches`；必须含 `patcher-`、`file-loader-`、`js-mod-loader-` 指纹，缺则 `gpNextCompatibilityError`。
- 双槽事务：`beginImport` 清空空闲槽并写 `extracting`；`completeImport` 依次 `validating → selfChecking → readyToActivate`，全部通过才写槽元数据、切换 `activeSlot`、`cleaningOldSlot` 清旧槽；任一步失败清候选槽并保留旧激活槽。
- 崩溃恢复：`extracting/validating/selfChecking` 清候选；`readyToActivate` 重新校验并完成激活；`cleaningOldSlot` 延迟清理；无 manifest 时从槽元数据按最大 generation 恢复。
- 旧版迁移：`current` 优先、`previous` 其次，复制到 slot-a 后删旧目录；失败保留旧布局。
- 自检：根目录不得为符号链接；必需文件路径逐段无符号链接、最终解析仍在根内、可读。

### 3.3 游戏会话与安全
- `GameSession` 必须校验 schema/platform/origin；`entryPath` 不允许 scheme、绝对路径、`.`/`..`、反斜线；`allowedRemoteHosts` 必须为合法 DNS 标签。
- WKContentRuleList：默认阻断 `^http://` 与 `^https://`，仅放行白名单主机（含子域）；规则缓存 key 为 `gardendless-network-v2-<hosts|offline>`。
- 资源处理器：只接受 scheme=gardendless-game、host=localhost；仅 GET/HEAD；支持 Range/206/416、If-None-Match/304、ETag、Cache-Control；大文件分块（128KB）读；停止任务后不再回调；音频小文件（≤256KB）内存缓存（24MB LRU），BGM/music 不缓存；MIME 显式映射；mp3 按魔数识别真 MP3/M4A（伪装 AAC）。
- 导航策略：主框架只允许本地 origin；其他 https 白名单主机交系统浏览器并 cancel；渲染进程退出写 rendererGone。
- GP-Next 沙箱：所有路径解析锚定 `gp-next` 根；`baseDir` 只允许 14（TAURI APPDATA 语义）；禁止符号链接、禁止删根；`open_url` 必须白名单；导入 ZIP 必须根含 `pack.json`，JSON 必须可解析，JSON5 非空；重名替换需确认且失败回滚（backup）。

### 3.4 触摸 / 自动收集 / 水印
- 触摸矩阵（见 `docs/acceptance-checklist.md` 与 `touch_patch.js`）：20 物理像素双指中心纵向阈值、`-4.5` 滚轮倍率、250ms 右键候选、RAF 合成事件、焦点丢失/取消手势不得残留鼠标键、原生豁免区（输入框/编辑区/GP-Next `#gp-overlay`、`#ge-toast-wrap`、`.gp-f1-hint`）保留原生触摸。
- 自动收集：仅标准资源；3 秒循环、keydown 50ms 后 keyup；离开游戏/暂停/空袭/特殊关卡/输入聚焦/后台/失焦取消；模块加载失败仅记一次不影响游戏。
- 水印：默认 true；`host:setWatermark` 写 `app_settings.json`；JS 端 `gardendless:watermark` 事件即时切换。

### 3.5 更新 / 公告 / 关于
- 加载器更新：GitHub release `tag_name` 与安装版本（package_info 优先，编译期 fallback）比较；同版本不提示；可“稍后提醒”（本次会话内不重复提示）。
- 游戏更新：本地版本从 index title 或入口模块 `Playing version|Game Version:` 提取；远端只认稳定 tag；本地高于远端显示“高于公开稳定版”；两个检查相互独立、任一失败给对应提示。
- 公告：schema v1；失败/无效回退本地公告；链接必须 https。
- 关于：schema v1；缓存版本号不高于本地则不动；bundled 兜底。

## 4. 安全和权限要求

- 无存储权限申请（iOS 无权限清单项；Android 用 SAF；OHOS 应用私有目录）。
- 路径越界防护（ZIP 路径、资源处理器、GP-Next FS、导出文件名）与符号链接拒绝（导入、自检、定位器、GP-Next）。
- 网络默认全拦截 + 白名单；外链仅 http/https；WebView 关闭 file access。
- 日志脱敏与本地保存（不上传）。
- 不内置/分发游戏资源；资源只来自用户导入。
- 密钥/证书不进仓库；Android 签名走 CI secrets。

## 5. 可复用资源

- `assets/game_bridge/*.js`：10 个共享脚本，是触摸/自动收集/导出/GP-Next/日志/水印的行为规格与可直接复用资产（若新架构继续注入 JS）。
- `about_content.json`、`announcements.json`：远程内容格式样例。
- `tool/generated_icons/app_icon_master.png` 与 iOS AppIcon/LaunchImage 资源。
- `docs/acceptance-checklist.md`：验收行为规格。
- `docs/research/native_gamehost_local_resource_loading.md`：WKURLSchemeHandler 设计依据。
- 现有 Swift 测试（`RunnerTests.swift`）：资源处理器/定位器/视口/网络策略的行为规格。
- Dart 测试 34+ 个文件：导入、manifest、更新、日志、首页布局等行为规格。
- CI 工作流：三平台构建流程（iOS 段可直接借鉴）。

## 6. 明显死代码 / 废弃功能 / 重复实现

- **未支持平台目录**：`linux/`、`macos/`、`web/`、`windows/`（AGENTS.md 明确“已退役平台生成目录，保留但不支持”）；`GameHostPlatform` 也只为 android/ios/ohos 提供宿主。
- **Android 历史残留**：双包名 `io.github.dey410.gardendless_loader` 与 `io.github.dey410.gardendlessloader` 并存；`build.gradle`/`build.gradle.kts`、`settings.gradle`/`settings.gradle.kts` 双份。
- **文档漂移**：README 写自动收集 1.5 秒，代码/验收清单是 3 秒；README 说 GP-Next 1.4.2，公告已提及 1.4.3 兼容。
- **旧事务状态兼容**：`ManifestStore` 把历史 `staging`/`switching` 映射为 `migrating`；`ImportService` 保留 `current/previous/import/staging` 旧布局迁移代码（对旧安装仍有价值，新架构应做一次性迁移而非长期保留）。
- **iOS `SceneDelegate`** 为空实现（模板残留）。
- **`about_content.json` 远程内容**与 bundled 兜底是双重渠道，但属有意设计（离线可用），不算死代码。

## 7. 隐藏副作用

- `GameViewController.buildDocumentStartScript()` 对静态配置使用 `try! JSONSerialization`：配置含非 JSON 值时会在启动期崩溃（当前值安全）。
- `WKContentRuleListStore.default()` 的编译结果跨会话持久化；白名单规则 key 变化会产生累积旧规则（WebKit 自行管理，但需验证）。
- iOS 导入完成后 Flutter launcher engine 被 `destroyContext()`；若桥接 channel 未被完全清理或回调在销毁后到达，可能丢事件（代码中已有 `setMethodCallHandler(nil)` 与弱引用防护）。
- `NativeSfxEngine` 的 `aliasFiles` 在 decodeQueue 线程内 `stateQueue.sync`，与主 stateQueue 任务存在跨队列等待（当前无反向等待，但属于脆弱并发点）。
- GP-Next 导入替换使用 `.backup-*` 临时文件；崩溃在 backup 阶段会留下备份文件，下次同名导入时不会被清理。
- 日志 `deleteHistory` 只删“已结束会话”文件；若同会话段文件残留，会继续累积。
- `auto_sun.js` 注入 `keydown/keyup` 到 `GameCanvas`：若游戏内部对合成事件有依赖（repeat/which 等），行为随游戏版本漂移。
- iOS `WebKitHighRefreshRate.h` 使用 WebKit 私有 SPI（运行时检查降级）：仅适合侧载构建，存在系统更新后失效/App Store 审核风险。
- 自定义 scheme 无 Service Worker、部分 Worker/WASM 流式特性无公共契约（记录在 research 文档）。

## 8. 风险区域

| 风险 | 说明 | 缓解现状 |
| --- | --- | --- |
| WebKit 私有 SPI | 60FPS 偏好开关 | 运行时 selector 检查，失败返回 NO |
| 自定义 scheme 能力边界 | SW/Worker/`instantiateStreaming` 等 | research 文档 + 真机门禁 |
| 手动 ZIP 解析 | 无 ZIP64/加密/多盘；超大资源或超 65535 项会失败 | 明确报错文案 |
| AVAudioEngine 异常 | 可能抛 ObjC 异常 | ObjC `@try` 守卫 + WebKit 音频 fallback |
| 大资源内存 | 音频 PCM 缓存 64MB、资源处理器 24MB 音频缓存 | LRU + 上限 + 分块读取 |
| 渲染进程崩溃 | WebContent 终止 | `webViewWebContentProcessDidTerminate` + 退出结果恢复 |
| 桥接协议漂移 | JS/原生/三端通道契约变化 | 静态检查脚本 + 配置测试 |
| CI 版本差异 | 本地 Flutter 3.44.3 vs CI 3.41.9 | CI 固定版本；本地验证时注意差异 |
| GP-Next 上游变化 | 指纹/命令面版本漂移 | 未知版本禁用兼容桥并显示原因 |
| 数据迁移 | 旧 manifest/槽/日志迁移失败 | 双槽事务 + 槽元数据恢复 + 迁移前保留 |

## 9. 无法确定的行为（待确认项，不猜测）

1. **“iOS 端”边界**：是 (A) 完全独立、不依赖 Flutter 的原生 iOS App，还是 (B) 保留 Flutter 启动器、只对 iOS 原生层做 Clean-Slate 重建？这决定候选架构取舍。
2. **当前分支是否为重建分支**：现分支为 `codex/native-sfx-exception-guard`，名称与“重建”无关；需要确认，或授权新建 `codex/shredder-ios-*`。
3. **旧资源布局迁移**：`current/previous/import/staging` 一次性迁移是否在新系统中保留（建议保留一次，迁移后删除）。
4. **私有 WebKit SPI**（高刷新率）是否保留：App Store 合规与游戏流畅度的取舍。
5. **iOS 最低版本**：保持 iOS 14.5，还是提升（例如 15/16）以简化代码。
6. **SPM 插件集成**是否继续（当前本地已验证 SPM enabled），还是回到 CocoaPods。
7. **自动化收集的文档口径**：README 1.5s 与代码 3s 矛盾，以哪个为准（建议以验收清单/代码 3s 为准）。
8. **macOS/桌面/Web 目录**：保留不动还是从新仓库布局中剔除（不删除，仅不再维护）。
9. **日志保留策略/脱敏规则**是否保持 v2 需求文档不变。
10. **GP-Next 兼容目标**：固定适配 1.4.x 指纹，还是设计可扩展版本注册机制。

## 10. 必须保留的数据

- 激活资源槽与未激活槽内的用户导入游戏资源（含 `.slot-metadata.json`）。
- `manifest.json`（激活槽、事务、统计、GP-Next 元数据、自动收集偏好）。
- `gp-next/packs/`、`gp-next/patches/`（用户已导入补丁与 Mod）。
- `app_settings.json`（水印偏好）。
- 本地游戏存档（由游戏内导出生成，用户自行保存；若新 Origin 变化需在文档中说明不迁移 WebKit localStorage/IndexedDB——旧公告已明确此限制）。
- 日志历史（可删除，但默认保留）。
- 关于内容缓存（可重建）。

## 11. 建议删除的遗留行为

- 未支持平台的生成目录（不再构建、不再出现在新架构说明中；物理删除需用户另行确认）。
- Android 双包名/双 Gradle 文件历史残留（属 Android 范围，仅记录）。
- `SceneDelegate` 空实现、模板注释、过时 README 描述。
- 旧 `staging/switching` 状态兼容与旧目录布局长期迁移代码：新系统只做一次升级迁移。
- 无法解释的版本/兼容判断（如无证据的旧指纹）需在重写前确认。
- 与产品无关的历史调试脚本/临时产物（若存在于跟踪目录）。

## 12. 候选架构（3 套）

### 候选 A：独立原生 iOS App（Swift/SwiftUI 全栈，零 Flutter 依赖）

用 Swift 重写整个 iOS 产品：SwiftUI 启动器 + 原生导入/校验/存储/更新/日志 + WKWebView 游戏宿主；Android/OHOS 继续使用现有 Flutter 代码。iOS 侧以 SwiftPM 模块化：

```text
Gardendless-iOS/
  App（SwiftUI）
  ImportKit（ZIP/校验/事务）
  ResourceCore（会话/策略/路径沙箱）
  WebHostKit（WKWebView/SchemeHandler/Bridge）
  AudioKit（短音效引擎）
  GpNextKit（沙箱 FS/导入导出）
  LoggingKit（JSONL）
```

### 候选 B：保留 Flutter 启动器，Clean-Slate 重写 iOS 原生层（推荐）

维持“Flutter 启动器 + 各端原生 GameHost”的产品架构，但 iOS 原生层从零重新设计：不再沿用 `AppDelegate` 巨型类、通道即接口、Swift 文件堆叠的现状，改为按业务能力划分的 SwiftPM 模块与显式协议契约；Dart 侧只保留最小适配层，通道/Bridge 契约重新定义并在 `docs/breaking-changes.md` 记录。

```text
ios/
  Package.swift（原生核心 + 测试，替代当前 AppDelegate 堆叠）
  Sources/GameHostCore/   # Session、NetworkPolicy、PathSandbox
  Sources/ResourceServer/ # WKURLSchemeHandler、MIME、Range、缓存
  Sources/Bridge/         # 脚本桥、导出协议、GP-Next 命令面
  Sources/AudioEngine/    # 短音效、fallback、生命周期
  Sources/ImportEngine/   # ZIP 解析、docs 发现、进度事件
  Sources/Logging/        # JSONL 存储、脱敏、轮转
  Sources/LauncherAdapter/ # 与 Flutter 启动器的精简通道层
  Runner/                  # 最小 AppDelegate/ViewController 壳
```

### 候选 C：全平台 Clean-Slate（KMP/Compose 或 Rust/Tauri 或新一代 Flutter 架构）

把 Android/iOS/OHOS 的产品整体迁移到新跨平台栈。iOS 只是其中一个目标。

### 比较

| 维度 | A 独立原生 iOS | B 保留启动器、重写原生层 | C 全平台重写 |
| --- | --- | --- | --- |
| 与产品需求匹配度 | 中（iOS 体验最优，但三端逻辑分叉） | 高（三端共享启动器逻辑不变） | 高（统一栈）但超范围 |
| 平台兼容性 | 仅 iOS | iOS + 保留 Android/OHOS | 需逐平台验证 |
| 长期维护成本 | 高（Dart + Swift 双业务实现） | 中（iOS 单端原生复杂度集中） | 很高 |
| 开发复杂度 | 高 | 中 | 极高 |
| 构建速度 | 快（无 Flutter） | 中（Flutter + Xcode） | 取决于选型 |
| 运行性能 | 最优（原生全栈） | 优（游戏页已原生） | 中/待验证 |
| 内存与资源占用 | 最小（无 Flutter runtime） | 中（启动器 Flutter，游戏页已释放） | 中 |
| 并发能力 | Swift 并发显式化 | Swift 并发显式化 | 取决于选型 |
| 测试能力 | 强（SwiftPM/XCUITest） | 强（SwiftPM + Flutter test） | 中 |
| 调试难度 | 中（双栈上下文） | 中 | 高 |
| 安全性 | 可做到同等 | 可做到同等（现有防护可直接重写） | 需重新建立 |
| 依赖成熟度 | SwiftUI/WebKit 成熟 | Flutter + WebKit 成熟 | 因选型而异 |
| 社区与生态 | iOS 原生生态 | Flutter + Apple 生态 | 因选型而异 |
| 部署复杂度 | 低（单 App） | 中（三平台发布流程保留） | 高 |
| 数据迁移成本 | 中（Documents 布局可复用，但需自建全部迁移） | 低（复用现有 Dart 事务/存储） | 高 |
| 团队学习成本 | 高（Swift 全栈） | 中 | 很高 |
| 后续扩展能力 | iOS 最佳 | 三端均衡 | 统一栈潜力大 |
| 从旧系统迁移风险 | 高（一次性重写全部用户流程） | 低-中（按能力纵向迁移） | 极高 |

### 推荐：候选 B

理由：

1. 用户目标明确为“当前项目的 iOS 端”，而不是全产品换栈；B 的破坏范围与授权范围一致。
2. 产品三端共享的启动器逻辑（导入事务、更新、公告、日志编排）不是 iOS 端问题；A 会把它们复制成第二份业务实现，长期维护成本显著上升。
3. iOS 端的真实复杂度集中在原生 GameHost（SchemeHandler、桥、音频、GP-Next、ZIP、日志），B 允许对这一层彻底重设计且可独立测试。
4. C 超出“iOS 端”范围，且需要重建 Android/OHOS 已验证的稳定性，风险与工期不可控。

拒绝 A/C 的补充理由：A 会破坏“三端行为一致”的既有承诺（触摸矩阵、导入事务、更新语义需在三端同步）；C 在本次没有全平台重建的授权证据。

> 若用户确认候选 A（完全独立 iOS App），本报告后续阶段将以 A 为基线重写第 12-13 节。

## 13. 分阶段重建计划

每个阶段独立提交，提交时新代码必须可构建；阶段间不合并、不 force push。

### Phase 2：架构选型与决策（等待用户确认后开始）

- 产出：`docs/architecture/target-architecture.md`、`docs/architecture/migration-plan.md`、`docs/architecture/risk-register.md`、`docs/architecture/decisions/*.md`（ADR 形式）。
- 决策项：候选 A/B 确认、iOS 最低版本、SPM/CocoaPods、私有 SPI 去留、Bridge 新契约、旧数据迁移策略。
- 提交：架构文档（纯文档，可构建性不变）。

### Phase 3：详细设计

- 产出：模块边界、依赖方向、领域模型、数据所有权、公共接口（Swift 协议 + Dart 适配层接口）、状态模型、错误模型、权限模型、配置模型、日志与监控、测试策略、构建/发布/部署/回滚设计。
- 提交：设计文档。

### Phase 4：新 iOS 骨架

- 在 `ios/`（或用户确认的新目录）建立全新 SwiftPM 模块骨架 + 最小 App 壳。
- 能力：依赖管理、编译构建、配置读取、错误处理、日志、测试框架、静态检查、格式化、CI（iOS job 改为新工程）、健康检查、基础部署配置。
- 验收：`flutter pub get`、`flutter analyze`、`flutter test`、SwiftPM `swift test`、`flutter build ios --release --no-codesign` 全绿。
- 提交：可构建骨架。

### Phase 5：按业务能力纵向实现

按以下顺序一次一个能力，每个能力包含 用户入口/API → 业务规则 → 数据访问 → 错误处理 → 权限 → 测试 → 日志 → 文档，并执行全量测试/静态检查/构建/依赖与行为变化检查后提交：

1. 导入能力（ZIP 解析、docs 发现、进度、路径安全、与 Dart 适配层的新契约）。
2. 资源与会话能力（Session 模型、路径沙箱、网络策略、自检）。
3. 资源服务能力（WKURLSchemeHandler：GET/HEAD/Range/ETag/MIME/缓存/取消）。
4. 桥接能力（脚本桥、宿主命令、导出分块协议）。
5. GP-Next 能力（FS 沙箱、导入/替换/导出、白名单外链）。
6. 音频能力（短音效引擎、fallback、生命周期、异常守卫）。
7. 日志能力（JSONL、脱敏、轮转、快照/删除）。
8. 启动器适配与收尾（Dart 适配层、退出恢复、诊断、README/验收清单更新）。

### Phase 6：数据重新设计与迁移

- 新数据模型与 Schema（若 manifest 升级为 v5，需给出字段映射）。
- 幂等迁移脚本：旧布局 → 新布局；旧 manifest → 新 manifest；槽元数据重建；日志路径变化。
- 迁移前检查、迁移后校验、备份、回滚、部分失败处理、默认不删除原始数据；破坏性操作需显式参数。

### Phase 7：验证与最终交付

- 验证矩阵：确认功能、业务规则、权限、安全、数据完整性、外部集成、异常/边界、构建可重复性、部署、性能关键路径、资源占用、错误恢复、迁移、回滚。
- 每项记录：执行命令、结果、失败原因、未执行原因、剩余风险。
- 交付：`SHREDDER_REPORT.md`（更新）、`README.md`、`docs/architecture/*`、`docs/breaking-changes.md`、`docs/data-migration.md`、`docs/deployment.md`、`docs/rollback.md`。

## 14. 验证命令

```bash
# Dart / Flutter
flutter pub get
flutter analyze
flutter test
dart format --set-exit-if-changed lib test
git diff --check

# iOS 原生
cd ios && swift test        # GardendlessNativeCoreTests
cd .. && flutter build ios --release --no-codesign

# 产物（CI 同流程）
mkdir -p build/ios/ipa/Payload
cp -R build/ios/iphoneos/Runner.app build/ios/ipa/Payload/Runner.app
cd build/ios/ipa && zip -r GardendlessLoader-unsigned.ipa Payload
```

## 15. Final Summary（将在 Phase 7 更新）

- 已重写内容：尚未开始（Phase 1）。
- 新架构：候选 B 推荐（待确认）。
- 新增/删除文件：仅新增本报告。
- 依赖变化：无。
- 行为保留/改变：尚未改变。
- 已执行命令：Git 状态、文件盘点、代码/文档阅读（均为只读）。
- 未执行命令：`flutter analyze/test/build`、`swift test`（Phase 4 起执行；本阶段未修改代码，无基线验证需求）。
- 已知限制：见第 8、9 节。
- 后续工作：等待用户确认第 9 节待确认项与候选架构后进入 Phase 2。
