# 按实际职责收敛的实施顺序

日期：2026-10-14，实施状态更新于2026-10-15。[实际接口与数据流审计](../docs/architecture/functional-interface-audit.md)是基线；接口/数据流生产收敛已实施，证据见[实施记录](../docs/architecture/runtime-convergence-implementation.md)。三端设备与完整Actions验收仍未完成。本计划取代此前按五个新Module、URL+块桥和双纹理拆出的任务图。

## 原则

现有UI与三端完整保留；一个功能一个所有者、一条选定执行路径。真实系统边界保留，私有帮助函数不强制拆成服务。先减少重复数据和无效转发，再测量，不以文件/类的数量当架构质量。

## 顺序与检查点

1. 锁定当前可观察行为：真实Tauri wrapper、Host/Native命令、导入失败/恢复、音频load/ended和当前数据复制。以审计总表作为回归范围，不新增另一份需求矩阵。
2. 收敛Dart内部：直接channel host；一次应用身份，一次导入inspect结果；统计只count/bytes；一份HTTP正文函数；诊断按事实格式化。保留启动前时点检查、设置重置规则与原子恢复。
3. 把JS参数归一、块编码和RPC放在一个共享桥；读写/Blob导出选同一64KiB协议，文本只解码一次。没有fetch URL、整文件JSON或另一传输后备。
4. 每平台GameHost直接拥有有界文件任务、picker/保存、原子提交与退出结算；停止每请求新线程、主回调大IO和销毁后工作。现有资源Handler继续直接提供文件流。
5. 修现有Cocos音频适配的加载语义/失败传播/模式冲突；默认资源走一条单ASTC加工链。没有Native音频或双纹理兜底；三端实机不通过就不报告通用完成。
6. Native日志唯一事实源；清理本地JSON往返、Dart mirror和无消费配置。包小manifest/index只包含运行必需信息，构建详情留报告。
7. 两仓默认Actions接入同一行为/包验证；以三端产物、真实关卡、进退/后台、存档/Mod和同场景测量完成验收。

每步交付可运行行为和对应测试，数据/权限/恢复错误不得静默改成成功。接口简化与行为改变分别验证；未证明收益的性能改动不保留。三端不同系统API不是要合并进通用框架的重复代码。

## 明确撤回

PackageStore/SessionCoordinator/PlatformHost/FileWorkspace外层代理链、GameHostRouter工厂路由、URL+chunks双传输、loopback/Native BGM候选后备、双纹理与多profile运行时选择、多种UI方案、跨仓组合发布、旧脚本失败重试、Dart日志后备均不进入当前目标。

原子文件和A/B事务恢复、Origin/路径/链接/消息校验、资源所有权、取消和终态仍是必须实现的正确性。不能为了去掉兜底删这些保证。

## 执行边界

详细进度见[todo.md](todo.md)。没有对应设备/构建/CI运行证据时，不用静态测试推导性能或平台成功。用户已替换旧删除规则，四个明确停用的占位文件已按授权移除。UI与签名身份不改，游戏资源不进入Git。
