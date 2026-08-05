# ADR-0003：模块边界与依赖方向

- 日期：2026-08-05
- 状态：已接受

## 决策

`GardendlessKit`（SwiftPM 包）按业务能力拆分为 7 个 target，Flutter 适配壳（Host）放在 Runner 应用 target：

```text
Core → Resource / Bridge / GPNext / Audio / Import
Bridge → Core / Resource / GPNext
Runner/Host → 全部（唯一允许 import Flutter 的代码）
```

规则：

- `Core` 不依赖上层模块；禁止循环依赖。
- 只有 Runner 中的 Host 壳可以 import Flutter；Kit 能力模块只使用系统框架，保证 `swift test` 可独立运行。
- 模块公开面用协议/结构体表达，内部实现为 `internal`。

## 后果

- 可独立 `swift test` 每个模块。
- 依赖方向清晰，避免旧代码“通道即接口、文件堆叠”的问题。
- Host 壳随 Xcode 工程编译，不参与 SwiftPM 独立测试。
