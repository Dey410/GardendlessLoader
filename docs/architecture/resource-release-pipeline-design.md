# 两仓一键发包职责

日期：2026-10-14。状态：收敛设计，未修改workflow。实际CLI/Actions接口与证据见[功能接口审计第7节](functional-interface-audit.md#7-提取项目与actions实际功能)。本文不重复定义另一份包schema。

## 仅两个实际产品入口

| 入口 | 常用输入 | 唯一产物职责 |
| --- | --- | --- |
| extract-pvzge-gpnext资源workflow_dispatch | release_tag（留空取最新），publish（默认关） | 同一已验证政策生成完整资源ZIP、基于最新Release的增量ZIP、摘要与诊断报告；publish时发布为Release |
| GardendlessLoader应用workflow_dispatch | 已审查的Loader ref | 同一套当前SDK流程生成APK、未签名IPA、未签名HAP与版本摘要 |

游戏内容更新不要求重编三端应用。三端应用是三种系统产物，不是同功能多样式。没有跨仓dispatch/组合调度、PAT或轮询。资源仓库只在勾选publish时创建Release，它是下一次增量包的基础，见[ADR-0004](../adr/0004-delta-resource-packages.md)。成功的一键入口必须明确自己实际产生了什么，缺HAP不能报告完整三端成功。

## 一条资源生成链

解析一次并锁定上游release/asset → 下载并hash → 提取到新目录 → 识别支持布局 → 固定音频与单ASTC加工 → 生成manifest/index → 封存ZIP并重开验证 → 对最新Release生成并验证增量ZIP → 上传ZIP及报告 → 勾选publish时发布Release。

- 新内容版本复用已验证布局；未知引擎/GP协议、ffprobe失败、目标不唯一或行为失败直接给诊断，不再换旧脚本/DOM政策试运行。
- 默认总是跑音频/桥/包契约测试，不以ASTC开关决定核心测试是否执行。
- 正式资源只含实际引用的单ASTC变体；源图/中间PNG留构建工作目录，不打双纹理回退。三端真实格式能力/上传/关卡门禁通过后才能发布该通用目标；不预先声称所有设备支持。
- 取消长期none/ASTC与hybrid开关的多政策维护；正常发包只release_tag。旧高级输入若迁移，明确报不支持或给迁移说明，不能静默忽略。
- 上游EXE只提取，不执行。每run用新输出目录，不靠删整个目录获得确定性，不原地试错覆盖用户源包。

## 数据只放需要它的地方

运行包格式唯一来源为[运行契约](loader-runtime-contracts.md)。小manifest位于docs/__gardendless/package，旧docs-only导入会保留；file-index排除两固定元数据路径。packageId不自指，最终ZIP摘要留包外。

完整上游repository/release/asset ID和摘要、EXE摘要、producer commit、实际工具版本、构建参数与逐项加工结果留build report。它们用于复现，不需要都经AppController/Session/JS再传一轮。固定政策由producer commit标识，不另建adapter/profile/feature注册表。

同锁定输入与工具应输出相同内容身份。打包文件顺序/时间戳固定，最终ZIP完整检查结构/CRC/索引/长度/摘要；只验证目录不能证明最终产物正确。hash证明一致性，不认证来源。

## 一键应用构建

保留当前三个平台job和固定工具链。Loader变更时检查分析、JS行为、原生契约与产物内版本；最终汇总每个平台文件/大小/hash/签名状态。缺OpenHarmony工具或某产物即明确失败，开发部分构建也标部分，不伪装完整发布。

iOS/HAP保持未签名；Android无发布签名时明确debug签名，不能冒称相同身份的升级包。构建成功与三端设备验收分别记录。资源ZIP不嵌入应用仓库，不改变用户存档或自动安装。

## 验证与范围

验证已知输入一键成功、未知布局明确失败、相同输入重跑身份一致、坏ZIP不上传、三端应用缺项失败。资源与应用workflow都保持独立，不把网络资源更新变成三端SDK/签名的共同故障域。

当前代码仍有多输入开关、ASTC条件测试与目录清理；以上是后续实施决定，本轮未执行它们。GitHub入口和artifact能力此前已核验；操作事实不等于本轮已经运行CI。
