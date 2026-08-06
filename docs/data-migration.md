# GardendlessLoader iOS 数据迁移说明

> 日期：2026-08-05
> 分支：`codex/native-sfx-exception-guard`

## 1. 结论

本次 iOS Clean-Slate 重建**不改变任何用户数据布局与格式**，因此**无需执行数据迁移**。

- `manifest.json`（schema v4）继续由 Flutter 启动器（Dart）读写，未被 iOS 原生层触碰。
- 资源双槽 `slot-a/`、`slot-b/` 与 `.slot-metadata.json` 继续由 Dart 导入事务管理。
- `gp-next/packs|patches` 的读写语义与路径沙箱保持不变。
- `app_settings.json`（水印开关）格式不变。
- `game_session.json`（schema v1）由 Dart 写入、新原生层读取；格式与字段未变。
- `game_exit_result.json`（schema v1）由新原生层写入，字段与旧实现一致。
- 日志目录与 JSONL schema v1 不变（Application Support/GardendlessLoader/logs）。
- WebKit localStorage / IndexedDB 不迁移（Origin 未变，天然保留）。

## 2. 兼容性验证（已完成）

| 契约 | 验证 |
| --- | --- |
| GameSession schema v1 解析/拒绝 | `GameSessionTests`（Swift） |
| 退出结果写入 | `GameHostController.writeExitResult` 与 schema 常量（构建验证） |
| 日志 JSONL schema v1 | `LogStoreTests`（Swift） |
| 通道契约（4 个 MethodChannel） | `flutter test`（189 项） |

## 3. 升级前后建议操作

1. 升级前：在游戏内导出重要存档（防意外）。
2. 升级后：
   - 打开 App，确认原有资源状态正常显示（无需重新导入）。
   - 启动一次游戏并返回，确认启动器恢复。
   - 打开日志页确认新会话已写入 JSONL。
3. 可选：备份 `Documents/GardendlessLoader/` 目录后再升级（iOS 文件 App 可见）。

## 4. 未来 Schema 变更规则

- 任何破坏性数据变更必须先更新 ADR-0005 与本文档。
- 迁移脚本必须幂等、默认不删除原始数据；破坏性操作要求显式参数。
- 提供备份、回滚、迁移前检查与迁移后校验。
