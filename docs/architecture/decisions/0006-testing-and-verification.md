# ADR-0006：测试与验证策略

- 日期：2026-08-05
- 状态：已接受

## 决策

1. 原生逻辑以 SwiftPM 单元测试为准（`GardendlessKitTests`），覆盖：ZIP 解析/路径安全、资源服务（Range/ETag/MIME/取消）、桥协议、GP-Next 沙箱、音频决策、日志脱敏/轮转、会话/策略解析。
2. Dart 侧保留并更新契约测试（通道名、桥命令、导出流程、配置断言），从“读源码字符串”逐步改为“读新源码路径 + 行为断言”。
3. 每个能力提交前执行：`swift test` + 相关 `flutter test` 文件；P5.5 后执行全量 `flutter analyze/test` 与 `flutter build ios --release --no-codesign`。
4. 静态检查：`git diff --check`、`dart format --set-exit-if-changed`、Swift 编译告警视作错误（`-warnings-as-errors` 用于 CI Debug 构建）。

## 后果

- 验证成本集中在 Swift 测试；Dart 契约测试保持轻量。
- CI 增加 iOS 原生测试门禁。
