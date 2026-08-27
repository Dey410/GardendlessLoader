# iOS Cocos 原生音频管线

## 决策

iOS 游戏宿主不再实现独立的原生音频引擎，也不再修改 Cocos 引擎包。音频的加载模式、解码、播放、音量、静音、循环、变速和结束事件全部由资源包自带的 Cocos Creator WebAudio / HTMLMediaElement 后端决定。

Loader 只负责两件事：

1. 通过 `gardendless-game://localhost` 正确提供音频资源。
2. 以不改变音频行为的浏览器 API 观察器记录错误、汇总和可选的详细事件。

该边界适用于通过现有资源校验的通用 Cocos Web 包，不再与某个压缩后的 Cocos bundle 版本绑定。

## iOS 数据流

```text
Cocos AudioSource / playOneShot
  -> Cocos 自带 WebAudio 或 HTMLMediaElement 路由
  -> gardendless-game://localhost/<relative-path>
  -> WKURLSchemeHandler
  -> MIME / Range / ETag / 有界小音频缓存
  -> 激活资源槽中的原始文件
```

关键实现：

- [`GameHostController.swift`](../../ios/Runner/GameHostController.swift) 创建 WKWebView，保留 `mediaTypesRequiringUserActionForPlayback = []`，但不注册音频专用消息处理器。
- [`ResourceSchemeHandler.swift`](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceSchemeHandler.swift) 提供 GET/HEAD、Range、ETag、取消、流式读取和有界小音频缓存。
- [`ResourceMIME.swift`](../../ios/GardendlessKit/Sources/GardendlessResource/ResourceMIME.swift) 映射 MP3、M4A、Ogg、WAV，并对扩展名为 `.mp3`、内容实际为 M4A/MP4 容器的文件进行头部嗅探。
- [`import_service.dart`](../../lib/src/services/import_service.dart) 校验并激活资源，但不改写 Cocos JavaScript。

不存在 Loader 侧的格式白名单、短音效/长音频分类、解码回退、AVAudioSession 管理、主音量、播放节点池或 Cocos bundle 补丁。

## 与 Android 当前实现的区别

| 项目 | iOS | Android |
| --- | --- | --- |
| 游戏 Origin | `gardendless-game://localhost` | `https://appassets.androidplatform.net` |
| 本地资源入口 | `WKURLSchemeHandler` | `WebViewClient.shouldInterceptRequest` |
| 音频播放归属 | Cocos WebAudio / HTMLMediaElement | Cocos WebAudio / HTMLMediaElement |
| Range / ETag | 支持 | 支持 |
| 小音频内存缓存 | iOS 资源处理器内有界 LRU | 无同等专用缓存 |
| MIME | MP3/M4A/Ogg/WAV；MP3 路径会嗅探 M4A 容器 | 按扩展名映射 MP3/Ogg/WAV |
| 详细音频诊断 | iOS document-start 被动观察器 | 本次不改动 |

Android 的 [`GameResourceResolver.kt`](../../android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameResourceResolver.kt) 当前没有 `.m4a` 映射，也不嗅探伪装成 MP3 的 M4A 容器。本次重建明确不修改 Android，因此该差异仍然保留。

## 被动诊断

[`audio_diagnostic.js`](../../assets/game_bridge/audio_diagnostic.js) 在 document-start 安装观察器：

- 包装 `AudioContext.decodeAudioData`，保持原返回值、Promise 身份、回调参数和抛出的异常不变。
- 观察 HTMLMediaElement 的加载、就绪、播放、结束和错误事件。
- 包装 `HTMLMediaElement.play` 只为观察调用与 Promise 拒绝；返回原始 Promise。
- 所有带路径的事件只记录相对路径，不记录资源根目录或完整 URL。
- 错误和 `audio_summary` 始终记录；逐事件详情仅在“详细音频诊断”开启时记录。
- 事件通过现有 `host:log` 进入统一 Session JSONL，不创建独立音频诊断文件。

开关位于启动器“日志”页，默认关闭，保存在 `app_settings.json` 的 `detailedAudioDiagnosticsEnabled` 字段。该值随 `GameSession` 传入 iOS 宿主；旧的已准备会话缺少字段时按 `false` 处理。

## 导入与旧资源

新导入的资源在校验后保持 Cocos 文件字节不变。Loader 不再检测、提示或应用音频补丁，也不迁移已经导入且曾被旧版本修改过的槽位。需要恢复原始 Cocos 文件时，应重新导入原始 ZIP。

## 0.13.0 参考包

本次只读审计的参考包为 `pvzge-lite-0.13.0.zip`：

- Cocos Creator `3.8.4`，目标平台 `web-mobile`。
- 包含 `docs/cocos-js/_virtual_cc-23be142f.js` 与 `docs/cocos-js/cc.js`。
- 包含 3,487 个 `.m4a` 和 627 个 `.mp3` 音频文件。
- ZIP 完整性检查通过，共 8,276 个文件，解压后约 455.6 MB。

参考包仅用于结构与格式覆盖确认，不进入仓库，也不是实现中的版本判断条件。

## 自动化门禁

- 导入测试验证 Cocos 音频 bundle 在激活前后字节完全相同。
- 静态契约验证 iOS 不注入 facade/proxy、不注册 `gardendlessAudio`，Swift Package 和 Xcode 工程不链接原生音频模块。
- Swift 资源测试覆盖 MIME、伪装 M4A 头部嗅探、Range/416、ETag、取消、并发流式读取和小音频缓存。
- Node 行为测试验证诊断包装器不改变 decode/play 的返回、回调和异常语义。

## 验证边界

自动化和无签名构建只能证明静态契约、资源响应和可编译性。Cocos 在实际 iPhone/iPad WebKit 上的 codec、自动播放、切后台恢复、并发音效与长时间稳定性，由真机验收确认。
