# 唯一运行契约

日期：2026-10-14。状态：收敛后的实施约定，尚未实现。实际接口清单与源码证据集中在[功能接口审计](functional-interface-audit.md)，本文件只规定必要的输入/输出与正确性，不再定义独立PackageStore/SessionCoordinator/FileWorkspace。

## 1. 资源包

```text
docs/
  index.html、assets/、cocos-js/、src/ ...
  __gardendless/package/resource-manifest.json
  __gardendless/package/file-index.json
reports/ ...    构建诊断，不是游戏payload
```

元数据放docs内，当前三端docs-only导入不会丢失。新Host拒绝页面直接读取package元数据；不创建workspace URL命名空间。索引覆盖所有docs payload，只排除上述两个固定文件；保留目录其它归档文件拒绝。reports受独立展开/条目预算，不可夹带未验证路径。

最低运行描述：

```json
{
  "schemaVersion": 1,
  "gameVersion": "0.15.0",
  "cocosVersion": "3.8.4",
  "hasGpNext": true,
  "gpNextVersion": null,
  "producerCommit": "0000000000000000000000000000000000000000",
  "minHostAbi": 1,
  "fileIndexSha256": "0000000000000000000000000000000000000000000000000000000000000000"
}
```

全零仅是形状示例。字段含义只定义一次；hasGpNext为Native是否创建GP核心的必要事实，gpNextVersion=null表示版本未知或无GP，不能据null否认已识别的GP。完整工具版本、来源资产/run和逐资源政策留外部构建报告，不再另设adapter ABI、profile版本、host major/minor和required/optional feature注册系统。producerCommit标明产生这组固定政策的实现，schemaVersion管理包数据形状，minHostAbi管理必需宿主协议，三者职责不同。

packageId为`sha256:`加manifest原始字节SHA-256，不写回manifest；fileIndexSha256为索引原始字节的64字符小写hex。索引按安全相对路径排序，每项path/sizeBytes/sha256，CRC与实际展开长度也检查。hash用于一致性与复现，不是来源认证。

导入只做一条链：取得一次私有输入快照 → 有界扫描 → 路径/格式/元数据检查 → 逐块解压核对实际长度/CRC/摘要 → readiness结果 → 原子激活。最终ZIP在CI封存后重开同样验证。拒绝链接/穿越/重复归一化路径/额外payload/超限展开；不能先无限解压再检查大小。

无manifest的既有标准包由同一检查函数产生本地描述，未知来源字段明确unknown；有新格式标志但坏/缺元数据就失败，不走legacy降级。旧Loader不认识minHostAbi，真正需要新ABI的资源须在入口明确检查并报告升级，不能仅写manifest就当旧App已受保护。

## 2. 启动与恢复

Dart调用一次launch(session)，当前平台GameHost保存必要恢复记录并启动。会话参数冻结资源槽/generation、包身份、设置与允许域；运行时不重读可能已变化的活动槽。Intent/Want必要的小型元数据编码保留，资源字节不随会话传输。

生命周期只保留`starting → running → closing → exited`；关键IO提交状态属于其实际操作，不再复制一套业务session状态机。防重复启动，每个session唯一退出结果。后台是运行状态变化，不是退出；rendererGone不能自动记为OOM。

退出关闭准入、取消排队/选择器/IO、停止数据回调、关闭句柄，原子保存终态后恢复启动器。未结束的IO仍持有原资源，槽不能复用；进程已终止由下次启动恢复，不能依赖JS finally。日志与退出文件持久化承担实际恢复，不是运行时后备实现。

成功导入重置自动收集off是既有规则；激活前失败/取消保留旧资源和偏好。提交后旧槽清理失败保留新活动资源、记录待清理，不能回滚已提交包。Origin、网站存档与槽外gp-next数据保持，不新增第二种存档格式或安装器。

## 3. 唯一文件数据协议

对游戏保持现有Tauri方法名和语义。改造前Native返回数字数组；已核对0.15真实wrapper接受底层invoke返回ArrayBuffer并直接生成视图/解码，当前共享桥已返回该类型，高层read_file得到Uint8Array、read_text_file得到string。其它支持版本仍需真实wrapper验证，不运行时试多种返回类型。文本只解码一次。

内部只有一个64KiB Base64分块实现，读/写/Blob导出共享块编码与原生任务所有权。以下三个阶段是同一次文件操作，不是新的三层服务：

| 内部命令 | 输入 | 输出及不变量 |
| --- | --- | --- |
| `file:begin` | mode=read/write、已归一的沙箱路径；write另有totalBytes/目的地 | Native随机handle、精确size；绑定session及一次文件版本；相同目标一个writer |
| `file:chunk` | handle、连续index/offset；read为请求长度，write为本块Base64 | read回本块Base64；write落盘后ack；每块≤64KiB，不累积完整number[]/Base64字符串 |
| `file:finish` | handle与close/commit/cancel | 每操作唯一终态；重复finish返回已确定结果，不重新执行覆盖写 |

读者一次分配受预算限制的最终ArrayBuffer，把每块解码写入正确位置，空文件返回空buffer。Native打开一次读取句柄；所有写入用临时文件+原子替换，保证读取的文件版本不在途中被原地截断。未完成短读/分配失败/超限/超时直接终结错误，不改用URL或整量JSON。

写者在通用serialize之前识别ArrayBuffer/TypedArray/Blob，尊重byteOffset/byteLength，只编码当前块，等ack后发下一块。空写也执行begin+commit，保持创建/截断语义。当前支持创建/覆盖，不借重构新增append。GP沙箱写与系统保存共用一个已准备文件提交终点，picker/文档URI只在当前Native实现处理。

commit要求总字节匹配、flush成功、原子替换完成。cancel先占终结权则不commit；commit已过提交点则返回committed，不谎报cancelled。超时后只用同一handle查询/终结，不自动重做写入。JS取消传播Native；Native自己限制队列/句柄/大小/期限，不能只靠JS活着。

准入的常量放实际GameHost文件任务实现旁，不新增全局Policy/Registry。取消/关闭可进入满队列；每次IO明确所属session，销毁后不再接新任务或发送迟到数据。业务不能在主线程做大文件编码/同步IO。

这个协议只消除整文件中间数字数组；最终交给GP-Next的完整buffer和ZIP解码仍可能占内存。Base64与RPC仍有成本，必须测量，不能写成常数总内存或零复制。

## 4. 原生边界与错误

各平台仍有一个资源Handler，一个系统picker/save实现和一个日志store，直接归当前GameHost管理。GET/HEAD/Range/MIME/取消及沙箱检查走实际平台API；Android不把304传给拒绝3xx的WebResourceResponse。iOS stop与回调串行化且可重入。三端共用行为测试向量，不新增FFI资源服务器。

请求在Native边界检查frame/Origin、ID、UTF-8消息字节数、相对路径、链接、块顺序和声明长度。JS入口归一参数不能代替Native权限判断。

```json
{
  "id": "request-1",
  "ok": false,
  "error": {"code": "resource_limit_exceeded", "message": "文件超过本次操作预算"}
}
```

错误code稳定，message可本地化；cancelled、deadline_exceeded、unsupported、io_failed、校验失败分别表达。错误直接返回现有日志/消息入口，不换另一套实现。不得泄漏私有绝对路径或能力句柄。

## 5. 验证门槛

- 同一读/写/空文件/子视图/短读/取消/commit竞态向量分别验证三端实际实现；真实GP-Next wrapper验返回类型和文本边界。
- 有/无/损坏manifest、隐藏payload、穿越、CRC/摘要/大小与最终ZIP验证；失败不改旧活动槽。
- 一次初始化/导入只取得一次对应事实；启动前时点检查与导入时检查分别覆盖，不能用去重取消安全验证。
- 单一音频路由、单ASTC路径必须有三端设备证据；未测不报告可用，失败不启用另一播放器/纹理备份。
- 20次进退/切关、前后台及固定高负载测量，区分宿主/WebContent、最终buffer和IO缓冲。

2026-10-15状态：接口与数据流实现、保留夹具导入及协议回归已落地，详见[实施记录](runtime-convergence-implementation.md)。三端可听输出、固定负载与完整产物验收尚未完成。此前验证未执行物理删除或带清理测试；用户随后替换删除规则，四个停用占位文件已按授权移除，完整Flutter回归246项通过。OHOS API12代理只能取得调用帧URL，不能宣称已经验证同源子帧隔离；Android/iOS保留main-frame校验。正确性检查与事务恢复持续保留，平行运行时兜底方案已经撤回。
