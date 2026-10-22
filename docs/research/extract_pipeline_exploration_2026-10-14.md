# extract-pvzge-gpnext 提取与运行时补丁探索（2026-10-14）

本笔记只记录探索，不修改两个项目的生产源码，不执行删除。本机0.15样本尚未由用户确认与其设备导入文件相同，以下真实包观察仅适用于该明确样本。结论分为已核实的代码行为、可复现的隔离语义、尚需 iOS 真机证实的症状假说。用户当前复现场景是 iOS Loader 0.8.2 + 资源 0.15：短音效正常，BGM 缺失；怪物多时出现性能与内存问题。没有用户设备日志、Instruments 或 Web Inspector 数据，不能把以下静态风险直接宣布为根因。

## 1. 审计基线与版本分叉

- 本地提取项目：`/Users/xiaozhu_410/Documents/Code/extract-pvzge-gpnext`，当前分支 `codex/dom-metadata-preload`，HEAD `1ffb59b061761ccee1592097abc78c63fc9a6bda`。工作区已有修改仅 `.DS_Store` 与 `.github/.DS_Store`，未触碰。
- GitHub 只读 API 核实远程默认分支仍为 `main`，其本地跟踪提交 `8d20729`。当前工作分支比 main 多混合音频、metadata preload 和 ASTC 处理，不能以 main 代表用户最近使用的构建。
- GitHub 最近 2026-09-30、09-29、09-11 三次成功运行均使用 `codex/dom-metadata-preload` 的 `1ffb59b`。最近运行：[36659966916](https://github.com/Dey410/extract-pvzge-gpnext/actions/runs/36659966916)，2026-09-30 UTC，原料为上游 `pvzge-lite-0.15.0.zip`，最后产物 610,156,829 字节，与本地 0.15 ZIP 大小一致；音频引擎 SHA 与本地包报告一致。这里只把这些视为一致性证据，没有把整包 SHA 未核实的同名文件等同为同一个文件。
- 只读 issue 查询只有 [#1 怎么做？](https://github.com/Dey410/extract-pvzge-gpnext/issues/1)，没有拿到可用于上述症状的设备证据。
- 提取目录未发现 AGENTS、CONTEXT 或 ADR。已读取 Loader 的 `docs/agents/domain.md` 与 `issue-tracker.md`；本次没有创建 issue 或评论。

历史至少存在四种不同音频策略，必须分别标记：

| 分支/提交 | 音频行为 | 与当前 Loader 的关系 |
| --- | --- | --- |
| `main@8d20729` | 所有音频强制 DOM；`preload=none`；第一次 play 才绑定 src；改游戏默认模式 | 与当前 metadata 混合包不同 |
| `codex/hybrid-audio-loading@9681318` | 时长 >=10 秒 DOM，其余 WebAudio；DOM `preload=none` | 本地 0.13 报告符合该政策 |
| `codex/dom-metadata-preload@1ffb59b` | 相同10秒分流，DOM 创建时绑定src并load，`preload=metadata` | 本地0.14、0.15报告符合该政策 |
| `codex/compact-150-audio-policy@c8e73d9` | 全DOM并优先 `window.__gardendlessNativeAudio.createNativeAudioHandle`，oneShot角色与release钩子，voice pool配置 | 当前 Loader 的架构文档已经移除原生 facade；历史资源和宿主必须组合审计 |

历史证据来自 `git show <ref>:scripts/patch_audio_runtime.py`，可复核 [main 脚本](https://github.com/Dey410/extract-pvzge-gpnext/blob/8d207293dc9a76fc778a2ff391fd7b50c6c90fb8/scripts/patch_audio_runtime.py)、[compact 脚本](https://github.com/Dey410/extract-pvzge-gpnext/blob/c8e73d96930e4bb3c3d95c1e96cb0ec3509b1ff6/scripts/patch_audio_runtime.py)。

## 2. 当前构建管线与两个项目的交界

当前 [.github/workflows/extract-pvzge-tauri.yml](https://github.com/Dey410/extract-pvzge-gpnext/blob/1ffb59b061761ccee1592097abc78c63fc9a6bda/.github/workflows/extract-pvzge-tauri.yml) 的可操作输入只有：

| 参数 | 默认值 | 实际含义 |
| --- | --- | --- |
| `release_tag` | 空 | 从 `Gzh0821/pvzg_site` 最新非draft release取资源，包含pre-release（L6、L53、L62） |
| `image_transcode_format` | `none` | 可选 `astc`；默认保持图片输入（L10–17） |
| `enable_hybrid_audio_loading` | `true` | 执行引擎补丁（L19–23、L359–372） |

流程为：筛选恰好一个非macOS Lite ZIP（L104–120）→ 下载并在日志打印ZIP SHA（L133–147）→ 取ZIP中恰好一个EXE（L153–183）→ 固定 `tauri-dumper 0.2.2 --locked`（L34、L232–235）→ verify/list/extract（L260、L272、L291）→ 可选音频补丁 → 可选ASTC → 上传 `docs/` 和 `reports/`（L469–478，保留7天）。

重要事实：

1. 当前 workflow **没有调用 `scripts/transcode-assets.sh`，没有执行音频压缩或转码**。`.m4a`、AVIF等输入本身来自上游Lite。遗留脚本不能解释为当前默认构建步骤。
2. 没有自有 Cocos 工程/原始 TypeScript 生产源码。此项目是 EXE 资源提取器和对压缩bundle做正则改写的后处理器；游戏逻辑和引擎版本来自上游。重构边界与完整游戏源码重建不同。
3. 验证提取结果只要求某处找到 `index.html`（L324–335）；音频补丁随后要求 `docs/cocos-js/_virtual_cc-*.js`，ASTC要求 `docs/assets/*/native`。完整 Loader 包契约尚未在提取workflow中统一验证。
4. 提取workflow存在已有 `rm -rf docs`（L288），本次没有执行。重构实现时必须遵守本会话不删除目录的规则，改用新输出目录等方式。
5. 目前CI只在 `image_transcode_format=astc` 时跑整套 Python tests（L424–427）；默认none音频补丁路径不会独立运行音频测试。
6. reports有逐音频路由和引擎before/after SHA，有ASTC映射；没有统一机器可读的资源manifest来持久记录提取git SHA、全部输入参数、上游archive digest、最低宿主/能力要求和完整hash。用户仅说“0.15”无法唯一确定音频策略/纹理策略。

Loader侧 [resource_validator.dart](/Users/xiaozhu_410/Documents/Code/GardendlessLoader/lib/src/services/resource_validator.dart:14) 检查assets/cocos-js/src、index/settings/import-map、title和Cocos配置及GP-Next指纹；[resource_self_check.dart](/Users/xiaozhu_410/Documents/Code/GardendlessLoader/lib/src/services/resource_self_check.dart:10)再要求cocos-js/cc.js、路径封闭和可读。不读取提取reports来选择音频后端，也不检查ASTC扩展、codec能力或上述生产参数。[iOS音频架构文档](/Users/xiaozhu_410/Documents/Code/GardendlessLoader/docs/architecture/cocos-audio-pipeline.md:5)把后端选择和播放交给资源包自带Cocos，宿主只提供资源和被动诊断；导入不再改引擎（该文档L61–64）。因此资源补丁会直接决定宿主实际使用的浏览器API。

## 3. 音频补丁的确切语义

源码为 [scripts/patch_audio_runtime.py](https://github.com/Dey410/extract-pvzge-gpnext/blob/1ffb59b061761ccee1592097abc78c63fc9a6bda/scripts/patch_audio_runtime.py)。

- 扫描整个docs所有指定音频后缀，对每个文件顺序启动ffprobe取 `format=duration`（L19–21、L44–72、L75–100）。>=10秒或探测失败都进入DOM清单；其他保留WebAudio。阈值在源码固定，不是workflow输入。没有按音乐/短音效角色、声道、解码后尺寸、目标平台或运行时能力分类。
- 路径matcher把每次URL转为pathname再与清单逐项比较，以完整相等或后缀匹配（L129–141）。复杂度与DOM文件数成正比；0.15清单215项。没有memoization或Set。是否构成可测热点需要profile，不能把215项扫描直接认定为怪物多时卡顿根因。
- 三个选择器（load、loadNative、loadOneShotAudio）的原 `audioLoadMode !== DOM_AUDIO && support` 被替换成 `support && !isListed(url)`（L119–126、L182–203）。这**完全忽略调用方audioLoadMode**，游戏设置及其显式BGM模式不能覆盖构建清单。
- DOM loader原先等待loadedmetadata/canplaythrough/canplay，监听error并有8秒readyState判断；替换后创建audio、preload=metadata、src=url、load()，立即resolve（L155–167；原布局见 `tests/test_patch_audio_runtime.py:L17–26`）。没有等待metadata和error，也没有保留timeout。`metadata`只是预加载提示，不是“音频就绪”的承诺。
- play前只在src仍空时补URL和load（L171–177）。没有修改DOM的destroy、stop或错误重试生命周期。
- 正则替换次数严格要求1个loader、1个play hook、3个selector，未知布局拒绝（L198–203）；这是有用的失败关闭机制。但命中次数不能证明JavaScript语义正确。
- 脚本先完成probe和构造引擎输出，再直接write_bytes引擎（L243–271），之后才写report（L273–321）；引擎与report没有一起提交/回滚的事务。重复补丁通常因marker/layout改变而失败，非幂等。

### 已复现的补丁缺陷：return与标识符粘连

0.15真实bundle的 wrapper 静态成员如下（成员 `docs/cocos-js/_virtual_cc-9deb4621.js`，单行压缩源码，字符offset1492373（函数起始））：

```js
function(t,e){returnR9.support&&!__pvzgeUseDomAudio(t)?O9.loadNative(t):(R9.support||tt(5201),b9.loadNative(t))}
```

原因：原代码的 `return(` 中左括号包含在正则匹配范围里，替换直接输出support变量，形成 `returnR9`。Node执行这段真实函数，设置R9/O9/b9等必要桩后，直接调用得到：`ReferenceError: returnR9 is not defined`。同类问题也存在0.13的returnE9。

**调用边界**：这是wrapper的直接 `loadNative` 入口缺陷。本次扫描0.15所有JS，9处`.loadNative`文本引用都在同一个引擎bundle内；常规音频downloader `k9` 调用 `N9.load(...)`，AudioSource同样调用 `N9.load(...)`，未找到游戏使用 `N9.loadNative(...)` 的直接调用。故缺陷确定，但不能用它直接解释“BGM全没”。当前测试仅断言字符串包含/消失，未执行这条入口，fixture甚至包含 `returnE9.support`（`test/import_service_test.dart:L587`也有该文本）。

### 已复现的路由覆盖与冻结duration

对0.15真实wrapper片段做纯Node执行：

```text
SHORT_WITH_EXPLICIT_DOM WEB_AUDIO
LONG_WITH_EXPLICIT_WEB DOM_AUDIO
```

对真实DOM loader使用readyState=0、duration=NaN的audio桩：promise在metadata尚未到来时resolve。真实Cocos downloader `k9`立即保存 `meta={player:e,url:t,duration:e.duration,type:e.type}`，AudioClip `getDuration()` 返回 `_duration` 或 `_meta.duration`，不是player的实时duration。把player.duration随后改为60，clip.getDuration仍NaN：

```text
DOM_RESOLVES_BEFORE_METADATA {readyState:0,durationIsNaN:true,...}
FROZEN_DURATION {playerDuration:60,clipDurationIsNaN:true,defaultCooldownIsNaN:true,wouldEnterCooldown:false}
```

这些实验只证明代码行为，并未模拟真实WebKit的媒体调度。某些包的AudioClip序列化duration可能已提供有效值；必须逐具体音乐和真机读取才能判断影响范围。

## 4. 真实0.15 BGM调用链与症状分层

只读参考包：[/Users/xiaozhu_410/Downloads/pvzge-lite-0.15.0 (1).zip](</Users/xiaozhu_410/Downloads/pvzge-lite-0.15.0 (1).zip>)；ZIP大小610,156,829字节，ZIP SHA256 `47febd56947fe5e4a513938cf5e5a4566c2c68ad0fc5d6acdb1ae2152c7cd0dd`；引擎SHA256 `030b9c1a89dd49a6cda9aa3460743046abf58d79c3d4a9f91275db262632d5a2`。Cocos `3.8.4/web-mobile`。

真实游戏成员 `docs/assets/main/index.js` 的虚拟模块可按如下字符offset定位：SoundManager.ts 2,953,087、SoundRescourses.ts 2,989,737、SoundsController.ts 3,023,629。bundle含CRLF，offset以Python解码字符串计；不等同于AST位置。

```text
MusicController.playMusic
 -> SoundManager.playBGM
 -> clip来自resources.load("music/" + path)
 -> loadMusic回调将clip.loadMode设为DOM_AUDIO
 -> player1/player2 AudioSource.clip = clip
 -> AudioSource._syncPlayer
 -> N9.load(url, {audioLoadMode: clip.loadMode})
 -> 构建hybrid清单决定DOM或WebAudio
 -> DOM media src指向 gardendless-game://localhost/...（iOS宿主）
```

SoundManager使用两套player连续换曲/循环，另有insert/piano/holiday源；普通BGM循环判断主要使用music JSON的 `musicLength`，不是一律使用getDuration。`insertMusic`则保存 `clip.getDuration()-1`。SoundRescourses默认cooldown为 `clip.getDuration()*0.5`（真实bundleoffset3,010,537），NaN会使 `t>0` 不成立，缺少跨帧冷却；同tick仍存在去重。不能把NaN笼统推广为所有BGM逻辑失效。

特别纠正：实际Cocos clamp Fi用大小比较 `t<min ? min : t>max ? max : t`，max为NaN、t为0时仍返回0；不能套用Math.min/max推导“设置currentTime=0必然变NaN”。

对`resources/config.json`中的music路径、UUID和音频路由报告做精确映射：241条命名music中167走DOM、74走WebAudio。短intro/outro/victory等也属于BGM类别但<10秒，会被hybrid改成WebAudio。应向用户确认是启动页/关卡loop消失，还是所有短音乐过场也无声；这能区分DOM链路问题与SoundManager全局状态问题。

215条DOM音频的容器头与采样信息（只读ZIP头，不是真实解码验收）：

| 类型 | 数量 | 检查结果 |
| --- | ---: | --- |
| `.mp3` | 173 | 171个ID3、2个直接MPEG frame；全部解析到MPEG Layer III帧 |
| `.m4a` | 42 | 全部MP4/M4A容器，包含mp4a音频sample entry |

MP3帧分布：112个32kHz双声道、44个48kHz双声道、15个44.1kHz双声道、1个32kHz单声道、1个MPEG2/24kHz双声道。M4A sample entry分布：29个32kHz双声道、3个48kHz双声道、2个16kHz单声道、2个44.1kHz双声道、3个48kHz单声道、3个32kHz单声道。没有证据说长音频全部转成低码率AAC或伪装MP3。此检查不包含音频内容完整解码。

## 5. 音频生命周期与怪物多时的候选热点

以下是实际0.15引擎代码，部分来自上游，不是当前提取补丁新增：

1. **WebAudio缓存按URL引用计数，没有字节预算**。`C9._audioBufferDataMap`存解码后的AudioBuffer；retain/tryReleasing管理计数，没有LRU或可用内存信号。`loadNative`只在开始查缓存；尚在XHR/decode中的相同URL请求不会共享promise，可能并行解码。不能据此断言常态下同文件会反复解码，已加载的clip一般会命中缓存。
2. **decode失败路径可能悬空**。WebAudio loadNative对decode rejection只调用日志 `z("loadNative error",...)`，没有reject外层promise；decoder在只有callback的旧实现失败时也只console.error。资源看似加载中可能永久不完成，需目标WebKit错误日志确认。
3. **one-shot变速生命周期不同步**。实际M9.play（offset1,484,642起）设置 `playbackRate.value=t`，随后以 `1000 * originalDuration` 的timer释放cache并调用onEnd，没有按t调整，也没有用原生onended。变慢时登记提前清除、变快时登记延后；可能影响48声道限制的实际效果与缓存时机。正常结束路径只释放cache计数/登记，没有像stop路径那样disconnect source并把buffer置null。Gain节点只存在于构造局部变量，未保存做显式disconnect。是否造成保留需WebAudio图和heap snapshot证据。
4. **DOM销毁只去listener并置null**。实际destroy移除game pause/resume和ended监听，未显式pause/清src/load；当前补丁又在创建时主动metadata请求。离开场景是否及时取消、媒体元素是否被其它队列/闭包持有，需要真机观测。
5. **操作队列吞失败**。`g9`为play/pause/seek/stop串行队列，仅在success时shift，catch为空；持续失败可能卡住后续操作。DOM播放拒绝后原Cocos会绑定GameCanvas手势重试；资源/codec失败与自动播放拒绝使用相同路径，错误分类不足。不能把该原有手势逻辑描述为“完全没有重试”。
6. **同tick音效已有合并和cooldown**。SoundRescourses维护tickPlaySounds/tickPlaySoundArrays并线性查询、lateUpdate处理后清空；cooling列表每帧concat副本并indexOf/splice。大量不同音效可能增加扫描/分配成本，但重复同clip在一帧会合并。只看到大量怪物不能判断CPU、GPU还是音频开销为主。
7. **48 voice限制是计数，不是PCM内存限制**。N9.maxAudioChannel=48；J9按登记播放数量淘汰最早声音，已经加载的clip和AudioBuffer缓存总量不因此受限。

0.15报告中3972条WebAudio累计时长6598.408秒，215条DOM累计11366.893秒。时长总和不是运行时驻留总量。若全部短音频以48kHz立体声Float32驻留，算术上约2.53GB，但实际采样/声道、加载集合与释放时机不同；该数只说明“单文件<10秒”不能替代总内存预算，不能作为实际OOM数据。

## 6. 图片/ASTC与内存

当前 [transcode_textures_astc.py](https://github.com/Dey410/extract-pvzge-gpnext/blob/1ffb59b061761ccee1592097abc78c63fc9a6bda/scripts/transcode_textures_astc.py)仅处理 `assets/*/native/**/*.{png,avif}`（L177–185），内容识别、拒绝动画、统一RGBA（L191–202）。小图<=512或PNG压缩bpp>=6用4x4；大图>=2048且可见连通区域>=0.35用6x6；其它8x8（L90–112）。一个指定旋涡图集强制4x4（L27、L215）。

已有ASTC会校验magic、块、尺寸与长度并复用（L229–248、L254–270）；新编码使用临时文件验证后atomic replace（L273–295）。元数据映射支持独立ImageAsset与pack，要求精确UUID/唯一fmt（L334–424）；预先规划所有元数据、备份原文件、编码全部成功后才改引用（L575–594）。优点是避免编码失败后指向不存在文件；多个JSON逐一替换仍不是整个目录事务。

引用只保留 `fmt=7@ASTC_FORMAT_CODE`，不保留自动普通图片fallback（L334–341）。保留原AVIF/PNG只是磁盘备份，设备无ASTC支持时不会自动恢复。Loader资源校验未协商ASTC能力。图片磁盘压缩体积、解码CPU、GPU驻留内存是不同指标。

构建侧也有内存/磁盘特性：每图先完整RGBA+PNG生成，所有中间PNG写入保留tmp；`discover_jobs`串行，之后按CPU数并行astcenc，每编码器1线程（L177–251、L298–318、L517–525）。瞬时RGBA和编码进程内存有并行峰值，报告所有原图也会增加artifact/导入磁盘负担。它不是手机运行期内存profile。

只读比较真实资源包（总字节含reports等，不等同游戏内存）：

| 本地包 | ZIP字节 | 文件数 | 解压后字节 | 音频DOM/Web | 图片PNG/AVIF/ASTC |
| --- | ---: | ---: | ---: | --- | --- |
| 0.13.0 | 320,032,163 | 8,276 | 455,581,795 | 215 / 3899，DOM preload none | 6 / 595 / 1 |
| 0.14.0 | 723,433,184 | 9,658 | 1,278,682,368 | 215 / 3970，metadata | 6 / 602 / 608 |
| 0.15.0 (1) | 610,156,829 | 9,750 | 1,169,574,584 | 215 / 3972，metadata | 6 / 602 / 608 |

0.15 ASTC报告：608张，复用1/新编码607，4x4 363张、6x6 46张、8x8 199张，保留原图63,575,579字节，ASTC合计706,395,232字节（约674MiB）。按每张ASTC头部的宽高计算，如果全是RGBA level0会合计6,001,056,148字节（约5.59GiB），**这不是实际同时驻留量**。最大有多张4096×4096纹理，4x4 ASTC单张16MiB，RGBA单张64MiB。ASTC降低GPU表示的理论占用，却显著增加相对AVIF的磁盘大小；不能只用artifact变小/变大推论运行时更快或更省内存。

0.14与0.15引擎文件SHA完全相同，上述音频差异不来自两者引擎补丁版本变化；0.13不同。ZIP压缩比不同也不能当性能比较。

遗留 [transcode-assets.sh](https://github.com/Dey410/extract-pvzge-gpnext/blob/1ffb59b061761ccee1592097abc78c63fc9a6bda/scripts/transcode-assets.sh)仍有PNG→AVIF原地覆写和MP3→M4A/AAC保持原.mp3路径，默认24kbps/mono，采样率>32kHz则一半否则16kHz（L8–13、L147–208）；它依赖GNU stat/nproc和清理命令。当前workflow不调用，本次未执行。部分旧资源包与平台MIME嗅探差异须按具体包追溯，不能把遗留脚本参数当当前上游Lite编码规格。

## 7. 验证记录与覆盖缺口

运行环境Python3.14.7、Node24.18.0；系统Python没有Pillow，PATH未找到astcenc/ffprobe。没有安装依赖，没有下载整个资源包，没有修改游戏资源。

- `bash -n scripts/transcode-assets.sh`：通过，仅语法检查。
- 已读全部三个Python测试文件，确认音频文件夹夹具使用2处TemporaryDirectory会递归清理；执行时仅在当前进程替换为无cleanup、写入`/private/tmp`的retained夹具类，源码未改变、没有执行删除。结果31例：16通过、15因缺Pillow跳过。这个运行方式只为遵守用户删除约束，不证明原命令可直接安全运行。
- 纯Node执行真实0.15函数片段：直接loadNative的returnR9 ReferenceError复现；路由覆盖显式选项复现；DOM提前resolve与冻结duration复现。没有运行完整Cocos游戏。
- ZIP只读检查了目录、reports、settings、音频容器/帧头、ASTC header、部分真实bundle和资源UUID映射。仅执行了上文列出的隔离函数片段与桩，没有运行归档中的完整游戏或完整bundle，也未逐音频完整解码/全包CRC测试。

测试覆盖已有：阈值边界与探测失败、未知布局拒绝、metadata调用顺序、fallback src、只改引擎不改game、ffprobe provision顺序、ASTC分类/alpha/metadata/无效文件/复用/编码失败等。缺口包括：三个音频入口完整语义、调用方显式模式、真实metadata异步/错误/超时、DOM pause/stop/destroy及后台恢复、重复并发decode、voice变速/失败清理、PCM总预算、真机custom-scheme媒体播放、无ASTC设备fallback、跨版本产物manifest契约。

## 8. 后续重构前必须取得的证据与边界

1. 锁定用户正在导入的0.15 ZIP完整SHA、reports和实际激活slot中的引擎SHA，防止同名不同策略或旧Loader修改slot造成偏差。
2. iOS0.8.2按真实tag代码而非当前工作区做对照；观察短WebAudio成功与长DOM失败是否同源、是否发起资源请求、Range/MIME返回、metadata/error/play rejection事件。
3. 分别试一条长MP3、一条长M4A、一个短music intro，记录AudioSource/clip/player的模式、duration、readyState、media.error和Promise状态。它比笼统“音频坏了”更能压缩根因范围。
4. 怪物数量固定、音频开/关、ASTC/原图、音效变速/正常速做对照，采集CPU帧、GPU帧、WebContent RSS、AudioBuffer估算字节、活动media/source节点与缓存计数，再决定资源级优化、引擎补丁还是宿主改动。
5. 重构先明确宿主/资源构建责任：保留Cocos播放，还是重引原生音频，不能让历史facade和当前被动observer同时成为隐含契约。UI重构与音频根因证据应分清验收目标，不能靠UI重写验证底层稳定性。
6. 新资源产物应可识别地记录来源、音频政策、纹理政策与目标能力；否则跨版本回归和设备比较仍不可复现。


## 9. 最小复现的可重复命令

只读脚本保存于 [extract_pipeline_audio_semantics_20261014.py](/private/tmp/extract_pipeline_audio_semantics_20261014.py)。它从上文完整SHA的ZIP读取实际函数文本与路由清单，在Node中给浏览器/后端加最小桩，不解压、不执行完整bundle、不写资源、不删除。所有结论只限隔离语义；不是WebKit媒体播放的替代测试。

```bash
python3 /private/tmp/extract_pipeline_audio_semantics_20261014.py
```

实际输出（exit 0）：

```text
SAMPLE /Users/xiaozhu_410/Downloads/pvzge-lite-0.15.0 (1).zip
ZIP_BYTES 610156829
ZIP_SHA256 47febd56947fe5e4a513938cf5e5a4566c2c68ad0fc5d6acdb1ae2152c7cd0dd
ENGINE_SHA256 030b9c1a89dd49a6cda9aa3460743046abf58d79c3d4a9f91275db262632d5a2
DIRECT_NATIVE_OFFSET 1492373
DIRECT_NATIVE_ERROR ReferenceError returnR9 is not defined
DOM_RESOLVES_BEFORE_METADATA {"readyState":0,"durationIsNaN":true,"loadRequested":true}
SHORT_WITH_EXPLICIT_DOM WEB_AUDIO
LONG_WITH_EXPLICIT_WEB DOM_AUDIO
FROZEN_DURATION {"playerDuration":60,"clipDurationIsNaN":true,"defaultCooldownIsNaN":true,"wouldEnterCooldown":false}
```

`FROZEN_DURATION`取真实getDuration函数，模拟downloader在duration=NaN时保存meta的后果；未声称所有AudioClip的序列化duration均NaN。直接loadNative复现的入口调用条件和未见常规BGM调用的边界，见第3节。

只读静态检查的准确命令：

```bash
cd /Users/xiaozhu_410/Documents/Code/extract-pvzge-gpnext
bash -n scripts/transcode-assets.sh
git status --short --branch
git show origin/main:scripts/patch_audio_runtime.py
git show origin/codex/compact-150-audio-policy:scripts/patch_audio_runtime.py
```

远程证据命令仅做读取：

```bash
gh api repos/Dey410/extract-pvzge-gpnext --jq '{default_branch,updated_at,pushed_at,html_url}'
gh run list --repo Dey410/extract-pvzge-gpnext --limit 12 --json databaseId,headBranch,headSha,displayTitle,conclusion,createdAt
gh run view 36659966916 --repo Dey410/extract-pvzge-gpnext --log
```

主审计补充边界：远程Loader main `95395bf` 与本地 `b615` 的Dart和原生代码无差异，但用户Loader0.8.2是否等价仍须按tag核实；本笔记不把当前工作区自动等同为0.8.2二进制。
