# ADR-0003：模块边界与依赖方向

- 日期：2026-08-05
- 状态：已接受

## 决策

`GardendlessKit` 按业务能力拆分为 8 个 target：

```text
Core → Resource / Bridge / GPNext / Audio / Import
Bridge → Core / Resource / GPNext
Host → 全部（唯一允许 import Flutter 的模块）
```

规则：

- `Core` 不依赖上层模块；禁止循环依赖。
- 只有 `Host` 可以 import Flutter；能力模块只使用系统框架。
- 模块公开面用协议/结构体表达，内部实现为 `internal`。

## 后果

- 可独立 `swift test` 每个模块。
- 依赖方向清晰，避免旧代码“通道即接口、文件堆叠”的问题。
