# 运行时收敛实施记录

日期：2026-10-15。范围来自[接口审计](functional-interface-audit.md)及[运行契约](loader-runtime-contracts.md)。Loader 版本 0.9.0，Host ABI 1；Android、iOS、纯血鸿蒙都保留。UI 布局、样式和入口源码未修改。

## 实际归属

| 功能入口 | 唯一实现/数据归属 | 本次收敛 |
| --- | --- | --- |
| Dart `MethodChannelGameHost.launch(session)` | `MethodChannelGameHost` → 当前平台宿主 | 去除没有选择作用的 Router；只传小型会话参数，不传游戏字节 |
| 资源检查 `ResourceValidator.validate(root)` | Validator 返回版本、包身份、兼容事实及 stats | 入口、自检及统计合并；新包摘要检查复用同一次目录遍历取得的大小 |
| 导入激活 | `ImportService` + 原子 manifest | 成功结果直接更新 controller；统计来自 validation；恢复记录移到槽外，不污染包索引 |
| 四类远程正文读取 | `loadHttpText` | 一次有界 UTF-8 正文读取与关闭；服务各自保留业务解释规则 |
| 应用版本 | controller 共享的一次安装身份查询 | 诊断与更新复用结果 |
| 日志 | `NativeAppLogger` → 各平台原生 store | 移除 Dart 镜像后备存储 |
| 游戏 Tauri 调用 | `assets/game_bridge/transport.js` | 配置、RPC、Tauri 参数归一和二进制传输在同一入口处理 |
| GP 文件读写、Blob 下载、系统保存 | `file:begin/chunk/finish` | 一种块协议；系统 picker 是写事务的提交终点 |
| 原生文件任务 | Android `GpNextNativeCore`、iOS `FileTaskCoordinator`、OHOS `GpNextNativeCore` | 每端一个所有者，负责队列、句柄、截止时间、取消及终态 |
| 游戏资源请求 | 各端现有资源 Handler | 保留 GET/HEAD/Range/Origin/路径限制；元数据命名空间禁止访问 |
| 音频路由 | 提取项目 `patch_audio_runtime.py` 修补 Cocos | 显式模式优先，否则 music UUID 用 DOM，其它音效用 WebAudio |
| 水印设置 | Dart manifest → 启动会话快照 | 原生重复设置命令移除，显示样式不变 |
| 资源包生产 | 提取项目 `resource_package.py` | 新输出只收录选中 ASTC；生成 manifest/index，封存 ZIP 后重开逐项验证 |

```mermaid
flowchart LR
  Source[上游 Lite EXE] --> Build[音频修补与单一 ASTC 加工]
  Build --> Package[新目录组装与 ZIP 重开校验]
  Package --> Check[Loader 一次 validate 返回事实及统计]
  Check --> Slot[原子激活资源槽]
  Slot --> Host[当前平台 GameHost]
  Host --> Game[Cocos / GP-Next]
  Game --> Bridge[共享 transport.js]
  Bridge --> Files[当前宿主文件任务所有者]
```

## 文件传输不变量

- 块最多 64 KiB，单文件最多 512 MiB，每端最多 8 个活跃句柄；原生最多 2 个文件任务、16 个排队任务。JS 文件操作串行，等待落盘回复后再发下一块。
- 普通 RPC 最多 64 个，close/cancel 另留 8 个准入位置，总数最多 72。原生独立限制，不依赖 JS 活着。
- 读取打开一次文件描述符；写入使用同目录临时文件及原子替换。JS 保留最终 ArrayBuffer，移除完整 number[] 和完整 Base64 中间副本。
- 子视图尊重 byteOffset/byteLength；文本读完后统一解码，不在块边界拆解字符。
- 原生十分钟截止时间负责回收失联任务；JS 普通回复十五秒、系统交互五分钟。终态有界保存，重复完成不重新写入。
- Android 最后 rename 与关闭会话共享临界区；iOS 资源 stop 与回调共享可重入门；OHOS 取消实际关闭 FD。选择器忙碌状态保持到暂存/复制结束，旧选择器结果不能提交新事务。
- 标准游戏也能导出 Blob。只有 GP 目的地受 GP 兼容能力限制；没有旧 exportBegin/Chunk/Commit 或整文件读写后备路径。

这减少中间复制，并不消除 GP 最终文件缓冲及 ZIP 解码内存。未取得设备数据前，不据此声称峰值内存或帧率改善了多少。

## 音频与资源包

音乐角色取自 Cocos `resources/config.json` 的 `music/` AudioClip UUID；不再用时长阈值猜测。DOM 等有效 metadata 后才成功，error/abort/超时拒绝；decode 失败传递给外层 Promise。one-shot 用真实 onended 结算并释放 source/gain，处理变速及 context 恢复前取消。

共享观察器覆盖离屏 Audio 元素，记录 ready/network/duration/error、解码并发与累计 PCM 字节，并限制日志频率。累计 PCM 不是常驻内存指标。没有引入原生音频播放器。

manifest 恰八字段，索引覆盖所有运行文件，两份固定元数据除外。包身份为 manifest 原始字节 SHA-256。元数据损坏不会降级为旧格式。新包 module 入口等待 Host ABI 检查，旧 Loader 显示升级提示；HTML 注释中的脚本不算入口。

Android 补齐 M4A/AAC MIME，并识别历史伪装 `.mp3` 的 MP4/ADTS 音频；iOS/OHOS使用对应内容识别。Android 条件请求返回 WebView 接受的 200/206，而不是非法的 304 包装。

## Actions 联动

Loader 一次 quality 门禁后构建三个平台，分别核对嵌入版本、实际文件 SHA-256 与 Host ABI；最终汇总要求三个构建都成功。缺少鸿蒙工具配置或 HAP 构建失败明确失败，不把跳过或失败产物描述为完整成功。签名身份沿用现有配置。

提取 Actions 只有 release_tag 输入，固定运行测试、音频修补、ASTC 加工、组装和封存验证；未知布局失败，不换其它脚本。构建报告留在包外，native 原图和中间图不进入正式包。

## 验证与实际限制

真实官方0.15原料已完成本地全管线：619张统一ASTC、553525098字节ZIP重开验证、Loader对8523文件完整摘要检查通过；该产物明确标记sourceDirty，仅作本地验证。原提取项目37测试、Loader安全Flutter清单135测试通过。最终命令、数量及未验证项记在仓库根目录 [CHANGE_MANIFEST.md](../../CHANGE_MANIFEST.md)。首次验证遵守旧规则，只运行纯测试及保留夹具测试；用户随后替换规则，本轮完整Flutter测试246项及静态分析通过，包含原导入、恢复、会话与UI用例。

已核对本机设备：Android 无连接设备；有连接的 iPad，但尚未使用新签名应用完成 BGM、后台恢复、固定怪物负载及内存曲线验收；没有本机完整鸿蒙构建工具。三端真实可听输出、帧率、峰值内存与完整 APK/IPA/HAP 的 Actions 运行证据均须单独取得，源码/协议测试不能替代。

用户替换旧删除规则并明确授权后，已删除四个停用占位文件：`assets/game_bridge/bootstrap.js`、`assets/game_bridge/gp_next_core.js`、`assets/game_bridge/gp_next_compat_bridge.js`、`lib/src/services/resource_self_check.dart`。桥接测试只加载实际的`transport.js`，自检测试继续覆盖`ResourceValidator`；历史审计链接固定到改造前的Git基线。工作区清理仅删除这四个文件；测试自行清理其生成的临时夹具。

完整测试中发现版本缓存的已完成Future跨异步zone复用问题：现只保留在途Future，完成后缓存字符串，保持安装版本只读取一次。新增跨zone回归及必需入口夹具后，所有246项Flutter测试通过，UI源码未改。

## 2026-10-15 无用代码清理

用户确认两个项目一起清理，保留现有行为、UI、Android/iOS/纯血鸿蒙、资源包协议及一键发包；明确删除已退出构建的历史转码工具。

- Dart 删除没有生产消费者的内存日志实现、Session 复制/值比较、小型 getter 和旧测试注入参数；启动直接使用唯一的 MethodChannelGameHost。入口传入的原生日志、同一个资源 validator、导入事务、Wakelock 恢复及默认请求/计时参数保留。
- Android 删除未实例化的原生鼠标 WebView/状态机；iOS 删除仅测试调用的 HealthProbe、无调用批量包装和常量；鸿蒙删除未注册空选择器插件及未使用 Ability 别名。对应专用检查与 CI 引用一起删除。
- 共享触摸只保留三平台原本固定使用的帧同步路径，删除即时派发分支和无选择作用的配置字段；保留种植、拖放、多指、取消和 DOM 归属检查。
- 提取项目删除 transcode-assets.sh、未使用常量和 step output。ASTC 只读取 16 字节头并用同一文件描述符的 fstat 核对长度；编码成功后的重复检查循环删除，编码器、包组装、ZIP 封存边界的有效校验保留。音频候选读取和包预算扫描减少重复 I/O。
- UI/入口、Session JSON、manifest 存储、资源 validator、原有未跟踪设计文档和 .DS_Store 不变；没有新增依赖、抽象层或 Flutter 测试。

验证：Dart 格式与 flutter analyze 通过；六个现有 Node 检查通过；Android 全部生产 Kotlin 编译及 19 项相关检查通过；六个 Swift 模块与实际宿主类型检查及 36 项选定检查通过；鸿蒙 API12 签名检查通过；提取器原有 37 项检查全部通过、零跳过，包含实际 ASTC 编码与 alpha 解码；Actions YAML、shell 和产物汇总约束检查通过。独立复核没有发现行为或协议阻塞项。

这些结果证明代码和构建链路的相应部分，不代表已完成 BGM、高怪物负载、FPS 或峰值内存的真机验收。Android Release APK 与未签名 iOS Release Runner.app 完整编译/链接成功，实际嵌入版本均为 0.9.0。Android 首次打包使用本机 Java26 在 Gradle 插件阶段失败，改用与 CI 相同的 JDK17 后通过，没有修改构建配置来规避检查。没有本机完整鸿蒙工具链，因此未构建 HAP；未安装或启动真机。


## Actions 执行路径修复

首次远程构建 [38704781347](https://github.com/Dey410/GardendlessLoader/actions/runs/38704781347) 的质量检查、Android APK 编译和 iOS IPA 生成成功，后续 Android 测试与鸿蒙工具启动失败。此前本地编译未覆盖这两条实际 CI 命令。

Android 测试任务现在明确指定 `:app:testReleaseUnitTest`，避免应用类名筛选传播到第三方插件测试。相同八个应用测试类的 30 项检查通过；插件的生产编译依赖保留。

鸿蒙的 `hvigor` 别名现在使用 `exec` 包装调用真实 `hvigorw`，避免符号链接让脚本按错误的 `$0` 目录寻找 `hvigorw.js`。临时目录夹具复现原错误并验证修复，含特殊字符的路径和参数原样保留；工作流 YAML、shell、失败传播和三端产物汇总约束检查通过。完整 HAP 结果须以修复提交对应的 Actions 为准。


随后构建 [38708146916](https://github.com/Dey410/GardendlessLoader/actions/runs/38708146916) 的 Android APK 与 iOS IPA 均成功生成、校验并上传；鸿蒙通过工具启动和依赖安装后，实际 ArkTS 编译在两个队列拒绝调用处报告 structural typing 错误。`NativeFileTask.reject` 只接收队列驱逐与宿主销毁产生的 `FileFailure`，现在字段与构造参数明确使用该具体类型。运行中 IO 异常仍直达 Promise 原始 reject，不改变错误对象、错误码或取消行为。类型设计依据见 [OpenHarmony ArkTS 迁移约束](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/quick-start/typescript-to-arkts-migration-guide.md)。现有鸿蒙 21 项行为检查和 API12 签名检查通过；这些本地检查不能替代对应提交的真实 ArkTS/HAP 编译结果。
