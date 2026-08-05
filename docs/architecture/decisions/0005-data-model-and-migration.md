# ADR-0005：数据模型与迁移策略

- 日期：2026-08-05
- 状态：已接受

## 决策

1. 数据布局与 schema 保持不变：manifest v4、槽目录、`.slot-metadata.json`、`app_settings.json`、日志目录。
2. 不引入破坏性迁移；新原生层必须能直接读取现有 `game_session.json` 并写入 `game_exit_result.json`。
3. 旧版资源布局迁移（`current/previous/import/staging`）继续由 Dart 启动器负责，不属于 iOS 原生层。

## 后果

- 用户无需备份/恢复即可升级；迁移文档只需说明兼容验证与回滚。
- 若未来需要 schema 变更，走 ADR 更新 + `docs/data-migration.md` 流程。
