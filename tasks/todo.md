# 实施清单：按真实工作归属

日期：2026-10-14，状态更新于2026-10-15。勾选表示代码及对应安全测试完成；设备与完整Actions验收另列，未以源码测试代替。范围和证据唯一来源是[接口审计](../docs/architecture/functional-interface-audit.md)，不再为同一功能铺多层服务任务。

- [x] **锁定实际行为。** 用45个精确命令名、9个Flutter方法/反向progress与28类UI意图做覆盖；真实0.15 wrapper、音频时序和文件副本回归。验证现有纯Node行为与明确失败输入，游戏资源只按外部摘要引用。
- [x] **Dart直接调用并复用事实。** 去无选择作用的Router；导入一次inspect返回metadata/count/bytes，消除成功refresh重复读取与长期selectedSource；应用身份一次，四份HTTP正文读取合一；保留结构/权限/启动前检查。验证成功/失败/恢复、更新两产品规则及UI不变。
- [x] **一份JS桥、一种块协议。** 在serialize前处理TypedArray/Blob视图；64KiB Base64读写和导出统一，内部返回ArrayBuffer；消除多事件总线、平行传输及整量number[]分支。验证子视图/空文件/文本边界、顺序、失败与取消，真实wrapper不多复制。
- [x] **三端文件任务实际接入。** Android用有界任务替代每请求线程；iOS/OHOS大IO移出桥回调；各端一个文件所有者，picker/save合流，原子提交与销毁结算。验证同path替换读取、迟到回复、commit/cancel和退出后无工作。
- [ ] **现有资源Handler正确性。** Android合法条件请求响应与声明API兼容；iOS stop/callback可重入串行；OHOS请求并发/取消有界。验证真实平台包装/内核，不另加资源服务器。
- [ ] **Cocos音频唯一政策。** 修三个入口执行语义、metadata/错误/超时、调用者模式与ended记账；明确BGM/短音效各自唯一路由和decode/PCM预算。共用观察器三端接入；验证离屏媒体、变速、中断和实际可听输出。
- [ ] **一条资源加工与包身份。** 默认固定单ASTC路径，不携备份图；一次输入快照、新输出目录、最小manifest/index、封存ZIP重开验证。已知版本一键成功、未知失败，不换旧脚本；三端图形能力/上传/关卡实测不通过不报告通用完成。
- [x] **Native唯一日志与配置。** 去Dart mirror后备和本地Map/JSON往返；测试覆盖生产入口；失效配置、死类和无调用表面按审计处理。CachedAudioEntry等真实引用保留；物理文件删除另按用户规则确认。
- [ ] **完整验收。** 旧存档/Mod/Origin与失败更新保留；成功导入自动收集off规则保留；固定高负载、进退/后台和内存回落分别测三端；资源/应用两个Actions各实际跑通，缺HAP不称完整成功。只报告已取得证据的收益。

本轮精确实现与限制见[实施记录](../docs/architecture/runtime-convergence-implementation.md)和[CHANGE_MANIFEST](../CHANGE_MANIFEST.md)。资源Handler已修已确认的304、回调取消、FD关闭、MIME和保留路径问题；音频变换已验证真实官方0.15引擎；完整三端运行时、解码/PCM预算及性能曲线仍不能视为完成。

真实官方0.15本地管线已完整通过（619张ASTC、ZIP重开与Loader实际消费），原提取目录37测试通过；Loader安全门禁135测试通过。其余未勾选项中的设备/完整Actions与性能证据仍未取得。
