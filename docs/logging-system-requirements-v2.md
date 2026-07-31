# GardendlessLoader 日志系统需求说明 v2

## 1. 文档状态

- 状态：已完成核心架构决策，可进入第一阶段设计与实现。
- 适用基线：当前 Native GameHost 架构。
- 支持平台：Android、iOS、HarmonyOS/OpenHarmony。
- 数据策略：完全本地保存，不自动上传。
- 本文描述产品需求、系统边界和验收标准，不规定各平台的具体文件 API。

## 2. 背景

当前应用只能提供状态快照和少量面向用户的错误信息，无法稳定还原故障发生前后的完整事件链。主要问题包括：

- 部分异常被静默处理，缺少异常类型、堆栈和业务上下文。
- 资源导入、Native GameHost、原生资源处理器、WebView、JavaScript 和网络 fallback 之间缺少统一关联。
- 无法区分成功、取消、降级、恢复和失败。
- 缺少统一的持久化、轮转、清理、脱敏和过载保护规则。
- 普通用户无法获得明确处理建议，维护者也难以复现问题。

日志系统的目标不是收集异常文本，而是形成一条有稳定语义、可以关联和导出的本地事件时间线。

## 3. 架构基线

GardendlessLoader 不再使用 Flutter `HttpServer` 提供游戏资源。

三端 Native GameHost 分别通过原生资源处理机制加载文件：

- Android：WebView 请求拦截与原生资源解析器。
- iOS：`WKURLSchemeHandler`。
- HarmonyOS/OpenHarmony：原生资源处理器。

因此，本系统不包含端口监听、端口冲突、Server 启停或后台恢复后重启 Server 等需求。相关诊断对象统一称为“原生资源处理器”。

## 4. 核心目标

日志系统必须能够回答：

1. 发生了什么。
2. 事件来自哪个运行时和业务模块。
3. 事件属于哪次应用运行、游戏运行和业务操作。
4. 操作最终是成功、失败、取消、恢复还是降级。
5. 失败的稳定错误码、技术原因和异常堆栈是什么。
6. 对普通用户造成了什么影响，下一步应该怎么做。
7. 日志系统本身是否正常持久化，是否发生过丢弃或降级。

## 5. 使用者与展示原则

日志系统同时面向普通用户和维护者，但只提供一个日志入口。

### 5.1 默认用户摘要

默认展示：

- 简短问题说明。
- 稳定错误码。
- 影响范围。
- 推荐处理动作。
- 事件时间及所属操作。
- 复制诊断摘要。

### 5.2 技术详情

用户主动展开后展示：

- `source`、`category`、`event`、`outcome`。
- `appSessionId`、`gameSessionId`、`operationId`。
- 经过白名单过滤和脱敏的上下文。
- 异常类型、错误信息和堆栈。
- 原始结构化 JSON。

技术详情不需要通过“开发者模式”解锁。诊断模式只影响采集详细度，不影响已有日志的可见性。

## 6. 总体设计边界

### 6.1 唯一持久化所有者

每个平台的原生层是日志文件的唯一写入者：

- Dart 将结构化事件发送给原生日志接收器。
- JavaScript 通过受控 Bridge 将事件发送给原生日志接收器。
- Kotlin、Swift、ArkTS 直接向各平台原生日志接收器提交事件。
- 原生日志接收器负责校验、分配顺序号、排队、序列化、写入、flush、轮转、清理和降级。

Dart、JavaScript 和多个原生模块不得分别追加同一个 JSONL 文件。

### 6.2 项目级日志 API

业务代码只依赖 GardendlessLoader 自有的窄日志接口和事件模型。第三方日志库只能作为平台内部实现细节，不能定义公开事件结构、错误码或业务 API。

### 6.3 三端一致性

各平台底层实现可以不同，但必须保持以下行为一致：

- 字段、等级、结果和错误码语义。
- Session 与 Operation 关联。
- 脱敏、截断和上下文字段白名单。
- JSONL 格式和 schema 版本。
- 写入队列、轮转、清理、降级及统计。
- JavaScript 错误采集。
- GameHost 退出前的限时 flush。

## 7. 关联模型

### 7.1 App Session

`appSessionId` 表示一次应用进程运行，由原生层在进程启动时生成。

- Flutter 销毁或重建不生成新的 `appSessionId`。
- 启动器进入 Native GameHost 后继续使用同一个 `appSessionId`。
- 每次新的应用进程生成新的 `appSessionId`。

### 7.2 Game Session

`gameSessionId` 表示一次 Native GameHost 游戏启动。

- 每次启动游戏生成新的 `gameSessionId`。
- 启动器事件通常不包含该字段。
- GameHost、WebView、JavaScript、Bridge 和原生资源处理器事件必须携带该字段。

### 7.3 Operation

`operationId` 表示一次完整业务操作，例如：

- 应用初始化。
- 资源刷新或导入。
- 更新检查。
- 游戏启动。
- 原生资源自检。
- 文件导入或导出。
- GP-Next Bridge 调用。

一次业务链路必须复用同一个 `operationId`。阶段变化通过 `event` 和上下文中的受控 `stage` 表达，不为每个阶段重新生成 ID。

Operation 必须记录开始和最终结果，并使用单调时钟计算耗时。

### 7.4 传递规则

- 跨服务、MethodChannel、GameSession 和 JavaScript Bridge 的关联 ID 必须显式传递。
- 禁止使用全局可变的“当前 Operation”。
- 局部代码可以使用受控作用域辅助器自动记录开始、成功、失败和耗时。
- 日志辅助器记录异常后必须保留原有业务控制流，不得吞掉或替换异常。

## 8. 事件语义

### 8.1 等级

| 等级 | 使用范围 |
|---|---|
| `DEBUG` | 详细进度、内部状态变化、诊断模式下的成功请求摘要 |
| `INFO` | 正常生命周期、操作开始和完成、用户主动取消 |
| `WARN` | 重试、fallback、可恢复损坏、降级和非关键功能失败 |
| `ERROR` | 当前业务操作失败，但应用仍可继续使用 |
| `FATAL` | 已确认当前运行无法继续或关键状态不可恢复 |

未捕获异常不自动等于 `FATAL`。严重度必须根据实际影响判断。

### 8.2 Event、Outcome 与 Code

三者必须分离：

- `event`：稳定描述发生了什么。
- `outcome`：描述操作结果。
- `code`：稳定标识需要诊断的问题，可为空。

`outcome` 第一阶段允许：

```text
started
succeeded
failed
cancelled
recovered
degraded
observed
```

用户取消文件选择或分享不属于错误，应使用 `INFO + cancelled`，不得生成错误码。

### 8.3 用户提示

用户提示和处理建议由 UI 根据稳定 `code` 从错误目录中生成：

- 不依赖系统异常文本。
- 支持本地化。
- 可以独立更新处理建议。
- 未知异常使用模块级兜底码。

每条技术日志不重复保存面向用户的 `suggestedAction`。

## 9. 日志数据结构

### 9.1 Session 头事件

每次应用启动首先写入 `app_session_started`，包含：

```json
{
  "schemaVersion": 1,
  "timestampUtc": "2026-07-31T08:12:00.000Z",
  "monotonicMs": 0,
  "sequence": 1,
  "level": "INFO",
  "source": "android",
  "category": "app.lifecycle",
  "event": "app_session_started",
  "outcome": "started",
  "code": null,
  "appSessionId": "20260731-081200-a31f9c",
  "context": {
    "appVersion": "0.6.4",
    "platform": "android",
    "osVersion": "<sanitized>"
  }
}
```

应用版本、平台和系统版本等 Session 级元数据不在每条普通事件中重复保存。

### 9.2 普通事件字段

| 字段 | 类型 | 必需 | 说明 |
|---|---|---:|---|
| `schemaVersion` | Integer | 是 | 事件 schema 版本 |
| `timestampUtc` | String | 是 | UTC ISO 8601 时间 |
| `monotonicMs` | Integer | 是 | 从 Session 开始计算的单调时间 |
| `sequence` | Integer | 是 | 原生接收器统一分配的 Session 内顺序 |
| `level` | String | 是 | 日志等级 |
| `source` | String | 是 | `dart/android/ios/ohos/javascript` |
| `category` | String | 是 | 稳定模块分类 |
| `event` | String | 是 | 稳定事件名称 |
| `outcome` | String | 是 | 事件或操作结果 |
| `code` | String? | 否 | 稳定问题码 |
| `message` | String? | 否 | 简短技术摘要，不用于程序判断 |
| `appSessionId` | String | 是 | 应用运行标识 |
| `gameSessionId` | String? | 否 | 游戏运行标识 |
| `operationId` | String? | 否 | 业务操作标识 |
| `durationMs` | Integer? | 否 | 使用单调时钟计算的耗时 |
| `context` | Object? | 否 | 事件级白名单允许的上下文 |
| `error` | Object? | 否 | 异常类型、脱敏消息和堆栈 |

### 9.3 错误对象

```json
{
  "type": "StateError",
  "message": "Required file was not found",
  "stackTrace": "..."
}
```

错误消息和堆栈必须经过二次脱敏、换行规范化和长度限制。

## 10. 隐私与数据最小化

### 10.1 白名单优先

业务代码不能向生产日志任意写入 `Map<String, Object?>`。

- 每个稳定 `event` 定义允许的上下文字段、类型、最大长度和最大集合数量。
- 未注册字段直接丢弃并增加内部计数。
- 日志系统不得为了报告字段被丢弃而递归写日志。

### 10.2 永不记录

- 密码、Token、Secret、API Key 和私钥。
- Cookie、Authorization、Set-Cookie 和完整 HTTP Header。
- HTTP 请求体、响应体和文件内容。
- 游戏资源内容和游戏存档内容。
- 完整 Bridge 参数。
- URL 查询参数和 fragment。
- 未脱敏的用户目录路径。
- 不必要的账号标识和设备唯一标识。

### 10.3 路径和 URL

- 应用目录内路径转换为 `<app-root>/...`。
- 游戏槽路径使用 `<active-slot>/...` 或 `<staging-slot>/...`。
- URL 默认只保留 scheme、host 和 path。
- 自由文本、异常消息、堆栈和 JavaScript 消息仍需执行通用模式脱敏。

### 10.4 大小和深度

- 单条事件序列化后最大 `16 KB`。
- 超长字符串和堆栈从尾部或中部按明确规则截断，并标记 `truncated`。
- 上下文只允许有限深度。
- 禁止序列化任意对象的 `toString()` 结果作为兜底。

## 11. 存储与文件生命周期

### 11.1 格式

使用 UTF-8 JSON Lines，每行一个完整 JSON 对象。

单行损坏不得阻止读取同文件中的其他有效行。

### 11.2 文件命名

启动时直接创建带 Session ID 的最终文件，不使用 `app-current.jsonl`：

```text
logs/
├── app-20260731T081200Z-a31f9c-000.jsonl
├── app-20260731T081200Z-a31f9c-001.jsonl
└── app-20260730T210500Z-f20be1-000.jsonl
```

同一 Session 超过单分片限制时递增分片编号。

### 11.3 默认保留策略

```yaml
segment_size_mb: 2
completed_sessions: 5
retention_days: 7
total_size_mb: 10
recent_events: 500
max_entry_size_kb: 16
```

清理规则：

- 任一限制超出时，删除最旧的完整已结束 Session。
- 禁止只删除一个 Session 的中间分片。
- 当前 Session 永不参与常规清理。
- 当前 Session 接近容量上限时进入过载保护，而不是直接删除关键错误。

### 11.4 Session 结束

正常退出时写入 `app_session_ended`。如果下次启动发现上次 Session 缺少正常结束事件，则记录：

```text
previous_run_unclean_shutdown
```

该事件只能表示上次运行未正常关闭，不能断言一定发生了崩溃。

## 12. 队列、内存和过载保护

### 12.1 两类缓冲

- `recentEvents`：供 UI 展示的环形缓冲，默认最近 `500` 条。
- `pendingWrites`：原生接收器的待写队列，具有独立的条数或字节上限。

二者不得共用同一容量。

### 12.2 过载策略

待写队列过载时按以下顺序处理：

1. 丢弃或采样 `DEBUG`。
2. 丢弃重复 `INFO`。
3. 合并或采样重复 `WARN`。
4. 使用保留容量接收 `ERROR/FATAL`。

必须按等级统计丢弃数量。日志页面显示队列状态和丢弃计数。

底层存储完全不可用时允许丢失 `ERROR/FATAL`，但必须在内存中保留降级状态和失败计数。不能承诺任何环境下绝不丢失日志。

## 13. 写入与 Flush

- 普通日志调用不得同步等待磁盘。
- 文件写入由原生层串行执行。
- `ERROR` 提升队列优先级并触发异步 flush，但业务调用方不等待。
- `FATAL` 尽最大努力立即 flush，最长等待约 `250 ms`。
- Native GameHost 正常退出前等待 flush，最长约 `500 ms`。
- 未来生成诊断包前等待 flush，最长约 `2 s`。
- flush 超时不得阻止应用退出或导致新的日志递归。

系统强杀、断电和底层原生崩溃仍可能丢失最后几条事件。

## 14. 第一阶段采集范围

### 14.1 应用生命周期

- 原生进程与 App Session 开始。
- Flutter 初始化开始、成功和失败。
- 应用核心初始化开始、阶段变化、成功和失败。
- 应用前台、后台及恢复。
- Flutter Framework 未处理异常。
- Dart 异步未处理异常。
- 正常 Session 结束。
- 下次启动识别上次未正常关闭。

### 14.2 资源导入

- 文件选择开始、取消、成功和失败。
- ZIP 导入或解压开始、成功和失败。
- 文件数量和总字节数摘要。
- 目录结构和必要文件校验。
- 游戏及 GP-Next 版本识别。
- 目标槽选择和事务创建。
- 槽切换、旧槽清理、回滚和恢复。
- 导入成功、失败、取消或中断。
- 启动时恢复未完成事务。

一次导入使用同一个 `operationId`。

### 14.3 Native GameHost

- Game Session 创建和持久化。
- GameHost 启动请求、成功和失败。
- 原生页面创建和销毁。
- WebView 创建、主页面加载开始、完成和失败。
- WebView 渲染进程退出。
- GameHost 正常返回、启动失败和异常结束。

### 14.4 原生资源处理器

- 资源处理器初始化。
- 入口资源自检开始和结果。
- 请求方法不允许。
- URL 或路径非法。
- 路径越出资源根目录。
- 文件不存在或不是普通文件。
- 文件读取失败。
- MIME 类型识别失败或不匹配。

生产环境默认不记录每个成功资源请求。诊断模式或 Debug 构建可以记录经过采样的成功请求摘要。

### 14.5 JavaScript 与 Bridge

- JavaScript 未捕获异常。
- 未处理 Promise rejection。
- `console.warn` 和 `console.error`。
- 外部导航或网络请求被安全策略阻止。
- Flutter/Native/GP-Next Bridge 请求校验失败。
- Bridge 调用失败和超时。
- 页面重新加载。

第一阶段不记录 `console.info` 和 `console.debug`。

## 15. 第一阶段崩溃边界

第一阶段支持：

- `FlutterError.onError`。
- `PlatformDispatcher.instance.onError`。
- 平台能够回调的 WebView 渲染进程退出。
- 正常关闭标记与上次未正常关闭识别。

第一阶段不支持：

- 自行安装底层 signal 或原生崩溃处理器。
- 保证原生崩溃、系统强杀或断电前产生 `FATAL`。
- 将所有未正常关闭都判断为应用崩溃。

## 16. 第一阶段日志页面

### 16.1 概览

- 当前 `appSessionId`。
- 当前或最近 `gameSessionId`。
- 应用版本和平台。
- 原生持久化状态。
- 日志占用空间。
- 写入失败和各等级丢弃数量。
- 最近错误。
- 当前 Session 的等级计数。

### 16.2 最近事件

- 显示最近事件。
- 按最低等级筛选。
- 只显示异常。
- 按 Operation 查看事件。
- 展开结构化上下文和异常堆栈。
- 复制单条事件 JSON。
- 复制诊断摘要。

第一阶段不要求跨所有历史文件的高级全文搜索。

### 16.3 清理语义

- “清空当前页面”只清空 UI 条件或视图，不删除磁盘文件。
- “删除历史日志”必须是单独的明确操作。
- 删除历史日志不得删除当前 Session 正在写入的分片。

## 17. 错误码目录

错误码采用稳定、小写、下划线格式，不能依赖异常文本。

第一阶段至少覆盖：

```text
app_initialization_failed
previous_run_unclean_shutdown
path_root_unavailable
path_permission_denied
manifest_json_invalid
manifest_write_failed
import_zip_invalid
import_extract_failed
import_transaction_recovery_failed
resource_missing_index
resource_missing_import_map
resource_path_forbidden
resource_file_not_found
resource_read_failed
resource_mime_mismatch
game_host_launch_failed
webview_page_load_failed
webview_render_process_gone
javascript_uncaught_error
javascript_unhandled_rejection
bridge_message_invalid
bridge_call_failed
log_context_rejected
log_write_failed
log_flush_timeout
log_rotation_failed
```

错误码目录必须同时定义：

- 所属 category。
- 默认等级。
- 面向用户的本地化标题。
- 处理建议。
- 是否允许自动恢复。

## 18. 稳定性要求

- 日志接收器初始化失败时，应用主体应尽可能继续运行。
- 日志目录不可写时退化为内存模式。
- 写入失败不得递归写入日志系统。
- 轮转失败不得删除当前有效分片。
- 清理失败不得阻止应用启动。
- 日志流订阅异常不得影响业务控制器。
- 单行 JSON 损坏不得阻止读取其他有效行。
- 日志辅助器不得吞掉、替换或改变业务异常。
- 日志系统关闭后，业务层日志调用必须安全失败或成为空操作。

## 19. 性能要求

- 普通日志 API 不同步等待磁盘。
- 昂贵上下文仅在对应等级启用时计算。
- 写入、轮转和清理不在 Flutter UI 线程执行。
- 日志页面只加载有限数量事件。
- 单条事件最大 `16 KB`。
- `recentEvents` 默认最多 `500` 条。
- 性能验收使用可复现的事件吞吐和页面帧时间测试，不使用缺少设备与测量条件的“平均 CPU 低于 1%”作为硬指标。

## 20. 第一阶段测试

### 20.1 共享模型和 Dart 单元测试

- schema 校验和版本。
- 等级过滤。
- Event、Outcome 和 Code 规则。
- Session/Game/Operation ID 关联。
- Operation 开始、完成、失败和耗时。
- 并发 Operation 不串线。
- 异常记录后保持原有异常传播。
- 事件级上下文字段白名单。
- 路径、URL、自由文本和堆栈脱敏。
- 深度、集合数量和单条大小限制。
- 最近事件环形缓冲。

### 20.2 原生接收器契约测试

三端使用相同输入样例验证：

- 顺序号统一分配。
- JSONL 串行写入。
- UTF-8 和换行规则。
- 队列优先级和过载丢弃。
- 写入失败后的内存降级。
- 限时 flush。
- 分片轮转。
- 按完整 Session 清理。
- 当前 Session 不被误删。
- 损坏行容错读取。

### 20.3 集成测试

- 应用初始化成功和失败。
- 资源导入成功、失败和事务恢复。
- Native GameHost 启动成功和失败。
- 入口资源缺失、非法路径和 MIME 不匹配。
- WebView 页面加载失败。
- WebView 渲染进程退出。
- JavaScript 异常和 Promise rejection。
- Bridge 请求失败。
- 日志目录不可写。
- 上次 Session 未正常关闭。

### 20.4 UI 测试

- 概览状态和计数。
- 最近事件与等级筛选。
- 用户摘要与技术详情。
- Operation 事件查看。
- 堆栈展开。
- 复制事件 JSON 和诊断摘要。
- 删除历史日志时保留当前 Session。

## 21. 第一阶段验收场景

### 场景 1：无效 ZIP

必须区分：

- 用户取消选择。
- ZIP 格式无效。
- 解压失败。
- 解压后目录结构错误。
- 缺少必要文件。
- 校验失败后的清理或回滚结果。

整条链路使用同一个 `operationId`。

### 场景 2：导入中途退出

下次启动必须记录：

- 检测到未完成事务。
- 原事务阶段和目标槽。
- 执行的恢复动作。
- 恢复或清理结果。
- 当前资源是否仍可使用。

### 场景 3：原生资源 MIME 错误

必须记录：

- 经过脱敏的资源相对路径。
- 预期和实际 MIME。
- 所属 `gameSessionId` 和 `operationId`。
- 原生平台来源。
- 最终处理结果。

### 场景 4：JavaScript 异常

必须记录：

- 脱敏后的页面相对路径。
- 行号和列号。
- 错误消息和 JavaScript stack。
- 是否为 Promise rejection。
- 是否发生截断、采样或丢弃。

### 场景 5：上次运行未正常结束

下次启动必须能够显示：

- 上一个 `appSessionId`。
- 上一个 Session 最后已落盘事件。
- 上次 Session 缺少正常结束事件。
- 若存在可用错误信息，则一并关联展示。

不得保证一定存在 `FATAL`，也不得直接断言发生崩溃。

### 场景 6：日志写入失败

必须满足：

- 应用不因日志系统崩溃。
- 自动切换为内存模式。
- 页面显示降级状态和失败次数。
- 不递归产生写入错误。

### 场景 7：大量重复事件

必须满足：

- UI 不出现明显卡顿。
- 待写队列和文件不会无限增长。
- 低优先级事件按规则采样或丢弃。
- 为 `ERROR/FATAL` 保留队列容量。
- 页面显示各等级丢弃数量。

## 22. 第一阶段不包含

- ZIP 诊断包和系统分享。
- 自动或用户主动上传日志。
- 多文件高级全文搜索。
- 通用错误聚合和可配置采样规则。
- Operation 可视化时间线。
- 全量 `console.info/debug`。
- 所有网络服务的完整埋点。
- 自建底层原生崩溃处理器。

这些能力应在第一阶段稳定后单独设计和验收。

## 23. 推荐交付顺序

第一阶段可以通过多个小提交和 PR 增量完成，但三端达到相同契约后才算整体完成：

1. 共享事件 schema、错误目录、Dart API 和内存测试接收器。
2. Android 原生接收器及应用初始化端到端链路。
3. Android 资源导入、GameHost、资源处理器和 JavaScript 链路。
4. iOS 等价实现。
5. HarmonyOS/OpenHarmony 等价实现。
6. 最小日志页面。
7. 三端契约测试、故障注入和验收矩阵。

## 24. 后续阶段候选

- 网络请求、缓存与 fallback 的统一埋点。
- 临时诊断模式及自动失效。
- 诊断包生成、系统保存与分享。
- 多 Session 历史查询。
- 错误聚合、重复指纹和限流配置。
- Operation 可视化时间线。
- 用户主动上传诊断包。

