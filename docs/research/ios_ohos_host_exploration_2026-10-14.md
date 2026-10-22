# iOS / OpenHarmony GameHost 音频、性能与内存只读探索

日期：2026-10-14。基线：`b6152704b22e2137efa4da1a542f76c6eb896ca8`。本次只增加研究文档，没有修改运行实现，没有执行删除。研究采用仓库源码、仓库现有决策和 Apple 官方 API 文档；以下“事实”指源码可证实的行为，“风险”指需要复现或测量验证的候选机制，不等于现有故障的根因。

已阅读 `AGENTS.md`、`docs/agents/domain.md`、`docs/agents/issue-tracker.md`、两份触摸 ADR、音频架构说明和本地资源加载研究。根目录没有 `CONTEXT.md`。ADR-0002 的共同 JavaScript 触摸适配器仍是已接受决策，本报告没有提出改变该边界。

## 1. 宿主和责任边界

| 层 | iOS | OpenHarmony |
| --- | --- | --- |
| 进入游戏 | 创建独立 `GameHostController`，替换根控制器，异步销毁启动器 FlutterEngine | 启动独立 `GameAbility`，成功后终止 `EntryAbility` |
| Web 容器 | WKWebView、默认持久网站数据存储 | ArkWeb Web 组件、DOM Storage 开启、fileAccess 关闭 |
| 游戏 Origin | `gardendless-game://localhost` | `https://gardendless.invalid` |
| 资源响应 | WKURLSchemeHandler，6 个一般资源 + 3 个音频并发 | WebSchemeHandler 接管 HTTP/HTTPS，异步逐块文件读取 |
| 播放与解码 | 游戏资源内 Cocos / 浏览器后端 | 游戏资源内 Cocos / 浏览器后端 |
| Native 音频引擎 | 无 | 无 |
| Audio 专用诊断 | document-start 注入观察器 | 未注入；桥也未识别音频事件 |

来源：[AppDelegate.swift:160–175](../../ios/Runner/AppDelegate.swift)、[GameHostController.swift:132–170](../../ios/Runner/GameHostController.swift)、[GameHostPlugin.ets:99–109](../../ohos/entry/src/main/ets/plugins/GameHostPlugin.ets)、[GamePage.ets:72–102](../../ohos/entry/src/main/ets/pages/GamePage.ets)、[GameConfiguration.swift:17–26](../../ios/GardendlessKit/Sources/GardendlessCore/GameConfiguration.swift)。OHOS 源码明确终止 launcher Ability，但本次未检查外部 Flutter embedding 的销毁实现，因此不将“销毁成功、所有 Flutter 常驻内存归零”写成已测量事实。

iOS 音频架构明确把 codec、播放、音量、循环、变速和结束事件交给 Cocos，Loader 负责资源传输及观察。源码没有 AVAudioSession 或 AudioContext 主动恢复管理，也没有 iOS memory warning / OHOS onMemoryLevel、原生前后台音频恢复回调。没有这些回调本身不能证明错误；它意味着恢复能力主要依赖游戏与 WebView，必须作为端到端验收项。[音频架构说明](../architecture/cocos-audio-pipeline.md)、[GameHostController.swift:760–803](../../ios/Runner/GameHostController.swift)、[GameAbility.ets:1–104](../../ohos/entry/src/main/ets/game/GameAbility.ets)

## 2. iOS 资源与缓存实现

### 2.1 请求管线

`start` 记录 task 状态，再按 URL 扩展名选 OperationQueue。一般资源并发 6、音频并发 3；音频队列只覆盖 `mp3/m4a/ogg`，`wav` 并不走该队列。OperationQueue 限制并发执行数量，代码没有限制等待中的任务数量或全部请求字节数。[ResourceSchemeHandler.swift:26–82、438–450](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceSchemeHandler.swift)、[GameConfiguration.swift:17–20](../../ios/GardendlessKit/Sources/GardendlessCore/GameConfiguration.swift)

处理器校验 scheme/host、GET/HEAD、sandbox 相对路径，然后生成 ETag、Cache-Control、MIME、Content-Length、Range 响应。支持单区间与 suffix range，拒绝多区间和不可满足范围。流式路径每次最多 128 KiB，以同步 FileHandle 读循环向 WebKit 发送，未看到消费端反馈或按 WebKit 内存压力暂停发送。[ResourceSchemeHandler.swift:85–301、397–435](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceSchemeHandler.swift)、[ResourceConstants.swift:8–10](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceConstants.swift)

**不能把 128 KiB 分块等同于 WebContent 总内存有界。** Apple 文档说明 WebKit 将每次提交的数据追加到之前收到的数据；这里的分块首先避免宿主一次性读入完整大文件，不能单凭它证明 WebKit 没有完整响应缓冲、Cocos 解码缓存或 GPU 纹理驻留。[Apple didReceiveData](https://developer.apple.com/documentation/webkit/wkurlschemetask/didreceive(_:)-8t5f8?language=objc)

### 2.2 小音频缓存

实际缓存写在 `ResourceSchemeHandler` 内：路径扩展名为 mp3/m4a/ogg、路径 token 不含 `bgm/music`、文件大小 ≤256 KiB，才整文件读取并加入 24 MiB LRU；数据以 `.mappedIfSafe` 读取。相同路径同时加载时通过 condition 等待复用，避免相同文件并发重复装入。缓存淘汰通过扫描字典查最旧条目实现，Range 响应使用 `subdata` 生成发送数据。[ResourceSchemeHandler.swift:304–395、438–450](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceSchemeHandler.swift)、[ResourceConstants.swift:10](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceConstants.swift)

明确的边界与调查点：

- 24 MiB 是缓存账面 payload 上限，不包括发送时 Data、WebKit 收到的数据、解码后 PCM、Cocos AudioBuffer、GPU、字典及待执行任务。不能直接用该上限估计 App 或 WebContent 峰值。
- 缓存按相对路径命中，不复查文件 stat/ETag；同一 handler 生命周期内命中会继续返回旧内容，甚至底层文件已消失。测试明确写入缓存后删除原文件仍希望 Range 返回缓存。这只有在激活资源根目录不可变的前提下才合理。[ResourceSchemeHandlerTests.swift:107–126](../../ios/GardendlessKit/Tests/GardendlessKitTests/ResourceSchemeHandlerTests.swift)
- HEAD/If-None-Match 的判断在 `loadAudio` 后面，所以对首次命中的小音频 HEAD/304 请求也可能先读入整个文件并占用缓存。需实际请求分布确定是否值得优化。[ResourceSchemeHandler.swift:128–145、212–223、264–270](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceSchemeHandler.swift)
- 未看到主动清空缓存、内存警告清空、缓存 hit/miss/eviction 指标。宿主退出时停止 WebView 并移除桥，缓存随 handler 释放；进行中的 serve 可能延长 handler 生命周期，需真机测量退出后驻留。[GameHostController.swift:721–739](../../ios/Runner/GameHostController.swift)
- `AudioResourceCache` 类在全仓只出现定义，没有调用者。它与 handler 内的 LRU 是重复实现，类自身 `insert` 替换同 key 时没有扣除原条目字节；这属于未使用代码的维护风险，不是当前运行内存问题的证据。[AudioResourceCache.swift:18–60](../../ios/GardendlessKit/Sources/GardendlessResource/AudioResourceCache.swift)

### 2.3 取消一致性风险

`stop` 加锁把 active 改为 cancelled；`performCallback` 在锁内预留回调，解锁后调用 `task.didReceive`；`callbackReservations` 只计数，不让 stop 等待已预留回调。因此源码存在“预留成功→stop 返回→再调用 didReceive”的潜在交错。Apple 文档规定 stop 之后调用数据回调会抛异常。[ResourceSchemeHandler.swift:73–82、540–575](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceSchemeHandler.swift)、[Apple didReceiveData](https://developer.apple.com/documentation/webkit/wkurlschemetask/didreceive(_:)-8t5f8?language=objc)

当前测试只在 response 回调内触发停止，再验证后面没有 body/finish；没有把线程停在 reserve 与 action 之间的确定性竞态测试。应审查 WebKit 实际 stop 调度、设计可重入且无死锁的串行生命周期，然后用压力测试证实。**本次没有观察到实际异常，不能将该候选竞态解释为 Issue #25 的原因。**[ResourceSchemeHandlerTests.swift:129–150](../../ios/GardendlessKit/Tests/GardendlessKitTests/ResourceSchemeHandlerTests.swift)

## 3. OpenHarmony 资源与生命周期实现

### 3.1 请求和文件读取

请求进入后同步 `lstatSync` 检查每个路径段、`statSync` 获取大小/mtime、必要时同步开文件嗅探，再启动异步 `fs.open/fs.read` 的 128 KiB 循环。每个活跃请求有一个取消标志，read 返回后检查取消，finally 关闭 fd。没有同等专用音频缓存，也没有请求并发上限、队列字节预算、向 ArkWeb 发送数据的背压信号。[NativeGameResourceHandler.ets:52–203、231–248、340–408](../../ohos/entry/src/main/ets/game/NativeGameResourceHandler.ets)

同步头部探测和路径元数据操作确实在请求回调路径上；它们是否占据设备 UI/ArkTS 主线程以及实际耗时，需要 SDK 与真机 tracing 确认。不能仅因 `Sync` 名称就推断当前掉帧已经由此造成。图片请求还会新建 MIME Map 并对 png/jpg/jpeg/webp 读取 64 字节判断 AVIF，mp3 则再读取 64 字节判断 AAC/MP4。[NativeGameResourceHandler.ets:340–408](../../ohos/entry/src/main/ets/game/NativeGameResourceHandler.ets)

`activeRequests` 在响应头送出后才登记；同一 synchronous request 回调内通常没有 JS await 交错，但回调线程语义仍需核实。`destroy` 仅标记取消并清 map，正在等待的 read 会在完成后关闭文件，不主动打断底层 IO。[NativeGameResourceHandler.ets:19–50、118–133、151–203](../../ohos/entry/src/main/ets/game/NativeGameResourceHandler.ets)

### 3.2 页面退出与恢复

页面消失时销毁 bridge/resource handler 并注销 JS proxy；主动返回时先 destroy bridge、flush 日志，再启动 launcher 并 terminateSelf。没有显式 stop Web 加载或 controller 销毁调用。页面组件销毁是否及时释放 ArkWeb renderer 及资源，只能结合设备观察确认，不能把“没有显式调用”当作已证实泄漏。[GamePage.ets:63–70、266–287、327–333](../../ohos/entry/src/main/ets/pages/GamePage.ets)

ArkWeb `onRenderExited` 会保存 `renderExitReason` 字符串并返回 launcher；iOS 回调只保存通用 `iOS WebContent process terminated`，没有平台终止原因参数。这两个日志的诊断能力不同。[GamePage.ets:157–170](../../ohos/entry/src/main/ets/pages/GamePage.ets)、[GameHostController.swift:633–644、872–874](../../ios/Runner/GameHostController.swift)

## 4. 两端资源 MIME 契约并不一致

| 输入 | iOS | OHOS |
| --- | --- | --- |
| 真正 .m4a | audio/mp4 | audio/mp4 |
| `.mp3` 内 M4A/MP4 | 前 16 字节搜索 `ftypM4A/isom/mp42`，命中 audio/mp4 | 前 64 字节，offset 4 为 ftyp 即 audio/mp4 |
| `.mp3` 内 ADTS AAC | 无嗅探，按 audio/mpeg | 按 ADTS 头识别 audio/aac |
| `.aac` | 未显式映射，octet-stream | audio/aac |
| `.avif` | 未显式映射，octet-stream | image/avif |
| png/jpg/jpeg/webp 扩展名内 AVIF | 按扩展名 | 嗅探 AVIF brand，image/avif |
| .wav | audio/wav；不走专用 audioQueue/cache | audio/wav |

来源：[ResourceMIME.swift:4–62](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceMIME.swift)、[ResourceMetadata.swift:17–36](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceMetadata.swift)、[NativeGameResourceHandler.ets:340–408](../../ohos/entry/src/main/ets/game/NativeGameResourceHandler.ets)。MIME 修正不等于 codec 支持；真实压缩格式、通道数、采样率、封装及浏览器解码能力需要对 `extract-pvzge-gpnext` 的具体产物抽样验证。上游产物若改变容器/格式但保留扩展名，重构时必须明确约定 MIME、头嗅探以及各平台能力矩阵。

## 5. GP-Next 文件桥是独立的内存放大路径

### 5.1 读取没有端到端分块

iOS `GpNextFileSystem.readFile` 整文件 `Data(contentsOf:)` 后转 `[UInt8]`；router 在 bridge delegate 路径同步 dispatch；返回结果经 `JSONSerialization.data`、UTF-8 String、JavaScript source，再 evaluateJavaScript 返回 Web 页面。[GpNextFileSystem.swift:71–75](../../ios/GardendlessKit/Sources/GardendlessGPNext/GpNextFileSystem.swift)、[GameHostController.swift:397–409](../../ios/Runner/GameHostController.swift)、[ScriptMessageBridge.swift:130–155](../../ios/GardendlessKit/Sources/GardendlessBridge/ScriptMessageBridge.swift)

OHOS 虽每次读取 64 KiB，但把每个字节 push 到同一个 `number[]`，整个文件读完后 JSON.stringify，拼接 JavaScript 再 runJavaScript。这个循环的读取缓冲有界，**最终数组与响应无文件大小上限，仍是整文件跨桥**。[GpNextNativeCore.ets:166–186](../../ohos/entry/src/main/ets/game/GpNextNativeCore.ets)、[GameBridge.ets:271–293、634–644](../../ohos/entry/src/main/ets/game/GameBridge.ets)

源码证明数据经过字节数组和 JSON 文本表示，可能同时存在多份；实际倍数取决于 Swift/ArkTS/JS 表示与复制优化，不能在没有 profile 时指定“固定 N 倍”。这条路径与常规 GameHost 128 KiB 网络资源响应完全不同，Mod 安装/加载大文件要单独测量。Bridge 的 1 MiB 限制只约束发往 Native 的请求，不约束 Native 返回的读文件结果。[transport.js:27–42](../../assets/game_bridge/transport.js)、[BridgeConstants.swift:5](../../ios/GardendlessKit/Sources/GardendlessBridge/BridgeConstants.swift)、[GameBridge.ets:81–112](../../ohos/entry/src/main/ets/game/GameBridge.ets)

### 5.2 写入分块只解决传输的一部分

写入支持 96 KiB chunk 顺序提交、最大总量 512 MiB、临时文件与原子替换。但兼容桥先 `Array.from(new Uint8Array(value))` 生成完整字节数组，core 再 `slice` 每个 chunk，原数组在异步循环期间被保留。不能把“请求分块”当作“JavaScript 内存随 chunk 大小有界”。[gp_next_compat_bridge.js:33–58、80–95](../../assets/game_bridge/gp_next_compat_bridge.js)、[gp_next_core.js:35–39、59–88](../../assets/game_bridge/gp_next_core.js)、[GpNextCommandRouter.swift:181–257](../../ios/GardendlessKit/Sources/GardendlessGPNext/GpNextCommandRouter.swift)

Transport pending 请求有 15 秒 / 用户交互 5 分钟超时，seenIds 最多 2048，但没有最大并发 pending 数；Native active IDs 也没有容量或定时清理。JS 超时只删自己的 pending，不直接取消 Native IO。正常完成与销毁会清理，因此这是异常或吞吐条件下待验证的边界，不是已证实累积泄漏。[transport.js:5–10、44–63、66–101](../../assets/game_bridge/transport.js)、[ScriptMessageBridge.swift:19–21、49–69、120–127](../../ios/GardendlessKit/Sources/GardendlessBridge/ScriptMessageBridge.swift)、[GameBridge.ets:60–64、100–112、189–197](../../ohos/entry/src/main/ets/game/GameBridge.ets)

## 6. 日志与音频诊断

iOS 的被动观察器包装 decodeAudioData/play，计数后默认只发失败及每 30 秒 summary；详细模式额外发 decode 开始/成功、media load/ready/play/playing/ended。详细事件没有音频观察器自己的吞吐限流，每条走完整 host:log 请求/回复链。[audio_diagnostic.js:41–64、67–141、153–247](../../assets/game_bridge/audio_diagnostic.js)

decode 成功事件没有 duration、sample rate、channels、decoded PCM bytes、AudioContext state 或当前活跃 source 数；decode 失败没有关联 URL；媒体事件主要记录相对路径。它可证明部分 API 失败，不能直接定位内存归属、音频丢失的声道/节点生命周期、输入格式与解码峰值。[audio_diagnostic.js:77–108、145–150](../../assets/game_bridge/audio_diagnostic.js)

**媒体观察器还存在与 BGM 排查直接相关的盲区。** loadstart/loadeddata/canplay/playing/ended/error 只注册在 `window` 上，捕获阶段也只能观察事件路径包含 window 的对象。对 `new Audio()` 或 `document.createElement('audio')` 创建、始终未插入文档树的音频元素，事件路径不经过 window，这些监听器不会记录其真实加载、就绪或错误。DOM 规范沿目标的 parent 生成事件路径，父节点为空时不会自动跳至 ownerDocument/window。[audio_diagnostic.js:158–193](../../assets/game_bridge/audio_diagnostic.js)、[WHATWG DOM dispatch](https://dom.spec.whatwg.org/#concept-event-dispatch)

prototype.play 包装仍会覆盖脱离 DOM 的 HTMLMediaElement，因此详细模式可记录 play 请求、始终可记录同步异常或 Promise 拒绝；但没有 play 调用时，脱离 DOM 的加载失败可以完全不出现在该观察器中。它也未监听 loadedmetadata，未记录 duration/readyState/networkState/MediaError.code。[audio_diagnostic.js:195–240](../../assets/game_bridge/audio_diagnostic.js)

现有 Node 检查通过假的 window.addEventListener 保存函数，再直接调用监听函数发送媒体事件，并没有构造真实 DOM event path，所以测试通过不能反证该盲区。[check_audio_diagnostic.mjs:10–69](../../tool/check_audio_diagnostic.mjs)。用户补充的 iOS 0.8.2 + 资源0.15“短音效有、BGM缺失”应优先把同一 BGM 的元素是否 connected、src/load、loadedmetadata、duration、canplay、play Promise 和媒体错误关联记录。上游若提前 resolve 再冻结 duration，则要结合上游真实 bundle 的调用顺序验证；本报告未自行读取该 bundle，不把父任务的新发现写成自身复现实验。

普通 JavaScript logging 每分钟最多 60 条，同 fingerprint 至少间隔 10 秒；音频观察器不经过这个限流。iOS Native 日志在 utility serial queue 持久化，最近 500 条、事件 16 KiB、pending soft/hard 为1000/1100，ERROR/FATAL 写入后 synchronizeFile；OHOS 用 Promise 串联但每条同步 stat/open/write/close。它们已有丢弃保护，不等于高吞吐零开销。[logging.js:6–41](../../assets/game_bridge/logging.js)、[LogStore.swift:29–42、101–118、194–278](../../ios/GardendlessKit/Sources/GardendlessLogging/LogStore.swift)、[AppLogStore.ets:175–196、244–301](../../ohos/entry/src/main/ets/logging/AppLogStore.ets)

父任务只读查看的 [Issue #25](https://github.com/Dey410/GardendlessLoader/issues/25) 提到 iOS WebContent terminated、sequence 10743、monotonicMs 274893。若这些计数在同一 app session 中，平均约 39 条/秒，只能作为排查日志类别分布的线索；不能假定它们全是音频日志，不能据此证明日志导致进程退出。Apple 公共回调表示内容进程因任意原因终止；仅 `rendererGone` 不证明 OOM，需同时间的 Jetsam/crash/device logs。[Apple termination callback](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webviewwebcontentprocessdidterminate(_:)?language=objc)、[Apple Jetsam 说明](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports)

OHOS 没有注入 audio_diagnostic.js，也没有把 `detailedAudioDiagnosticsEnabled` 传入 config，host:log 允许事件只有 JavaScript 三类；需要先统一观测契约才能横向比较两端音频。[GamePage.ets:208–244](../../ohos/entry/src/main/ets/pages/GamePage.ets)、[GameBridge.ets:128–161](../../ohos/entry/src/main/ets/game/GameBridge.ets)

## 7. 测试覆盖与本次验证边界

现有 Swift 资源测试覆盖：GET/HEAD、Range/ETag、Unicode、伪装 M4A、重复缓存 Range、response 后 stop、非法方法/host/traversal、符号链接、并发 8 个 4 KiB range、新 handler 切 root。[ResourceSchemeHandlerTests.swift:35–263](../../ios/GardendlessKit/Tests/GardendlessKitTests/ResourceSchemeHandlerTests.swift)

仍缺：超过 24 MiB 的真实 LRU 压力与释放、同路径密集并发缓存、取消的 reserve/action 竞态、完整大文件多 chunk 峰值、memory pressure、后台中断恢复、解码/播放真机 matrix、GP-Next 大文件读取响应上限、长期循环进出关卡/宿主后的常驻内存。

Flutter 对原生配置主要是读取源文件后判断 `contains`；OHOS resource handler 目前可见覆盖以这些静态契约为主，不能证明 ArkWeb 中的 range/缓存/线程/codec/销毁行为。[native_game_host_config_test.dart:112–262、264–359](../../test/native_game_host_config_test.dart)、[native_logging_config_test.dart:89–106](../../test/native_logging_config_test.dart)

本次仅执行已检查为读源码 + 内存 VM mock、无删除的 `node tool/check_audio_diagnostic.mjs`，结果为 `passive audio diagnostics contract passes`。它验证回调、原 promise 身份、同步异常和诊断过滤，不能替代 WebKit/ArkWeb codec 实测。[game_bridge_assets_test.dart:144–201](../../test/game_bridge_assets_test.dart)、[check_audio_diagnostic.mjs](../../tool/check_audio_diagnostic.mjs)

没有运行 Swift 资源测试：其 teardown 和多处用例会删除临时目录/文件，违反用户本次禁止未经逐文件确认删除的要求。[ResourceSchemeHandlerTests.swift:25–27、118、198、237](../../ios/GardendlessKit/Tests/GardendlessKitTests/ResourceSchemeHandlerTests.swift)。没有启动真机游戏、改变导入资源、执行构建或声称达到性能基准。

## 8. 为重构准备的最小实证顺序

1. 固定“同一个上游 commit、同一个资源 ZIP hash、同一 Loader commit”，列设备、系统、WebView 版本；区分普通包/GP-Next、开启/关闭 Mod、详细音频诊断开关。
2. 对产物列真实封装/codec、音频数量/时长/通道/采样率、图片实际编码/尺寸；比较扩展名与容器，先确证资源契约。
3. 分开测 launcher import、初次 boot、Mod read/write、进入关卡、密集音效、长 BGM、切关、后台/前台、退出宿主；分别记 native App 与 WebContent/ArkWeb renderer 的峰值和稳定态。
4. 先为资源队列、缓存 hit/miss/bytes、桥入出 bytes/耗时/in-flight、decode 输入与 PCM、音频节点计数、帧长/long task、进程退出补足低频聚合观测，避免详细逐事件日志干扰基线。
5. 对 #25 获取同时间 Apple Jetsam 或 crash report，核对实际被杀进程与 reason；在证据前保留 CPU、GPU、native/renderer crash、内存等多个候选。
6. 再决定是否改 GP-Next 大文件读协议、队列/背压、缓存归属、音频产物格式、前后台恢复；每次改动保留可量化前后对比。现有零服务器、稳定 Origin、active slot path confinement、网络白名单和 ADR-0002 不应在缺少设计决策时被顺带改变。

这份报告提供可验证的候选机制和代码地图；没有证据支持“所有版本的音频、性能、内存问题有同一个根因”，也没有证据支持直接替换框架或全面重写即可解决。

## 9. 补充：大量怪物场景的独立反证审查

本节只通过 Python `zipfile` 内存读取 `/Users/xiaozhu_410/Downloads/pvzge-lite-0.15.0 (1).zip`，没有解压或删除。不能仅凭文件名断言它与用户设备已导入的资源字节一致。`docs/assets/main/index.js` SHA-256：`4d629cc552baaba3b9591ef1990c3e14ad49836b3da8556d9697966946daafed`；引擎成员为 `docs/cocos-js/_virtual_cc-9deb4621.js`。以下行号在 ZIP 成员内，char 为 UTF-8 解码后 Python 字符串偏移（保留 CRLF），不是本仓库文件行号。

### 9.1 不能忽略的现有保护

- **并非完全没有音效并发限制。** 引擎 char `1494053` 设置 `N9.maxAudioChannel=48`，`J9.discardOnePlayingIfNeeded`（char `1497466`）检查普通音频与 one-shot 列表总数，达到上限优先停止最旧 one-shot，只有没有 one-shot 时才停止最旧普通 player。`AudioSource.playOneShot`（char `1501898`）在播放前调用此逻辑。因此“每个怪物都无限创建永不清理的并发声音”不能从当前样本成立。这个限制约束引擎记账中的 playing 对象，不自动保证异步 load/decode in-flight、缓存或 GPU 内存也被限制。
- **同 tick 去重和冷却已有实现。** `SoundRescourses.ts`（main 成员 L1075，`play` char `3010537`、`lateUpdate` char `3004274`）对同 clip + speed 的 cooldown、同 tick 相同 clip 做线性查找与合并，lateUpdate 再播放。默认 cooldown 为 clip duration 的一半；`playzombieChew` 还有 0.5 秒独立 cooldown。不能按僵尸数直接等同每帧实际播放节点数。
- **已有对象池和切场景清理。** `NodePools.ts`（L815，char `2232258`）按 `node.name` 分池，每个池 size 超过100时 clear，另有 clearAll。`KeyListener.ts`（char `1440177`、`1440444`）的 defaultRelease/onSceneLoadedDefault，以及 `UI.ts`（char `3390220` 起）的 exit/restart/next-level 路径会调用 clearAll。`Zombie.ts.characterOnDisable`（L1283，char `3603684`）停止多个 tween，删除全局/lane zombie 登记并清 buff。因此“完全没有池或释放”不符合样本。池按 name 而不是总字节限额；资源引用和池内节点的真实驻留大小仍需测量。
- **已有资源释放调用。** `SoundManager.ts.unLoadMusic`（L1073，char `2985676`）清空 bgms clip 并调用 assetManager.releaseAsset；KeyListener 的切场景流程卸载 Zombies、Vases、Tombs、Tiles、TileLiquids、Plants、Dinosaurs、Projectiles。是否每一条用户实际场景转换都经过这些路径、release 后依赖是否仍被持有，本次没有运行证据，不能写成“释放正确”或“资源全部泄漏”。

### 9.2 与数量相关的可见 CPU / 分配候选

| 样本位置 | 源码行为 | 仍需测量的量 |
| --- | --- | --- |
| `CharacterManager.ts` L181：update char `480915`，getBodyRecLeftest char `477894` | 每帧找最左 zombie；先调用 ArrayGet.shuffle，再两次 filter 和位置 sort | zombie 数量、方法累计耗时、临时数组/GC、是否可改为单次扫描 |
| `ArrayGet.ts`：shuffle char `179012` | `concat().sort(() => .5 - Math.random())` | 调用频率、排序比较次数、GC 时间；随机排序本身也不是均匀洗牌，但本次不改行为 |
| `CharacterManager.ts.characterManagerUpdate` char `481348` | 每帧重新创建 zombieInLawnPool 数组，遍历所有 zombie 判断 isInLawn | N 与帧耗时/分配的实测关系 |
| `Zombie.ts.characterUpdate` L1283 char `3653167` | 每个 zombie 更新矩形、位置、动画 timeScale、多个 buff/粒子/材质/深度，再调用 detectPlant | CPU、动画、粒子、draw call/GPU 各自占比 |
| `Zombie.ts.defaultDetectPlant` char `3633089` | 在 lane 植物池上 filter、矩形相交、sort、find，并构造 damage 对象 | 同 lane zombie×plant 数量、碰撞调用/分配占比；不能仅凭嵌套关系认定当前瓶颈 |
| `SoundRescourses.ts.lateUpdate` char `3004274` | 逐 tick sound 播放，复制 cooldown 数组，indexOf/splice 移除完成项 | 实际 sounds 数、WebAudio nodes、异步 decode、桥日志与帧时间 |

这些路径运行在游戏 JavaScript/Cocos 内。Loader 可以提供资源、配置、兼容桥和观测；只改启动器 UI 不会自动改掉这些算法、骨骼动画、纹理驻留或音效调度。若以后选择改这些行为，需要明确把上游产物的游戏/引擎补丁纳入重构范围，并按资源版本/hash 做兼容与回归。

### 9.3 能利用的观测接口与限制

Loader 已通过 `System.import('chunks:///_virtual/...')` 读取游戏模块来实现 auto_sun，因此对这个固定样本可以用同类、带版本/指纹限制的可选诊断读取：`CharacterManager` 导出的 `ZombiePool.pool()/inLawnPool()`、`PlantPool.pool()`；`NodePools.nodepools` 的每池 size；`sounds.sr` 的 tick/cooldown 列表；`SoundManager.component` 的 currentMusic/currentPlayingComponent、currentTime、volume、playbackRate。采样应低频聚合，不能每个 zombie 每帧发 bridge log。这些是样本导出/属性，并非跨所有 Cocos 包承诺的公共稳定协议。[auto_sun.js:159–214](../../assets/game_bridge/auto_sun.js)

浏览器层仍可用 RAF 帧间隔、performance timing、AudioContext state、decode 输入/输出参数、实际 AudioBufferSourceNode 的 start/ended，以及直接在每个媒体元素上的 loadedmetadata/canplay/error/play Promise 采集。必须把 request/decode/node/renderer 的统计分开，避免用“音频请求少”推断“声音节点少”。引擎 `J9` 是压缩 chunk 内闭包变量，不能假定可通过公开 `cc` API直接读出其两个 playing 列表；如需其精确计数，先设计受控埋点或通过节点 API 观测，不能硬编码压缩变量名。

引擎 one-shot WebAudio 的结束记账使用 `duration` 定时器（char `1484871` 起），播放时设置 playbackRate；timer 时间未除以 playbackRate。正常 timer 回调释放 cache 引用并触发 onEnd，stop 才显式 disconnect/buffer=null。这是播放倍率变化时“引擎记账与实际 source 结束时间可能不同”的可测试候选；不能仅凭没有显式 disconnect 断言浏览器永远不回收或已经 OOM。

### 9.4 UI 重写论点的独立审核

“全面重写 UI 能保证大量怪物时不掉帧/不 OOM”没有源码支持。iOS 游戏启动后 `AppDelegate.swift:167–175` 已把 launcherEngine 置空并 destroyContext，游戏主渲染由独立 WKWebView 负责。新 UI 可以改善导入/启动/返回状态、瞬时峰值和用户操作，却不能直接保证上述游戏 update、WebAudio、WebContent/GPU 的性能。反过来，也不能保证 UI 和 launcher 永远零影响：销毁是异步的，启动交叠峰值、原生 App 全局日志/资源队列以及退出残留仍应测量。[AppDelegate.swift:160–175](../../ios/Runner/AppDelegate.swift)
