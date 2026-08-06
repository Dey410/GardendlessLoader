# ADR-0004：公共契约保持不变

- 日期：2026-08-05
- 状态：已接受

## 决策

以下契约作为产品公共 API 冻结，本次重建不改：

- MethodChannel：`resource_zip_importer`、`game_host`、`external_browser`、`app_logger`（名称与方法）。
- `GameSession` schema v1、退出结果 schema v1、日志事件 schema v1。
- Origin `gardendless-game://localhost` 与 `?generation=N`。
- JS 桥命令面与 `assets/game_bridge/*.js` 注入顺序。
- 用户可见文案与验收清单行为。

## 后果

- Dart 适配层只需最小改动（错误码映射、路径断言），Android/OHOS 原生层不受影响。
- Breaking Changes 仅限 iOS 内部结构与实现。
