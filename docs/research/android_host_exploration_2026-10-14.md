# Android GameHost 探索：音频、性能与内存

调查日期：2026-10-14。源码基线：当前工作区 `b6152704b22e2137efa4da1a542f76c6eb896ca8`；结论只针对本次查看的工作区，不代表历史所有版本或未检验的发布产物。本次只读调查 Android 实现，并新增本笔记；未修改运行代码，未删除文件，未执行会清理临时目录的测试。这里只解释现有实现和可验证的问题，不把源码风险等同于用户报告的故障根因。

## 边界与已读约束

- 已读根目录 `AGENTS.md`、`docs/agents/domain.md`、`docs/agents/issue-tracker.md`；调查时根目录无 `CONTEXT.md`。
- 已读 [ADR-0001](../adr/0001-cross-platform-touch-state-machine.md) 与 [ADR-0002](../adr/0002-use-javascript-touch-adapters-on-all-platforms.md)。后者已经取代 Android 原生鼠标注入路径：Android、iOS、OpenHarmony 都选择 `touchAdapter: javascript`。目录里的 `MouseGameWebView.kt` 和 `ReferenceNativeTouchStateMachine.kt` 不能当成当前游戏输入路径。
- 本笔记不评价 iOS/OHOS，也不重复共享 JavaScript 或提取器完整调查；GP-Next 只追踪到 Android 文件协议边界。
- 证据分级：**确定行为**由当前代码或官方 API 契约直接确认；**候选风险**有明确路径，但发生频率、实际代价未测；**待真机验证**不能用字符串测试或桌面推演代替。

## 主要结论

1. **确定的 Android API 契约错误**：匹配 `If-None-Match` 时 Resolver 生成 `304`，随后直接构造 `WebResourceResponse`；该 Android API 不接受任何 `3xx` 状态。现有测试只检查中间数据对象，未经过实际包装。
2. **确定存在大文件整量多副本路径**：GP-Next `read_file`/`read_text_file` 把文件逐字节转为 `JSONArray`，再整量 JSON 编码、引号转义、`evaluateJavascript`、JS 解析。底层 64 KiB 读缓冲不能把这条路径变成流式传输。
3. **确定没有任务并发和退出取消边界**：每条 GP-Next 调用创建一个新线程，宿主退出只清理部分状态，不取消读取、导入或等待用户确认的线程。并发压力、内存峰值和销毁后继续运行属于需要测量的候选风险。
4. 普通游戏资源通过 `RandomAccessFile` 按请求范围流式读取；没有证据表明 Android Resolver 会把所有音频文件一次性加载到 Kotlin 堆。这与 GP-Next 文件桥的整量读取是两条不同路径。
5. Android 宿主目前仅配置允许自动媒体播放，没有自身的前后台音频策略、音频焦点处理或音频诊断。后台恢复无声、音效重叠、解码失败和 OOM 尚不能归为同一故障。
6. 当前本地 SDK 的默认 `minSdkVersion=24`，而启动路径直接调用 API 26 方法；必须再查实际发布 APK 的最低版本，不能外推为所有发布版本都受影响。

## 运行链与所有权

```text
Flutter MainActivity
  game_host MethodChannel.launch
    -> 序列化 GameSession
    -> startActivity(GameActivity)
    -> 回应 launch 成功
    -> post finish(MainActivity)

原生 GameActivity
  GameSessionCodec
    -> 普通 Android WebView
    -> 受 Origin 限制的 document-start JS 与消息桥
    -> GameWebViewClient
         -> appassets.androidplatform.net -> 激活资源槽 Resolver
         -> 白名单 HTTPS -> WebView 默认网络路径
         -> 其他请求 -> 403
    -> GP-Next 命令 -> 每请求新线程 -> AppData 文件沙箱

退出 / 渲染进程消失
  -> 写 game_exit_result.json
  -> 启动新的 MainActivity
  -> finish GameActivity
  -> destroy Bridge / WebView
```

启动入口是 [MainActivity.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/MainActivity.kt) L28–58，原生宿主是 [GameActivity.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameActivity.kt) L51–178。`GameActivity` 继承 `Activity`，没有创建 FlutterEngine。`MainActivity` 启动宿主后结束自身，未使用缓存引擎。

本地 Flutter SDK 的 `FlutterActivity.java` L1081–1090 对自行创建的引擎默认返回 `shouldDestroyEngineWithHost=true`；`FlutterActivityAndFragmentDelegate.java` L809–817 随后执行 `flutterEngine.destroy()`。因此当前通常路径具有销毁启动器引擎的代码依据；进入游戏瞬间两 Activity 的短暂重叠、销毁耗时、进程 PSS 回落不能仅凭 `finish()` 推定。SDK 文件位于 `/Users/xiaozhu_410/Public/Environment/flutter/engine/src/flutter/shell/platform/android/io/flutter/embedding/android/`。

[GameSessionCodec.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameSessionCodec.kt) L26–58 强制 Android 固定 Origin `https://appassets.androidplatform.net`、schemaVersion 1、入口同 Origin 前缀，传入 resourceRoot、GP-Next 根、临时导出根与 activationGeneration。启动器 MethodChannel 的成功回应表示 `startActivity` 已提交，不表示游戏页面或音频已经就绪；原生启动失败另写退出结果。

## 普通本地资源请求

### 已有流式路径

[GameResourceResolver.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameResourceResolver.kt) 的契约：

| 能力 | 当前实现 | 证据行号 |
| --- | --- | --- |
| 路径约束 | 固定 HTTPS 主机、严格一轮百分号解码、拒绝危险双编码/反斜线/NUL/空段/`.`/`..` | L38–45、L98–138 |
| 激活槽边界 | 根及祖先符号链接检测、canonical containment、仅普通文件 | L23–28、L98–109、L238–246 |
| 请求方法 | GET/HEAD，其余 405 | L35–37 |
| Range | 单区间、开放尾区间、suffix；不支持多区间；非法范围 416 | L64–81、L140–159 |
| 读取 | 每响应独立 `RandomAccessFile`，seek 后限定 remaining；HEAD 不开流 | L83–95、L248–271 |
| 缓存头 | 元数据 ETag；入口和配置 no-cache；带较长十六进制 hash 的文件 immutable；媒体/bin 等 1 天 | L47–63、L161–185 |
| MIME | 显式 HTML/JS/CSS/JSON/WASM/常见图片、MP3/OGG/WAV、MP4/WebM、字体 | L187–213 |

拦截发生在 [GameWebViewClient.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameWebViewClient.kt) L22–95。Android 官方说明 `shouldInterceptRequest` 在非 UI 线程调用；传给 `WebResourceResponse` 的流会在 WebView 使用结束后关闭。因此普通文件资源不必由宿主整量驻留内存。这不限制 Chromium/Cocos 后续 ArrayBuffer、音频解码 PCM、纹理/GPU 内存。[WebViewClient 官方契约](https://developer.android.com/reference/android/webkit/WebViewClient#shouldInterceptRequest(android.webkit.WebView,%20android.webkit.WebResourceRequest))、[WebResourceResponse 官方契约](https://developer.android.com/reference/android/webkit/WebResourceResponse)

没有宿主自己的大文件缓存，也没有 gzip/Brotli 解码、`Content-Encoding` 选择、音频格式 sniff 或音频转码。导入内容须已经是浏览器可直接消费的文件。`m4a`、`aac`、`flac`、`opus` 等当前落到 `application/octet-stream`；只有资源包实际使用这些扩展名时，这才是相关兼容性风险。扩展名与真实编码是否一致也须检验真实包。

每次请求都会进行路径分段检查、文件状态查询、metadata ETag SHA-256 与格式化，没有缓存 metadata。可疑开销随资源请求数增长，但这里的 SHA-256 输入只是时间戳和长度，不是整文件内容；不能误报为每请求重新 hash 大音频。没有文件描述符总量限制、主动取消注册表或流读取耗时日志，实际内核是否及时关闭取消的流尚须设备验证。

### 确定问题：304 不可直接作为 Android WebResourceResponse

1. Resolver L54–62：请求头 ETag 等于当前 ETag 时返回 `statusCode=304`。
2. Client L67–74：把 `response.statusCode` 无判断传入六参数 `WebResourceResponse`。
3. Android 官方要求该构造器 statusCode 只能位于 `[100,299]` 或 `[400,599]`；3xx 被排除。[官方 API](https://developer.android.com/reference/android/webkit/WebResourceResponse)
4. 因而匹配条件请求会走入非法参数路径。Client 没有 catch 包装异常。
5. [GameResourceResolverTest.kt](../../android/app/src/test/kotlin/io/github/dey410/gardendlessloader/game/GameResourceResolverTest.kt) L47–60 只断言 Resolver 的 DTO 返回 304，未建立 Android 包装对象或让 WebView真正消费响应。

这是可确定的接口不兼容。尚未抓到真实 WebView 请求中匹配 `If-None-Match` 的发生频率，不能宣称它解释所有音频或内存问题。验收清单 [acceptance-checklist.md](../acceptance-checklist.md) L94 同时要求各平台支持 ETag/304；Android 的实现策略需按平台 API 能力重新明确，跨平台契约不能只写同一个状态码。

### 缓存与 Origin：目前只能提验证项

固定 Origin 的入口会携带 activationGeneration，而资源 URL 是否都携带 generation 必须查看真实资源。`LOAD_DEFAULT` 与 Cache-Control/ETag 已配置，但仅靠这两点不能证明拦截响应进入 WebView 普通磁盘缓存，也不能证明更新后会读旧资源。应记录冷/热启动请求、请求头、文件实际版本和传输字节，测试普通路径资源替换后的行为。

`If-Range` 和多 ETag 列表没有专门处理；现有代码对多 Range 直接 416。对于不再变化的激活槽，此类语义缺失是否影响实际媒体播放器，应以捕获到的请求为准。

## 音频与生命周期

[GameActivity.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameActivity.kt) L90–105 配置 `mediaPlaybackRequiresUserGesture=false`、DOM storage、默认缓存、禁止混合内容、重要 renderer priority。它使用系统 WebView 内核，并没有自己的 Android 音频播放器、音频解码器、AudioTrack 或音频缓存。

在 Android native 源码中没有发现以下宿主管理路径：`onPause`/`onResume` 对 WebView 的转发、`pauseTimers`/`resumeTimers`、AudioManager audio focus、AudioContext suspend/resume、后台静音或音频状态诊断、`onTrimMemory`/`onLowMemory`。文件选择器和外部浏览器都可能让游戏 Activity 暂停，但宿主未定义相应播放策略。缺少策略与出现具体音频故障之间仍有一步运行证据，游戏/Cocos/系统内核可能自己处理部分情况。

Android 官方的 `WebView.onPause()` 也只是尽力暂停动画等处理，明确不暂停 JavaScript；因此以后即使新增这一调用，也不能把它视为完整音频/游戏暂停方案。[WebView 官方文档](https://developer.android.com/reference/android/webkit/WebView#onPause())

需要把症状至少分开采集：首启无声；点击后才有声；切后台/锁屏/来电后不恢复；蓝牙切换后无声；音效延迟/断续；音效叠加；伴随卡顿或退出。对每一种记录平台和系统 WebView 版本、资源版本、GP-Next 开关、AudioContext 状态、媒体元素错误、失败 URL 和 MIME/Range。没有这些信息，不应先决定把音频全部移到原生层。

WebView 的 `setRendererPriorityPolicy(IMPORTANT,false)` 与系统默认策略相同，会让渲染进程保持高优先级，但不等于内存上限或避免所有低内存退出；不能把这一调用当作优化已完成，也不宜未经测量就降低优先级。[WebView 官方说明](https://developer.android.com/reference/android/webkit/WebView#setRendererPriorityPolicy(int,%20boolean))

## GP-Next 桥：最明显的内存与线程接缝

### 整量读取和 JSON 放大

[GpNextNativeCore.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GpNextNativeCore.kt) L39–41 把 `read_file` 与 `read_text_file` 路由到同一个 `readFile`。L108–120 以 64 KiB 读取后，每字节 `result.put(int)`，最终返回包含所有字节的 `JSONArray`，没有读文件大小限制。

L82 把 `bridge.complete(requestId,value)` 排到 UI 线程；[GameBridge.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameBridge.kt) L166–186 在回应中完成整量 `JSONObject.toString()` 与 `JSONObject.quote()`，再向 WebView 提交 JS 代码。运行时至少经过：

```text
文件 -> JSONArray 数值元素 -> 完整 JSON 文本
     -> 转义后的完整 JS 字符串 -> Chromium/JS 字符串
     -> JS 解析后的数组 -> 上层所需字节/文本/解压结果
```

后半部分的精确副本数须与共享 JS/GP-Next 调用者交叉核对。仅 Android 部分已经确定是整量返回；对象布局取决于运行时，不能伪造具体倍数。十进制 JSON 数字需要比原始字节更多字符，且多次编码会增加 CPU 与短期内存。只有 GP-Next 确实读取大 ZIP/大文件时才触发相应峰值；没有 GP-Next 的会话不能把此路径当根因。

### 无界线程与销毁后继续工作

`GpNextNativeCore.dispatch` L26–88 每个调用都 `thread(name="GardendlessGpNext")`，没有线程池、并发限制、全局 byte budget 或可取消 job。`GameBridge.activeRequestIds` 只去重，没有并发上限。请求大小上限为 1 MiB 字符（L36–40、L192–194），它只约束 JS 到 Native 的单条请求，不约束 Native 到 JS 的读结果。

`destroy()` L260–264 清理分块写状态，没有关闭 dispatch 或取消已启动线程。`GameActivity.onDestroy` L496–514 同样没有追踪 GP-Next 导入/选择/导出复制线程。桥本身会以 destroyed 标志拒绝后续回应，但这不会停止后台磁盘工作、JSONArray 创建或对 Activity 的暂时强引用。`confirmReplacement` L724–736 还可让工作线程等待用户确认最多 5 分钟。

`pendingExports` 是普通 mutableSet，多个 dispatch 线程可访问；`pendingWrites` 的分块写与 destroy 加了 synchronized，但 destroy 后新线程仍可再次创建状态。这些是明确的任务所有权和并发接缝，是否发生竞态或泄漏需用并发与退出场景验证。

### 写入与导出的现有边界

- GP-Next 分块写有 96 KiB 单块、512 MiB 总大小、token/索引/声明大小检查，并使用临时文件/备份/rename 提交（L189–258、L377–379）。这是应保留的行为边界。
- 非分块写把输入 JSONArray 用 64 KiB 缓冲落盘（L152–187），请求 JSON 已整量存在，不能因此宣称输入流式。
- 普通存档导出支持最多 512 MiB、256 KiB 单块，文件复制到系统目标使用后台线程和 128 KiB 缓冲；但是接收 `host:exportChunk` 的 JSON 解析、Base64 解码和输出流写入都在消息回调的 UI 线程上。[GameActivity.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameActivity.kt) L207–277、L443–458。
- AndroidX `WebMessageListener.onPostMessage` 明确标为 `@UiThread`。因此导出分块磁盘 I/O、`persistWatermark` 的写文件、部分选择暂存目录清理是可定位的主线程工作，但是否引起可见掉帧需测量。[AndroidX 官方 API](https://developer.android.com/reference/androidx/webkit/WebViewCompat.WebMessageListener)

## 导入、ZIP 与暂存

### 启动器游戏资源导入

[MainActivity.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/MainActivity.kt) L183–197 将导入放到后台线程。L283–309 用 `ZipInputStream` 顺序扫描完整归档并保存全部文件/目录路径，L200–280 再打开 URI 进行第二遍顺序读取/解压，文件输出使用 64 KiB 缓冲。对 `ZipInputStream` 扫描，关闭/跳过 entry 仍须顺序消耗数据，不能等同于读取中央目录的快速索引；因此大 ZIP 存在重复读取/解压消耗的候选性能点。

这条路径没有源码可见的总条目数、单 entry 展开大小、总展开大小或压缩比预算。路径集合按全部 archive entries 增长；解压字节和磁盘用量按展开内容增长。并未用大包或恶意包实际测量，因此仅列为边界缺失和压力验证项。进度每 100 ms 限流，但每个文件完成使用 force，海量小文件可能产生更多 UI channel 通知（L361–386）。

存在 `resetDirectory`/递归清理函数（L413–430）。本次没有调用这些函数，也没有为了验证而运行导入流程。用户文件删除约束是本次执行规则，不把应用已有业务代码的删除能力当成本次已获执行授权。

### 游戏中的 GP-Next 导入

[GameActivity.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameActivity.kt) L558–608：导入 ZIP/JSON/JSON5，先复制 incoming，ZIP 调 normalizer，JSON 使用整量 `readText()` 再解析；该路径没有总大小限制。需要和另一条 GP-Next selection 路径区分：L610–688、L764–776 的 selection 有 10,000 条目和 512 MiB 累计字节预算。

[GpNextPackArchiveNormalizer.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GpNextPackArchiveNormalizer.kt) L10–69 先检查中央目录；根已有 `pack.json` 时返回原归档，否则仅在唯一单层 wrapper 里规范化，逐 entry 用 64 KiB 缓冲重新解压/压缩。它保存全部 entry 元数据列表，但不把所有内容直接读入内存。L72–113 拒绝 ZIP64、加密 entry 与符号链接；未看到展开字节预算。嵌套包重写导致额外 CPU/磁盘消耗，实际代价与压缩方法和包大小有关。

selection 清理在 begin/取消/onDestroy 的部分路径位于主线程，最多可遍历上万项；worker staging 与主线程退出清理没有统一取消/等待协议。应验证导入中返回启动器、连续选择、取消和销毁后的资源闭合。

## 日志与可观测性

[AppLogStore.kt](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/logging/AppLogStore.kt) 有单写线程、1,000 队列容量、最近 500 条、2 MiB 分段、事件 16 KiB 限制，排队满时丢弃并统计；高优先级事件会尝试替换低优先级事件（L25–44、L178–213、L262–301）。这些边界避免了无限日志队列，但排队对象在落盘前仍未被最终 sanitize。

10 MiB/7 天/5 会话清理只从 `initialize` 调用 `cleanupLocked`（L93–105、L316–334），`ensureWriter` 的新分段路径未再次调用清理；因此它不是长时间同一会话严格 10 MiB 的连续硬上限。

资源失败与未知 MIME 会日志化。Client L50–65 将 `application/octet-stream` 也记为 `resource_request_failed`；若资源本来是合法 bin/引擎私有二进制，可能产生噪声，不能仅凭此日志认定载入失败。没有成功请求数量、读取字节、Range、打开/首次字节/完成耗时、媒体错误、AudioContext 状态、帧时长、renderer PSS、JS heap 或音频解码内存统计。

`onPageFinished` 写成功，只代表 WebView 页面完成回调；不代表 Cocos 场景、音频预加载和用户操作已通过。`onReceivedError` 只处理主框架，读流异常和子资源媒体解码失败不一定进入现有日志。渲染进程退出会记录 `didCrash`，再返回启动器（Client L133–151）；没有记录 rendererPriorityAtExit 或内存上下文。

退出 `AppLogStore.flush(500)`（Activity L488）在 UI 线程最多等待 500 ms，随后同步写退出 JSON。其后 WebView stopLoading/remove/destroy 已显式执行。是否符合“音频退出后立即停止、RSS/PSS 可回落”的目标尚须实测。

## Android 版本边界

[android/app/build.gradle](../../android/app/build.gradle) L32–37 使用 `flutter.minSdkVersion`。本地 `android/local.properties` 指向 `/Users/xiaozhu_410/Public/Environment/flutter`，该 SDK 的 `packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt` L23–34 当前为 compileSdk 36/minSdk 24/targetSdk 36。

Activity L101–102 无 API 判断调用 `WebSettings.setSafeBrowsingEnabled` 与 `WebView.setRendererPriorityPolicy`，二者均 API 26；`onRenderProcessGone` 也 API 26。以这个 SDK 生成的支持声明与调用路径不一致。必须检查实际 APK 最终 manifest、CI SDK 和最低设备，再决定提高 minSdk 或做兼容分支。[WebSettings 官方](https://developer.android.com/reference/android/webkit/WebSettings#setSafeBrowsingEnabled(boolean))、[WebView 官方](https://developer.android.com/reference/android/webkit/WebView#setRendererPriorityPolicy(int,%20boolean))

AndroidX WebKit 依赖固定在 1.12.1（build.gradle L63）。document-start 和 origin scoped message listener 由 `WebViewFeature.isFeatureSupported` 检查，不支持则记录启动失败并退出（Activity L83–89），没有静默降级。系统 WebView 的实际包版本尚未写入当前日志，应该成为故障采集的必需字段。

## 测试覆盖与本次验证

Android JVM 测试覆盖：Resolver GET/HEAD、单 Range、ETag DTO、缓存头、Unicode、路径/符号链接、4 MiB 文件下 8 线程 32 个 4 KiB Range；GP-Next sandbox path、ZIP wrapper normalizer；导出 MIME、viewport、picker orientation；旧原生触摸状态机。见 [android/app/src/test](../../android/app/src/test/kotlin/io/github/dey410/gardendlessloader)。

[native_game_host_config_test.dart](../../test/native_game_host_config_test.dart) L25–110 的 Android 部分主要通过源码字符串验证结构、配置、脚本名和命令存在。这是架构护栏，不能证明真实 WebView 的输入、音频、缓存、生命周期和内存表现。仓库未发现 `android/app/src/androidTest` 仪器测试目录。

明确缺口：Android WebResourceResponse 实际构造/条件请求；音频 codec/MIME/Range/seek；自动播放与前后台恢复；GP-Next 大包桥接、线程洪峰和退出取消；导出 UI 线程磁盘写；重复进退游戏后的宿主/renderer 内存；真实资源包/真实内核的运行验收。现有 4 MiB 文件、4 KiB Range 测试不等于 GiB 常驻内存压力测试，也不包含音频解码。

本次执行了 `rg`/`nl`/`cat`、Git 只读元数据检查以及官方 Android/AndroidX 文档核对。没有执行 Flutter/Gradle 测试：`GameResourceResolverTest.tearDown` L29–31 明确逐树删除临时目录，其他测试/构建工具也可能清理缓存，未经授权不能把它们当作只读验证。没有为了测试修改清理逻辑。

尝试 `adb devices -l` 时本地没有可用 daemon，启动 daemon 的 5037 监听被 sandbox 拒绝（`Operation not permitted`）。因此未取得设备列表，不能判断是否确实没有接设备，也没有采集 logcat、Perfetto、PSS 或真机音频数据。没有把此限制包装成已完成设备验证。

## 下一轮有针对性的验证

以下是基于已定位接缝的候选调查顺序，不是已经决定的重构方案：

1. 固定一份资源包、一个复现关卡、一个系统 WebView 版本，先建立音频症状与实际请求/AudioContext 事件的对应；分别测试 GP-Next 关闭与开启。
2. 在 Android API 24/25 与 26+ 检查实际产物支持范围；让真实 WebView请求带匹配 ETag，验证 304 包装失败路径。
3. 区分普通资源加载和 GP-Next read_file；记录文件大小、线程数、UI thread stall、主进程与 renderer PSS，测大包读取及退出时取消。
4. 以同一资源做冷/热启动、反复切场景、回主页重进、导入/导出、切后台/锁屏/蓝牙/来电矩阵。保存 p50/p95 帧时长、峰值与稳定 PSS、音频失效事件，而不是只记录“能打开”。
5. 对并发/总字节预算、二进制传输和任务生命周期建立可验证接口后，再决定抽取 shared contract 或替换宿主；保留激活槽路径约束、源限制与 ADR-0002 的输入规则。

这里没有证明一个统一原因能解释所有版本的所有音频、性能和内存问题。最强的现有源码证据是 Android 304 包装不合法，以及 GP-Next 整量 JSONArray 文件返回与无界任务模型；音频故障需要把提取结果、游戏引擎、共享注入脚本与设备运行事件一起对齐。
