# GardendlessLoader iOS 详细设计（Phase 3）

> 状态：已接受（候选 B 的模块级设计）

## 1. 系统边界

- **边界外（保留）**：Flutter 启动器业务编排、Android/OHOS 原生层、JS 桥资产、远程内容。
- **边界内（重建）**：iOS App 启动壳、Flutter 通道适配、WKWebView 游戏宿主、资源服务、桥、ZIP 导入、GP-Next、音频、日志。

## 2. GardendlessCore

### 2.1 会话模型

```swift
public struct GameSession: Codable, Equatable {
  public static let origin = "gardendless-game://localhost"
  public static let schemaVersion = 1
  public let sessionId: String
  public let resourceRoot: URL
  public let entryURL: URL
  public let activationGeneration: Int
  public let hasGpNext: Bool
  public let gpNextCompatible: Bool
  public let gpNextVersion: String?
  public let watermarkEnabled: Bool
  public let autoCollectSunEnabled: Bool
  public let allowedRemoteHosts: Set<String>
  public let gpNextRoot: URL
  public let exportTemporaryRoot: URL
  public var appRoot: URL
}
```

- 解析入口 `GameSessionDecoder`：校验 schema、platform=ios、origin、entryPath 沙箱约束、host 合法性；失败抛 `GameError.invalidSession`。

### 2.2 路径沙箱

```swift
public struct PathSandbox {
  public init(root: URL) throws
  public func relativePath(for url: URL) -> String?
  public func resolve(_ relativePath: String) -> URL?
  public func isWithin(_ url: URL) -> Bool
}
```

- 行为规格来自旧 `GameResourceLocator`：单次百分号解码、拒绝双重编码、拒绝 NUL/反斜线/`.`/`..`、逐段符号链接检查、canonical 前缀校验。
- GP-Next 沙箱复用 `PathSandbox`，锚点为 `gp-next` 根。

### 2.3 网络策略

```swift
public enum NetworkPolicy {
  public static func encodedRules(for hosts: Set<String>) throws -> String
  public static func load(for session: GameSession,
                          store: WKContentRuleListStore,
                          completion: @escaping (Result<WKContentRuleList, Error>) -> Void)
}
```

- 默认拦 `^http://` 与 `^https://`；白名单主机（含子域）`ignore-previous-rules`。

### 2.4 错误模型

```swift
public enum GameError: LocalizedError {
  public enum Code: String { case invalidSession, invalidPath, resourceNotFound,
    methodNotAllowed, rangeNotSatisfiable, resourceReadFailed, zipInvalid,
    zipEncrypted, zipUnsupported, zipSymbolicLink, gpNextForbidden,
    gpNextUnavailable, exportInProgress, exportCancelled, nativeAudioFailed,
    loggingDegraded, unavailable }
  case failed(Code, String)
  case underlying(Code, String, Error)
}
```

- 用户可见文案由 Dart 适配层统一映射为中文；原生错误码稳定。

### 2.5 配置

```swift
public struct GameConfiguration {
  public var resourceQueueConcurrency = 6
  public var audioQueueConcurrency = 1
  public var audioCacheByteLimit = 24 * 1024 * 1024
  public var pcmCacheByteLimit = 64 * 1024 * 1024
  public var singleBufferByteLimit = 4 * 1024 * 1024
  public var maxExportBytes = 512 * 1024 * 1024
  public var maxExportChunkBytes = 256 * 1024
  public var bridgeMaxMessageBytes = 1024 * 1024
  public var logSegmentBytes = 2 * 1024 * 1024
}
```

- 统一默认值；`nativeSfxEnabled` 继续读 `UserDefaults`，其余不新增持久化配置。

## 3. GardendlessResource

### 3.1 定位与元数据

```swift
public protocol ResourceServing {
  func serve(_ task: WKURLSchemeTask, using locator: PathSandbox)
  func cancel(_ task: WKURLSchemeTask)
}
public struct ResourceMetadata { let length: Int64; let etag: String; let mimeType: String }
```

### 3.2 协议行为矩阵（与旧实现一致）

- 仅 `gardendless-game` + `localhost`；GET/HEAD；`Accept-Ranges: bytes`；Range 单区间；206/416；ETag/304；`Cache-Control`（index/settings/import-map=no-cache；带哈希名=immutable；媒体=86400；其余 no-cache）；`X-Content-Type-Options: nosniff`。
- MIME 显式映射（HTML/JS/MJS/CSS/JSON/JSON5/WASM/SVG/图片/音频/视频/字体/bin）；`.mp3` 魔数识别真 MP3 vs M4A。
- 音频缓存：≤256KB 且非 bgm/music 的短音效进入 LRU（24MB）；大文件流式。
- 取消语义：任务取消后不再回调；回调计数 + 状态锁保证不重复 finish/fail。

## 4. GardendlessBridge

### 4.1 消息协议

```swift
public struct BridgeRequest: Codable { let id: String; let command: String; let args: [String: Any] }
public enum BridgeCommand: String { case returnHome, setWatermark, log, export, exportBegin,
  exportChunk, exportCommit, exportAbort, gpNextNamespace }
```

- 使用 `WKScriptMessageHandlerWithReply`；首答 `{accepted:true}`，业务结果经 `evaluateJavaScript(window.__gardendlessTransport.resolve(...))` 回传。
- 校验：main frame、securityOrigin、1MB 上限、重复 ID 拒绝、销毁 rejectAll。

### 4.2 导出协议

```swift
public final class ExportCoordinator {
  public func begin(id: String, suggestedFilename: String, mimeType: String, totalBytes: Int) throws -> String
  public func append(token: String, index: Int, data: Data) throws
  public func commit(token: String) throws -> URL
  public func abort(token: String)
}
```

- 写 `.exports/` 下随机临时文件；校验序号、字节数、上限；commit 交 Host 弹文档保存选择器；取消/中止删除临时文件。

## 5. GardendlessImport

```swift
public final class ZipImportSession {
  public init(zipURL: URL, targetDirectory: URL)
  public func run(progress: @escaping (ImportProgress) -> Void) throws -> URL
}
public struct ImportProgress { phase, processedBytes, totalBytes, processedFiles, totalFiles, message }
```

- 流式：EOCD 定位 → 中央目录 → 每项 local header 偏移 → 64KB 缓冲 stored/deflate 解压。
- 拒绝：ZIP64 极限值、加密位、符号链接、不安全路径。
- docs 定位规则与旧实现一致（index.html + 三个文件 + 三个目录；优先 basename=docs，其次最短路径）。
- 进度节流 100ms；目标目录由 Dart 事务给定（空闲槽）。

## 6. GardendlessGPNext

```swift
public final class GpNextFileSystem {
  public func mkdir/readDirectory/readFile/exists/remove/writeFile(...)
}
public final class GpNextPackageImporter {
  public func importPackages(from urls: [URL], confirmReplacement: (String) -> Bool) throws
}
```

- 命令路由：`plugin:fs|*`、`plugin:dialog|save`、`plugin:opener|open_url/open_path`；未知命令报“未兼容”。
- 写文件先写 `.incoming-*`，重名走“确认 → backup → 替换 → 失败回滚”。
- ZIP 补丁根须含 `pack.json`（仅扫描中央目录）。

## 7. GardendlessAudio

```swift
public final class ShortSfxEngine {
  public func register(_ url: URL)
  public func play(elementId: String, url: URL, volume: Float)
  public func stop(elementId: String)
  public func release(elementId: String)
  public func stopAll()
  public func setMasterVolume(_ volume: Float)
  public func shutdown()
}
```

- 串行解码队列；≤256KB、≤10s、非 bgm/music 才走原生；PCM LRU 64MB；16 节点池；AVAudioSession ambient + mixWithOthers；后台/中断/路由变化处理；`SfxExceptionGuard` 包裹 start/schedule；失败回退 WebKit 音频。

## 8. GardendlessLogging

```swift
public final class LogStore {
  public func install(messenger: FlutterBinaryMessenger)
  public func emit(_ event: [String: Any])
  public func snapshot(limit: Int) -> [String: Any]
  public func flush(timeout: TimeInterval) -> Bool
  public func deleteHistory()
  public func endSession()
}
```

- schema v1、2MB 分段、500 条内存环、7 天/5 组/10MB 清理、16KB 事件截断、pending 1000/1100 丢弃保护、脱敏正则与 `<user-home>` 替换。

## 9. GardendlessHost（App 壳）

```swift
public final class LauncherBootstrap {
  public static func start(application: UIApplication, window: UIWindow)
}
public final class GameHostController: UIViewController { ... }
```

- 唯一 import Flutter 的模块；负责：launcher engine 生命周期、4 个通道注册、ZIP 导入通道转 `GardendlessImport`、launch 转 Core/Bridge/Resource/Audio/GPNext 装配、退出结果写入、AppLogStore 安装。
- ViewController 装配使用组合而非继承：`GameHostController` 聚合 `WKWebView`、`ScriptMessageBridge`、`ResourceSchemeHandler`、`ShortSfxEngine`。

## 10. 测试策略

| 层 | 框架 | 覆盖 |
| --- | --- | --- |
| Kit 单元测试 | XCTest（SwiftPM） | Core 解析/沙箱/策略；Resource 协议矩阵；Import ZIP；GP-Next 沙箱；Audio 决策；Logging 脱敏/轮转 |
| Dart 契约测试 | flutter_test | 通道名与方法、桥命令面、导出协议、配置断言（更新路径指向新源码） |
| 集成 | `swift test` + `flutter test` | 会话 JSON 读写、退出结果、ZIP 进度 |
| 构建 | `flutter build ios --release --no-codesign` | 最终门禁 |

## 11. 构建 / 发布 / 回滚

- 构建：SPM 解析 Kit → Xcode 构建 Runner → unsigned IPA。
- 发布：版本同步、announcements、draft PR（用户确认）。
- 回滚：`git checkout <上一提交>` 即可恢复旧 Runner；旧文件保留至用户确认删除。
