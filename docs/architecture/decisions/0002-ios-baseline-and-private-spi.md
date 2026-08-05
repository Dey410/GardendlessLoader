# ADR-0002：iOS 基线、包管理方式与 WebKit 私有 SPI

- 日期：2026-08-05
- 状态：已接受

## 决策

1. iOS 最低版本保持 **14.5**（与现网一致，避免引入新兼容成本）。
2. Flutter 插件继续使用 **Swift Package Manager** 集成（本地已验证 `swift_package_manager_enabled: ios=true`）；不退回 CocoaPods。
3. WebKit 高刷新率调整（`PreferPageRenderingUpdatesNear60FPSEnabled`）保留为 **独立、可选、运行时自检** 的兼容组件，放入 `GardendlessCore`，不进入公共接口；App Store 风险记录在风险登记表。

## 后果

- 14.5 允许使用 `WKScriptMessageHandlerWithReply`（iOS 14+）与 SPM（Flutter 3.44+）。
- 私有 SPI 仅用于侧载构建；selector 不存在时静默 no-op。
