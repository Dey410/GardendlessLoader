# iOS 与 HarmonyOS/OpenHarmony 原生 GameHost 的零服务器本地资源加载

## 研究边界

本文只研究游戏运行阶段如何在 **零 FlutterEngine、零 HTTP Server** 的前提下，让原生 `WKWebView`/ArkWeb 安全、高性能地读取用户导入的大型 Web 游戏资源。重构不保留旧 loopback Origin、旧网页存储或旧 Flutter WebView 路径。

结论先行：两端都能移除 FlutterEngine 和 HTTP Server，但不能使用完全相同的 URL 传输层。

| 平台 | 推荐本地 Origin/入口 | 资源提供方式 | 最低版本 |
| --- | --- | --- | --- |
| iOS | `gardendless-game://localhost/index.html?generation=N` | `WKURLSchemeHandler` + 分块 `WKURLSchemeTask` | 处理器 iOS 11；建议项目基线升至 iOS 14.5 |
| HarmonyOS/OpenHarmony | `https://gardendless.invalid/index.html?generation=N` | ArkWeb NDK SchemeHandler 拦截合成 HTTPS 主机 | API 12，与仓库当前 `5.0.0(12)` 一致 |

`gardendless.invalid` 使用 IETF 保留的 `.invalid` 顶级域，不应落到真实网络；宿主仍必须只拦截完全匹配的 scheme、host 和允许的方法。[RFC 2606](https://www.rfc-editor.org/rfc/rfc2606.html#section-2)

## iOS：WKWebView + WKURLSchemeHandler

### 推荐结构

```text
原生 GameViewController
  -> 原生 WKWebView
  -> GardendlessURLSchemeHandler
  -> 激活资源槽
```

Apple 的公共 API 不允许给 WebKit 已处理的 `http`/`https` 注册处理器，尝试注册会抛出异常。因此 iOS 的零服务器方案必须使用应用专属 scheme，不能仿照 ArkWeb 映射一个合成 HTTPS 主机。[`setURLSchemeHandler`](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/seturlschemehandler(_:forurlscheme:))

`WKURLSchemeHandler` 从 iOS 11 起可处理 WebKit 不认识的 scheme。[`WKURLSchemeHandler`](https://developer.apple.com/documentation/webkit/wkurlschemehandler) 当前仓库最低版本是 iOS 13（`ios/Podfile` 和 Xcode 工程），所以基础能力已经可用。

### 流式、Range、MIME 与缓存

- `WKURLSchemeTask` 要求先返回带 MIME 和长度的 `URLResponse`，之后可多次调用 `didReceive(Data)` 增量发送数据，最后 `didFinish()`；因此实现不需要把大文件一次性读入 `Data`。[`WKURLSchemeTask`](https://developer.apple.com/documentation/webkit/wkurlschemetask)
- WebKit 官方问题跟踪中，Apple WebKit 工程师明确指出 `didReceiveData` 可以分多次调用，视频通常使用 byte-range，只需返回请求范围的数据。[WebKit issue 154916](https://bugs.webkit.org/show_bug.cgi?id=154916#c34)
- 处理器应读取 `Range`，返回 `206`、`Content-Range`、`Accept-Ranges: bytes`、正确的区间 `Content-Length`；非法范围返回 `416`。`HEAD` 只返回响应头；其他本地资源方法拒绝。
- MIME 由扩展名映射，至少显式覆盖 HTML、JS/MJS、CSS、JSON/JSON5、WASM、字体、图片、音频、视频、bin；响应对象必须包含 MIME。[Apple 对响应 MIME 的要求](https://developer.apple.com/documentation/webkit/wkurlschemetask/didreceive(_:)-2u23r)
- 读取应在专用有界队列进行，使用 `FileHandle`/POSIX fd 定位到 Range 起点并以固定大小缓冲块读取；收到 `stop` 后必须原子取消并停止回调，因为任务停止后继续发送数据会抛异常。[`WKURLSchemeHandler`](https://developer.apple.com/documentation/webkit/wkurlschemehandler)
- 可返回 `ETag`、`If-None-Match`/`304` 与 `Cache-Control`，但 Apple 公共文档没有承诺自定义 scheme 会获得与 HTTP(S) 相同的磁盘 HTTP 缓存语义。不要为大资源再建一份内存缓存；依赖文件系统页缓存，并把“自定义 scheme 是否命中 WebKit 磁盘缓存”列为真机验证项。

### 路径安全

处理器只接受固定 host `localhost`，并执行一次严格百分号解码；拒绝解码失败、NUL、反斜线、空路径段、`.`/`..`、双重编码后的危险形式。规范化后的相对路径必须落在会话资源根目录内；打开文件前后都应验证 canonical path，并使用不跟随符号链接的打开方式，防止 TOCTOU 和符号链接越界。错误响应不得泄露真实文件路径。

### document-start 与 Bridge

- `WKUserScript(.atDocumentStart)` 在文档元素创建后、其他内容加载前注入，满足公共 bootstrap、触摸、水印和菜单脚本的时序要求。[`atDocumentStart`](https://developer.apple.com/documentation/webkit/wkuserscriptinjectiontime/atdocumentstart)
- 所有公共脚本应在原生宿主创建 WebView 前从同一应用资源来源读入并注册，不能在 Swift 中复制脚本文本。[`WKUserScript`](https://developer.apple.com/documentation/webkit/wkuserscript)
- iOS 14 起可用 `WKScriptMessageHandlerWithReply` 返回 Promise 式结果；当前 iOS 13 基线只能使用普通 `WKScriptMessageHandler` 加请求 ID 回调。为减少两套桥接并结合 `WKDownload`，建议重构后最低版本升至 iOS 14.5。[带回复消息处理器](https://developer.apple.com/documentation/webkit/wkscriptmessagehandlerwithreply)
- Bridge 收到消息时必须检查 `message.frameInfo.securityOrigin` 与预期 scheme/host，限制消息大小、并发 ID、超时和重复完成；销毁时从 `WKUserContentController` 移除 handler，避免强引用环。[`WKUserContentController`](https://developer.apple.com/documentation/webkit/wkusercontentcontroller)

### Worker、Service Worker、WASM 与音视频

- **Service Worker 是明确限制**：WebKit 当前公开问题记录显示，WKWebView 的 Service Worker 脚本只能从 HTTP/HTTPS 加载，`WKURLSchemeHandler` 自定义 scheme 无法注册 Service Worker。[WebKit issue 206741](https://bugs.webkit.org/show_bug.cgi?id=206741)
- 普通 Dedicated/Module Worker、Worklet、动态 `import()` 对自定义 scheme 的组合没有 Apple 公共兼容契约，必须以实际游戏资源做真机门禁测试，不能在规格中先承诺可用。
- WASM 必须返回 `application/wasm`。普通 `fetch` + `ArrayBuffer` + `WebAssembly.instantiate` 应纳入功能测试；`instantiateStreaming`、WASM threads、`SharedArrayBuffer` 以及 COOP/COEP 在非 HTTP(S) Origin 上不能预设可用。[WebAssembly JS API](https://webassembly.github.io/spec/js-api/#dom-webassembly-instantiatestreaming)
- 音视频必须实现 Range/206/416 和取消；codec、seek 行为以及 WebKit 是否对该自定义 scheme 发 Range 请求需要真机验证。

这意味着：如果导入的游戏硬依赖 Service Worker、模块 Worker 或 `SharedArrayBuffer`，iOS 的“零服务器 + 公共 API + 不修改游戏文件”三项约束可能不可同时满足，必须在正式实施前用真实资源验证。

### 文件选择、下载、外链与进程退出

- 普通 `<input type=file>` 可使用 WebKit 的系统行为；自 iOS 18.4 起才有公开的 `WKUIDelegate` open-panel 自定义回调。当前目标版本下，宿主自有的导入操作应通过受信任 Bridge 调用 `UIDocumentPickerViewController`，而不是依赖私有 API。[`WKOpenPanelParameters`](https://developer.apple.com/documentation/webkit/wkopenpanelparameters)、[`UIDocumentPickerViewController`](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)
- `WKDownload` 从 iOS 14.5 起提供原生下载生命周期和目标路径委托，但 Blob/游戏存档导出仍应由公共 document-start 脚本捕获，经受限 Bridge 写入临时文件，再用 `UIDocumentPickerViewController(forExporting:asCopy:)` 导出，避免把完整 Blob 以单条消息复制。[`WKDownload`](https://developer.apple.com/documentation/webkit/wkdownload)、[导出 Document Picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(forexporting:ascopy:))
- `WKNavigationDelegate` 只允许应用专属 scheme 的游戏主框架和明确白名单子资源；用户触发的外部 HTTP(S) 导航取消后交给系统浏览器。[导航策略](https://developer.apple.com/documentation/webkit/wknavigationdelegate)
- 使用 `webViewWebContentProcessDidTerminate` 检测 WebContent 进程退出，原生页面负责重建或返回启动器。[进程退出回调](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webviewwebcontentprocessdidterminate(_:))

## HarmonyOS/OpenHarmony：ArkWeb HTTPS SchemeHandler

### 推荐结构

```text
原生 GameAbility / ArkUI GamePage
  -> 原生 ArkWeb Web
  -> 小型 Native C++ SchemeHandler
  -> 激活资源槽
```

ArkWeb 官方文档明确允许 SchemeHandler 拦截 Web 组件或 Service Worker 发出的 HTTP、HTTPS 和自定义协议请求；它是内核回调，不创建 socket，也不是 HTTP Server。[SchemeHandler 开发指南](https://github.com/openharmony/docs/blob/master/en/application-dev/web/web-scheme-handler.md)

推荐拦截 `https`，但只对 `https://gardendless.invalid/` 返回本地内容；其他 HTTPS 请求按远程白名单决定放行或拒绝。与自定义 scheme 相比，合成 HTTPS Origin 更接近普通浏览器的同源、Worker、Service Worker、媒体和 WASM 行为。

### 初始化、流式与 Range

- SchemeHandler、`WebSchemeHandlerRequest`、`WebResourceHandler` 和响应对象从 API 12 起可用。[`WebSchemeHandler`](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-apis-webview-WebSchemeHandler.md)
- 为拦截首个主文档请求，先在 UIAbility 主线程调用 `WebviewController.initializeWebEngine()`，再设置 SchemeHandler 后创建/加载 Web 页面；官方特别说明设置过早会失败。[初始化与首请求说明](https://github.com/openharmony/docs/blob/master/en/application-dev/web/web-scheme-handler.md#setting-schemehandler-for-web-components)
- NDK 用 `OH_ArkWeb_SetSchemeHandler("https", webTag, handler)` 处理 Web 组件请求，并用 `OH_ArkWebServiceWorker_SetSchemeHandler("https", handler)` 处理 Service Worker 请求。[ArkWeb SchemeHandler C API](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/capi-arkweb-scheme-handler-h.md)
- 响应可设置 status、MIME、charset、`Content-Length` 和其他头；`OH_ArkWebResourceHandler_DidReceiveData()` 可多次调用，所以能够从 fd 分块发送大文件。[官方流式响应示例](https://github.com/openharmony/docs/blob/master/en/application-dev/web/web-scheme-handler.md#intercepting-web-kernel-requests-and-providing-custom-responses)
- 宿主自行实现 GET/HEAD、Range、206/416、ETag/304、MIME、取消和并发；ArkWeb 不会替宿主生成这些 HTTP 语义。大型文件推荐 NDK 而不是 ArkTS `ArrayBuffer` 循环，避免 ArkTS/Native 间的持续数据复制。
- 路径解码、canonical root、符号链接、TOCTOU 和错误信息隔离采用与 iOS 相同的安全契约。`onRequestStop` 必须关闭 fd 并取消工作，官方要求结束回调清理资源以避免泄漏。[请求停止回调](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-apis-webview-WebSchemeHandler.md#onrequeststop12)
- 标准 `Cache-Control`/ETag 可返回，但官方没有明确承诺被 SchemeHandler 合成的响应一定进入 ArkWeb 普通磁盘 HTTP 缓存；缓存命中必须真机测量，不能当作已证明事实。

### document-start、Bridge 与页面边界

- `javaScriptOnDocumentStart` 从 API 11 起在 HTML 根元素创建后、其他内容加载前注入，但多个脚本按字典序执行；API 15 的 `runJavaScriptOnDocumentStart` 才按数组顺序执行。[Web document-start 属性](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-basic-components-web-attributes.md#javascriptondocumentstart11)
- 当前仓库基线为 API 12，因此应把公共脚本构建为单个有固定内部顺序的 bootstrap，或使用稳定名称前缀，不能依赖数组顺序。
- `registerJavaScriptProxy` 的 `permission` 参数从 API 12 起可把对象/方法限制到指定 scheme 和完整 host；官方也说明代理默认暴露给所有 frame。每次调用还应使用 `getLastJavascriptProxyCallingFrameUrl()` 二次校验 frame 来源。[JavaScriptProxy](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-apis-webview-WebviewController.md#registerjavascriptproxy)
- 页面退出时调用 `deleteJavaScriptRegister()` 并清除 SchemeHandler，防止 Bridge 和请求上下文泄漏。

### Worker、Service Worker、WASM 与音视频

- 合成 Origin 是 HTTPS，普通 Worker/模块相对路径保留标准同源语义；Service Worker 的请求还必须注册专用的 Service Worker SchemeHandler。官方明确支持拦截 Service Worker 请求，但游戏注册、更新和缓存生命周期仍需真机验证。[SchemeHandler 开发指南](https://github.com/openharmony/docs/blob/master/en/application-dev/web/web-scheme-handler.md)
- WASM 返回 `application/wasm`；若游戏使用 threads/`SharedArrayBuffer`，响应应提供所需的 COOP/COEP 头，并按目标设备 ArkWeb 版本验证 SIMD、threads 与 streaming。
- 音视频响应实现 Range，具体 codec 和连续 seek 行为按设备验证。

### 文件选择、下载与外链

- Web 文件选择使用 `onShowFileSelector`（API 9）与系统 `DocumentViewPicker`；游戏专属导入仍通过受限 Bridge 完成。[Web 事件参考](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-basic-components-web-events.md)
- 普通下载可使用 `onDownloadStart`/ArkWeb 下载能力；Blob 存档导出采用公共 JS 分块 Bridge、临时文件和 `DocumentViewPicker.save()`，并正确返回用户取消。[ArkWeb 下载](https://github.com/openharmony/docs/blob/master/en/application-dev/web/web-download.md)
- `onOverrideUrlLoading` 拦截主框架外链，白名单内子资源按策略加载，用户外链交给 Ability Kit 的系统浏览器。渲染进程退出和无响应分别由 Web 组件事件处理并重建原生页面。

## 当前仓库实现

- iOS 已由 [`GameHostController.swift`](../../ios/Runner/GameHostController.swift) 创建独立 WKWebView，
  [`ResourceSchemeHandler.swift`](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceSchemeHandler.swift) 并发分块读取激活槽；进入游戏后
  [`AppDelegate.swift`](../../ios/Runner/AppDelegate.swift) 销毁启动器 FlutterEngine，退出游戏时重新创建。
- HarmonyOS/OpenHarmony 已新增独立 `GameAbility` 与
  [`GamePage.ets`](../../ohos/entry/src/main/ets/pages/GamePage.ets)，不把 ArkWeb 放入 FlutterPage；
  [`NativeGameResourceHandler.ets`](../../ohos/entry/src/main/ets/game/NativeGameResourceHandler.ets)
  使用异步固定大小分块读取并在 `onRequestStop` 后停止回调。
- [`ohos/build-profile.json5`](../../ohos/build-profile.json5) 继续使用
  `compatibleSdkVersion: 5.0.0(12)`，对应 SchemeHandler、Bridge permission 和来源查询的最低 API 12。
- 三平台通过同一份 [`assets/game_bridge`](../../assets/game_bridge) document-start 脚本共享 Transport、
  GP-Next 协议、触摸、导出、水印和菜单行为；平台代码只保留资源、文件选择器、系统浏览器和生命周期边界。

## 可统一与不可统一

可以统一：`GameSession` 字段、相对路径规则、MIME 表、Range/ETag/缓存头规则、目录穿越与符号链接防护、公共 JavaScript 文件、Bridge JSON 协议、远程白名单、退出结果和验收用例。

不能统一：iOS 公共 API 只能处理自定义 scheme，ArkWeb 则可拦截合成 HTTPS；iOS 自定义 scheme 不支持 Service Worker，ArkWeb HTTPS 方案可以接管 Service Worker 请求；两端的缓存命中、Worker/WASM threads 和媒体 codec 也必须各自真机验证。

## 发布前真机验证项

1. 用真实 Gardendless 与 GP-Next 资源枚举 `Worker`、Service Worker、WASM streaming/threads、动态 import 和媒体请求；iOS 若命中硬性 Service Worker 依赖，零服务器方案不可行。
2. 在当前支持的最低 iPhone/iPad 与 API 12 鸿蒙设备上验证 Range seek、并发取消、1 GiB 级文件常驻内存、WebContent/Render 进程退出恢复。
3. 验证自定义/合成响应的 WebView 缓存行为；在结果出来前只依赖 ETag 和操作系统文件页缓存，不创建大对象缓存。
4. 当前 iOS 工程基线与 `WKScriptMessageHandlerWithReply` 的部署版本一致；发布构建之外仍需覆盖最低支持系统的真机启动与导出。
5. 验证三个平台从原生游戏宿主退出后均能读取退出结果、重新创建 Flutter 启动器，且不会误改激活资源状态。
