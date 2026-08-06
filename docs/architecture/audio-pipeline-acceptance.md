# 音频管线 P0 验收手册（iPad 实机）

> 目标：完成 [audio-pipeline-framework.md](audio-pipeline-framework.md) 的 P0 门槛
> （验收 1、2、3、6），以及 P1 回归项（验收 4、5）。

## 1. 安装

1. 使用本机构建的 `build/ios/iphoneos/Runner.app`（`flutter build ios --release --no-codesign`），
   或用 Xcode 签名后安装到 iPad。
2. 首次启动后导入 `pvzge-gpnext-0.12.1.zip` 游戏资源包，进入游戏主界面。

## 2. 验收步骤

按顺序执行，每步完成后停留至少 10 秒再进入下一步（诊断每 10 秒自动落盘一次）。

| # | 操作 | 期望 |
| --- | --- | --- |
| 1 | 进入有环境音的关卡（如草坪），等待 20 秒以上 | 环境音持续可闻；不再出现“每 3 秒重播一次”的断音节奏；诊断中 ambience 无重复 silent |
| 2 | 进入 WorldMap，打开设置把 BGM 速度拉到 0.5 和 2.0 各试一次；再播放 BGM、暂停、恢复、拖进度 | BGM 全程可听见；变速/暂停/恢复/seek 生效；音量滑杆和淡入淡出正常 |
| 3 | 在僵尸潮/阳光爆发场景连续操作 30 秒（如大量种植+释放植物） | 无明显掉帧；诊断 rAF 无 >100ms 间隔、p99 ≤20ms；33 路以上并发时丢最旧而不是丢新（可用 `preempted` 计数确认） |
| 4 | 播放 BGM 时来电或插拔耳机，等待恢复 | 恢复后 BGM 能重新发声；诊断出现 `stoppedReceived`（reason=interruption/route_changed） |
| 5 | 连续触发同一个不可播放 URL（正常游戏包不应出现） | `silentThrottled` 增长后窗口内不再发 play；`silentReceived` 停止增长 |
| 6 | 打开诊断面板或导出 JSON | `lazySrcSet=0`、`webkitFallback≈0`、`facadeCreated>0` |

## 3. 导出诊断

1. iPad 上打开“文件”App → 我的 iPad → GardendlessLoader → `Diagnostics`。
2. 复制 `audio-diagnostics.json` 和（如有）日志到可分享位置（隔空投送/微信/iCloud）。
3. 把文件发回给 Codex，同时说明第 1–6 步里哪一步表现异常。

## 4. 判断标准

- P0 完成 = 验收 1、2、3、6 全部通过；
- P1 回归 = 验收 4、5 通过；
- 任何一项失败都带上对应时间点（诊断事件有毫秒时间戳），Codex 据此定位 JS / 原生 / 游戏包哪一层。
