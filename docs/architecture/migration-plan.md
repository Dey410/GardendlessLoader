# GardendlessLoader iOS 迁移计划

> 状态：已确认（候选 B）

## 1. 目标

在保留 Flutter 启动器与全部公共契约的前提下，用新的 `GardendlessKit` SwiftPM 包替换 `ios/Runner` 旧原生实现。

## 2. 迁移阶段

| 阶段 | 内容 | 退出条件 |
| --- | --- | --- |
| P1 分析 | SHREDDER_REPORT.md | 已完成并提交 |
| P2 架构 | 本目录文档 + ADR | 已提交 |
| P3 设计 | design.md（接口/错误/并发/测试） | 已提交 |
| P4 骨架 | GardendlessKit 空包 + 测试框架 + CI 门禁 | `swift test` 绿 |
| P5 能力 | Core → Resource → Bridge → Import → GP-Next → Audio → Logging → Host | 每能力独立提交 + 测试 |
| P5.5 切换 | Runner 壳改为调用 Kit；旧文件移出编译目标 | `flutter build ios` 绿 |
| P6 数据 | 迁移/回滚方案与验证 | 文档 + 检查脚本 |
| P7 验证 | 全量验证矩阵 + 最终文档 | 全部记录 |

## 3. 代码迁移方式

- 新代码全部新建在 `ios/GardendlessKit/`，不复制旧文件。
- 旧 `ios/Runner/*.swift` 文件保留在仓库（不删除、不编译），作为行为参考；Phase 7 向用户列出完整路径，经确认后再移除。
- Xcode 工程通过 Ruby `xcodeproj` 脚本更新目标文件引用（该脚本随仓库维护，保证可重复）。

## 4. 数据迁移

- 数据布局与 schema 不变（manifest v4、槽目录、settings、日志目录）。
- 唯一需要验证的是：新原生层读取 Dart 写入的 `game_session.json` 与写入 `game_exit_result.json` 的兼容性；行为由 Swift 测试覆盖。
- 不做破坏性迁移；旧数据保留原路径。

## 5. 验证与回滚

- 每个能力提交前：`swift test` + 相关 Dart 契约测试。
- P5.5 切换后：`flutter analyze`、`flutter test`、`swift test`、`flutter build ios --release --no-codesign`。
- 回滚：检出上一个提交即可恢复旧 Runner 实现（旧文件仍在工作树与 Git 历史中）；不修改 main、不 force push。
