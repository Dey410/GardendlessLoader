# GardendlessLoader iOS Breaking Changes

> 日期：2026-08-05
> 范围：iOS 原生层 Clean-Slate 重建（候选 B）

## 1. 变更清单

| # | 变更 | 影响 | 迁移方式 |
| --- | --- | --- | --- |
| 1 | `ios/Runner` 旧 Swift 原生实现（AppDelegate 中的 ZIP 逻辑、GameViewController、SchemeHandler、桥、音频、GP-Next、日志）不再编译 | 仅内部实现 | 无需用户操作；旧文件已按确认从磁盘删除（Git 历史可恢复） |
| 2 | 新实现移至 `ios/GardendlessKit/`（SwiftPM 7 模块 + 1 个 ObjC 守卫 target） | 仅内部结构 | 无需迁移 |
| 3 | `ios/Runner.xcodeproj` 增加本地 SwiftPM 依赖；`tool/update_ios_project.rb` 可重复执行该工程更新 | 开发者构建流程 | 以脚本为唯一工程更新入口 |
| 4 | 原生错误码/内部 API 全部重新设计（`GameError.Code`） | 仅内部 | Dart 通道错误码不变 |
| 5 | 存档导出：提交阶段临时文件在 commit 后重命名为用户建议文件名（修复旧 `.chunk-UUID-` 前缀） | 用户可见文件名改善 | 无 |
| 6 | CI iOS job 新增 `swift test` 门禁 | CI | 自动生效 |
| 7 | `ios/RunnerTests` 缩减为冒烟测试；原生行为测试迁移到 `GardendlessKitTests` | 测试组织 | 无 |
| 8 | `ios/Package.swift`（旧 GardendlessNativeGameHost 测试包）退役保留 | 开发者 | 新包为 `ios/GardendlessKit/Package.swift` |

## 2. 不变（公共契约）

- 四个 MethodChannel 名称与消息形态。
- `GameSession` schema v1、退出结果 schema v1、日志 schema v1。
- `gardendless-game://localhost` Origin 与 `?generation=N`。
- JS 桥命令面与 `assets/game_bridge/*.js` 注入顺序。
- 用户可见行为、中文文案与验收清单。
- 数据布局与存档。

## 3. 旧文件删除记录（2026-08-05 用户已确认）

以下旧文件已移出编译目标，并在用户确认后从磁盘删除（遵守仓库删除安全规则，逐文件操作）：

```text
ios/Runner/AppLogStore.swift
ios/Runner/GameAudioBridge.swift
ios/Runner/GameNavigationDelegate.swift
ios/Runner/GameResourceLocator.swift
ios/Runner/GameResourceSchemeHandler.swift
ios/Runner/GameScriptBridge.swift
ios/Runner/GameSession.swift
ios/Runner/GameViewController.swift
ios/Runner/GpNextNativeCore.swift
ios/Runner/JavaScriptArgumentEncoder.swift
ios/Runner/NativeSfxEngine.swift
ios/Runner/NativeSfxExceptionGuard.h
ios/Runner/NativeSfxExceptionGuard.m
```

`ios/Runner/WebKitHighRefreshRate.h` **保留**：新 Runner 壳仍在调用其中的刷新率兼容函数（ADR-0002 的独立兼容组件）。
