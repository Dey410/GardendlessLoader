# ADR-0001：Clean-Slate 范围（候选 B）

- 日期：2026-08-05
- 状态：已接受（用户确认“B”）

## 背景

用户要求对 GardendlessLoader 的 iOS 端做 Clean-Slate 重建，并确认候选 B。

## 决策

1. 保留 Flutter 启动器（Dart）与其业务编排、双槽事务、更新、公告、日志 UI。
2. 对 iOS 原生层（`ios/Runner` 的 Swift 实现）从零重建为 `GardendlessKit` SwiftPM 包。
3. 保留四个 MethodChannel 与 JS 桥契约，避免重写 Android/OHOS 与 Dart 适配层。
4. 用户可见行为、验收清单与数据布局不变。

## 后果

- 好处：三端共享逻辑不复制；iOS 侧复杂度集中并可独立测试；风险可控。
- 代价：iOS 原生层不是“完全独立 App”；Dart 启动器仍是旧架构（不在本次范围）。
