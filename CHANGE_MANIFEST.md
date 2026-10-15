# CHANGE MANIFEST — runtime-convergence

日期：2026-10-15。用户批准按接口审计实际改造两个项目，UI暂不动。

Loader 基线 `b615270`，分支 `codex/runtime-convergence`。提取项目基线 `1ffb59b`，隔离验证目录 `/private/tmp/gardendless-extract-refactor-20261015`。代码未推送，未触发远程工作流。实际归属和协议见[实施记录](docs/architecture/runtime-convergence-implementation.md)。

## 范围与事实

- 一份JS RPC/Tauri实现，一种64KiB文件协议；每平台一个真实文件任务所有者，无URL或整文件JSON后备。
- Dart去Router、日志mirror、重复HTTP/身份查询/校验统计及成功导入refresh。新增http_text承担真实IO；并发门直接保护实际rename或WK回调，不是转发服务。
- manifest/index/Host ABI1在两仓联动；资源构建详情留包外。版本0.9.0。
- UI目录与main源文件diff为空；三端维护入口、现有Origin、签名身份保留。
- crypto3.0.7从已有间接依赖变为直接依赖，没有版本升级；TypeScript5.8.3仅用于OHOS生产代码测试，不进入App。
- 文件删除数：4。用户替换旧规则并明确授权后，已移除停用的旧桥/自检占位文件；现有用户`.DS_Store`与`docs/releases`改动保留。

## 验证

| 项目 | 最终结果 | 命令/证据 |
| --- | --- | --- |
| Flutter首次安全清单 | 135通过（解除旧限制前） | 工作流quality的24文件清单；`/private/tmp/Loader-safe-Flutter-verification-final.txt` |
| Flutter完整回归 | 246通过 | `flutter test --no-pub --reporter expanded`；`/private/tmp/Loader-full-Flutter-after-retired-cleanup.txt` |
| Dart/Flutter分析 | 无问题 | `flutter analyze --no-pub`；`dart format lib test` |
| JS行为 | 6脚本通过 | 工作流Test shared game bridge；包含子视图/空写/短读/取消/UTF-8边界/反压/超时/音频观察 |
| 真实GP0.15 wrapper | binary/text/write通过 | `/private/tmp/check_real_gp_015_wrapper.mjs`，模块SHA256 `9aeae9d1a791cea896b76f35bdb9f6ae5db5e61f7f32449f7f10baf4902017db` |
| Android | 全生产Kotlin编译，19测试通过 | 实际Android36、Kotlin2.1.0、JDK17；`python3 /private/tmp/compile_android_runtime.py` |
| iOS | 六模块arm64-iOS编译及Host真实Flutter.framework typecheck通过，36测试通过 | `python3 /private/tmp/gardendless-verify-ios-runtime.py`；`/private/tmp/iOS-runtime-verification.txt` |
| OHOS | 官方API12签名及生产内存测试21通过 | `python3 /private/tmp/check_ohos_runtime.py`；`npm test --prefix ohos/test` |
| Loader CI | YAML、所有shell块和失败矩阵通过 | `python3 /private/tmp/verify_loader_ci.py`；缺工具/失败HAP/缺平台/错版本/错ABI/坏摘要均拒绝 |
| 提取器 | 原目录37测试通过；真实原料封包重开及Loader消费通过 | Python3.12/Pillow12.1.1/astcenc5.6.0；最终结果追加下节 |
| 独立终审 | 无Required问题 | 只读核对JS/三端任务、Dart激活、两仓包契约和Actions；没有以审查替代运行证据 |

定向RED→GREEN：JS取消满队列、旧全文件协议及Blob导出；Android关闭与commit互斥、M4A MIME；iOS元数据路径、AAC/ADTS、stop回调；OHOS重复ID提前结算；Dart重复目录遍历；Cocos return拼接/metadata提前成功/decode悬空；真实HTML注释module误计及native WebP未纳入ASTC。

首次验证按旧规则未运行含清理的全量测试；额外候选失败测试当时被自动审批拒绝并撤回。用户随后替换旧规则，本轮完整Flutter测试246项通过，测试只清理自身夹具。完整Runner链接/签名、APK/HAP打包、三端Actions实跑、真实BGM/固定怪物负载/内存曲线仍未验证；本机有连接iPad，Android无连接设备，无完整Hvigor工具。SwiftPM用当前SDK27交叉构建iOS14目标受SDK范围限制，直接编译通过；仓库实际部署目标15未为绕过检查而变动。

## 提取项目真实管线

官方上游0.15 Lite输入326811799字节，SHA256 `d25f91e4c09af65532494256c9bc81e6fc7d6120566b22b0fb22e832428dd80f`。tauri-dumper0.2.2提取8524资源；真实引擎修补命中one_shot1/dom_loader1/selector3/decode_callback1/decode_rejection1/dom_destroy1，完整JS语法通过。music UUID映射241项。

Python3.12、Pillow12.1.1、astcenc5.6.0按官方发布摘要取得。619张ASTC共725911712字节，614个ImageAsset JSON只选择ASTC；native原图、中间PNG、metadata备份留源目录/报告。首次遗漏11张WebP的正式组包被拒绝，然后沿同一ASTC链补齐，通过37测试（无跳过）。

实际验证包 `/private/tmp/pvzge-raw-audio-C5vu3N/final-package/GardendlessResources.zip` 为553525098字节；docs8523文件、1076835821字节。封存与重开完整校验通过，packageId为 `sha256:119ca394ed11c08a55c11c433c20429b18748c370d95999581521ee66c960064`。最新Loader对该真实目录完成全量validate/hash：8523文件、1076835821字节、游戏0.15.0、GP兼容true、packageId完全一致，测试通过，耗时9.739秒。ZIP SHA256 `10d0e36e1431d1ddcf42cca3744c61c2b4ea965180619cdad1e6ddca040aa088`。原料、脚本摘要、每步耗时和sourceDirty标记保存在 `/private/tmp/pvzge-raw-audio-C5vu3N/reports/validation-summary.json`。

本地包外报告明确 `sourceDirty:true`，producerCommit是实际基线1ffb59b，仅用于未提交工作区验证，不发布。CI使用实际GITHUB_SHA，无该本地标志。已验证12文件补丁应用到实际提取目录，并逐文件SHA相等；原目录再跑37测试全部通过，两个原有.DS_Store修改保留。

## Loader文件清单

跟踪文件共92项发生变化，其中88项修改、4项删除；本轮明确新增20项。此前审计/设计/research/tasks未跟踪文档继续保留，实施状态已更新，不算新增运行抽象。

| 文件 | 变更量 |
| --- | --- |
| `.github/workflows/build-mobile.yml` | +249/-86 |
| `android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/ExportDocumentSpec.kt` | +7/-0 |
| `android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameActivity.kt` | +109/-171 |
| `android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameBridge.kt` | +44/-38 |
| `android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameResourceResolver.kt` | +16/-12 |
| `android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameSessionCodec.kt` | +6/-0 |
| `android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GpNextNativeCore.kt` | +427/-232 |
| `android/app/src/main/kotlin/io/github/dey410/gardendlessloader/logging/AppLogStore.kt` | +10/-7 |
| `android/app/src/test/kotlin/io/github/dey410/gardendlessloader/game/ExportDocumentSpecTest.kt` | +7/-0 |
| `android/app/src/test/kotlin/io/github/dey410/gardendlessloader/game/GameResourceResolverTest.kt` | +2/-1 |
| `assets/game_bridge/audio_diagnostic.js` | +115/-213 |
| `assets/game_bridge/bootstrap.js` | 已授权删除 |
| `assets/game_bridge/export_download_patch.js` | +57/-248 |
| `assets/game_bridge/gp_next_compat_bridge.js` | 已授权删除 |
| `assets/game_bridge/gp_next_core.js` | 已授权删除 |
| `assets/game_bridge/transport.js` | +202/-70 |
| `assets/game_bridge/watermark.js` | +0/-8 |
| `ios/Flutter/AppVersion.xcconfig` | +1/-1 |
| `ios/GardendlessKit/Package.swift` | +1/-1 |
| `ios/GardendlessKit/Sources/GardendlessBridge/BridgeConstants.swift` | +6/-0 |
| `ios/GardendlessKit/Sources/GardendlessBridge/BridgeRequest.swift` | +6/-17 |
| `ios/GardendlessKit/Sources/GardendlessBridge/ExportCoordinator.swift` | +365/-126 |
| `ios/GardendlessKit/Sources/GardendlessBridge/ScriptMessageBridge.swift` | +21/-25 |
| `ios/GardendlessKit/Sources/GardendlessCore/GameConfiguration.swift` | +1/-19 |
| `ios/GardendlessKit/Sources/GardendlessCore/GameSession.swift` | +4/-0 |
| `ios/GardendlessKit/Sources/GardendlessCore/PathSandbox.swift` | +9/-1 |
| `ios/GardendlessKit/Sources/GardendlessGPNext/GpNextCommandRouter.swift` | +17/-140 |
| `ios/GardendlessKit/Sources/GardendlessGPNext/GpNextFileSystem.swift` | +16/-34 |
| `ios/GardendlessKit/Sources/GardendlessGPNext/GpNextPackageImporter.swift` | +3/-0 |
| `ios/GardendlessKit/Sources/GardendlessGPNext/GpNextSelectionStager.swift` | +11/-4 |
| `ios/GardendlessKit/Sources/GardendlessResource/AudioResourceCache.swift` | +0/-47 |
| `ios/GardendlessKit/Sources/GardendlessResource/ResourceMIME.swift` | +7/-1 |
| `ios/GardendlessKit/Sources/GardendlessResource/ResourceSchemeHandler.swift` | +10/-74 |
| `ios/GardendlessKit/Tests/GardendlessKitTests/BridgeTests.swift` | +276/-82 |
| `ios/GardendlessKit/Tests/GardendlessKitTests/GameConfigurationTests.swift` | +0/-3 |
| `ios/GardendlessKit/Tests/GardendlessKitTests/GameSessionTests.swift` | +8/-0 |
| `ios/GardendlessKit/Tests/GardendlessKitTests/GpNextTests.swift` | +16/-106 |
| `ios/GardendlessKit/Tests/GardendlessKitTests/PathSandboxTests.swift` | +26/-0 |
| `ios/GardendlessKit/Tests/GardendlessKitTests/ResourceSchemeHandlerTests.swift` | +1/-6 |
| `ios/Runner/GameHostController.swift` | +101/-161 |
| `lib/src/app_controller.dart` | +30/-66 |
| `lib/src/constants.dart` | +1/-1 |
| `lib/src/game_host/game_host.dart` | +10/-31 |
| `lib/src/logging/app_logger.dart` | +63/-22 |
| `lib/src/logging/native_app_logger.dart` | +65/-117 |
| `lib/src/models.dart` | +22/-12 |
| `lib/src/services/about_content_service.dart` | +10/-63 |
| `lib/src/services/announcement_service.dart` | +9/-58 |
| `lib/src/services/app_paths_service.dart` | +9/-28 |
| `lib/src/services/diagnostics_service.dart` | +36/-81 |
| `lib/src/services/game_update_check_service.dart` | +4/-130 |
| `lib/src/services/import_service.dart` | +59/-79 |
| `lib/src/services/manifest_store.dart` | +1/-0 |
| `lib/src/services/resource_self_check.dart` | 已授权删除 |
| `lib/src/services/resource_validator.dart` | +271/-23 |
| `lib/src/services/update_check_service.dart` | +18/-57 |
| `ohos/AppScope/app.json5` | +2/-2 |
| `ohos/entry/src/main/ets/game/ExportDocumentSpec.ets` | +6/-0 |
| `ohos/entry/src/main/ets/game/GameBridge.ets` | +162/-321 |
| `ohos/entry/src/main/ets/game/GameSession.ets` | +7/-0 |
| `ohos/entry/src/main/ets/game/GpNextNativeCore.ets` | +525/-315 |
| `ohos/entry/src/main/ets/game/GpNextPackArchiveNormalizer.ets` | +42/-32 |
| `ohos/entry/src/main/ets/game/NativeGameResourceHandler.ets` | +23/-10 |
| `ohos/entry/src/main/ets/logging/AppLogStore.ets` | +26/-0 |
| `ohos/entry/src/main/ets/pages/GamePage.ets` | +23/-19 |
| `ohos/entry/src/main/ets/plugins/GameHostPlugin.ets` | +4/-0 |
| `pubspec.lock` | +1/-1 |
| `pubspec.yaml` | +2/-1 |
| `test/android_export_config_test.dart` | +6/-5 |
| `test/announcement_service_test.dart` | +4/-8 |
| `test/app_controller_announcement_test.dart` | +3/-0 |
| `test/app_controller_game_update_test.dart` | +11/-0 |
| `test/app_controller_paths_test.dart` | +27/-2 |
| `test/app_controller_update_check_test.dart` | +6/-0 |
| `test/game_bridge_assets_test.dart` | +12/-16 |
| `test/game_host_router_test.dart` | +25/-33 |
| `test/game_session_test.dart` | +3/-0 |
| `test/game_update_check_service_test.dart` | +0/-51 |
| `test/github_actions_upload_config_test.dart` | +120/-0 |
| `test/harmony_build_config_test.dart` | +23/-20 |
| `test/home_page_layout_test.dart` | +13/-6 |
| `test/home_page_update_check_test.dart` | +6/-0 |
| `test/import_service_test.dart` | +5/-6 |
| `test/ios_export_config_test.dart` | +4/-3 |
| `test/native_app_logger_test.dart` | +36/-19 |
| `test/native_game_host_config_test.dart` | +27/-13 |
| `test/resource_self_check_test.dart` | +30/-64 |
| `test/resource_validator_test.dart` | +1/-4 |
| `test/update_check_service_test.dart` | +57/-4 |
| `tool/check_audio_diagnostic.mjs` | +54/-4 |
| `tool/check_export_download_patch.mjs` | +63/-138 |
| `tool/check_game_bridge.mjs` | +173/-225 |
| `android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/FileCommitGate.kt` | 新增 18 行 |
| `android/app/src/test/kotlin/io/github/dey410/gardendlessloader/game/FileCommitGateTest.kt` | 新增 42 行 |
| `android/app/src/test/kotlin/io/github/dey410/gardendlessloader/game/FileTransferCursorTest.kt` | 新增 45 行 |
| `android/app/src/test/kotlin/io/github/dey410/gardendlessloader/game/FileTransferRetainedFixtureTest.kt` | 新增 48 行 |
| `android/app/src/test/kotlin/io/github/dey410/gardendlessloader/game/GameResourceRetainedFixtureTest.kt` | 新增 68 行 |
| `ios/GardendlessKit/Sources/GardendlessResource/TaskCallbackGate.swift` | 新增 42 行 |
| `ios/GardendlessKit/Tests/GardendlessKitTests/TaskCallbackGateTests.swift` | 新增 42 行 |
| `ios/GardendlessKit/Tests/GardendlessKitTests/ResourceMIMETests.swift` | 新增 30 行 |
| `lib/src/services/http_text.dart` | 新增 51 行 |
| `ohos/test/file_protocol_test.cjs` | 新增 468 行 |
| `ohos/test/package.json` | 新增 11 行 |
| `ohos/test/package-lock.json` | 新增 29 行 |
| `test/about_content_cache_test.dart` | 新增 44 行 |
| `test/app_paths_retained_test.dart` | 新增 38 行 |
| `test/http_text_test.dart` | 新增 52 行 |
| `test/resource_package_test.dart` | 新增 240 行 |
| `test/resource_readiness_test.dart` | 新增 131 行 |
| `docs/architecture/runtime-convergence-implementation.md` | 新增 69 行 |
| `.refactor-session.md` | 新增 25 行 |
| `OBSERVATIONS.md` | 新增 3 行 |

## 提取项目文件清单

修改workflow、README、audio runtime与其测试；新增resource_package、音频执行夹具/契约及封包测试；真实WebP输入沿原ASTC路径加入transcoder及对应测试。最终精确diff同时保留在实际项目工作区。无物理删除，无另一种图片运行格式或播放器。

## 已授权占位文件清理

用户最新AGENTS替换旧删除限制。四文件无生产引用；仅Node测试harness曾读取旧JS占位文件，现只加载transport.js。自检行为测试保留，历史审计链接指向b615270快照。删除后桥接行为检查、完整Flutter测试246项、flutter analyze及git diff --check通过。全量测试先暴露7个UI异步失败；根因是已完成版本Future跨zone复用，现缓存完成字符串、仅共用在途Future，新增回归保证版本只读取一次。另补齐已有UI夹具必需的cc.js，未修改UI或放宽断言。只读复核无Required问题。
